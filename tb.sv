module tb;
    localparam int DEPTH  = 8;
    localparam int AE_MAX = 2;   // almost_empty when 1..AE_MAX entries
    localparam int AF_MIN = 5;   // almost_full  when AF_MIN..DEPTH-1 entries

    logic       clk = 0, reset_n = 0, write_en = 0, read_en = 0;
    logic [7:0] write_data = 0, read_data;
    logic       full, empty, almost_full, almost_empty, overflow, underflow;

    synchronous_FIFO dut (.*);

    always #5 clk = ~clk;

    // ------------------------------------------------------------
    // Reference model + checker
    // ------------------------------------------------------------
    logic [7:0] q[$];
    logic [7:0] exp_data;
    logic [7:0] last_rd;
    bit         rd_pending;
    int         errors = 0;
    int         ign_wr = 0, ign_rd = 0;
    int         seen_af = 0, seen_ae = 0, seen_ov = 0, seen_un = 0;

    // Posedge: update model, and check the combinational flags
    // (inputs are stable, DUT flops haven't updated yet in this region).
    always @(posedge clk) begin
        rd_pending = 0;
        if (!reset_n) begin
            q.delete();
        end else begin
            bit wr_ok, rd_ok, exp_ov, exp_un;
            wr_ok  = write_en && (q.size() < DEPTH);
            rd_ok  = read_en  && (q.size() > 0);
            exp_ov = write_en && (q.size() == DEPTH);
            exp_un = read_en  && (q.size() == 0);

            if (overflow !== exp_ov) begin
                errors++;
                $error("%0t: overflow=%b expected %b (occupancy %0d, write_en=%b)",
                       $time, overflow, exp_ov, q.size(), write_en);
            end
            if (underflow !== exp_un) begin
                errors++;
                $error("%0t: underflow=%b expected %b (occupancy %0d, read_en=%b)",
                       $time, underflow, exp_un, q.size(), read_en);
            end
            if (exp_ov) seen_ov++;
            if (exp_un) seen_un++;

            if (write_en && !wr_ok) ign_wr++;
            if (read_en  && !rd_ok) ign_rd++;
            if (rd_ok) begin
                exp_data   = q.pop_front();
                rd_pending = 1;
            end
            if (wr_ok) q.push_back(write_data);
        end
    end

    // Negedge: state-based checks
    always @(negedge clk) begin
        if (!reset_n) begin
            last_rd = 8'd0;
        end else begin
            bit exp_af, exp_ae;
            exp_af = (q.size() >= AF_MIN) && (q.size() < DEPTH);
            exp_ae = (q.size() >= 1)      && (q.size() <= AE_MAX);

            if (full !== (q.size() == DEPTH)) begin
                errors++;
                $error("%0t: full=%b but model has %0d entries", $time, full, q.size());
            end
            if (empty !== (q.size() == 0)) begin
                errors++;
                $error("%0t: empty=%b but model has %0d entries", $time, empty, q.size());
            end
            if (almost_full !== exp_af) begin
                errors++;
                $error("%0t: almost_full=%b expected %b (occupancy %0d)", $time, almost_full, exp_af, q.size());
            end
            if (almost_empty !== exp_ae) begin
                errors++;
                $error("%0t: almost_empty=%b expected %b (occupancy %0d)", $time, almost_empty, exp_ae, q.size());
            end
            if (exp_af) seen_af++;
            if (exp_ae) seen_ae++;

            if (rd_pending) begin
                if (read_data !== exp_data) begin
                    errors++;
                    $error("%0t: read_data=%h expected %h", $time, read_data, exp_data);
                end
                last_rd = read_data;
            end else if (read_data !== last_rd) begin
                errors++;
                $error("%0t: read_data changed to %h without a valid read", $time, read_data);
            end

            if (errors > 0) begin
                $display("FIRST FAILURE at %0t, stopping", $time);
                $finish;
            end
        end
    end

    // ------------------------------------------------------------
    // Stimulus helpers (driven at negedge)
    // ------------------------------------------------------------
    task automatic cycle(input bit we, input bit re, input logic [7:0] d);
        write_en   = we;
        read_en    = re;
        write_data = d;
        @(negedge clk);
    endtask

    task automatic idle(input int n = 1);
        repeat (n) cycle(0, 0, 8'h00);
    endtask

    task automatic do_reset();
        reset_n = 0; write_en = 0; read_en = 0;
        repeat (2) @(negedge clk);
        reset_n = 1;
        @(negedge clk);
    endtask

    // ------------------------------------------------------------
    // Tests
    // ------------------------------------------------------------
    initial begin
        repeat (3) @(negedge clk);
        reset_n = 1;
        @(negedge clk);

        // ---- Test 1: light traffic, low occupancy (almost_empty region) ----
        $display("Test 1: normal writes/reads, low occupancy");
        cycle(1, 0, 8'h11);
        cycle(1, 0, 8'h22);
        cycle(1, 0, 8'h33);
        cycle(0, 1, 0);
        cycle(0, 1, 0);
        cycle(1, 0, 8'h44);
        cycle(0, 1, 0);
        idle(2);                       // 8'h44 still inside

        // ---- Test 2: fill step by step, then keep writing ----
        // checker verifies empty/almost_empty/normal/almost_full/full at each occupancy
        $display("Test 2: fill to full, extra writes -> overflow pulses, data ignored");
        while (q.size() < DEPTH) cycle(1, 0, 8'hA0 + q.size());
        repeat (3) cycle(1, 0, 8'hE0);           // overflow must pulse each cycle
        idle(2);                                  // overflow must drop again

        // ---- Test 3: drain step by step, then keep reading ----
        $display("Test 3: drain to empty, extra reads -> underflow pulses, read_data holds");
        while (q.size() > 0) cycle(0, 1, 0);
        repeat (3) cycle(0, 1, 0);               // underflow must pulse each cycle
        idle(2);

        // ---- Test 4a: write + read same cycle while FULL ----
        $display("Test 4a: simultaneous write+read when full (overflow=1, read goes through)");
        while (q.size() < DEPTH) cycle(1, 0, 8'hC0 + q.size());
        cycle(1, 1, 8'hF1);            // write blocked, read ok
        idle(1);
        while (q.size() > 0) cycle(0, 1, 0);     // F1 must NOT appear
        idle(1);

        // ---- Test 4b: write + read same cycle while EMPTY ----
        $display("Test 4b: simultaneous write+read when empty (underflow=1, write goes through)");
        cycle(1, 1, 8'hF2);            // write ok, read blocked
        idle(1);
        cycle(0, 1, 0);                // F2 comes out now
        idle(1);

        // ---- Test 4c: write + read same cycle, middle occupancy ----
        $display("Test 4c: simultaneous write+read, normal occupancy");
        cycle(1, 0, 8'h51);
        cycle(1, 0, 8'h52);
        for (int i = 0; i < 6; i++) cycle(1, 1, 8'h60 + i);
        while (q.size() > 0) cycle(0, 1, 0);
        idle(2);

        // ---- Test 4d: hover around the almost_full / full boundary ----
        $display("Test 4d: oscillate around full boundary");
        while (q.size() < DEPTH - 1) cycle(1, 0, 8'h80 + q.size());
        repeat (4) begin
            cycle(1, 0, 8'h90);        // -> full
            cycle(0, 1, 0);            // -> DEPTH-1
        end
        while (q.size() > 0) cycle(0, 1, 0);
        idle(1);

        // ---- Test 4e: hover around the almost_empty / empty boundary ----
        $display("Test 4e: oscillate around empty boundary");
        repeat (4) begin
            cycle(1, 0, 8'h95);        // -> 1
            cycle(0, 1, 0);            // -> empty
        end
        idle(1);

        // ---- Test 5: reset while FIFO holds data ----
        $display("Test 5: reset in the middle of use");
        while (q.size() < DEPTH) cycle(1, 0, 8'h70 + q.size());   // reset while full
        do_reset();
        cycle(0, 1, 0);                // read from empty after reset -> underflow
        cycle(1, 0, 8'h74);
        cycle(0, 1, 0);                // must be 74
        idle(2);

        // ---- Test 6: random traffic ----
        $display("Test 6: random traffic");
        repeat (1000) cycle($urandom_range(99) < 50, $urandom_range(99) < 50, $urandom);
        repeat (1000) cycle($urandom_range(99) < 80, $urandom_range(99) < 20, $urandom);
        repeat (1000) cycle($urandom_range(99) < 20, $urandom_range(99) < 80, $urandom);
        idle(2);

        // ---- coverage sanity: every flag must have actually been exercised ----
        if (seen_af == 0) begin errors++; $error("almost_full never exercised");  end
        if (seen_ae == 0) begin errors++; $error("almost_empty never exercised"); end
        if (seen_ov == 0) begin errors++; $error("overflow never exercised");     end
        if (seen_un == 0) begin errors++; $error("underflow never exercised");    end

        // ---- summary ----
        $display("--------------------------------------------");
        $display("ignored writes (full)  : %0d", ign_wr);
        $display("ignored reads  (empty) : %0d", ign_rd);
        $display("cycles almost_full=%0d almost_empty=%0d overflow=%0d underflow=%0d",
                 seen_af, seen_ae, seen_ov, seen_un);
        if (errors == 0) $display("ALL CHECKS PASSED");
        else             $display("%0d CHECK(S) FAILED", errors);
        $finish;
    end
endmodule