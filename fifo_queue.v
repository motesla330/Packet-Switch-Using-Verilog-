/*
Author : tesla 

*/


module fifo_queue #(
    parameter DATA_WIDTH = 8, //bits per packet
    parameter DEPTH = 8 // max number of packets in the queue
)
(
    input wire clk ,
    input wire rst_n , // active low reset: 0 = reset, 1 = normal operation

    //write side 
    input wire wr_en,
    input wire [DATA_WIDTH-1:0] din ,

    //read side 
    input wire rd_en,
    output reg [DATA_WIDTH-1:0] dout ,
    // status flag 
    output wire full ,
    output wire empty 

);

// storage array (queue)
reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

// Write pointer — points to next slot to write into
reg[$clog2(DEPTH)-1:0] wr_ptr;

// Read pointer — points to next slot to read from
reg [$clog2(DEPTH)-1:0] rd_ptr;

// Count — how many valid entries are currently stored
reg [$clog2(DEPTH):0] count; // Counts from 0 to DEPTH (inclusive), so width is $clog2(DEPTH)+1$ bits

assign full  = (count == DEPTH);
assign empty = (count == 0);

//The write logic

always @(posedge clk or negedge rst_n)begin

    if(!rst_n)begin
    wr_ptr <=0;

    end else begin
     // Only write if enabled AND there is space
        if (wr_en && !full) begin
                mem[wr_ptr] <= din;          // store data
                wr_ptr <= (wr_ptr + 1) % DEPTH; // wrap around


         end 
    end 
end 
 //The read logic 
 always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= 0;
            dout   <= 0;
        end else begin
            // Only read if enabled AND there is data
            if (rd_en && !empty) begin
                dout   <= mem[rd_ptr];       // output the data
                rd_ptr <= (rd_ptr + 1) % DEPTH;        // advance pointer with wrap-around
            end
        end
    end
always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= 0;
        end else begin
            case ({wr_en && !full, rd_en && !empty})
                2'b10 : count <= count + 1;  // write only
                2'b01 : count <= count - 1;  // read only
                2'b11 : count <= count;      // both — net zero
                default: count <= count;     // neither
            endcase
        end
    end

endmodule 
