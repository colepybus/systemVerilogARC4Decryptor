`timescale 1ps / 1ps

module tb_syn_arc4();

    // Signals connected to the DUT
    logic clk, rst_n, en;
    logic rdy;
    logic [23:0] key;
    logic [7:0] ct_addr, ct_rddata, pt_addr, pt_rddata, pt_wrdata;
    logic pt_wren;

    // The module under test: arc4 from arc4.vo (the post-synthesis netlist), not arc4.sv
    arc4 dut(.clk(clk), .rst_n(rst_n), .en(en), .rdy(rdy), .key(key),
             .ct_addr(ct_addr), .ct_rddata(ct_rddata),
             .pt_addr(pt_addr), .pt_rddata(pt_rddata), .pt_wrdata(pt_wrdata), .pt_wren(pt_wren));

    // Clock with a 10 ps period
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Models of the CT and PT memories with the same timing as ct_mem and pt_mem
    logic [7:0] CT [0:255];
    logic [7:0] PT [0:255];
    int pt_writes;
    always @(posedge clk) begin
        ct_rddata <= CT[ct_addr];
        if (pt_wren) begin
            PT[pt_addr] <= pt_wrdata;
            pt_writes <= pt_writes + 1;
        end
        pt_rddata <= pt_wren ? pt_wrdata : PT[pt_addr];
    end

    // Expected plaintext, computed by a software copy of init, ksa and prga
    logic [7:0] exp_PT [0:255];

    task automatic compute_expected(input logic [23:0] k);
        logic [7:0] s [0:255];
        logic [7:0] kb [0:2];
        logic [7:0] i, j, tmp;
        kb[0] = k[23:16];   // key is big-endian: key[0] is the top byte
        kb[1] = k[15:8];
        kb[2] = k[7:0];
        for (int x = 0; x < 256; x++) s[x] = x[7:0];             // init
        j = 8'd0;
        for (int x = 0; x < 256; x++) begin                       // ksa
            j = j + s[x] + kb[x % 3];
            tmp = s[x]; s[x] = s[j]; s[j] = tmp;
        end
        i = 8'd0;                                                 // prga
        j = 8'd0;
        exp_PT[0] = CT[0];
        for (int x = 1; x <= CT[0]; x++) begin
            i = i + 8'd1;
            j = j + s[i];
            tmp = s[i]; s[i] = s[j]; s[j] = tmp;
            exp_PT[x] = s[8'(s[i] + s[j])] ^ CT[x];
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

    // One full decryption: send en with the key for one cycle, then change the key straight away
    // (arc4 must capture it), wait for rdy, and check PT, the number of PT writes, and untouched entries
    task automatic run_arc4(input logic [23:0] k, input string name);
        int len, bad;
        len = CT[0];
        compute_expected(k);
        for (int x = 0; x < 256; x++) PT[x] = 8'hEE;
        pt_writes = 0;
        @(negedge clk);
        check(rdy === 1'b1, {name, ": rdy should be 1 before the request"});
        key = k;
        en = 1'b1;
        @(negedge clk);
        en = 1'b0;
        key = ~k;
        check(rdy === 1'b0, {name, ": rdy should drop the cycle after en"});
        for (int c = 0; c < 10000 && rdy !== 1'b1; c++) @(negedge clk);
        check(rdy === 1'b1, {name, ": timeout, rdy never returned to 1"});
        check(pt_wren === 1'b0, {name, ": pt_wren should be 0 once finished"});
        check(pt_writes == len + 1, $sformatf("%s: expected %0d PT writes, got %0d", name, len + 1, pt_writes));
        bad = 0;
        for (int x = 0; x <= len; x++)
            if (PT[x] !== exp_PT[x]) begin
                if (bad < 5) $display("FAIL @%0t: %s: PT[%0d] = %h, expected %h", $time, name, x, PT[x], exp_PT[x]);
                bad++;
            end
        for (int x = len + 1; x < 256; x++)
            if (PT[x] !== 8'hEE) bad++;
        if (bad > 0) begin
            $display("FAIL @%0t: %s: %0d wrong entries in PT", $time, name, bad);
            errors++;
        end
    endtask

    initial begin
        en = 1'b0;
        key = 24'd0;
        pt_writes = 0;
        for (int x = 0; x < 256; x++) CT[x] = 8'd0;

        // Test 1: reset state is idle, nothing is written before a request
        rst_n = 1'b0;
        #12;
        check(rdy === 1'b1, "rdy should be 1 during reset");
        check(pt_wren === 1'b0, "pt_wren should be 0 during reset");
        rst_n = 1'b1;
        repeat (5) @(negedge clk);
        check(pt_writes == 0, "no PT writes should happen before en");

        // Test 2: test1 message with key 'h1E4600 (too big for the switches, so only tested here)
        $readmemh("test1.memh", CT);
        run_arc4(24'h1E4600, "test1, key 1E4600");

        // Test 3: test2 message with key 'h000018 (the board demo)
        $readmemh("test2.memh", CT);
        run_arc4(24'h000018, "test2, key 000018");

        // Test 4: arc4 can be run again and again (Task 4 depends on this): wrong key, then the right one
        run_arc4(24'h000019, "test2, wrong key 000019");
        run_arc4(24'h000018, "test2, key 000018 again");

        // Test 5: empty message and longest message
        for (int x = 0; x < 256; x++) CT[x] = 8'd0;
        run_arc4(24'h00033C, "empty message");
        CT[0] = 8'd255;
        for (int x = 1; x < 256; x++) CT[x] = 8'($urandom);
        run_arc4(24'hA5C3F1, "255-byte message");

        // Test 6: asynchronous reset in the middle of a run returns to idle immediately,
        // and a full run afterwards still works
        $readmemh("test1.memh", CT);
        @(negedge clk); key = 24'h1E4600; en = 1'b1; @(negedge clk); en = 1'b0;
        repeat (1000) @(negedge clk);
        #2 rst_n = 1'b0;
        #1;
        check(rdy === 1'b1 && pt_wren === 1'b0, "async reset should return arc4 to idle immediately");
        @(negedge clk); rst_n = 1'b1;
        run_arc4(24'h1E4600, "run after mid-run reset");

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $stop;
    end

endmodule: tb_syn_arc4
