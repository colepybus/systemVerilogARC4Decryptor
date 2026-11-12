`timescale 1ps / 1ps

module tb_rtl_crack();

    // Signals connected to the DUT
    logic clk, rst_n, en, stop;
    logic rdy, key_valid;
    logic [23:0] key, key_start, key_step;
    logic [7:0] ct_addr, ct_rddata, pt_rd_addr, pt_rd_data;

    // The module under test: crack from crack.sv (Task 5 version), with pt_mem and arc4 inside it
    crack dut(.clk(clk), .rst_n(rst_n), .en(en), .rdy(rdy), .key(key), .key_valid(key_valid),
              .ct_addr(ct_addr), .ct_rddata(ct_rddata),
              .key_start(key_start), .key_step(key_step), .stop(stop),
              .pt_rd_addr(pt_rd_addr), .pt_rd_data(pt_rd_data));

    // The PT memory inside crack (RTL path from the handout)
    `define PT_MEM dut.pt.altsyncram_component.m_default.altsyncram_inst.mem_data

    // Clock with a 10 ps period
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Model of the CT memory with the same timing as ct_mem
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

    // The first key in start, start + step, start + 2*step, ... that gives a readable message
    function automatic logic [23:0] first_readable_key(input logic [23:0] start, input logic [23:0] step);
        for (int n = 0; n < 4096; n++)
            if (decrypt_readable(start + n * step)) return start + n * step;
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

    // Send en (with key_start and key_step) for one cycle; change both straight away, since crack must capture them
    task automatic start_search(input logic [23:0] start, input logic [23:0] step, input string name);
        @(negedge clk);
        check(rdy === 1'b1, {name, ": rdy should be 1 before the request"});
        key_start = start;
        key_step = step;
        en = 1'b1;
        @(negedge clk);
        en = 1'b0;
        key_start = 24'hFFFFFF;
        key_step = 24'd7;
        check(rdy === 1'b0, {name, ": rdy should drop the cycle after en"});
        check(key_valid === 1'b0, {name, ": key_valid should be 0 while searching"});
    endtask

    task automatic wait_rdy(input string name);
        for (int c = 0; c < 2000000 && rdy !== 1'b1; c++) @(negedge clk);
        check(rdy === 1'b1, {name, ": timeout, rdy never returned to 1"});
    endtask

    // Check key_valid, the key, PT inside crack, and reading PT back through pt_rd_addr / pt_rd_data
    task automatic check_found(input logic [23:0] exp_key, input string name);
        int bad;
        logic unused;
        check(key_valid === 1'b1, {name, ": key_valid should be 1"});
        check(key === exp_key, $sformatf("%s: key = %h, expected %h", name, key, exp_key));
        unused = decrypt_readable(exp_key);
        bad = 0;
        for (int x = 0; x <= CT[0]; x++) begin
            if (`PT_MEM[x][7:0] !== ref_PT[x]) bad++;
            pt_rd_addr = x[7:0];
            @(negedge clk);                                 // read data arrives after the next rising edge
            if (pt_rd_data !== ref_PT[x]) bad++;
        end
        if (bad > 0) begin
            $display("FAIL @%0t: %s: %0d wrong PT entries (memory or read port)", $time, name, bad);
            errors++;
        end
    endtask

    // Full search with the given start and step on the message in CT
    task automatic crack_and_check(input logic [23:0] start, input logic [23:0] step, input string name);
        logic [23:0] exp_key;
        exp_key = first_readable_key(start, step);
        start_search(start, step, name);
        wait_rdy(name);
        check_found(exp_key, name);
    endtask

    initial begin
        en = 1'b0;
        stop = 1'b0;
        key_start = 24'd0;
        key_step = 24'd1;
        pt_rd_addr = 8'd0;
        for (int x = 0; x < 256; x++) CT[x] = 8'd0;

        // Test 1: reset state is idle with no key
        rst_n = 1'b0;
        #12;
        check(rdy === 1'b1, "rdy should be 1 during reset");
        check(key_valid === 1'b0, "key_valid should be 0 during reset");
        rst_n = 1'b1;
        repeat (5) @(negedge clk);

        // Test 2: start 0, step 1 behaves exactly like Task 4's crack
        $readmemh("sentence1.memh", CT); crack_and_check(24'd0, 24'd1, "sentence 1, step 1");
        check(key === 24'h000001, "sentence 1 should crack with key 000001");
        $readmemh("sentence2.memh", CT); crack_and_check(24'd0, 24'd1, "sentence 2, step 1");
        check(key === 24'h000007, "sentence 2 should crack with key 000007");
        $readmemh("test2.memh", CT);     crack_and_check(24'd0, 24'd1, "test2, step 1");
        check(key === 24'h000018, "test2 should crack with key 000018");

        // Test 3: the doublecrack settings: even keys (start 0, step 2) and odd keys (start 1, step 2)
        $readmemh("test2.memh", CT);     crack_and_check(24'd0, 24'd2, "test2, even keys");
        check(key === 24'h000018, "test2 should crack with key 000018 on the even core");
        $readmemh("sentence1.memh", CT); crack_and_check(24'd1, 24'd2, "sentence 1, odd keys");
        $readmemh("sentence2.memh", CT); crack_and_check(24'd1, 24'd2, "sentence 2, odd keys");
        make_message(40, 24'h000010);    crack_and_check(24'd0, 24'd2, "even key 000010");

        // Test 4: other starts and steps: start at the key itself, and start 5 with step 3 (5, 8, 11)
        $readmemh("test2.memh", CT);     crack_and_check(24'h000018, 24'd1, "start at 000018");
        make_message(30, 24'h00000B);    crack_and_check(24'd5, 24'd3, "start 5, step 3, key 00000B");

        // Test 5: empty, one-character and longest messages
        CT[0] = 8'd0;                    crack_and_check(24'd0, 24'd1, "empty message");
        check(key === 24'd0, "empty message should crack with key 000000");
        make_message(1, 24'h000003);     crack_and_check(24'd1, 24'd2, "1-character message");
        make_message(255, 24'h000006);   crack_and_check(24'd0, 24'd2, "255-character message");

        // Test 6: stop ends the search straight away with key_valid = 0, and the next search still works
        $readmemh("test2.memh", CT);
        start_search(24'd0, 24'd1, "stopped search");
        repeat (3000) @(negedge clk);
        stop = 1'b1;
        @(negedge clk);
        stop = 1'b0;
        check(rdy === 1'b1 && key_valid === 1'b0, "stop should make crack idle with key_valid = 0");
        crack_and_check(24'd0, 24'd1, "search after a stop");

        // Tests below reach inside crack (key_r) to skip most of the 16 million keys, so they are RTL-only
        // (force/release overrides the register for one cycle; crack keeps the value and counts on from it)
        // Test 7: a large odd key on the odd core
        make_message(20, 24'hABCDEF);
        start_search(24'd1, 24'd2, "large key ABCDEF");
        repeat (100) @(negedge clk);
        force dut.key_r = 24'hABCDED;           // the next key tried is ABCDEF
        @(negedge clk);
        release dut.key_r;
        wait_rdy("large key ABCDEF");
        check_found(24'hABCDEF, "large key ABCDEF");

        // Test 8: no key works: the search stops at the last key it can try without going past FFFFFF
        CT[0] = 8'd200;
        for (int x = 1; x < 256; x++) CT[x] = 8'h00;
        start_search(24'd0, 24'd2, "no key, even core");
        repeat (100) @(negedge clk);
        force dut.key_r = 24'hFFFFFA;           // remaining keys: FFFFFC, FFFFFE
        @(negedge clk);
        release dut.key_r;
        wait_rdy("no key, even core");
        check(key_valid === 1'b0 && key === 24'hFFFFFE, "even core should give up after FFFFFE with key_valid = 0");

        start_search(24'd1, 24'd2, "no key, odd core");
        repeat (100) @(negedge clk);
        force dut.key_r = 24'hFFFFFB;           // remaining keys: FFFFFD, FFFFFF
        @(negedge clk);
        release dut.key_r;
        wait_rdy("no key, odd core");
        check(key_valid === 1'b0 && key === 24'hFFFFFF, "odd core should give up after FFFFFF with key_valid = 0");
        // End of RTL-only tests

        // Test 9: asynchronous reset in the middle of a search returns to idle immediately
        $readmemh("test2.memh", CT);
        start_search(24'd0, 24'd1, "mid-search reset");
        repeat (5000) @(negedge clk);
        #2 rst_n = 1'b0;
        #1;
        check(rdy === 1'b1 && key_valid === 1'b0, "async reset should return crack to idle immediately");
        @(negedge clk); rst_n = 1'b1;
        crack_and_check(24'd0, 24'd1, "test2 after mid-search reset");

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $stop;
    end

endmodule: tb_rtl_crack
