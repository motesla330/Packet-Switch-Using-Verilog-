// ============================================================
//  uart_packet_switch_top.v  (just an example wiring - not a
//  required deliverable, mostly here to show the connections)
//
//  Wires the two new bridge modules between the EXISTING,
//  UNTOUCHED uart_rx / uart_tx / packet_switch_top modules on
//  one chosen switch port (BRIDGE_PORT).
//
//  Nothing in the existing modules changes here - this file
//  just instantiates them alongside the new bridges.
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
        .resetn       (rst_n),     // see the reset-style note in the write-up
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

    // ---------------- the existing switch, untouched ----------------
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
