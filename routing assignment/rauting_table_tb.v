`timescale 1 ns / 1 ps

module routing_table_tb(); // FIXED: Changed 'raiting' to 'routing'

    parameter ADDR_WIDTH = 4;
    parameter PORT_WIDTH = 2;
    
    integer i;

    reg                  clk;
    reg                  rst_n;

    reg [ADDR_WIDTH-1:0] lookup_addr;
    wire [PORT_WIDTH-1:0] lookup_port;
    wire                 lookup_valid;

    reg                  wr_en;
    reg [ADDR_WIDTH-1:0] wr_addr;
    reg [PORT_WIDTH-1:0] wr_port;
    reg                  wr_valid;

    
    routing_table #(
        .ADDR_WIDTH(ADDR_WIDTH), 
        .PORT_WIDTH(PORT_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .lookup_addr(lookup_addr),
        .lookup_port(lookup_port),
        .lookup_valid(lookup_valid),
        .wr_en(wr_en),
        .wr_addr(wr_addr),
        .wr_port(wr_port),
        .wr_valid(wr_valid)   
    );

   
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
        
    initial begin
        $dumpfile("routing_table_tb.vcd");
        $dumpvars(0, routing_table_tb);
    end 
        
    initial begin 
        rst_n       = 1'b0;
        wr_en       = 1'b0;
        wr_addr     = 0;
        wr_port     = 0;
        wr_valid    = 0;
        lookup_addr = 0;
		
        #20;
        rst_n       = 1'b1;
        #10;

        $display("\n=================================");
        $display("   FULL ROUTING TABLE (DEFAULTS) ");
        $display("=================================");
        $display("  ADDR  |  PORT  |  VALID  ");
        $display("---------------------------------");

        
        for (i = 0; i < 16; i = i + 1) begin
            lookup_addr = i;
            @(posedge clk); 
			#10;
            $display("   %2d   |   %2d   |    %b    ", lookup_addr, lookup_port, lookup_valid);
        end

        $display("=================================\n");
		
        
        #50;
        
        
        wr_en   = 1'b1;
        wr_addr = 4'd4; wr_port = 2'b01; wr_valid = 1;
        #10;
        wr_en   = 1'b0;
        lookup_addr = 4'd4;
        #10;
        
        
        wr_en   = 1'b1;
        wr_addr = 4'd15; wr_port = 2'b10; wr_valid = 1;
        #10;
        wr_en   = 1'b0;
        lookup_addr = 4'd15;
        #10;
        
        
        wr_en   = 1'b1;
        wr_addr = 4'd10; wr_port = 2'b00; wr_valid = 0;
        #10;
        wr_en   = 1'b0;
        lookup_addr = 4'd10;
        #10;
        
        
        $display("\n=================================");
        $display("     FULL ROUTING TABLE          ");
        $display("=================================");
        $display("  ADDR  |  PORT  |  VALID  ");
        $display("---------------------------------");

        for (i = 0; i < 16; i = i + 1) begin
            lookup_addr = i;
            #10; 
            $display("   %2d   |   %2d   |    %b    ", lookup_addr, lookup_port, lookup_valid);
        end

        $display("=================================\n");
        
        #50;
        $stop;
    end

endmodule