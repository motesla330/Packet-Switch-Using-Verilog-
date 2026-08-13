
module packet_to_uart_bridge #(
    parameter DATA_WIDTH   = 64,   
    parameter PAYLOAD_BITS = 8    
)(
    input  wire                     clk,
    input  wire                     rst_n,       
                                                   
    input  wire [DATA_WIDTH-1:0]    port_out_data,
    input  wire                     port_out_valid,
    output wire                     port_out_ready,

    // to uart_tx
    output wire [PAYLOAD_BITS-1:0]  uart_tx_data,
    output wire                     uart_tx_en,     
    input  wire                     uart_tx_busy
);

    localparam integer NUM_BYTES = DATA_WIDTH / PAYLOAD_BITS;
    localparam integer CNT_W     = (NUM_BYTES <= 1) ? 1 : $clog2(NUM_BYTES);

    localparam [1:0] S_IDLE      = 2'd0,  
                      S_WAIT_IDLE = 2'd1,  
                      S_PULSE     = 2'd2, 
                      S_WAIT_BUSY = 2'd3; 

    reg [1:0]              state;
    reg [DATA_WIDTH-1:0]   pkt_reg;
    reg [CNT_W-1:0]        byte_idx;

    assign port_out_ready = (state == S_IDLE);
    assign uart_tx_en     = (state == S_PULSE);
    assign uart_tx_data =
        pkt_reg[ (DATA_WIDTH-1) - (byte_idx*PAYLOAD_BITS) -: PAYLOAD_BITS ];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            pkt_reg  <= {DATA_WIDTH{1'b0}};
            byte_idx <= {CNT_W{1'b0}};
        end else begin
            case (state)

                S_IDLE: begin
                    
                    if (port_out_valid) begin
                        pkt_reg  <= port_out_data;
                        byte_idx <= {CNT_W{1'b0}};
                        state    <= S_WAIT_IDLE;
                    end
                end

                
                S_WAIT_IDLE: begin
        
                    if (!uart_tx_busy) begin
                        state <= S_PULSE;
                    end
                end

                S_PULSE: begin
                   
                    state <= S_WAIT_BUSY;
                end

                S_WAIT_BUSY: begin
                    if (!uart_tx_busy) begin
                     
                        if (byte_idx == NUM_BYTES-1) begin
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
