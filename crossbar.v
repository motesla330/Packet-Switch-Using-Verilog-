
`include "packet_defs.vh"

module crossbar #(
    parameter NUM_PORTS  = 4,
    parameter DATA_WIDTH = 64
)(
    input  wire                              clk,
    input  wire                              rst_n,

   
    input  wire [DATA_WIDTH*NUM_PORTS-1:0]   in_data_flat,
    input  wire [NUM_PORTS-1:0]              in_valid,   

    
    input  wire [2*NUM_PORTS-1:0]            sel_flat,   
    input  wire [NUM_PORTS-1:0]              sel_valid,  


    output wire [DATA_WIDTH*NUM_PORTS-1:0]   out_data_flat,
    output reg  [NUM_PORTS-1:0]              out_valid
);

    integer inp, outp;

    
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
            for (outp = 0; outp < NUM_PORTS; outp = outp + 1) begin
                out_data[outp]  <= {DATA_WIDTH{1'b0}};
                out_valid[outp] <= 1'b0;
            end
        end else begin
            for (outp = 0; outp < NUM_PORTS; outp = outp + 1) begin
                out_data[outp]  <= {DATA_WIDTH{1'b0}};
                out_valid[outp] <= 1'b0;
            end

            
            for (inp = 0; inp < NUM_PORTS; inp = inp + 1) begin
                if (in_valid[inp] && sel_valid[inp]) begin
                    out_data[sel[inp]]  <= in_data[inp];
                    out_valid[sel[inp]] <= 1'b1;
                end
            end
        end
    end

endmodule