// ============================================================
//  routing_table.v  — fixed: renamed "table" to "rt_mem"
// ============================================================
`include "packet_defs.vh"

module routing_table #(
    parameter ADDR_WIDTH = 4,
    parameter PORT_WIDTH = 2
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // Lookup port
    input  wire [ADDR_WIDTH-1:0] lookup_addr,
    output reg  [PORT_WIDTH-1:0] lookup_port,
    output reg                   lookup_valid,

    // Update port
    input  wire                  wr_en,
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire [PORT_WIDTH-1:0] wr_port,
    input  wire                  wr_valid
);

    localparam TABLE_SIZE = 2 ** ADDR_WIDTH;

    // ← was "table" — now "rt_mem" (routing table memory)
    reg [PORT_WIDTH:0] rt_mem [0:TABLE_SIZE-1];

    integer i;

    // --- Reset and write ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < TABLE_SIZE; i = i + 1)
                rt_mem[i] <= {(PORT_WIDTH+1){1'b0}};  // ← was table[i]
        end else if (wr_en) begin
            rt_mem[wr_addr] <= {wr_valid, wr_port};   // ← was table[wr_addr]
        end
    end

    // --- Lookup ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lookup_port  <= 0;
            lookup_valid <= 0;
        end else begin
            lookup_port  <= rt_mem[lookup_addr][PORT_WIDTH-1:0]; // ← was table
            lookup_valid <= rt_mem[lookup_addr][PORT_WIDTH];     // ← was table
        end
    end

endmodule