// ============================================================
//  packet_switch_top.v  — The complete 4-port packet switch
// ============================================================
`include "packet_defs.vh"

module packet_switch_top #(
    parameter NUM_PORTS  = 4,
    parameter DATA_WIDTH = 64,
    parameter FIFO_DEPTH = 16
)(
    input  wire                   clk,
    input  wire rst_n,

    // External input — one per port
    input  wire [DATA_WIDTH-1:0]  port_in_data  [0:NUM_PORTS-1],
    input  wire [NUM_PORTS-1:0]   port_in_valid,
    output wire [NUM_PORTS-1:0]   port_in_ready,  // back-pressure: 1 = accept

    // External output — one per port
    output wire [DATA_WIDTH-1:0]  port_out_data  [0:NUM_PORTS-1],
    output wire [NUM_PORTS-1:0]   port_out_valid,
    input  wire [NUM_PORTS-1:0]   port_out_ready, // downstream ready

    // Control plane — routing table update port
    input  wire                   rt_wr_en,
    input  wire [3:0]             rt_wr_addr,
    input  wire [1:0]             rt_wr_port,
    input  wire                   rt_wr_valid
);

    // =========================================================
    // Internal wires — glue between modules
    // =========================================================

    // Input FIFO outputs
    wire [DATA_WIDTH-1:0]  fifo_in_dout  [0:NUM_PORTS-1];
    wire [NUM_PORTS-1:0]   fifo_in_empty;
    wire [NUM_PORTS-1:0]   fifo_in_full;
    wire [NUM_PORTS-1:0]   fifo_in_rd_en;

    // Header parser outputs (one parser per port)
    wire [3:0]  parsed_dst    [0:NUM_PORTS-1];
    wire [1:0]  parsed_type   [0:NUM_PORTS-1];
    wire [1:0]  parsed_prio   [0:NUM_PORTS-1];
    wire        parsed_valid  [0:NUM_PORTS-1];
    wire        parsed_bcast  [0:NUM_PORTS-1];

    // Routing table outputs
    wire [1:0]  routed_port   [0:NUM_PORTS-1];
    wire        routed_valid  [0:NUM_PORTS-1];

    // Arbiter
    wire [NUM_PORTS-1:0]  arb_req;
    wire [NUM_PORTS-1:0]  arb_grant;
    wire [1:0]            arb_grant_idx;

    // Crossbar outputs
    wire [DATA_WIDTH-1:0] xbar_out_data  [0:NUM_PORTS-1];
    wire [NUM_PORTS-1:0]  xbar_out_valid;

    // Output FIFO outputs
    wire [NUM_PORTS-1:0]  fifo_out_empty;
    wire [NUM_PORTS-1:0]  fifo_out_full;

    // =========================================================
    // Generate block — instantiate one copy per port
    // =========================================================
    // "generate" lets you create N identical instances with
    // a for loop. genvar is a special loop variable for generate.

    genvar p;
    generate
        for (p = 0; p < NUM_PORTS; p = p + 1) begin : per_port

            // ----- Input FIFO -----
            fifo_queue #(
                .DATA_WIDTH(DATA_WIDTH),
                .DEPTH     (FIFO_DEPTH)
            ) u_in_fifo (
                .clk   (clk),
                .rst_n (rst_n),
                .wr_en (port_in_valid[p] && !fifo_in_full[p]),
                .din   (port_in_data[p]),
                .rd_en (fifo_in_rd_en[p]),
                .dout  (fifo_in_dout[p]),
                .full  (fifo_in_full[p]),
                .empty (fifo_in_empty[p])
            );

            // Back-pressure: tell upstream we can't accept if full
            assign port_in_ready[p] = !fifo_in_full[p];

            // ----- Header Parser -----
            header_parser u_parser (
                .packet_in   (fifo_in_dout[p]),
                .valid_in    (!fifo_in_empty[p]),
                .dst_addr    (parsed_dst[p]),
                .pkt_type    (parsed_type[p]),
                .priority    (parsed_prio[p]),
                .is_broadcast(parsed_bcast[p]),
                .is_valid    (parsed_valid[p]),
                // unused ports tied off:
                .src_addr(), .pkt_len(), .payload(),
                .is_data(), .is_ctrl(), .is_drop()
            );

            // ----- Routing Table (shared, but each port has
            //       its own lookup port — possible with proper
            //       multi-port RAM or registered pipelining) -----
            routing_table #(
                .ADDR_WIDTH(4),
                .PORT_WIDTH(2)
            ) u_rt (
                .clk         (clk),
                .rst_n       (rst_n),
                .lookup_addr (parsed_dst[p]),
                .lookup_port (routed_port[p]),
                .lookup_valid(routed_valid[p]),
                // Only port 0's routing table is writable from CPU
                // Others are read-only (tied off)
                .wr_en   (rt_wr_en   && (p == 0)),
                .wr_addr (rt_wr_addr),
                .wr_port (rt_wr_port),
                .wr_valid(rt_wr_valid)
            );

            // Output FIFO
            fifo_queue #(
                .DATA_WIDTH(DATA_WIDTH),
                .DEPTH     (FIFO_DEPTH)
            ) u_out_fifo (
                .clk   (clk),
                .rst_n (rst_n),
                .wr_en (xbar_out_valid[p] && !fifo_out_full[p]),
                .din   (xbar_out_data[p]),
                .rd_en (port_out_ready[p] && !fifo_out_empty[p]),
                .dout  (port_out_data[p]),
                .full  (fifo_out_full[p]),
                .empty (fifo_out_empty[p])
            );

            assign port_out_valid[p] = !fifo_out_empty[p];
        end
    endgenerate

    // =========================================================
    // Arbiter — one instance, looks at all ports
    // =========================================================
    // Request: port wants to send if it has a valid routed packet
    // Broadcast packets are sent from port 0's arbiter slot
    genvar q;
    generate
        for (q = 0; q < NUM_PORTS; q = q + 1) begin : arb_req_gen
            assign arb_req[q] = parsed_valid[q] && routed_valid[q]
                                 && !fifo_in_empty[q];
        end
    endgenerate

    arbiter #(.NUM_PORTS(NUM_PORTS)) u_arb (
        .clk       (clk),
        .rst_n     (rst_n),
        .req       (arb_req),
        .grant     (arb_grant),
        .grant_idx (arb_grant_idx)
    );

    // Pop from the winning input FIFO when granted
    genvar r;
    generate
        for (r = 0; r < NUM_PORTS; r = r + 1) begin : rd_en_gen
            assign fifo_in_rd_en[r] = arb_grant[r];
        end
    endgenerate

    // =========================================================
    // Crossbar — connect granted input to its destination output
    // =========================================================
    // Build sel[] array: for the winning port, sel = routed_port
    wire [1:0] xbar_sel [0:NUM_PORTS-1];
    genvar s;
    generate
        for (s = 0; s < NUM_PORTS; s = s + 1) begin : sel_gen
            assign xbar_sel[s] = routed_port[s];
        end
    endgenerate

    // fifo_in_dout is a PURELY COMBINATIONAL read of the input FIFO
    // (fifo_queue.v: `assign dout = mem[rd_ptr]`, no output register).
    // rd_ptr itself doesn't advance until the clock edge AFTER rd_en
    // was sampled, so during the very cycle arb_grant/rd_en is high,
    // fifo_in_dout is already showing the word that grant refers to.
    // No extra delay is needed (or correct) here: an earlier version
    // of this file registered arb_grant/xbar_sel through one more
    // pipeline stage before handing them to the crossbar, on the
    // theory that fifo_in_dout needed a cycle to "catch up" the way a
    // registered-output FIFO would. It doesn't, so that stage was
    // actively wrong -- by the time the delayed grant/sel arrived,
    // rd_ptr had already moved on to the NEXT word, so the crossbar
    // forwarded the wrong packet's payload paired with the previous
    // packet's route (or, for a single isolated packet with nothing
    // queued behind it, forwarded nothing at all -- the packet was
    // silently dropped). arb_grant and xbar_sel are fed to the
    // crossbar directly, undelayed, below.
    wire [DATA_WIDTH*NUM_PORTS-1:0] fifo_in_dout_flat;
    wire [2*NUM_PORTS-1:0]          xbar_sel_flat;
    genvar u;
    generate
        for (u = 0; u < NUM_PORTS; u = u + 1) begin : flatten_gen
            assign fifo_in_dout_flat[u*DATA_WIDTH +: DATA_WIDTH] = fifo_in_dout[u];
            assign xbar_sel_flat[u*2 +: 2]                       = xbar_sel[u];
        end
    endgenerate

    // Flatten xbar output array into a single bus for the crossbar port
    wire [DATA_WIDTH*NUM_PORTS-1:0] xbar_out_data_flat;
    genvar v;
    generate
        for (v = 0; v < NUM_PORTS; v = v + 1) begin : flatten_xbar_out
            assign xbar_out_data_flat[v*DATA_WIDTH +: DATA_WIDTH] = xbar_out_data[v];
        end
    endgenerate

    crossbar #(
        .NUM_PORTS(NUM_PORTS),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_xbar (
        .clk      (clk),
        .rst_n    (rst_n),
        .in_data_flat (fifo_in_dout_flat),
        .in_valid (arb_grant),
        .sel_flat      (xbar_sel_flat),
        .sel_valid(arb_grant),
        .out_data_flat (xbar_out_data_flat),
        .out_valid(xbar_out_valid)
    );

endmodule