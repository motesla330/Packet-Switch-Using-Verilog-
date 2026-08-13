
`include "packet_defs.vh"

module packet_switch_top #(
    parameter NUM_PORTS  = 4,
    parameter DATA_WIDTH = 64,
    parameter FIFO_DEPTH = 16
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // External input — one per port
    input  wire [DATA_WIDTH*NUM_PORTS-1:0]  port_in_data_flat,
    input  wire [NUM_PORTS-1:0]   port_in_valid,
    output wire [NUM_PORTS-1:0]   port_in_ready,  // back-pressure: 1 = accept

    // External output — one per port 
    output wire [DATA_WIDTH*NUM_PORTS-1:0]  port_out_data_flat,
    output wire [NUM_PORTS-1:0]   port_out_valid,
    input  wire [NUM_PORTS-1:0]   port_out_ready, // downstream ready

    // Control plane — routing table update port
    input  wire                   rt_wr_en,
    input  wire [3:0]             rt_wr_addr,
    input  wire [1:0]             rt_wr_port,
    input  wire                   rt_wr_valid
);


    // Internal wires — glue between modules
   

    wire [DATA_WIDTH-1:0] port_in_data  [0:NUM_PORTS-1];
    wire [DATA_WIDTH-1:0] port_out_data [0:NUM_PORTS-1];

    genvar f;
    generate
        for (f = 0; f < NUM_PORTS; f = f + 1) begin : io_flatten_glue
            assign port_in_data[f] = port_in_data_flat[(f+1)*DATA_WIDTH-1 -: DATA_WIDTH];
            assign port_out_data_flat[(f+1)*DATA_WIDTH-1 -: DATA_WIDTH] = port_out_data[f];
        end
    endgenerate

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

    
    wire [1:0] xbar_sel [0:NUM_PORTS-1];
    genvar s;
    generate
        for (s = 0; s < NUM_PORTS; s = s + 1) begin : sel_gen
            assign xbar_sel[s] = routed_port[s];
        end
    endgenerate

    wire [DATA_WIDTH*NUM_PORTS-1:0] fifo_in_dout_flat;
    wire [2*NUM_PORTS-1:0]          xbar_sel_flat;
    wire [DATA_WIDTH*NUM_PORTS-1:0] xbar_out_data_flat;

    genvar x;
    generate
        for (x = 0; x < NUM_PORTS; x = x + 1) begin : xbar_flatten_glue
            assign fifo_in_dout_flat[(x+1)*DATA_WIDTH-1 -: DATA_WIDTH] = fifo_in_dout[x];
            assign xbar_sel_flat[(x+1)*2-1 -: 2]                      = xbar_sel[x];
            assign xbar_out_data[x] = xbar_out_data_flat[(x+1)*DATA_WIDTH-1 -: DATA_WIDTH];
        end
    endgenerate

    crossbar #(
        .NUM_PORTS (NUM_PORTS),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_xbar (
        .clk           (clk),
        .rst_n         (rst_n),
        .in_data_flat  (fifo_in_dout_flat),
        .in_valid      (arb_grant),
        .sel_flat      (xbar_sel_flat),
        .sel_valid     (arb_grant),
        .out_data_flat (xbar_out_data_flat),
        .out_valid     (xbar_out_valid)
    );

endmodule