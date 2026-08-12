// ============================================================
//  packet_to_uart_bridge.v
//
//  Direction: packet_switch_top output port -> UART TX
//
//  What this does:
//    Grabs one 64-bit word off a switch output port (the usual
//    valid/ready dance), chops it into 8 bytes, and feeds them to
//    uart_tx one at a time, waiting for uart_tx_busy to clear
//    between each one. Same deal as the RX side - no length byte,
//    no sequence number, nothing extra on the wire. The order the
//    bytes go out in is the only "framing" there is, and it has to
//    line up with how uart_to_packet_bridge reassembles them on the
//    other end.
//
//  Byte order (must match uart_to_packet_bridge):
//    1st byte out  -> port_out_data[DATA_WIDTH-1 -: PAYLOAD_BITS]   (top byte, DST/SRC)
//    last byte out -> port_out_data[PAYLOAD_BITS-1 -: PAYLOAD_BITS] (bottom byte)
// ============================================================

module packet_to_uart_bridge #(
    parameter DATA_WIDTH   = 64,   // must match packet_switch_top's DATA_WIDTH
    parameter PAYLOAD_BITS = 8     // must match uart_tx's PAYLOAD_BITS
)(
    input  wire                     clk,
    input  wire                     rst_n,        // active-low, async
                                                    // (same convention as fifo_queue /
                                                    //  arbiter / crossbar / routing_table)

    // -------- from the switch's output port --------
    // hook these straight into packet_switch_top.port_out_data[PORT_ID],
    // .port_out_valid[PORT_ID], .port_out_ready[PORT_ID]
    input  wire [DATA_WIDTH-1:0]    port_out_data,
    input  wire                     port_out_valid,
    output wire                     port_out_ready,

    // -------- to uart_tx --------
    output wire [PAYLOAD_BITS-1:0]  uart_tx_data,
    output wire                     uart_tx_en,     // 1-cycle pulse
    input  wire                     uart_tx_busy
);

    localparam integer NUM_BYTES = DATA_WIDTH / PAYLOAD_BITS;
    localparam integer CNT_W     = (NUM_BYTES <= 1) ? 1 : $clog2(NUM_BYTES);

    // synthesis translate_off
    initial begin
        if (DATA_WIDTH % PAYLOAD_BITS != 0) begin
            $fatal(1, "packet_to_uart_bridge: DATA_WIDTH must be an integer multiple of PAYLOAD_BITS");
        end
    end
    // synthesis translate_on

    // Four states to walk through per byte. state is the only thing
    // that's actually clocked here - port_out_ready and uart_tx_en
    // are just plain combinational reads of whatever state we're in,
    // so they're clean for a full cycle and don't add any extra delay.
    localparam [1:0] S_IDLE      = 2'd0,  // sitting around waiting for a word from the switch
                      S_WAIT_IDLE = 2'd1,  // making sure uart_tx is actually free before we poke it
                      S_PULSE     = 2'd2,  // the one cycle where we pulse uart_tx_en
                      S_WAIT_BUSY = 2'd3;  // waiting out the current byte's transmission

    reg [1:0]              state;
    reg [DATA_WIDTH-1:0]   pkt_reg;
    reg [CNT_W-1:0]        byte_idx;

    // straightforward decodes of the state
    assign port_out_ready = (state == S_IDLE);
    assign uart_tx_en     = (state == S_PULSE);

    // pick out whichever byte we're currently on, top-down
    assign uart_tx_data =
        pkt_reg[ (DATA_WIDTH-1) - (byte_idx*PAYLOAD_BITS) -: PAYLOAD_BITS ];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            pkt_reg  <= {DATA_WIDTH{1'b0}};
            byte_idx <= {CNT_W{1'b0}};
        end else begin
            case (state)

                // ---------------------------------------------
                S_IDLE: begin
                    // port_out_ready is high here. When the switch
                    // has a word for us, grab it right off port_out_data
                    // on this same edge - before the upstream FIFO's
                    // dout register moves on to the next entry.
                    if (port_out_valid) begin
                        pkt_reg  <= port_out_data;
                        byte_idx <= {CNT_W{1'b0}};
                        state    <= S_WAIT_IDLE;
                    end
                end

                // ---------------------------------------------
                S_WAIT_IDLE: begin
                    // Belt-and-suspenders check: by the time we get
                    // here uart_tx should already be idle (that's how
                    // we always leave S_WAIT_BUSY), so this state
                    // usually just falls through in one cycle. Keeping
                    // it explicit means this bridge stays safe even if
                    // it's ever paired with a UART core that behaves
                    // a bit differently.
                    if (!uart_tx_busy) begin
                        state <= S_PULSE;
                    end
                end

                // ---------------------------------------------
                S_PULSE: begin
                    // uart_tx_en is high for exactly this cycle.
                    // uart_tx grabs uart_tx_data right now (while its
                    // own FSM is idle) and starts driving uart_tx_busy
                    // high starting next cycle.
                    state <= S_WAIT_BUSY;
                end

                // ---------------------------------------------
                S_WAIT_BUSY: begin
                    if (!uart_tx_busy) begin
                        // that byte (start bit, data, stop bit - all of
                        // it) has fully gone out on the wire
                        if (byte_idx == NUM_BYTES-1) begin
                            // last byte done - word's fully sent
                            state <= S_IDLE;
                        end else begin
                            byte_idx <= byte_idx + 1'b1;
                            state    <= S_WAIT_IDLE;
                        end
                    end
                end

            endcase
        end
    end

endmodule
