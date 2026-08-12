// ============================================================
//  tb_packet_switch_top.v
//
//  Bus-level testbench for packet_switch_top -- talks to
//  port_in_data/valid/ready and port_out_data/valid/ready
//  directly, no UART in the loop.
//
//  Why this exists alongside tb_uart_packet_switch_top.v:
//  the UART tb only ever drives BRIDGE_PORT (port 0), one byte
//  every ~10 clock cycles, so a new 64-bit word only lands in
//  port 0's input FIFO once every ~80 cycles. By the time the
//  next word arrives, the switch has had ages to fully drain
//  the previous one, so back-to-back-in-the-FIFO behaviour and
//  multi-port arbitration are never actually exercised. This tb
//  drives all four ports directly at full bus rate instead, so
//  it can push packets back-to-back and simultaneously across
//  ports and see exactly what the arbiter/crossbar do with them.
//
//  Relies on routing_table's power-up defaults (addr 0-3->port0,
//  4-7->port1, 8-11->port2, 12-15->port3) -- no rt_wr needed for
//  any of the tests below.
// ============================================================
`include "packet_defs.vh"
`timescale 1ns/1ns

module tb_packet_switch_top;

    localparam NUM_PORTS  = 4;
    localparam DATA_WIDTH = 64;
    localparam FIFO_DEPTH = 16;

    reg clk;
    reg rst_n;

    reg  [DATA_WIDTH-1:0] port_in_data  [0:NUM_PORTS-1];
    reg  [NUM_PORTS-1:0]  port_in_valid;
    wire [NUM_PORTS-1:0]  port_in_ready;

    wire [DATA_WIDTH-1:0] port_out_data [0:NUM_PORTS-1];
    wire [NUM_PORTS-1:0]  port_out_valid;
    reg  [NUM_PORTS-1:0]  port_out_ready;

    reg        rt_wr_en;
    reg [3:0]  rt_wr_addr;
    reg [1:0]  rt_wr_port;
    reg        rt_wr_valid;

    integer errors;
    integer tests_run;

    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------
    packet_switch_top #(
        .NUM_PORTS (NUM_PORTS),
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .port_in_data  (port_in_data),
        .port_in_valid (port_in_valid),
        .port_in_ready (port_in_ready),
        .port_out_data (port_out_data),
        .port_out_valid(port_out_valid),
        .port_out_ready(port_out_ready),
        .rt_wr_en      (rt_wr_en),
        .rt_wr_addr    (rt_wr_addr),
        .rt_wr_port    (rt_wr_port),
        .rt_wr_valid   (rt_wr_valid)
    );

    // ------------------------------------------------------------
    // Clock
    // ------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk; // 100MHz

    // ------------------------------------------------------------
    // Output capture -- always ready, log every word that comes
    // out of every port along with which cycle it landed on.
    // ------------------------------------------------------------
    reg [DATA_WIDTH-1:0] captured [0:NUM_PORTS-1][0:31];
    integer               captured_count [0:NUM_PORTS-1];
    integer cp;

    always @(posedge clk) begin
        if (!rst_n) begin
            for (cp = 0; cp < NUM_PORTS; cp = cp + 1)
                captured_count[cp] <= 0;
        end else begin
            for (cp = 0; cp < NUM_PORTS; cp = cp + 1) begin
                if (port_out_valid[cp] && port_out_ready[cp]) begin
                    captured[cp][captured_count[cp]] <= port_out_data[cp];
                    captured_count[cp] <= captured_count[cp] + 1;
                end
            end
        end
    end

    // ------------------------------------------------------------
    // Packet field builder -- matches packet_defs.vh layout:
    // [63:60]=dst [59:56]=src [55:54]=type [53:52]=prio [51:48]=len [47:0]=payload
    // ------------------------------------------------------------
    function [63:0] make_pkt;
        input [3:0]  dst;
        input [3:0]  src;
        input [1:0]  typ;
        input [1:0]  prio;
        input [3:0]  len;
        input [47:0] payload;
        begin
            make_pkt = {dst, src, typ, prio, len, payload};
        end
    endfunction

    // ------------------------------------------------------------
    // Drive tasks
    // ------------------------------------------------------------

    // Single-port send: assert valid+data, hold until ready.
    task automatic send_pkt(input integer p, input [63:0] pkt);
        begin
            port_in_data[p]  = pkt;
            port_in_valid[p] = 1'b1;
            @(posedge clk);
            while (!port_in_ready[p]) @(posedge clk);
            port_in_valid[p] = 1'b0;
        end
    endtask

    // Fire the SAME cycle's valid on multiple ports at once, so
    // they genuinely contend for the arbiter/crossbar together
    // (used by the multi-port test below).
    task automatic send_pkt_all4(input [63:0] p0, input [63:0] p1,
                                  input [63:0] p2, input [63:0] p3);
        begin
            port_in_data[0] = p0; port_in_data[1] = p1;
            port_in_data[2] = p2; port_in_data[3] = p3;
            port_in_valid   = 4'b1111;
            @(posedge clk);
            while (port_in_valid & ~port_in_ready) begin
                // drop valid on any port that already got accepted,
                // keep holding the ones that didn't
                port_in_valid = port_in_valid & ~port_in_ready;
                @(posedge clk);
            end
            port_in_valid = 4'b0000;
        end
    endtask

    task automatic wait_for_count(input integer p, input integer count,
                                   input integer max_cycles, output reg timed_out);
        integer waited;
        begin
            waited = 0;
            timed_out = 1'b0;
            while (captured_count[p] < count && waited < max_cycles) begin
                @(posedge clk);
                waited = waited + 1;
            end
            if (captured_count[p] < count) timed_out = 1'b1;
        end
    endtask

    task automatic check(input [63:0] expected, input [63:0] got, input [127:0] label);
        begin
            tests_run = tests_run + 1;
            if (got !== expected) begin
                errors = errors + 1;
                $display("[FAIL] %0s : expected %h, got %h", label, expected, got);
            end else begin
                $display("[PASS] %0s : %h", label, got);
            end
        end
    endtask

    task automatic check_count(input integer p, input integer expected, input [127:0] label);
        begin
            tests_run = tests_run + 1;
            if (captured_count[p] !== expected) begin
                errors = errors + 1;
                $display("[FAIL] %0s : port %0d expected %0d word(s), got %0d",
                          label, p, expected, captured_count[p]);
            end else begin
                $display("[PASS] %0s : port %0d got exactly %0d word(s) as expected",
                          label, p, expected);
            end
        end
    endtask

    // ------------------------------------------------------------
    // Stimulus
    // ------------------------------------------------------------
    reg [63:0] pkt0, pkt1, pkt2, pkt3;
    reg        timed_out;
    integer    i;

    initial begin
        errors    = 0;
        tests_run = 0;
        rst_n     = 1'b0;
        port_in_valid  = 4'b0000;
        port_out_ready = 4'b1111;   // always draining every output port
        rt_wr_en    = 1'b0;
        rt_wr_addr  = 4'b0;
        rt_wr_port  = 2'b0;
        rt_wr_valid = 1'b0;
        for (i = 0; i < NUM_PORTS; i = i + 1) port_in_data[i] = 64'b0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        // ============================================================
        // Test 1: one packet, one port, self-loop (dst=0 -> port0
        // by the routing table's power-up default).
        // ============================================================
        $display("--- Test 1: single packet, port0 -> port0 ---");
        pkt0 = make_pkt(4'd0, 4'd1, `PKT_DATA, `PRIO_NORMAL, 4'd8, 48'hA1B2C3D4E5F6);
        send_pkt(0, pkt0);
        wait_for_count(0, 1, 200, timed_out);
        if (timed_out) begin
            errors = errors + 1;
            $display("[FAIL] Test 1: timed out waiting for the packet at port_out[0] (got %0d/1)",
                      captured_count[0]);
        end else begin
            check(pkt0, captured[0][0], "Test 1 (single packet, port0->port0)");
        end

        // ============================================================
        // Test 2: two packets sent back-to-back into the SAME input
        // port, both routed to port0 (self-loop), with no idle cycle
        // between them -- i.e. the second word is already sitting in
        // port0's input FIFO right behind the first one, exactly the
        // case the UART tb's slow byte pacing can never create.
        // ============================================================
        $display("--- Test 2: two packets back-to-back on port0 ---");
        pkt1 = make_pkt(4'd0, 4'd2, `PKT_DATA, `PRIO_HIGH, 4'd8, 48'h111122223333);
        pkt2 = make_pkt(4'd0, 4'd3, `PKT_DATA, `PRIO_LOW,  4'd8, 48'hAAAABBBBCCCC);
        send_pkt(0, pkt1);
        send_pkt(0, pkt2);
        wait_for_count(0, 3, 200, timed_out); // 3 = 1 leftover from Test1 + 2 new
        check_count(0, 3, "Test 2 (back-to-back burst word count)");
        if (captured_count[0] >= 3) begin
            check(pkt1, captured[0][1], "Test 2, packet 1 of 2");
            check(pkt2, captured[0][2], "Test 2, packet 2 of 2");
        end

        // ============================================================
        // Test 3: one packet on every input port, launched the same
        // cycle, each headed to a DIFFERENT output port (0->1->2->3->0
        // rotation) -- checks the crossbar pairs the right payload
        // with the right destination under real multi-port contention,
        // not just that data shows up somewhere.
        // ============================================================
        $display("--- Test 3: 4 simultaneous packets, rotated destinations ---");
        for (i = 0; i < NUM_PORTS; i = i + 1) captured_count[i] = 0;
        pkt0 = make_pkt(4'd4,  4'd0, `PKT_DATA, `PRIO_NORMAL, 4'd8, 48'h000000AAAAAA); // port0->port1
        pkt1 = make_pkt(4'd8,  4'd1, `PKT_DATA, `PRIO_NORMAL, 4'd8, 48'h000000BBBBBB); // port1->port2
        pkt2 = make_pkt(4'd12, 4'd2, `PKT_DATA, `PRIO_NORMAL, 4'd8, 48'h000000CCCCCC); // port2->port3
        pkt3 = make_pkt(4'd0,  4'd3, `PKT_DATA, `PRIO_NORMAL, 4'd8, 48'h000000DDDDDD); // port3->port0
        send_pkt_all4(pkt0, pkt1, pkt2, pkt3);

        wait_for_count(1, 1, 300, timed_out);
        if (!timed_out) wait_for_count(2, 1, 300, timed_out);
        if (!timed_out) wait_for_count(3, 1, 300, timed_out);
        if (!timed_out) wait_for_count(0, 1, 300, timed_out);

        if (timed_out) begin
            errors = errors + 1;
            $display("[FAIL] Test 3: timed out (counts: p0=%0d p1=%0d p2=%0d p3=%0d)",
                      captured_count[0], captured_count[1], captured_count[2], captured_count[3]);
        end else begin
            check(pkt0, captured[1][0], "Test 3, port0's packet arriving at port_out[1]");
            check(pkt1, captured[2][0], "Test 3, port1's packet arriving at port_out[2]");
            check(pkt2, captured[3][0], "Test 3, port2's packet arriving at port_out[3]");
            check(pkt3, captured[0][0], "Test 3, port3's packet arriving at port_out[0]");
        end

        // ---------------- summary ----------------
        $display("=====================================");
        $display(" TEST SUMMARY: %0d checks run, %0d failed", tests_run, errors);
        if (errors == 0) $display(" RESULT: ALL TESTS PASSED");
        else              $display(" RESULT: FAILURES PRESENT");
        $display("=====================================");
        $finish;
    end

    // Safety net in case something hangs completely.
    initial begin
        #200_000;
        $display("[FAIL] Global watchdog expired -- simulation did not finish");
        $finish;
    end

endmodule
