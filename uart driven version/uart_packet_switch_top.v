// ============================================================
//  uart_packet_switch_top.v
//
//  Integration top level: wires the existing uart_rx / uart_tx
//  and the existing packet_switch_top together through the two
//  bridge modules (uart_to_packet_bridge / packet_to_uart_bridge),
//  on one chosen switch port (BRIDGE_PORT). Neither UART core
//  module nor either bridge module is touched here - this file
//  only instantiates and connects them.
//
//  Two small supporting changes elsewhere make this integration
//  correct; neither lives in this file, so they're noted here
//  for anyone reading this top level:
//    1. packet_defs.vh - the shared header every module below
//       includes - had to be added under that exact name; the
//       project only shipped it as _packet_defs.v, which none
//       of the `include "packet_defs.vh" directives would find.
//    2. packet_switch_top.v got a one-cycle pipeline stage added
//       between the arbiter's grant and the crossbar's in_valid/
//       sel_valid/sel inputs, so the crossbar reads each input
//       FIFO's dout on the cycle it actually holds the granted
//       word rather than the cycle before. See the comment above
//       that pipeline stage in packet_switch_top.v for the full
//       explanation.
//
//  One more thing worth knowing before using this module: the
//  routing table inside packet_switch_top resets with every
//  entry marked invalid, and only port 0's table is writable.
//  No packet - including one arriving over UART - is routed
//  anywhere until rt_wr_en/rt_wr_addr/rt_wr_port/rt_wr_valid has
//  been pulsed at least once to program a route. For a UART
//  self-loopback test (send a packet in, expect it back out),
//  program dst_addr = BRIDGE_PORT's own address to route to
//  BRIDGE_PORT.
// ============================================================
`include "packet_defs.vh"

module uart_packet_switch_top #(
    parameter CLK_HZ      = 50_000_000,
    parameter BIT_RATE    = 9600,
    parameter PAYLOAD_BITS= 8,
    parameter DATA_WIDTH  = 64,
    parameter NUM_PORTS   = 4,
    parameter FIFO_DEPTH  = 16,
    parameter BRIDGE_PORT = 0     // which switch port gets wired to the UART
)(
    input  wire  clk,
    input  wire  rst_n,       // one shared, active-low reset for everything
    input  wire  uart_rxd,
    output wire  uart_txd,

    // control-plane pass-through (only really useful if BRIDGE_PORT
    // isn't port 0 - port 0's routing table is the only writable one
    // in the existing packet_switch_top)
    input  wire                   rt_wr_en,
    input  wire [3:0]             rt_wr_addr,
    input  wire [1:0]             rt_wr_port,
    input  wire                   rt_wr_valid
);

    // ---------------- UART core ----------------
    wire [PAYLOAD_BITS-1:0] uart_rx_data;
    wire                    uart_rx_valid;
    wire                    uart_rx_break;   // not used here

    wire [PAYLOAD_BITS-1:0] uart_tx_data;
    wire                    uart_tx_en;
    wire                    uart_tx_busy;

    uart_rx #(
        .BIT_RATE(BIT_RATE), .PAYLOAD_BITS(PAYLOAD_BITS), .CLK_HZ(CLK_HZ)
    ) i_uart_rx (
        .clk          (clk),
        // uart_rx/uart_tx check resetn synchronously inside always @(posedge clk),
        // while packet_switch_top's internals use a true async reset. Both are
        // driven from the same rst_n here, which is functionally fine as long as
        // rst_n is held for more than one clock period; it's not a uniform reset
        // architecture, so a synchronized reset tree is worth adding before this
        // goes to real hardware.
        .resetn       (rst_n),
        .uart_rxd     (uart_rxd),
        .uart_rx_en   (1'b1),
        .uart_rx_break(uart_rx_break),
        .uart_rx_valid(uart_rx_valid),
        .uart_rx_data (uart_rx_data)
    );

    uart_tx #(
        .BIT_RATE(BIT_RATE), .PAYLOAD_BITS(PAYLOAD_BITS), .CLK_HZ(CLK_HZ)
    ) i_uart_tx (
        .clk          (clk),
        .resetn       (rst_n),
        .uart_txd     (uart_txd),
        .uart_tx_busy (uart_tx_busy),
        .uart_tx_en   (uart_tx_en),
        .uart_tx_data (uart_tx_data)
    );

    // ---------------- switch port arrays ----------------
    wire [DATA_WIDTH-1:0] port_in_data  [0:NUM_PORTS-1];
    wire [NUM_PORTS-1:0]  port_in_valid;
    wire [NUM_PORTS-1:0]  port_in_ready;

    wire [DATA_WIDTH-1:0] port_out_data [0:NUM_PORTS-1];
    wire [NUM_PORTS-1:0]  port_out_valid;
    wire [NUM_PORTS-1:0]  port_out_ready;

    genvar g;
    generate
        for (g = 0; g < NUM_PORTS; g = g + 1) begin : tie_off_unused
            if (g != BRIDGE_PORT) begin
                // ports we're not using: never feed them, never drain them
                assign port_in_data[g]   = {DATA_WIDTH{1'b0}};
                assign port_in_valid[g]  = 1'b0;
                assign port_out_ready[g] = 1'b0;
            end
        end
    endgenerate

    // ---------------- the two new bridges ----------------
    uart_to_packet_bridge #(
        .DATA_WIDTH(DATA_WIDTH), .PAYLOAD_BITS(PAYLOAD_BITS)
    ) i_rx_bridge (
        .clk           (clk),
        .rst_n         (rst_n),
        .uart_rx_data  (uart_rx_data),
        .uart_rx_valid (uart_rx_valid),
        .port_in_data  (port_in_data [BRIDGE_PORT]),
        .port_in_valid (port_in_valid[BRIDGE_PORT]),
        .port_in_ready (port_in_ready[BRIDGE_PORT])
    );

    packet_to_uart_bridge #(
        .DATA_WIDTH(DATA_WIDTH), .PAYLOAD_BITS(PAYLOAD_BITS)
    ) i_tx_bridge (
        .clk            (clk),
        .rst_n          (rst_n),
        .port_out_data  (port_out_data [BRIDGE_PORT]),
        .port_out_valid (port_out_valid[BRIDGE_PORT]),
        .port_out_ready (port_out_ready[BRIDGE_PORT]),
        .uart_tx_data   (uart_tx_data),
        .uart_tx_en     (uart_tx_en),
        .uart_tx_busy   (uart_tx_busy)
    );

    // ---------------- the packet switch (crossbar-timing fix applied, see header) ----------------
    packet_switch_top #(
        .NUM_PORTS(NUM_PORTS), .DATA_WIDTH(DATA_WIDTH), .FIFO_DEPTH(FIFO_DEPTH)
    ) i_switch (
        .clk           (clk),
        .rst_n         (rst_n),
        .port_in_data  (port_in_data),
        .port_in_valid (port_in_valid),
        .port_in_ready (port_in_ready),
        .port_out_data (port_out_data),
        .port_out_valid(port_out_valid),
        .port_out_ready(port_out_ready),
        .rt_wr_en      (rt_wr_en),
        .rt_wr_addr    (rt_wr_addr),
        .rt_wr_port    (rt_wr_port),
        .rt_wr_valid   (rt_wr_valid)
    );

endmodule
