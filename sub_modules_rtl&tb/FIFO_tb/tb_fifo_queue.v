
`timescale 1ns/1ps

module tb_fifo_queue;

  parameter DATA_WIDTH = 8;
  parameter DEPTH      = 8;

  reg clk;
  reg rst_n;
  reg wr_en;
  reg [DATA_WIDTH-1:0] din;
  reg rd_en;

  wire [DATA_WIDTH-1:0] dout;
  wire full;
  wire empty;

  integer i;

  fifo_queue #(
    .DATA_WIDTH(DATA_WIDTH),
    .DEPTH(DEPTH)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .wr_en(wr_en),
    .din(din),
    .rd_en(rd_en),
    .dout(dout),
    .full(full),
    .empty(empty)
  );

  always
 begin  
 #5 clk = ~clk;
end 

  initial begin

    clk   = 0;
    rst_n = 0;
    wr_en = 0;
    rd_en = 0;
    din   = 8'h00;

    #15;
    rst_n = 1;

    @(posedge clk);
    #1;

    for (i = 0; i < DEPTH; i = i + 1) begin
      wr_en = 1;
      din   = i + 1;
      @(posedge clk);
      #1;
    end

    wr_en = 0;
    din   = 8'h00;

    repeat(5) @(posedge clk);
    #1;

    for (i = 0; i < DEPTH; i = i + 1) begin
      rd_en = 1;
      @(posedge clk);
      #1;
    end

    rd_en = 0;

    repeat(5) @(posedge clk);
    #1;

    wr_en = 1;
    rd_en = 0;
    din   = 8'hAA;

    @(posedge clk);
    #1;

    wr_en = 1;
    rd_en = 1;
    din   = 8'hBB;

    @(posedge clk);
    #1;

    wr_en = 0;
    rd_en = 1;

    @(posedge clk);
    #1;

    rd_en = 0;

    #40;
    $finish;

  end

endmodule

