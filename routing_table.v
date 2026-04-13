// ============================================================
//  routing_table.v
//  Synchronous read, synchronous write (1-cycle read latency)
// ============================================================
`include "packet_defs.vh"

module routing_table #(
    parameter ADDR_WIDTH = 4,   // 2^4 = 16 possible destinations
    parameter PORT_WIDTH = 2    // log2(NUM_PORTS) = 2 for 4 ports
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // --- Lookup port (used every cycle by routing logic) ---
    input  wire [ADDR_WIDTH-1:0] lookup_addr,   // dst from header parser
    output reg  [PORT_WIDTH-1:0] lookup_port,   // which output port
    output reg                   lookup_valid,  // 1 = entry exists

    // --- Update port (used by CPU / control plane) ---
    // When wr_en=1, we write wr_port into the entry for wr_addr
    input  wire                  wr_en,
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire [PORT_WIDTH-1:0] wr_port,
    input  wire                  wr_valid       // 1=valid entry, 0=clear it
);

    localparam TABLE_SIZE = 2 ** ADDR_WIDTH;   // 16 entries

    // Each entry stores: [valid bit | port number]
    // valid bit is the MSB — this packs both into one word
    reg [PORT_WIDTH:0] table [0:TABLE_SIZE-1]; // PORT_WIDTH+1 bits wide
    //   ↑ that's 3 bits: 1 valid + 2 port

    integer i;

    // --- Reset and write logic ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Clear all entries on reset
            for (i = 0; i < TABLE_SIZE; i = i + 1)
                table[i] <= {(PORT_WIDTH+1){1'b0}};
        end else if (wr_en) begin
            // Write: pack valid bit and port into one entry
            table[wr_addr] <= {wr_valid, wr_port};
        end
    end

    // --- Lookup logic (registered — output available next cycle) ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lookup_port  <= 0;
            lookup_valid <= 0;
        end else begin
            // Index into table with the destination address
            lookup_port  <= table[lookup_addr][PORT_WIDTH-1:0];
            lookup_valid <= table[lookup_addr][PORT_WIDTH]; // MSB = valid
        end
    end

endmodule
