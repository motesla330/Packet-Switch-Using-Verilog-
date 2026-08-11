
//  tb_arbiter.v
//  Testbench for the round-robin arbiter module
//  Written by: Tesla


`timescale 1ns/1ps

module arbiter_tb;

    
    parameter NUM_PORTS  = 4;
    parameter CLK_PERIOD = 10; // 10ns clock = 100MHz

    
    reg                          clk;
    reg                          rst_n;
    reg  [NUM_PORTS-1:0]         req;
    wire [NUM_PORTS-1:0]         grant;
    wire [$clog2(NUM_PORTS)-1:0] grant_idx;

    
    arbiter #(.NUM_PORTS(NUM_PORTS)) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .req       (req),
        .grant     (grant),
        .grant_idx (grant_idx)
    );

   
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    
    initial begin

    

       
        
        rst_n = 0;
        req   = 4'b0000;
        @(posedge clk); #1;
        @(posedge clk); #1;

        // check that grant is zero while in reset
        if (grant == 4'b0000)
            $display("PASS  reset: grant is zero as expected");
        else
            $display("FAIL  reset: grant should be 0000, got %b", grant);

        
        rst_n = 1;
        @(posedge clk); #1;

       
        // test 1: only one port is requesting
    
        $display("\n Test 1: single request from port 2 ");
        req = 4'b0100; // only port 2
        @(posedge clk); #1;

        if (grant == 4'b0100)
            $display("PASS  port 2 got the grant");
        else
            $display("FAIL  expected 0100, got %b", grant);

        req = 4'b0000;
        @(posedge clk); #1;

       
        // Test 2 : all ports request at the same time
        // after reset last_served = 3, so scan starts at 0
    
       
        $display("\n Test 2: all ports requesting, check round-robin order");

        
        rst_n = 0; @(posedge clk); #1; @(posedge clk); #1;
        rst_n = 1; @(posedge clk); #1;

        req = 4'b1111; 

        @(posedge clk); #1;
        $display("cycle 1 -> grant = %b (expected 0001, port 0)", grant);

        @(posedge clk); #1;
        $display("cycle 2 -> grant = %b (expected 0010, port 1)", grant);

        @(posedge clk); #1;
        $display("cycle 3 -> grant = %b (expected 0100, port 2)", grant);

        @(posedge clk); #1;
        $display("cycle 4 -> grant = %b (expected 1000, port 3)", grant);

        @(posedge clk); #1;
        $display("cycle 5 -> grant = %b (expected 0001, wraps to port 0)", grant);

        req = 4'b0000;
        @(posedge clk); #1;

        
        //test 3: no requests at all
        
        $display("\n Test 3: no requests ");
        req = 4'b0000;
        @(posedge clk); #1;
        @(posedge clk); #1;

        if (grant == 4'b0000)
            $display("PASS  grant stayed zero with no requests");
        else
            $display("FAIL  grant should be 0000, got %b", grant);


        // Test 4: two ports requesting
        
        $display("\n Test 4: ports 0 and 3 requesting");
        rst_n = 0; @(posedge clk); #1; @(posedge clk); #1;
        rst_n = 1; @(posedge clk); #1;

        req = 4'b1001; // port 0 and port 3

        @(posedge clk); #1;
        $display("cycle 1 -> grant = %b (expected 0001, port 0)", grant);

        @(posedge clk); #1;
        $display("cycle 2 -> grant = %b (expected 1000, port 3)", grant);

        @(posedge clk); #1;
        $display("cycle 3 -> grant = %b (expected 0001, port 0 again)", grant);

        req = 4'b0000;
        @(posedge clk); #1;


    
        $finish;
    end

endmodule