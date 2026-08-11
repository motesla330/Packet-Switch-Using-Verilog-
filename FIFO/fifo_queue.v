module fifo_queue #(
    parameter DATA_WIDTH = 8, 
    parameter DEPTH = 8 
)
(
    input wire clk ,
    input wire rst_n , 

    
    input wire wr_en,
    input wire [DATA_WIDTH-1:0] din ,


    input wire rd_en,
    output wire [DATA_WIDTH-1:0] dout ,

    output wire full ,
    output wire empty 

);


reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

reg[$clog2(DEPTH)-1:0] wr_ptr;

reg [$clog2(DEPTH)-1:0] rd_ptr;


reg [$clog2(DEPTH):0] count; 

assign full  = (count == DEPTH);
assign empty = (count == 0);



always @(posedge clk or negedge rst_n)begin

    if(!rst_n)begin
    wr_ptr <=0;

    end else begin
     
        if (wr_en && !full) begin
                mem[wr_ptr] <= din;         
                wr_ptr <= (wr_ptr + 1) ; 


         end 
    end 
end 
 
 assign dout = mem[rd_ptr]; 
 
 always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= 0;
        end else begin
            if (rd_en && !empty) begin
                rd_ptr <= (rd_ptr + 1) % DEPTH;       
            end
        end
    end

always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= 0;
        end else begin
            case ({wr_en && !full, rd_en && !empty})
                2'b10 : count <= count + 1;  
                2'b01 : count <= count - 1;   
                2'b11 : count <= count;      
                default: count <= count;    
            endcase
        end
    end

endmodule 