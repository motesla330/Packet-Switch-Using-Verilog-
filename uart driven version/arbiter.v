
//  arbiter (FSM)   Priority aware round-robin technique
// aouthor:  mohamed mahmoud
// refrence : 

module arbiter #(
    parameter NUM_PORTS = 4
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // One bit per port — 1 means "I have a packet ready"
    input  wire [NUM_PORTS-1:0]  req,

    // One-hot grant signal — exactly one bit set to indicate winner
    // e.g. 4'b0100 means port 2 wins this cycle
    output reg  [NUM_PORTS-1:0]  grant,
    output reg  [$clog2(NUM_PORTS)-1:0] grant_idx  // binary index of winner
);

    // last_served tracks which port we served most recently
    reg [$clog2(NUM_PORTS)-1:0] last_served;

    // Combinational: figure out who wins this cycle
    // We do this in a generate-style integer loop
    integer i, offset;
    reg [NUM_PORTS-1:0]          next_grant;
    reg [$clog2(NUM_PORTS)-1:0]  next_idx;
    reg                          found;

    always @(*) begin
        next_grant = {NUM_PORTS{1'b0}};  // default: nobody wins
        next_idx   = 0;
        found      = 1'b0; // to track if we found a frist winner 
                           // i need it to avoid granting multiple ports in the same cycle 

        // Scan starting from port after last_served
        // The trick: use modulo to wrap around
        for (offset = 1; offset <= NUM_PORTS; offset = offset + 1) begin
            i = (last_served + offset) % NUM_PORTS;

            // Only grant if not already found a winner
            if (!found && req[i]) begin
                next_grant[i] = 1'b1;
                next_idx       = i[($clog2(NUM_PORTS)-1):0];
                found          = 1'b1;
            end
        end
    end

    // Register the result — grant is stable for one full cycle
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            grant       <= {NUM_PORTS{1'b0}};
            grant_idx   <= 0;
            last_served <= NUM_PORTS - 1;
        end else begin
            grant       <= next_grant;
            grant_idx   <= next_idx;
            if (|next_grant)           //  true if any bit set , update last_served 
                last_served <= next_idx;
        end
    end

endmodule