
//  packet_defs.v  — shared constants, include in every file


`define PKT_WIDTH     64
`define ADDR_WIDTH     4   // supports 16 ports (0-15)
`define NUM_PORTS      4  // number of input/output ports in the switch

// Header field positions
`define DST_HI        63
`define DST_LO        60
`define SRC_HI        59
`define SRC_LO        56
`define TYPE_HI       55
`define TYPE_LO       54
`define PRIO_HI       53
`define PRIO_LO       52
`define LEN_HI        51
`define LEN_LO        48
`define PAYLOAD_HI    47
`define PAYLOAD_LO     0

// Packet type encodings
`define PKT_DATA      2'b00
`define PKT_CTRL      2'b01
`define PKT_BCAST     2'b10
`define PKT_DROP      2'b11

// Priority encodings
`define PRIO_LOW      2'b00
`define PRIO_NORMAL   2'b01
`define PRIO_HIGH     2'b10
`define PRIO_CRITICAL 2'b11
