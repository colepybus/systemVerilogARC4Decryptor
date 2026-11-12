`timescale 1ps / 1ps

module tb_rtl_prga();

    // Signals connected to the DUT
    logic clk, rst_n, en;
    logic rdy;
    logic [23:0] key;
    logic [7:0] s_addr, s_rddata, s_wrdata, ct_addr, ct_rddata, pt_addr, pt_rddata, pt_wrdata;
    logic s_wren, pt_wren;

    // The module under test: prga from prga.sv (RTL)
    prga dut(.clk(clk), .rst_n(rst_n), .en(en), .rdy(rdy), .key(key),
             .s_addr(s_addr), .s_rddata(s_rddata), .s_wrdata(s_wrdata), .s_wren(s_wren),
             .ct_addr(ct_addr), .ct_rddata(ct_rddata),
             .pt_addr(pt_addr), .pt_rddata(pt_rddata), .pt_wrdata(pt_wrdata), .pt_wren(pt_wren));

    // Clock with a 10 ps period
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Models of the S, CT and PT memories with the same timing as the generated memories:
    // the address is sampled on the rising edge and the read data appears after that edge
    logic [7:0] S [0:255];
    logic [7:0] CT [0:255];
    logic [7:0] PT [0:255];
    int pt_writes;
    always @(posedge clk) begin
        if (s_wren) S[s_addr] <= s_wrdata;
        s_rddata <= s_wren ? s_wrdata : S[s_addr];
        ct_rddata <= CT[ct_addr];
        if (pt_wren) begin
            PT[pt_addr] <= pt_wrdata;
            pt_writes <= pt_writes + 1;
        end
        pt_rddata <= pt_wren ? pt_wrdata : PT[pt_addr];
    end

    // Expected results, computed by a software copy of the ARC4 pseudocode
    logic [7:0] exp_S [0:255];
    logic [7:0] exp_PT [0:255];

    // S after init and ksa for a key (the state prga starts from), written into the S model
    task automatic load_S_for_key(input logic [23:0] k);
        logic [7:0] kb [0:2];
        logic [7:0] j, tmp;
        kb[0] = k[23:16];   // key is big-endian: key[0] is the top byte
        kb[1] = k[15:8];
        kb[2] = k[7:0];
        for (int i = 0; i < 256; i++) S[i] = i[7:0];
        j = 8'd0;
        for (int i = 0; i < 256; i++) begin
            j = j + S[i] + kb[i % 3];
            tmp = S[i]; S[i] = S[j]; S[j] = tmp;
        end
    endtask

    // Expected PT and final S, starting from whatever S and CT hold right now
    task automatic compute_expected();
        logic [7:0] i, j, tmp;
        for (int x = 0; x < 256; x++) exp_S[x] = S[x];
        i = 8'd0;
        j = 8'd0;
        exp_PT[0] = CT[0];
        for (int k = 1; k <= CT[0]; k++) begin
            i = i + 8'd1;
            j = j + exp_S[i];
            tmp = exp_S[i]; exp_S[i] = exp_S[j]; exp_S[j] = tmp;
            exp_PT[k] = exp_S[8'(exp_S[i] + exp_S[j])] ^ CT[k];
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

    // One full request: compute the expected result, fill PT with a marker value, send en for one cycle,
    // wait for rdy, then check PT, the number of PT writes, untouched PT entries past the message, and S
    task automatic run_prga(input string name);
        int len, bad;
        len = CT[0];
        compute_expected();
        for (int x = 0; x < 256; x++) PT[x] = 8'hEE;
        pt_writes = 0;
        @(negedge clk);
        check(rdy === 1'b1, {name, ": rdy should be 1 before the request"});
        en = 1'b1;
        @(negedge clk);
        en = 1'b0;
        check(rdy === 1'b0, {name, ": rdy should drop the cycle after en"});
        for (int c = 0; c < 5000 && rdy !== 1'b1; c++) @(negedge clk);
        check(rdy === 1'b1, {name, ": timeout, rdy never returned to 1"});
        check(s_wren === 1'b0 && pt_wren === 1'b0, {name, ": write enables should be 0 once finished"});
        check(pt_writes == len + 1, $sformatf("%s: expected %0d PT writes, got %0d", name, len + 1, pt_writes));
        bad = 0;
        for (int x = 0; x <= len; x++)
            if (PT[x] !== exp_PT[x]) begin
                if (bad < 5) $display("FAIL @%0t: %s: PT[%0d] = %h, expected %h", $time, name, x, PT[x], exp_PT[x]);
                bad++;
            end
        for (int x = len + 1; x < 256; x++)
            if (PT[x] !== 8'hEE) bad++;
        for (int x = 0; x < 256; x++)
            if (S[x] !== exp_S[x]) bad++;
        if (bad > 0) begin
            $display("FAIL @%0t: %s: %0d wrong entries in PT or S", $time, name, bad);
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
        check(s_wren === 1'b0 && pt_wren === 1'b0, "write enables should be 0 during reset");
        rst_n = 1'b1;
        repeat (5) @(negedge clk);
        check(pt_writes == 0, "no PT writes should happen before en");

        // Test 2: test1 message with key 'h1E4600 (S prepared as init + ksa would leave it)
        $readmemh("test1.memh", CT);
        load_S_for_key(24'h1E4600);
        run_prga("test1, key 1E4600");

        // Test 3: test2 message with key 'h000018
        $readmemh("test2.memh", CT);
        load_S_for_key(24'h000018);
        run_prga("test2, key 000018");

        // Test 4: empty message: only pt[0] = 0 is written
        for (int x = 0; x < 256; x++) CT[x] = 8'd0;
        load_S_for_key(24'h00033C);
        run_prga("empty message");

        // Test 5: one-byte message
        CT[0] = 8'd1;
        CT[1] = 8'h41;
        load_S_for_key(24'h00033C);
        run_prga("one-byte message");

        // Test 6: longest possible message (255 random bytes)
        CT[0] = 8'd255;
        for (int x = 1; x < 256; x++) CT[x] = 8'($urandom);
        load_S_for_key(24'hA5C3F1);
        run_prga("255-byte message");

        // Test 7: a second run starts again from i = 0, j = 0 on the S left by the first run
        $readmemh("test2.memh", CT);
        run_prga("second run on the previous S");

        // Test 8: asynchronous reset in the middle of a run returns to idle immediately,
        // and a full run afterwards still works
        $readmemh("test1.memh", CT);
        load_S_for_key(24'h1E4600);
        @(negedge clk); en = 1'b1; @(negedge clk); en = 1'b0;
        repeat (200) @(negedge clk);
        #2 rst_n = 1'b0;
        #1;
        check(rdy === 1'b1 && s_wren === 1'b0 && pt_wren === 1'b0, "async reset should return prga to idle immediately");
        @(negedge clk); rst_n = 1'b1;
        load_S_for_key(24'h1E4600);
        run_prga("run after mid-run reset");

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $stop;
    end

endmodule: tb_rtl_prga
