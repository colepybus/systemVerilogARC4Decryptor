`timescale 1ps / 1ps

module tb_syn_ksa();

    // Signals connected to the DUT
    logic clk, rst_n, en;
    logic rdy, wren;
    logic [23:0] key;
    logic [7:0] addr, rddata, wrdata;

    // The module under test: ksa from ksa.vo (the post-synthesis netlist), not ksa.sv
    ksa dut(.clk(clk), .rst_n(rst_n), .en(en), .rdy(rdy), .key(key),
            .addr(addr), .rddata(rddata), .wrdata(wrdata), .wren(wren));

    // Clock with a 10 ps period
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Model of the S memory with the same timing as s_mem: the address is sampled on the
    // rising edge, the read data appears after that edge, and a write returns the new data
    logic [7:0] S [0:255];
    int num_writes;
    always @(posedge clk) begin
        if (wren) begin
            S[addr] <= wrdata;
            num_writes <= num_writes + 1;
        end
        rddata <= wren ? wrdata : S[addr];
    end

    // Expected contents of S, computed by a software copy of the KSA pseudocode
    logic [7:0] expected [0:255];

    task automatic compute_expected(input logic [23:0] k);
        logic [7:0] kb [0:2];
        logic [7:0] j, tmp;
        kb[0] = k[23:16];   // key is big-endian: key[0] is the top byte
        kb[1] = k[15:8];
        kb[2] = k[7:0];
        j = 8'd0;
        for (int i = 0; i < 256; i++) begin
            j = j + expected[i] + kb[i % 3];
            tmp = expected[i];
            expected[i] = expected[j];
            expected[j] = tmp;
        end
    endtask

    // Error counter and check helper
    int errors = 0;
    task automatic check(input logic cond, input string msg);
        if (!cond) begin
            $display("FAIL @%0t: %s", $time, msg);
            errors++;
        end
    endtask

    // Compare S against the expected contents and report up to five wrong entries
    task automatic check_S(input string when);
        int bad = 0;
        for (int k = 0; k < 256; k++)
            if (S[k] !== expected[k]) begin
                if (bad < 5) $display("FAIL @%0t: %s: S[%0d] = %h, expected %h", $time, when, k, S[k], expected[k]);
                bad++;
            end
        if (bad > 0) begin
            $display("FAIL @%0t: %s: %0d wrong entries in S", $time, when, bad);
            errors++;
        end
    endtask

    // Load S with 0..255, the state init leaves behind
    task automatic load_identity();
        for (int k = 0; k < 256; k++) begin
            S[k] = k[7:0];
            expected[k] = k[7:0];
        end
    endtask

    // One full request: send en with a key for one cycle, then change the key straight away
    // (ksa must capture it when en is accepted), wait for rdy, and check S and the write count
    task automatic run_ksa(input logic [23:0] k, input string name);
        compute_expected(k);
        num_writes = 0;
        @(negedge clk);
        check(rdy === 1'b1, {name, ": rdy should be 1 before the request"});
        key = k;
        en = 1'b1;
        @(negedge clk);
        en = 1'b0;
        key = ~k;
        check(rdy === 1'b0, {name, ": rdy should drop the cycle after en"});
        for (int c = 0; c < 5000 && rdy !== 1'b1; c++) @(negedge clk);
        check(rdy === 1'b1, {name, ": timeout, rdy never returned to 1"});
        check(wren === 1'b0, {name, ": wren should be 0 once finished"});
        check(num_writes == 512, $sformatf("%s: expected 512 writes (2 per i), got %0d", name, num_writes));
        check_S(name);
    endtask

    initial begin
        en = 1'b0;
        key = 24'd0;
        num_writes = 0;
        load_identity();

        // Test 1: reset state is idle, nothing is written before a request
        rst_n = 1'b0;
        #12;
        check(rdy === 1'b1, "rdy should be 1 during reset");
        check(wren === 1'b0, "wren should be 0 during reset");
        rst_n = 1'b1;
        repeat (5) @(negedge clk);
        check(num_writes == 0, "no writes should happen before en");

        // Test 2: the handout's key 'h00033C, checked against the published first row
        run_ksa(24'h00033C, "key 00033C");
        check(S[0] === 8'hb4 && S[1] === 8'h04 && S[2] === 8'h2b && S[3] === 8'he5 &&
              S[12] === 8'h3a && S[15] === 8'h77, "key 00033C does not match the handout's first row");

        // Test 3: nothing is written while idle after a run
        num_writes = 0;
        repeat (50) @(negedge clk);
        check(num_writes == 0, "no writes should happen while idle");

        // Test 4: more keys, each starting from 0..255 (test1 key, test2 key, all ones, all zeros, all three bytes different)
        load_identity(); run_ksa(24'h1E4600, "key 1E4600");
        load_identity(); run_ksa(24'h000018, "key 000018");
        load_identity(); run_ksa(24'hFFFFFF, "key FFFFFF");
        load_identity(); run_ksa(24'h000000, "key 000000");
        load_identity(); run_ksa(24'hA5C301, "key A5C301");

        // Test 5: ksa must use whatever S already holds (it must not re-initialize S),
        // so start from a reversed S, then run again on top of the result
        for (int k = 0; k < 256; k++) begin
            S[k] = 8'(255 - k);
            expected[k] = 8'(255 - k);
        end
        run_ksa(24'h00033C, "reversed starting S");
        run_ksa(24'h123456, "second run on top of the previous result");

        // Test 6: asynchronous reset in the middle of a run returns to idle immediately,
        // and a new request afterwards still works from i = 0, j = 0
        load_identity();
        @(negedge clk); key = 24'h00033C; en = 1'b1; @(negedge clk); en = 1'b0;
        repeat (300) @(negedge clk);
        #2 rst_n = 1'b0;
        #1;
        check(rdy === 1'b1 && wren === 1'b0, "async reset should return ksa to idle immediately");
        @(negedge clk); rst_n = 1'b1;
        load_identity();
        run_ksa(24'h00033C, "run after mid-run reset");

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $stop;
    end

endmodule: tb_syn_ksa
