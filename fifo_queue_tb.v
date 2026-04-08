`timescale 1ns/1ps

module fifo_queue_tb;

parameter DATA_WIDTH = 8;
parameter DEPTH = 8;

// signals
reg clk;
reg rst_n;

reg wr_en;
reg [DATA_WIDTH-1:0] din;

reg rd_en;
wire [DATA_WIDTH-1:0] dout;

wire full;
wire empty;

// Instantiate FIFO
fifo_queue #(
    .DATA_WIDTH(DATA_WIDTH),
    .DEPTH(DEPTH)
) uut (
    .clk(clk),
    .rst_n(rst_n),

    .wr_en(wr_en),
    .din(din),

    .rd_en(rd_en),
    .dout(dout),

    .full(full),
    .empty(empty)
);

/////////////////////
// Clock generation
/////////////////////

always #5 clk = ~clk; // 10ns clock

/////////////////////
// Stimulus
/////////////////////

initial begin

    clk = 0;
    rst_n = 0;
    wr_en = 0;
    rd_en = 0;
    din = 0;

    // Reset
    #20;
    rst_n = 1;

    /////////////////////
    // Write to FIFO
    /////////////////////

    repeat (5) begin
        @(posedge clk);
        wr_en = 1;
        din = din + 1;
    end

    @(posedge clk);
    wr_en = 0;

    /////////////////////
    // Read from FIFO
    /////////////////////

    repeat (5) begin
        @(posedge clk);
        rd_en = 0;
    end

    @(posedge clk);
    rd_en = 0;

    #50;

    $finish;   // End simulation

end

endmodule
