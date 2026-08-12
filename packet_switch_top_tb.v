`timescale 1ns/1ps

module packet_switch_top_tb #(
    parameter NUM_PORTS  = 4,
    parameter DATA_WIDTH = 64,
    parameter FIFO_DEPTH = 16
);

localparam TOTAL_WIDTH = NUM_PORTS * DATA_WIDTH;

reg clk;
reg rst_n;

reg  [TOTAL_WIDTH-1:0] port_in_data_flat;
reg  [NUM_PORTS-1:0]   port_in_valid;
wire [NUM_PORTS-1:0]   port_in_ready;

wire [TOTAL_WIDTH-1:0] port_out_data_flat;
wire [NUM_PORTS-1:0]   port_out_valid;
reg  [NUM_PORTS-1:0]   port_out_ready;

reg       rt_wr_en;
reg [3:0] rt_wr_addr;
reg [1:0] rt_wr_port;
reg       rt_wr_valid;

integer i;



packet_switch_top #(
    .NUM_PORTS  (NUM_PORTS),
    .DATA_WIDTH (DATA_WIDTH),
    .FIFO_DEPTH (FIFO_DEPTH)
) DUT (
    .clk                (clk),
    .rst_n              (rst_n),

    .port_in_data_flat  (port_in_data_flat),
    .port_in_valid      (port_in_valid),
    .port_in_ready      (port_in_ready),

    .port_out_data_flat (port_out_data_flat),
    .port_out_valid     (port_out_valid),
    .port_out_ready     (port_out_ready),

    .rt_wr_en           (rt_wr_en),
    .rt_wr_addr         (rt_wr_addr),
    .rt_wr_port         (rt_wr_port),
    .rt_wr_valid        (rt_wr_valid)
);


// ============================================================
// CLOCK
// ============================================================

initial begin
    clk = 1'b0;

    forever
        #5 clk = ~clk;
end


// ============================================================
// RESET
// ============================================================

task reset;

begin

    rst_n = 1'b0;

    port_in_data_flat = {TOTAL_WIDTH{1'b0}};
    port_in_valid     = {NUM_PORTS{1'b0}};
    port_out_ready    = {NUM_PORTS{1'b1}};

    rt_wr_en    = 1'b0;
    rt_wr_addr  = 4'b0;
    rt_wr_port  = 2'b0;
    rt_wr_valid = 1'b0;

    #20;

    rst_n = 1'b1;

    $display("[INFO] Reset released.");

end

endtask


// ============================================================
// SEND PACKET
// ============================================================

task send_packet;

input integer input_port;
input [DATA_WIDTH-1:0] packet;

begin

    @(negedge clk);

    port_in_data_flat[
        (input_port+1)*DATA_WIDTH-1 -:
        DATA_WIDTH
    ] = packet;

    port_in_valid[input_port] = 1'b1;

    @(negedge clk);

    while(!port_in_ready[input_port])
        @(negedge clk);

    @(negedge clk);

    port_in_valid[input_port] = 1'b0;

    $display(
        "[SEND] Input %0d -> Packet %h",
        input_port,
        packet
    );

end

endtask


// ============================================================
// CHECK OUTPUT
// ============================================================

task check_output;

input integer output_port;
input [DATA_WIDTH-1:0] expected;

reg [DATA_WIDTH-1:0] actual;

begin

    for(i = 0; i < 50; i = i + 1) begin

        @(posedge clk);

        if(port_out_valid[output_port]) begin

            actual =
                port_out_data_flat[
                    (output_port+1)*DATA_WIDTH-1 -:
                    DATA_WIDTH
                ];

            if(actual === expected)

                $display(
                    "[PASS] Output %0d received %h",
                    output_port,
                    actual
                );

            else

                $display(
                    "[FAIL] Output %0d received %h, expected %h",
                    output_port,
                    actual,
                    expected
                );
			

            @(posedge clk);

            

            i = 50;

        end

    end

end

endtask


// ============================================================
// MAIN TEST
// ============================================================

reg [DATA_WIDTH-1:0] pkt;

initial begin

    reset;

    #10;


    // ----------------------------------------------------------
    // Destination 2 -> Output 0
    // ----------------------------------------------------------

    pkt = 64'h2014_1234_5678_9ABC;

    send_packet(0, pkt);
    check_output(0, pkt);


    // ----------------------------------------------------------
    // Destination 6 -> Output 1
    // ----------------------------------------------------------

    pkt = 64'h6014_1111_2222_3333;

    send_packet(0, pkt);
    check_output(1, pkt);


    // ----------------------------------------------------------
    // Destination 10 -> Output 2
    // ----------------------------------------------------------

    pkt = 64'hA014_AAAA_BBBB_CCCC;

    send_packet(0, pkt);
    check_output(2, pkt);


    // ----------------------------------------------------------
    // Destination 14 -> Output 3
    // ----------------------------------------------------------

    pkt = 64'hE014_DEAD_BEEF_1234;

    send_packet(0, pkt);
    check_output(3, pkt);


    // ----------------------------------------------------------
    // Test all input ports
    // ----------------------------------------------------------

    pkt = 64'h1014_0000_0000_0000;

    send_packet(0, pkt);
    check_output(0, pkt);


    pkt = 64'h5114_1111_1111_1111;

    send_packet(1, pkt);
    check_output(1, pkt);


    pkt = 64'h9214_2222_2222_2222;

    send_packet(2, pkt);
    check_output(2, pkt);


    pkt = 64'hD314_3333_3333_3333;

    send_packet(3, pkt);
    check_output(3, pkt);


    #100;

    $display("");
    $display("======================================");
    $display("TESTBENCH FINISHED");
    $display("======================================");

    $finish;

end

endmodule