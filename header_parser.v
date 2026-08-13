
`include "packet_defs.vh"

module header_parser (
    input  wire [`PKT_WIDTH-1:0]  packet_in,   // raw 64-bit word
    input  wire                   valid_in,     // is packet_in meaningful?

    output wire [`ADDR_WIDTH-1:0] dst_addr,     // who is this for?
    output wire [`ADDR_WIDTH-1:0] src_addr,     // who sent it?(not used now )
    output wire [1:0]             pkt_type,     // DATA/CTRL/BCAST/DROP(not used now )
    output wire [1:0]             priority,     // LOW/NORMAL/HIGH/CRITICAL(not used now )
    output wire [3:0]             pkt_len,      // payload length hint (not used now )
    output wire [47:0]            payload,      // the actual data (not used now )

    //  (not used now )d ecoded control signals — useful for routing logic
    output wire                   is_data,
    output wire                   is_ctrl,
    output wire                   is_broadcast,
    output wire                   is_drop,
    output wire                   is_valid      
);

    
    assign dst_addr  = valid_in ? packet_in[`DST_HI  :`DST_LO  ] : 4'b0;
    assign src_addr  = valid_in ? packet_in[`SRC_HI  :`SRC_LO  ] : 4'b0;
    assign pkt_type  = valid_in ? packet_in[`TYPE_HI :`TYPE_LO ] : 2'b0;
    assign priority  = valid_in ? packet_in[`PRIO_HI :`PRIO_LO ] : 2'b0;
    assign pkt_len   = valid_in ? packet_in[`LEN_HI  :`LEN_LO  ] : 4'b0;
    assign payload   = valid_in ? packet_in[`PAYLOAD_HI:`PAYLOAD_LO] : 48'b0;

   
    assign is_data      = valid_in && (pkt_type == `PKT_DATA);
    assign is_ctrl      = valid_in && (pkt_type == `PKT_CTRL);
    assign is_broadcast = valid_in && (pkt_type == `PKT_BCAST);
    assign is_drop      = valid_in && (pkt_type == `PKT_DROP);
    assign is_valid     = valid_in && (pkt_type != `PKT_DROP);

endmodule
