module fifo_queue_new (
    input wire clk,
    input wire rst_n,
    input wire wr_en,
    input wire [63:0] din,
    input wire rd_en,
    output wire [63:0] dout,
    output wire full,
    output wire empty
);

  reg [63:0] mem [0:15];
  reg [3:0] wr_ptr;
  reg [3:0] rd_ptr;
  reg [4:0] count;

  assign full  = (count == 16);
  assign empty = (count == 0);

  assign dout = (empty || !rd_en) ? 64'b0 : mem[rd_ptr];

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr <= 0;
    end else begin
      if (wr_en && !full) begin
        mem[wr_ptr] <= din;
        wr_ptr <= (wr_ptr + 1) % 16;
      end
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_ptr <= 0;
    end else begin
      if (rd_en && !empty) begin
        rd_ptr <= (rd_ptr + 1) % 16;
      end
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      count <= 0;
    end else begin
      case ({wr_en && !full, rd_en && !empty})
        2'b10:   count <= count + 1;
        2'b01:   count <= count - 1;
        default: count <= count;
      endcase
    end
  end

endmodule