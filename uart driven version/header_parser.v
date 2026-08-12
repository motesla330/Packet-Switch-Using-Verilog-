// ============================================================
//  header_parser.v
//  Combinational — no clock needed, output is immediate
// ============================================================
`include "packet_defs.vh"

module header_parser (
    input  wire [`PKT_WIDTH-1:0]  packet_in,   // raw 64-bit word
    input  wire                   valid_in,     // is packet_in meaningful?

    output wire [`ADDR_WIDTH-1:0] dst_addr,     // who is this for?
    output wire [`ADDR_WIDTH-1:0] src_addr,     // who sent it?
    output wire [1:0]             pkt_type,     // DATA/CTRL/BCAST/DROP
    output wire [1:0]             priority,     // LOW/NORMAL/HIGH/CRITICAL
    output wire [3:0]             pkt_len,      // payload length hint
    output wire [47:0]            payload,      // the actual data

    // Decoded control signals — useful for routing logic
    output wire                   is_data,
    output wire                   is_ctrl,
    output wire                   is_broadcast,
    output wire                   is_drop,
    output wire                   is_valid      // valid AND not DROP
);

    // --- Field extraction via bit slicing ---
    // If valid_in is 0, we output zeros to prevent garbage
    // from propagating into the routing logic.
    // The ternary here is just: valid_in ? real_bits : zeros
    assign dst_addr  = valid_in ? packet_in[`DST_HI  :`DST_LO  ] : 4'b0;
    assign src_addr  = valid_in ? packet_in[`SRC_HI  :`SRC_LO  ] : 4'b0;
    assign pkt_type  = valid_in ? packet_in[`TYPE_HI :`TYPE_LO ] : 2'b0;
    assign priority  = valid_in ? packet_in[`PRIO_HI :`PRIO_LO ] : 2'b0;
    assign pkt_len   = valid_in ? packet_in[`LEN_HI  :`LEN_LO  ] : 4'b0;
    assign payload   = valid_in ? packet_in[`PAYLOAD_HI:`PAYLOAD_LO] : 48'b0;

    // --- Type decode flags ---
    assign is_data      = valid_in && (pkt_type == `PKT_DATA);
    assign is_ctrl      = valid_in && (pkt_type == `PKT_CTRL);
    assign is_broadcast = valid_in && (pkt_type == `PKT_BCAST);
    assign is_drop      = valid_in && (pkt_type == `PKT_DROP);
    assign is_valid     = valid_in && (pkt_type != `PKT_DROP);

endmodule
