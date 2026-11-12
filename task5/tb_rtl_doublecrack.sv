`timescale 1ps / 1ps

module tb_rtl_doublecrack();

    // Signals connected to the DUT
    logic clk, rst_n, en;
    logic rdy, key_valid;
    logic [23:0] key;
    logic [7:0] ct_addr, ct_rddata;

    // The module under test: doublecrack from doublecrack.sv, with two crack cores and the shared PT inside it
    doublecrack dut(.clk(clk), .rst_n(rst_n), .en(en), .rdy(rdy), .key(key), .key_valid(key_valid),
                    .ct_addr(ct_addr), .ct_rddata(ct_rddata));

    // The shared PT and each core's PT (RTL paths from the handout)
    `define PT_MEM  dut.pt.altsyncram_component.m_default.altsyncram_inst.mem_data
    `define PT1_MEM dut.c1.pt.altsyncram_component.m_default.altsyncram_inst.mem_data
    `define PT2_MEM dut.c2.pt.altsyncram_component.m_default.altsyncram_inst.mem_data

    // Clock with a 10 ps period
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Model of the CT memory with the same timing as ct_mem (doublecrack only gets this one port)
    logic [7:0] CT [0:255];
    always @(posedge clk) ct_rddata <= CT[ct_addr];

    // Software copy of ARC4: decrypts CT with a key into ref_PT and says whether the result is readable
    logic [7:0] ref_PT [0:255];

    function automatic logic decrypt_readable(input logic [23:0] k);
        logic [7:0] s [0:255];
        logic [7:0] kb [0:2];
        logic [7:0] i, j, tmp;
        logic ok;
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
        ok = 1'b1;
        ref_PT[0] = CT[0];
        for (int x = 1; x <= CT[0]; x++) begin
            i = i + 8'd1;
            j = j + s[i];
            tmp = s[i]; s[i] = s[j]; s[j] = tmp;
            ref_PT[x] = s[8'(s[i] + s[j])] ^ CT[x];
            if (ref_PT[x] < 8'h20 || ref_PT[x] > 8'h7E) ok = 1'b0;
        end
        return ok;
    endfunction

    // The key doublecrack should report: both cores move in lock step (one even and one odd key per round),
    // so the winner is found in the first round with a readable key; c1 (the even key) wins a tie
    function automatic logic [23:0] expected_key();
        for (int r = 0; r < 4096; r++) begin
            if (decrypt_readable(2 * r))     return 2 * r;
            if (decrypt_readable(2 * r + 1)) return 2 * r + 1;
        end
        return 24'hFFFFFF;
    endfunction

    // Encrypt a readable message with key k and put it in CT (ARC4 encryption is the same xor as decryption)
    task automatic make_message(input int len, input logic [23:0] k);
        logic unused;
        CT[0] = len[7:0];
        for (int x = 1; x <= len; x++) CT[x] = 8'h20 + 8'($urandom % 95);
        unused = decrypt_readable(k);
        for (int x = 1; x <= len; x++) CT[x] = ref_PT[x];
    endtask

    // Error counter and check helper
    int errors = 0;
    task automatic check(input logic cond, input string msg);
        if (!cond) begin
            $display("FAIL @%0t: %s", $time, msg);
            errors++;
        end
    endtask

    // Send en for one cycle, then wait for rdy and count how many cycles it took
    int cycles;
    task automatic start_and_wait(input string name);
        @(negedge clk);
        check(rdy === 1'b1, {name, ": rdy should be 1 before the request"});
        en = 1'b1;
        @(negedge clk);
        en = 1'b0;
        check(rdy === 1'b0, {name, ": rdy should drop the cycle after en"});
        check(key_valid === 1'b0, {name, ": key_valid should be 0 while searching"});
        for (cycles = 1; cycles < 2000000 && rdy !== 1'b1; cycles++) @(negedge clk);
        check(rdy === 1'b1, {name, ": timeout, rdy never returned to 1"});
    endtask

    // Check key_valid, the key, the shared PT, and the PT of the core that tried that key (even = c1, odd = c2)
    task automatic check_found(input logic [23:0] exp_key, input string name);
        int bad_shared, bad_core;
        logic unused;
        check(key_valid === 1'b1, {name, ": key_valid should be 1"});
        check(key === exp_key, $sformatf("%s: key = %h, expected %h", name, key, exp_key));
        unused = decrypt_readable(exp_key);
        bad_shared = 0;
        bad_core = 0;
        for (int x = 0; x <= CT[0]; x++) begin
            if (`PT_MEM[x][7:0] !== ref_PT[x]) bad_shared++;
            if (exp_key[0] == 1'b0 && `PT1_MEM[x][7:0] !== ref_PT[x]) bad_core++;
            if (exp_key[0] == 1'b1 && `PT2_MEM[x][7:0] !== ref_PT[x]) bad_core++;
        end
        if (bad_shared > 0) begin
            $display("FAIL @%0t: %s: %0d wrong entries in the shared PT", $time, name, bad_shared);
            errors++;
        end
        if (bad_core > 0) begin
            $display("FAIL @%0t: %s: %0d wrong entries in the winning core's PT", $time, name, bad_core);
            errors++;
        end
    endtask

    task automatic crack_and_check(input string name);
        logic [23:0] exp_key;
        exp_key = expected_key();
        start_and_wait(name);
        check_found(exp_key, name);
    endtask

    initial begin
        en = 1'b0;
        for (int x = 0; x < 256; x++) CT[x] = 8'd0;

        // Test 1: reset state is idle with no key
        rst_n = 1'b0;
        #12;
        check(rdy === 1'b1, "rdy should be 1 during reset");
        check(key_valid === 1'b0, "key_valid should be 0 during reset");
        rst_n = 1'b1;
        repeat (5) @(negedge clk);

        // Test 2: test2 (key 000018, even, found by c1); about twice as fast as one crack core:
        // a single crack needs about 57,000 cycles here, so doublecrack must finish in under 60% of that
        $readmemh("test2.memh", CT);
        crack_and_check("test2");
        check(key === 24'h000018, "test2 should crack with key 000018");
        check(cycles < 34000, $sformatf("test2 took %0d cycles; should be under 34000 (about twice as fast as crack)", cycles));

        // Test 3: the two handout sentences (keys 1 and 7, both odd, found by c2)
        $readmemh("sentence1.memh", CT); crack_and_check("sentence 1");
        check(key === 24'h000001, "sentence 1 should crack with key 000001");
        $readmemh("sentence2.memh", CT); crack_and_check("sentence 2");
        check(key === 24'h000007, "sentence 2 should crack with key 000007");

        // Test 4: messages made here with known even and odd keys, a one-character, a 255-character and an empty message
        make_message(50, 24'h00000E);    crack_and_check("even key 00000E");
        make_message(50, 24'h000015);    crack_and_check("odd key 000015");
        make_message(1, 24'h000004);     crack_and_check("1-character message");
        make_message(255, 24'h00000A);   crack_and_check("255-character message");
        CT[0] = 8'd0;                    crack_and_check("empty message");
        check(key === 24'd0, "empty message should crack with key 000000");

        // Test 5: doublecrack can be run again and again
        $readmemh("test2.memh", CT);     crack_and_check("test2 again");

        // Tests below reach inside the crack cores (key_r) to skip most of the 16 million keys, so they are RTL-only
        // (force/release overrides a register for one cycle; the core keeps the value and counts on from it)
        // Test 6: a large odd key: c2 finds it, c1 is stopped, and the shared PT gets c2's plaintext
        make_message(20, 24'hABCDEF);
        @(negedge clk); en = 1'b1; @(negedge clk); en = 1'b0;
        repeat (1000) @(negedge clk);           // past the CT copy, both cores searching
        force dut.c2.key_r = 24'hABCDED;        // c2's next key is ABCDEF
        @(negedge clk);
        release dut.c2.key_r;
        for (cycles = 0; cycles < 2000000 && rdy !== 1'b1; cycles++) @(negedge clk);
        check_found(24'hABCDEF, "large key ABCDEF");
        check(dut.c1.rdy === 1'b1, "c1 should have been stopped once c2 found the key");

        // Test 7: no key works: both cores reach the end of their keys, and doublecrack stops with key_valid = 0
        CT[0] = 8'd200;
        for (int x = 1; x < 256; x++) CT[x] = 8'h00;
        @(negedge clk); en = 1'b1; @(negedge clk); en = 1'b0;
        repeat (1000) @(negedge clk);
        force dut.c1.key_r = 24'hFFFFFA;        // c1 still tries FFFFFC, FFFFFE
        force dut.c2.key_r = 24'hFFFFFB;        // c2 still tries FFFFFD, FFFFFF
        @(negedge clk);
        release dut.c1.key_r;
        release dut.c2.key_r;
        for (cycles = 0; cycles < 2000000 && rdy !== 1'b1; cycles++) @(negedge clk);
        check(rdy === 1'b1, "no-key search should finish");
        check(key_valid === 1'b0, "key_valid should be 0 when no key works");
        // End of RTL-only tests

        // Test 8: asynchronous reset in the middle of a search returns to idle immediately
        $readmemh("test2.memh", CT);
        @(negedge clk); en = 1'b1; @(negedge clk); en = 1'b0;
        repeat (5000) @(negedge clk);
        #2 rst_n = 1'b0;
        #1;
        check(rdy === 1'b1 && key_valid === 1'b0, "async reset should return doublecrack to idle immediately");
        @(negedge clk); rst_n = 1'b1;
        crack_and_check("test2 after mid-search reset");

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $stop;
    end

endmodule: tb_rtl_doublecrack
