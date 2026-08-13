// ============================================================
//  uart_to_packet_bridge.v
//
//  Direction: UART RX -> packet_switch_top input port
//
//  What this does:
//    uart_rx hands us one byte at a time (a 1-cycle uart_rx_valid
//    pulse each time). We just sit there catching bytes until we've
//    got 8 of them, glue them into a single 64-bit word, and then
//    offer that word to a switch input port the normal valid/ready
//    way.
//
//    There's no sequence number or start/end marker riding along
//    on the wire - we're told not to add one, and honestly we don't
//    need one. A UART line can't reorder or duplicate bytes, so
//    "byte 3 of this packet" is just "the 4th byte we've seen since
//    the last packet finished." The tradeoff (spelled out in the
//    write-up) is that if a byte ever gets lost or corrupted, we
//    have no way to notice or resync - we just quietly keep counting
//    to 8 forever, out of step. Worth knowing, not fixing here.
//
//  Byte order (has to match packet_to_uart_bridge on the other end,
//  and whatever's actually driving the UART line):
//    1st byte in  -> port_in_data[DATA_WIDTH-1 -: PAYLOAD_BITS]   (top byte, has DST/SRC)
//    last byte in -> port_in_data[PAYLOAD_BITS-1 -: PAYLOAD_BITS] (bottom byte)
// ============================================================

module uart_to_packet_bridge #(
    parameter DATA_WIDTH   = 64,   // must match packet_switch_top's DATA_WIDTH
    parameter PAYLOAD_BITS = 8     // must match uart_rx's PAYLOAD_BITS
)(
    input  wire                     clk,
    input  wire                     rst_n,        // active-low, async
                                                    // (same convention as fifo_queue /
                                                    //  arbiter / crossbar / routing_table)

    // -------- from uart_rx --------
    input  wire [PAYLOAD_BITS-1:0]  uart_rx_data,
    input  wire                     uart_rx_valid,  // 1-cycle pulse, data's good that same cycle

    // -------- to the switch's input port --------
    // hook these straight into packet_switch_top.port_in_data[PORT_ID],
    // .port_in_valid[PORT_ID], .port_in_ready[PORT_ID]
    output reg  [DATA_WIDTH-1:0]    port_in_data,
    output reg                      port_in_valid,
    input  wire                     port_in_ready
);

    localparam integer NUM_BYTES = DATA_WIDTH / PAYLOAD_BITS;
    localparam integer CNT_W     = (NUM_BYTES <= 1) ? 1 : $clog2(NUM_BYTES);

    // Just a sanity check at elaboration time so nobody accidentally
    // sets a DATA_WIDTH that doesn't split evenly into bytes.
    // synthesis translate_off
    initial begin
        if (DATA_WIDTH % PAYLOAD_BITS != 0) begin
            $fatal(1, "uart_to_packet_bridge: DATA_WIDTH must be an integer multiple of PAYLOAD_BITS");
        end
    end
    // synthesis translate_on

    // Two states, nothing fancy:
    //   COLLECT - shoveling bytes from UART into assemble_reg
    //   PRESENT - got a full word, holding it out for the switch
    //             to grab whenever it's ready
    localparam STATE_COLLECT = 1'b0;
    localparam STATE_PRESENT = 1'b1;

    reg                     state;
    reg [DATA_WIDTH-1:0]    assemble_reg;
    reg [CNT_W-1:0]         byte_cnt;

    // This is "what assemble_reg would look like if we shifted the
    // current byte in right now." Working it out as its own wire
    // (instead of just writing assemble_reg <= ... twice) means we
    // can safely reuse the same value both for the running shift AND
    // for the final word latch on the byte-8 cycle, with no risk of
    // reading a stale/half-updated assemble_reg.
    wire [DATA_WIDTH-1:0] next_assemble =
        { assemble_reg[DATA_WIDTH-PAYLOAD_BITS-1:0], uart_rx_data };

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= STATE_COLLECT;
            assemble_reg  <= {DATA_WIDTH{1'b0}};
            byte_cnt      <= {CNT_W{1'b0}};
            port_in_data  <= {DATA_WIDTH{1'b0}};
            port_in_valid <= 1'b0;
        end else begin
            case (state)

                // ---------------------------------------------
                STATE_COLLECT: begin
                    if (uart_rx_valid) begin
                        assemble_reg <= next_assemble;

                        if (byte_cnt == NUM_BYTES-1) begin
                            // that was byte 8 - word's done, hand it off
                            byte_cnt      <= {CNT_W{1'b0}};
                            port_in_data  <= next_assemble;
                            port_in_valid <= 1'b1;
                            state         <= STATE_PRESENT;
                        end else begin
                            byte_cnt <= byte_cnt + 1'b1;
                        end
                    end
                    // if uart_rx_valid is low we just sit tight - and
                    // that's basically every cycle, since a new byte
                    // only shows up roughly once every ~10*CYCLES_PER_BIT
                    // clocks
                end

                // ---------------------------------------------
                STATE_PRESENT: begin
                    // hold valid/data steady until the switch says
                    // it's ready - standard handshake, nothing clever
                    if (port_in_ready) begin
                        port_in_valid <= 1'b0;
                        state         <= STATE_COLLECT;
                    end
                    // heads up: if a new byte shows up from UART while
                    // we're stuck here waiting, we drop it - assemble_reg
                    // and byte_cnt just don't move. Given how long a UART
                    // byte takes compared to how fast the switch usually
                    // frees up, this basically never happens in practice,
                    // but it's a real edge case worth knowing about (see
                    // "known limitation" in the write-up).
                end

            endcase
        end
    end

endmodule
