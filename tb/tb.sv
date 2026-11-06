module tb;
    logic       clk = 0, reset_n = 0, write_en = 0, read_en = 0;
    logic [7:0] write_data = 0, read_data;
    logic       full, empty;

    synchronous_FIFO dut (.*);

    always #5 clk = ~clk;

    // ------------------------------------------------------------
    // Reference model + checker
    // ------------------------------------------------------------
    logic [7:0] q[$];            // what the FIFO *should* contain
    logic [7:0] exp_data;        // value the DUT should output after a valid read
    logic [7:0] last_rd;         // previous read_data (it must hold when no valid read happens)
    bit         rd_pending;      // a valid read happened on the last posedge
    int         errors = 0;
    int         ign_wr = 0, ign_rd = 0;   // how many illegal requests we actually threw at it

    // Model: sample at posedge. Decisions use the state BEFORE the edge,
    // exactly like the DUT's full/empty do.
    always @(posedge clk) begin
        rd_pending = 0;
        if (!reset_n) begin
            q.delete();
        end else begin
            bit wr_ok, rd_ok;
            wr_ok = write_en && (q.size() < 4);
            rd_ok = read_en  && (q.size() > 0);
            if (write_en && !wr_ok) ign_wr++;
            if (read_en  && !rd_ok) ign_rd++;
            if (rd_ok) begin
                exp_data   = q.pop_front();
                rd_pending = 1;
            end
            if (wr_ok) q.push_back(write_data);
        end
    end

    // Checker: sample at negedge, when everything has settled.
    always @(negedge clk) begin
        if (!reset_n) begin
            last_rd = 8'd0;
        end else begin
            if (full !== (q.size() == 4)) begin
                errors++;
                $error("%0t: full=%b but model has %0d entries", $time, full, q.size());
            end
            if (empty !== (q.size() == 0)) begin
                errors++;
                $error("%0t: empty=%b but model has %0d entries", $time, empty, q.size());
            end
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

            // <-- NEW: stop at the first failure
            if (errors > 0) begin
                $display("FIRST FAILURE at %0t, stopping", $time);
                $finish;
            end
        end
    end

    // ------------------------------------------------------------
    // Stimulus helpers. Everything is driven at negedge, so there is
    // no race with the DUT sampling at posedge.
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
        // initial reset
        repeat (3) @(negedge clk);
        reset_n = 1;
        @(negedge clk);

        // ---- Test 1: normal traffic, occupancy stays between 1 and 3 ----
        $display("Test 1: normal writes/reads, never full or empty");
        cycle(1, 0, 8'h11);
        cycle(1, 0, 8'h22);
        cycle(1, 0, 8'h33);
        cycle(0, 1, 0);
        cycle(0, 1, 0);
        cycle(1, 0, 8'h44);
        cycle(0, 1, 0);
        idle(2);                       // 8'h44 is still inside

        // ---- Test 2: fill to full, then keep writing ----
        $display("Test 2: write until full, extra writes must be ignored");
        for (int i = 0; i < 3; i++) cycle(1, 0, 8'hA0 + i);   // now full
        for (int i = 0; i < 3; i++) cycle(1, 0, 8'hE0 + i);   // must be ignored
        idle(2);

        // ---- Test 3: drain to empty, then keep reading ----
        $display("Test 3: read until empty, extra reads must not return garbage");
        for (int i = 0; i < 4; i++) cycle(0, 1, 0);           // 44, A0, A1, A2
        for (int i = 0; i < 3; i++) cycle(0, 1, 0);           // empty: read_data must hold
        idle(2);

        // ---- Test 4a: write + read in the same cycle while FULL ----
        $display("Test 4a: simultaneous write+read when full");
        for (int i = 0; i < 4; i++) cycle(1, 0, 8'hC0 + i);   // full
        cycle(1, 1, 8'hF1);            // read goes through, write is blocked (full at the edge)
        idle(1);
        for (int i = 0; i < 4; i++) cycle(0, 1, 0);           // drain; F1 must NOT appear
        idle(1);

        // ---- Test 4b: write + read in the same cycle while EMPTY ----
        $display("Test 4b: simultaneous write+read when empty");
        cycle(1, 1, 8'hF2);            // write goes through, read is blocked (empty at the edge)
        idle(1);
        cycle(0, 1, 0);                // F2 must come out now
        idle(1);

        // ---- Test 4c: write + read in the same cycle in the middle ----
        $display("Test 4c: simultaneous write+read, normal occupancy");
        cycle(1, 0, 8'h51);
        cycle(1, 0, 8'h52);
        for (int i = 0; i < 6; i++) cycle(1, 1, 8'h60 + i);   // occupancy stays at 2
        for (int i = 0; i < 3; i++) cycle(0, 1, 0);           // drain
        idle(2);

        // ---- Test 5: reset while the FIFO holds data ----
        $display("Test 5: reset in the middle of use");
        cycle(1, 0, 8'h71);
        cycle(1, 0, 8'h72);
        cycle(1, 0, 8'h73);
        do_reset();                    // flags must go back to empty
        cycle(0, 1, 0);                // read from empty after reset
        cycle(1, 0, 8'h74);
        cycle(0, 1, 0);                // must be 74, not an old value
        idle(2);

        // ---- Test 6: random traffic (hits wrap-around many times) ----
        $display("Test 6: random traffic");
        repeat (1000) cycle($urandom_range(99) < 50, $urandom_range(99) < 50, $urandom);  // balanced
        repeat (1000) cycle($urandom_range(99) < 80, $urandom_range(99) < 20, $urandom);  // mostly full
        repeat (1000) cycle($urandom_range(99) < 20, $urandom_range(99) < 80, $urandom);  // mostly empty
        idle(2);

        // ---- summary ----
        $display("--------------------------------------------");
        $display("ignored writes (full)  : %0d", ign_wr);
        $display("ignored reads  (empty) : %0d", ign_rd);
        if (errors == 0) $display("ALL CHECKS PASSED");
        else             $display("%0d CHECK(S) FAILED", errors);
        $finish;
    end
endmodule