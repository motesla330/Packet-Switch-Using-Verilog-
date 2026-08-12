// ============================================================
//  tb_uart_packet_switch_top.v
//
//  Integration-level testbench for uart_packet_switch_top.
//
//  Drives uart_rxd with a bit-accurate serial stream (the way an
//  external device actually would), and monitors uart_txd with a
//  second, independent uart_rx instance acting purely as a
//  reference receiver -- so the test is checking real byte-level
//  UART framing end to end, not just internal bus signals.
//
//  Uses an accelerated CLK_HZ/BIT_RATE pair (10 clocks/bit instead
//  of the ~5208 the default 50MHz/9600baud parameters would need)
//  purely to keep simulation runtime short. The bridge and switch
//  logic being exercised don't change with baud rate -- only how
//  many clock edges the UART core waits between bit samples does.
// ============================================================
`include "packet_defs.vh"
`timescale 1ns/1ns

module tb_uart_packet_switch_top;

    // Accelerated UART timing for simulation: 1MHz clock,
    // 100kbps -> exactly 10 clock cycles per UART bit.
    localparam TB_CLK_HZ   = 1_000_000;
    localparam TB_BIT_RATE = 100_000;
    localparam CYCLES_PER_BIT = TB_CLK_HZ / TB_BIT_RATE; // = 10

    reg clk;
    reg rst_n;
    reg  uart_rxd;
    wire uart_txd;

    reg        rt_wr_en;
    reg [3:0]  rt_wr_addr;
    reg [1:0]  rt_wr_port;
    reg        rt_wr_valid;

    integer errors;
    integer tests_run;

    // ------------------------------------------------------------
    // Device under test
    // ------------------------------------------------------------
    uart_packet_switch_top #(
        .CLK_HZ     (TB_CLK_HZ),
        .BIT_RATE   (TB_BIT_RATE),
        .BRIDGE_PORT(0)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .uart_rxd   (uart_rxd),
        .uart_txd   (uart_txd),
        .rt_wr_en   (rt_wr_en),
        .rt_wr_addr (rt_wr_addr),
        .rt_wr_port (rt_wr_port),
        .rt_wr_valid(rt_wr_valid)
    );

    // ------------------------------------------------------------
    // Reference receiver: an independent uart_rx instance whose
    // only job is to decode whatever comes back out on uart_txd,
    // so the test verifies real UART framing rather than peeking
    // at internal bridge signals.
    // ------------------------------------------------------------
    wire [7:0] mon_rx_data;
    wire       mon_rx_valid;

    uart_rx #(
        .BIT_RATE(TB_BIT_RATE), .PAYLOAD_BITS(8), .CLK_HZ(TB_CLK_HZ)
    ) monitor_rx (
        .clk          (clk),
        .resetn       (rst_n),
        .uart_rxd     (uart_txd),
        .uart_rx_en   (1'b1),
        .uart_rx_break(),
        .uart_rx_valid(mon_rx_valid),
        .uart_rx_data (mon_rx_data)
    );

    // Captured bytes from the monitor, most-recent-appended.
    reg [7:0] captured [0:63];
    integer   captured_count;

    always @(posedge clk) begin
        if (!rst_n) begin
            captured_count <= 0;
        end else if (mon_rx_valid) begin
            captured[captured_count] <= mon_rx_data;
            captured_count <= captured_count + 1;
        end
    end

    // ------------------------------------------------------------
    // Clock
    // ------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk; // 100MHz sim clock -- unrelated to
                           // TB_CLK_HZ, which only sets how many
                           // of these edges make up one UART bit

    // ------------------------------------------------------------
    // Bit/byte/packet level UART drive tasks
    // ------------------------------------------------------------
    task automatic send_bit(input b);
        integer k;
        begin
            uart_rxd = b;
            for (k = 0; k < CYCLES_PER_BIT; k = k + 1) @(posedge clk);
        end
    endtask

    // One full UART byte frame: start bit, 8 data bits LSB-first
    // (matching uart_tx/uart_rx's own shift convention), stop bit.
    task automatic send_byte(input [7:0] data);
        integer k;
        begin
            send_bit(1'b0);
            for (k = 0; k < 8; k = k + 1) send_bit(data[k]);
            send_bit(1'b1);
        end
    endtask

    // One full packet: 8 bytes, most-significant byte first, per
    // the byte-ordering convention the bridge modules use.
    task automatic send_packet(input [63:0] pkt);
        begin
            send_byte(pkt[63:56]);
            send_byte(pkt[55:48]);
            send_byte(pkt[47:40]);
            send_byte(pkt[39:32]);
            send_byte(pkt[31:24]);
            send_byte(pkt[23:16]);
            send_byte(pkt[15:8]);
            send_byte(pkt[7:0]);
        end
    endtask

    // Writes one routing_table entry through the switch's control
    // plane. Only port 0 is writable (packet_switch_top.v), which
    // is also BRIDGE_PORT here, so this is the only route source
    // the UART-attached port will ever see.
    task automatic write_route(input [3:0] addr, input [1:0] out_port);
        begin
            @(posedge clk);
            rt_wr_en    = 1'b1;
            rt_wr_addr  = addr;
            rt_wr_port  = out_port;
            rt_wr_valid = 1'b1;
            @(posedge clk);
            rt_wr_en    = 1'b0;
            rt_wr_valid = 1'b0;
        end
    endtask

    // Blocks until `count` bytes have been captured by the monitor
    // receiver, or the cycle budget runs out. Bounding the wait
    // keeps a genuine hang (lost/stuck packet) from running forever
    // instead of failing the test.
    task automatic wait_for_bytes(input integer count, input integer max_cycles, output reg timed_out);
        integer waited;
        begin
            waited = 0;
            timed_out = 1'b0;
            while (captured_count < count && waited < max_cycles) begin
                @(posedge clk);
                waited = waited + 1;
            end
            if (captured_count < count) timed_out = 1'b1;
        end
    endtask

    task automatic check_packet(input [63:0] expected, input integer base_idx, input [127:0] label);
        reg [63:0] got;
        begin
            got = { captured[base_idx],   captured[base_idx+1],
                    captured[base_idx+2], captured[base_idx+3],
                    captured[base_idx+4], captured[base_idx+5],
                    captured[base_idx+6], captured[base_idx+7] };
            tests_run = tests_run + 1;
            if (got !== expected) begin
                errors = errors + 1;
                $display("[FAIL] %0s : expected %h, got %h", label, expected, got);
            end else begin
                $display("[PASS] %0s : %h round-tripped correctly", label, got);
            end
        end
    endtask

    // ------------------------------------------------------------
    // Stimulus
    // ------------------------------------------------------------
    reg [63:0] pkt_a, pkt_b, pkt_unrouted;
    reg        timed_out;

    initial begin
        errors     = 0;
        tests_run  = 0;
        uart_rxd   = 1'b1;   // idle line is high
        rt_wr_en    = 1'b0;
        rt_wr_addr  = 4'b0;
        rt_wr_port  = 2'b0;
        rt_wr_valid = 1'b0;
        rst_n      = 1'b0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        // Loopback route: destination address 0 -> port 0 (the
        // only port wired to the UART). Nothing can be routed
        // anywhere until this is written -- see the "empty
        // routing table on reset" limitation in the report.
        write_route(4'd0, 2'd0);
        repeat (5) @(posedge clk);

        // ---------------- Test 1: single packet ----------------
        pkt_a = { 4'd0, 4'd1, `PKT_DATA, `PRIO_NORMAL, 4'd8, 48'hA1B2C3D4E5F6 };
        //         DST=0  SRC=1  TYPE=DATA  PRIO=NORMAL  LEN=8  PAYLOAD
        $display("--- Test 1: single packet, dst=0 (routed to self) ---");
        send_packet(pkt_a);
        wait_for_bytes(8, 5000, timed_out);
        if (timed_out) begin
            errors = errors + 1;
            $display("[FAIL] Test 1: timed out waiting for packet to return (only %0d/8 bytes captured)", captured_count);
        end else begin
            check_packet(pkt_a, 0, "Test 1 (single packet)");
        end

        // ---------------- Test 2: back-to-back packets ----------------
        // Sent one right after the other with no extra gap beyond
        // normal UART framing, to exercise consecutive-packet
        // handling through the bridge and the switch fabric.
        $display("--- Test 2: two back-to-back packets ---");
        pkt_a = { 4'd0, 4'd2, `PKT_DATA, `PRIO_HIGH,   4'd8, 48'h1111_2222_3333 };
        pkt_b = { 4'd0, 4'd3, `PKT_DATA, `PRIO_LOW,    4'd8, 48'hAAAA_BBBB_CCCC };
        captured_count = 0;
        send_packet(pkt_a);
        send_packet(pkt_b);
        wait_for_bytes(16, 10000, timed_out);
        if (timed_out) begin
            errors = errors + 1;
            $display("[FAIL] Test 2: timed out (only %0d/16 bytes captured)", captured_count);
        end else begin
            check_packet(pkt_a, 0, "Test 2, packet 1 of 2");
            check_packet(pkt_b, 8, "Test 2, packet 2 of 2");
        end

        // ---------------- Test 3: reset mid-transmission ----------------
        // Interrupts a packet partway through, then confirms the
        // system comes back to a clean, working state afterward --
        // not that the interrupted packet itself is recoverable
        // (it isn't, by design; see the no-resync limitation).
        $display("--- Test 3: reset partway through a packet, then verify recovery ---");
        captured_count = 0;
        fork
            begin
                pkt_unrouted = { 4'd0, 4'd4, `PKT_DATA, `PRIO_NORMAL, 4'd8, 48'hDEAD_0000_0000 };
                send_packet(pkt_unrouted);
            end
            begin
                repeat (250) @(posedge clk); // partway into the 3rd/8th byte
                rst_n = 1'b0;
                repeat (5) @(posedge clk);
                rst_n = 1'b1;
            end
        join

        uart_rxd = 1'b1; // release the line the interrupted task left mid-frame

        // Give uart_rx a full byte period of idle line to fall back
        // to FSM_IDLE on its own before trusting the line again --
        // otherwise it may still be hunting for the tail of the
        // interrupted frame when Test 3's real packet starts, which
        // would corrupt that packet's first byte for reasons that
        // have nothing to do with the RTL under test.
        repeat (15 * CYCLES_PER_BIT) @(posedge clk);
        write_route(4'd0, 2'd0); // routing table was cleared by the reset
        repeat (5) @(posedge clk);

        pkt_a = { 4'd0, 4'd5, `PKT_DATA, `PRIO_CRITICAL, 4'd8, 48'h5A5A_5A5A_5A5A };
        captured_count = 0;
        send_packet(pkt_a);
        wait_for_bytes(8, 5000, timed_out);
        if (timed_out) begin
            errors = errors + 1;
            $display("[FAIL] Test 3: system did not recover cleanly after mid-packet reset");
        end else begin
            check_packet(pkt_a, 0, "Test 3 (post-reset recovery packet)");
        end

        // ---------------- Test 4: unrouted destination ----------------
        // Destination address 7 has no routing_table entry, so this
        // packet is expected to sit in the input FIFO and never be
        // forwarded -- this is documented, existing behaviour
        // (see "routing table starts empty" in the report), not a
        // new fix, and this test exists to confirm nothing comes
        // out rather than something coming out wrong.
        $display("--- Test 4: destination with no routing entry (expect silence) ---");
        captured_count = 0;
        send_packet({ 4'd7, 4'd1, `PKT_DATA, `PRIO_NORMAL, 4'd8, 48'h0 });
        repeat (2000) @(posedge clk);
        tests_run = tests_run + 1;
        if (captured_count != 0) begin
            errors = errors + 1;
            $display("[FAIL] Test 4: expected no output for an unrouted destination, got %0d bytes", captured_count);
        end else begin
            $display("[PASS] Test 4: unrouted packet correctly produced no output");
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
        #2_000_000;
        $display("[FAIL] Global watchdog expired -- simulation did not finish");
        $finish;
    end

endmodule
