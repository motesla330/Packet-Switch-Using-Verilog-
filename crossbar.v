// ============================================================
//  crossbar.v  — 4×4 non-blocking crossbar switch fabric
// ============================================================
`include "packet_defs.vh"

module crossbar #(
    parameter NUM_PORTS  = 4,
    parameter DATA_WIDTH = 64
)(
    input  wire                              clk,
    input  wire                              rst_n,

    // Data arriving from each input port's FIFO
    // NOTE: was "input wire [DATA_WIDTH-1:0] in_data [0:NUM_PORTS-1]"
    // (unpacked-array port) — ModelSim's port binder rejects array
    // ports, so this is now a single flattened packed vector.
    // Port i lives in bits [(i+1)*DATA_WIDTH-1 -: DATA_WIDTH].
    input  wire [DATA_WIDTH*NUM_PORTS-1:0]   in_data_flat,
    input  wire [NUM_PORTS-1:0]              in_valid,   // which inputs have data

    // Routing decision from arbiter + routing table
    // sel[i] = which output port input i should go to
    // Flattened the same way: port i in bits [(i+1)*2-1 -: 2]
    input  wire [2*NUM_PORTS-1:0]            sel_flat,   // flattened array of 2-bit selections
    input  wire [NUM_PORTS-1:0]              sel_valid,  // grant is actually active

    // Output to each output port's FIFO — flattened for the same reason
    output wire [DATA_WIDTH*NUM_PORTS-1:0]   out_data_flat,
    output reg  [NUM_PORTS-1:0]              out_valid
);

    integer inp, outp;

    // --- Internal unpacked-array views of the flattened ports ---
    // These are ordinary internal wires/regs (not ports), so ModelSim
    // has no problem with them being arrays. All the logic below is
    // untouched — it just reads/writes these instead of the ports
    // directly, with a generate block doing the flatten/unflatten.
    wire [DATA_WIDTH-1:0] in_data  [0:NUM_PORTS-1];
    wire [1:0]            sel      [0:NUM_PORTS-1];
    reg  [DATA_WIDTH-1:0] out_data [0:NUM_PORTS-1];

    genvar gv;
    generate
        for (gv = 0; gv < NUM_PORTS; gv = gv + 1) begin : flatten_glue
            assign in_data[gv] = in_data_flat[(gv+1)*DATA_WIDTH-1 -: DATA_WIDTH];
            assign sel[gv]     = sel_flat[(gv+1)*2-1 -: 2];
            assign out_data_flat[(gv+1)*DATA_WIDTH-1 -: DATA_WIDTH] = out_data[gv];
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Clear all outputs
            for (outp = 0; outp < NUM_PORTS; outp = outp + 1) begin
                out_data[outp]  <= {DATA_WIDTH{1'b0}};
                out_valid[outp] <= 1'b0;
            end
        end else begin
            // Default: all outputs invalid this cycle
            for (outp = 0; outp < NUM_PORTS; outp = outp + 1) begin
                out_data[outp]  <= {DATA_WIDTH{1'b0}};
                out_valid[outp] <= 1'b0;
            end

            // For each input port, if it has a valid grant,
            // forward its data to the selected output port
            for (inp = 0; inp < NUM_PORTS; inp = inp + 1) begin
                if (in_valid[inp] && sel_valid[inp]) begin
                    out_data[sel[inp]]  <= in_data[inp];
                    out_valid[sel[inp]] <= 1'b1;
                end
            end
        end
    end

endmodule