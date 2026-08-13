`timescale 1ns/1ps

`include "packet_defs.vh"

module tb_packet_switch_top;

    // =========================================================
    // Parameters
    // =========================================================
    localparam NUM_PORTS  = 4;
    localparam DATA_WIDTH = 64;

    // =========================================================
    // Clock / Reset
    // =========================================================
    reg clk;
    reg rst_n;

    // =========================================================
    // DUT input
    // Port i occupies:
    // [(i+1)*64-1 -: 64]
    // =========================================================
    reg  [DATA_WIDTH*NUM_PORTS-1:0] port_in_data_flat;
    reg  [NUM_PORTS-1:0]            port_in_valid;
    wire [NUM_PORTS-1:0]            port_in_ready;

    // =========================================================
    // DUT output
    // =========================================================
    wire [DATA_WIDTH*NUM_PORTS-1:0] port_out_data_flat;
    wire [NUM_PORTS-1:0]            port_out_valid;
    reg  [NUM_PORTS-1:0]            port_out_ready;

    // =========================================================
    // Routing table write interface
    // Not needed for these tests because your routing table
    // has default values loaded during reset.
    // =========================================================
    reg        rt_wr_en;
    reg [3:0]  rt_wr_addr;
    reg [1:0]  rt_wr_port;
    reg        rt_wr_valid;

    // =========================================================
    // DUT
    // =========================================================
    packet_switch_top #(
        .NUM_PORTS  (NUM_PORTS),
        .DATA_WIDTH (DATA_WIDTH),
        .FIFO_DEPTH (16)
    ) dut (
        .clk               (clk),
        .rst_n             (rst_n),

        .port_in_data_flat (port_in_data_flat),
        .port_in_valid     (port_in_valid),
        .port_in_ready     (port_in_ready),

        .port_out_data_flat(port_out_data_flat),
        .port_out_valid    (port_out_valid),
        .port_out_ready    (port_out_ready),

        .rt_wr_en          (rt_wr_en),
        .rt_wr_addr        (rt_wr_addr),
        .rt_wr_port        (rt_wr_port),
        .rt_wr_valid       (rt_wr_valid)
    );

    // =========================================================
    // Clock generation
    // =========================================================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =========================================================
    // Test packet generator
    //
    // Packet format:
    // [63:60] destination
    // [59:56] source
    // [55:54] type
    // [53:52] priority
    // [51:48] length
    // [47:0]  payload
    // =========================================================
    function [63:0] make_packet;
        input [3:0]  dst;
        input [3:0]  src;
        input [1:0]  pkt_type;
        input [1:0]  prio;
        input [3:0]  length;
        input [47:0] payload;

        begin
            make_packet = {
                dst,
                src,
                pkt_type,
                prio,
                length,
                payload
            };
        end
    endfunction

    // =========================================================
    // Send one packet and check expected output port/data
    // =========================================================
    task send_and_check;
        input [63:0] packet;
        input [1:0]  expected_port;
        input [63:0] expected_packet;

        integer timeout;
        reg found;

        begin
            found = 1'b0;

            // -------------------------------------------------
            // Put packet on input port 0
            // -------------------------------------------------
            @(posedge clk);

            while (!port_in_ready[0])
                @(posedge clk);

            port_in_data_flat[63:0] = packet;
            port_in_valid[0]        = 1'b1;

            @(posedge clk);

            // Remove valid after one clock
            port_in_valid[0] = 1'b0;
            port_in_data_flat[63:0] = 64'b0;

            // -------------------------------------------------
            // Wait for packet at expected output
            // -------------------------------------------------
            timeout = 0;

            while (!found && timeout < 30) begin

                @(posedge clk);
                #1;

                if (port_out_valid[expected_port]) begin
                    found = 1'b1;

                    if (port_out_data_flat[
                        (expected_port+1)*DATA_WIDTH-1
                        -: DATA_WIDTH
                    ] == expected_packet) begin

                        $display(
                            "[PASS] Packet 0x%016h routed to output port %0d",
                            expected_packet,
                            expected_port
                        );

                    end
                    else begin

                        $display(
                            "[FAIL] Wrong packet at output port %0d. Expected=0x%016h Got=0x%016h",
                            expected_port,
                            expected_packet,
                            port_out_data_flat[
                                (expected_port+1)*DATA_WIDTH-1
                                -: DATA_WIDTH
                            ]
                        );

                    end
                end

                timeout = timeout + 1;
            end

            if (!found) begin
                $display(
                    "[FAIL] Timeout waiting for packet 0x%016h at output port %0d",
                    expected_packet,
                    expected_port
                );
            end

        end
    endtask

