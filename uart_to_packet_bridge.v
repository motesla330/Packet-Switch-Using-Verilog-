
module uart_to_packet_bridge #(
    parameter DATA_WIDTH   = 64,  
    parameter PAYLOAD_BITS = 8     
)(
    input  wire  clk,
    input  wire  rst_n,        // active-low
	
	
    // from uart_rx
    input  wire [PAYLOAD_BITS-1:0]  uart_rx_data,
    input  wire                     uart_rx_valid,  

    //to the switch's input port
  
    output reg  [DATA_WIDTH-1:0]    port_in_data,
    output reg                      port_in_valid,
    input  wire                     port_in_ready
);

    localparam integer NUM_BYTES = DATA_WIDTH / PAYLOAD_BITS;
    localparam integer CNT_W     = (NUM_BYTES <= 1) ? 1 : $clog2(NUM_BYTES);
  
    localparam STATE_COLLECT = 1'b0;
    localparam STATE_PRESENT = 1'b1;

    reg                     state;
    reg [DATA_WIDTH-1:0]    assemble_reg;
    reg [CNT_W-1:0]         byte_cnt;

    
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

                
                STATE_COLLECT: begin
                    if (uart_rx_valid) begin
                        assemble_reg <= next_assemble;

                        if (byte_cnt == NUM_BYTES-1) begin
                           
                            byte_cnt      <= {CNT_W{1'b0}};
                            port_in_data  <= next_assemble;
                            port_in_valid <= 1'b1;
                            state         <= STATE_PRESENT;
                        end else begin
                            byte_cnt <= byte_cnt + 1'b1;
                        end
                    end
                   
                end

               
                STATE_PRESENT: begin
                    
                    if (port_in_ready) begin
                        port_in_valid <= 1'b0;
                        state         <= STATE_COLLECT;
                    end
                   
                end

            endcase
        end
    end

endmodule