task send_two_packets_same_time;
    input [63:0] packet0;          // packet entering input port 0
    input [63:0] packet1;          // packet entering input port 1
    input [1:0]  expected_port0;
    input [1:0]  expected_port1;

    integer timeout;
    reg found0;
    reg found1;

    begin
        found0 = 1'b0;
        found1 = 1'b0;

        // -------------------------------------------------
        // Wait until both input ports are ready
        // -------------------------------------------------
        @(posedge clk);

        while (!(port_in_ready[3] && port_in_ready[1]))
            @(posedge clk);

        // -------------------------------------------------
        // Put packets on input ports 3 and 1 at SAME TIME
        // -------------------------------------------------
        port_in_data_flat[4*DATA_WIDTH-1 -: DATA_WIDTH] = packet0; // input 3
        port_in_data_flat[2*DATA_WIDTH-1 -: DATA_WIDTH] = packet1; // input 1

        port_in_valid[3] = 1'b1;
        port_in_valid[1] = 1'b1;

        @(posedge clk);

        // Remove valid
        port_in_valid[3] = 1'b0;
        port_in_valid[1] = 1'b0;

        port_in_data_flat[4*DATA_WIDTH-1 -: DATA_WIDTH] = 64'b0;
        port_in_data_flat[2*DATA_WIDTH-1 -: DATA_WIDTH] = 64'b0;

        // -------------------------------------------------
        // Wait for both packets at their expected outputs
        // -------------------------------------------------
        timeout = 0;

        while ((!found0 || !found1) && timeout < 30) begin
            @(posedge clk);
            #1;

            // Check packet from input 3
            if (!found0 && port_out_valid[expected_port0]) begin
                if (port_out_data_flat[
                    (expected_port0+1)*DATA_WIDTH-1
                    -: DATA_WIDTH
                ] == packet0) begin

                    $display(
                        "[PASS] Input 3 packet routed to output %0d",
                        expected_port0
                    );

                    found0 = 1'b1;
                end
            end

            // Check packet from input 1
            if (!found1 && port_out_valid[expected_port1]) begin
                if (port_out_data_flat[
                    (expected_port1+1)*DATA_WIDTH-1
                    -: DATA_WIDTH
                ] == packet1) begin

                    $display(
                        "[PASS] Input 1 packet routed to output %0d",
                        expected_port1
                    );

                    found1 = 1'b1;
                end
            end

            timeout = timeout + 1;
        end

        if (!found0)
            $display(
                "[FAIL] Input 3 packet did not reach output %0d",
                expected_port0
            );

        if (!found1)
            $display(
                "[FAIL] Input 1 packet did not reach output %0d",
                expected_port1
            );
    end
endtask
    // =========================================================
    // Main test sequence
    // =========================================================
    initial begin

        // -----------------------------------------------------
        // Initial values
        // -----------------------------------------------------
        port_in_data_flat = 256'b0;
        port_in_valid     = 4'b0000;

        // All outputs ready
        port_out_ready    = 4'b1111;

        // No routing table writes
        rt_wr_en          = 1'b0;
        rt_wr_addr        = 4'b0;
        rt_wr_port        = 2'b0;
        rt_wr_valid       = 1'b0;

        // -----------------------------------------------------
        // Reset
        // -----------------------------------------------------
        rst_n = 1'b0;

        repeat (3)
            @(posedge clk);

        rst_n = 1'b1;

        repeat (2)
            @(posedge clk);

        $display(" Starting Packet Switch Test");
    

        // =====================================================
        // TEST 1
        // Destination = 2
        //
        // Routing table:
        // 0-3   -> output 0
        // =====================================================
        send_and_check(
            make_packet(
                4'd2,                   // destination
                4'd1,                   // source
                `PKT_DATA,              // type
                `PRIO_NORMAL,           // priority
                4'd4,                   // length
                48'h0000_0000_1111      // payload
            ),
            2'd0,
            make_packet(
                4'd2,
                4'd1,
                `PKT_DATA,
                `PRIO_NORMAL,
                4'd4,
                48'h0000_0000_1111
            )
        );

        // =====================================================
        // TEST 2
        // Destination = 6
        //
        // Routing table:
        // 4-7   -> output 1
        // =====================================================
        send_and_check(
            make_packet(
                4'd6,
                4'd0,
                `PKT_DATA,
                `PRIO_HIGH,
                4'd4,
                48'h0000_0000_2222
            ),
            2'd1,
            make_packet(
                4'd6,
                4'd0,
                `PKT_DATA,
                `PRIO_HIGH,
                4'd4,
                48'h0000_0000_2222
            )
        );

        // =====================================================
        // TEST 3
        // Destination = 9
        //
        // Routing table:
        // 8-11  -> output 2
        // =====================================================
        send_and_check(
            make_packet(
                4'd9,
                4'd2,
                `PKT_DATA,
                `PRIO_LOW,
                4'd4,
                48'h0000_0000_3333
            ),
            2'd2,
            make_packet(
                4'd9,
                4'd2,
                `PKT_DATA,
                `PRIO_LOW,
                4'd4,
                48'h0000_0000_3333
            )
        );

        // =====================================================
        // TEST 4
        // Destination = 14
        //
        // Routing table:
        // 12-15 -> output 3
        // =====================================================
        send_and_check(
            make_packet(
                4'd14,
                4'd3,
                `PKT_DATA,
                `PRIO_CRITICAL,
                4'd4,
                48'h0000_0000_4444
            ),
            2'd3,
            make_packet(
                4'd14,
                4'd3,
                `PKT_DATA,
                `PRIO_CRITICAL,
                4'd4,
                48'h0000_0000_4444
            )
        );
// =====================================================
// TEST 5 - Two packets entering at the SAME TIME
//
// Input port 3 -> destination 2 -> output port 0
// Input port 1 -> destination 6 -> output port 1
//
// This tests simultaneous traffic from two inputs.
// =====================================================

send_two_packets_same_time(
    make_packet(
        4'd2,                   // destination -> output 0
        4'd3,                   // source
        `PKT_DATA,
        `PRIO_NORMAL,
        4'd4,
        48'h0000_0000_AAAA
    ),

    make_packet(
        4'd6,                   // destination -> output 1
        4'd1,                   // source
        `PKT_DATA,
        `PRIO_HIGH,
        4'd4,
        48'h0000_0000_BBBB
    ),

    2'd0,                       // expected output for input 3 packet
    2'd1                        // expected output for input 1 packet
);
        // -----------------------------------------------------
        // End simulation
        // -----------------------------------------------------
        $display("==============================================");
        $display(" Testbench Finished");
        $display("==============================================");

        #20;
        $finish;
    end

endmodule
