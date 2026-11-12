`timescale 1ps / 1ps

module tb_syn_crack();

    // Signals connected to the DUT
    logic clk, rst_n, en;
    logic rdy, key_valid;
    logic [23:0] key;
    logic [7:0] ct_addr, ct_rddata;

    // The module under test: crack from crack.vo (the post-synthesis netlist), not crack.sv
    crack dut(.clk(clk), .rst_n(rst_n), .en(en), .rdy(rdy), .key(key), .key_valid(key_valid),
              .ct_addr(ct_addr), .ct_rddata(ct_rddata));

    // The PT memory inside the netlist (the cyclonev_ram_block instance in crack.vo).
    // The space before ".ram_core0" is part of the escaped name and must stay.
    // Each entry is 20 bits wide in the M10K block; our 8-bit data is in bits [7:0].
    `define PT_MEM dut.\pt|altsyncram_component|auto_generated|altsyncram1|ram_block3a0 .ram_core0.ram_core0.mem

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

    // The first key, counting up from start, that gives a readable message (searches at most limit keys)
    function automatic logic [23:0] first_readable_key(input logic [23:0] start, input int limit);
        for (int n = 0; n < limit; n++)
            if (decrypt_readable(start + n)) return start + n;
        return 24'hFFFFFF;
    endfunction

    // Encrypt a readable message with key k and put it in CT (ARC4 encryption is the same xor as decryption)
    task automatic make_message(input int len, input logic [23:0] k);
        logic unused;
        CT[0] = len[7:0];
        for (int x = 1; x <= len; x++) CT[x] = 8'h20 + 8'($urandom % 95);   // readable characters
        unused = decrypt_readable(k);                                        // ref_PT[x] = pad ^ plaintext
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

    // Send en for one cycle and wait for rdy (with a timeout)
    task automatic start_and_wait(input string name, input int max_cycles);
        @(negedge clk);
        check(rdy === 1'b1, {name, ": rdy should be 1 before the request"});
        en = 1'b1;
        @(negedge clk);
        en = 1'b0;
        check(rdy === 1'b0, {name, ": rdy should drop the cycle after en"});
        check(key_valid === 1'b0, {name, ": key_valid should be 0 while searching"});
        for (int c = 0; c < max_cycles && rdy !== 1'b1; c++) @(negedge clk);
        check(rdy === 1'b1, {name, ": timeout, rdy never returned to 1"});
    endtask

    // Check the result: key_valid, the key, and the length-prefixed plaintext inside crack's PT
    task automatic check_found(input logic [23:0] exp_key, input string name);
        int bad;
        logic unused;
        check(key_valid === 1'b1, {name, ": key_valid should be 1"});
        check(key === exp_key, $sformatf("%s: key = %h, expected %h", name, key, exp_key));
        unused = decrypt_readable(exp_key);
        bad = 0;
        for (int x = 0; x <= CT[0]; x++)
            if (`PT_MEM[x][7:0] !== ref_PT[x]) bad++;
        if (bad > 0) begin
            $display("FAIL @%0t: %s: %0d wrong entries in PT", $time, name, bad);
            errors++;
        end
    endtask

    // Run crack on the message in CT and check it finds the first readable key at or above 0
    task automatic crack_and_check(input string name);
        logic [23:0] exp_key;
        exp_key = first_readable_key(24'd0, 4096);
        start_and_wait(name, 2000000);
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

        // Test 2: the two handout sentences (keys 1 and 7) and test2 (key 'h18)
        $readmemh("sentence1.memh", CT); crack_and_check("sentence 1");
        check(key === 24'h000001, "sentence 1 should crack with key 000001");
        $readmemh("sentence2.memh", CT); crack_and_check("sentence 2");
        check(key === 24'h000007, "sentence 2 should crack with key 000007");
        $readmemh("test2.memh", CT);     crack_and_check("test2");
        check(key === 24'h000018, "test2 should crack with key 000018");

        // Test 3: a new request clears key_valid and searches again from 0 (crack is re-runnable)
        $readmemh("sentence1.memh", CT); crack_and_check("sentence 1 again");

        // Test 4: messages made here with known keys, including a one-character and a 255-character message
        make_message(1, 24'h000003);   crack_and_check("1-character message");
        make_message(255, 24'h00000C); crack_and_check("255-character message");
        make_message(60, 24'h000021);  crack_and_check("60-character message");

        // Test 5: an empty message has no unreadable characters, so key 0 is accepted straight away
        CT[0] = 8'd0;
        crack_and_check("empty message");
        check(key === 24'd0, "empty message should crack with key 000000");

        // (The large-key and no-key tests jump the search by forcing crack's internal key register,
        //  which does not exist by name in the netlist, so they are only in tb_rtl_crack.)


        // Test 8: asynchronous reset in the middle of a search returns to idle immediately
        $readmemh("test2.memh", CT);
        @(negedge clk); en = 1'b1; @(negedge clk); en = 1'b0;
        repeat (5000) @(negedge clk);
        #2 rst_n = 1'b0;
        #1;
        check(rdy === 1'b1 && key_valid === 1'b0, "async reset should return crack to idle immediately");
        @(negedge clk); rst_n = 1'b1;
        crack_and_check("test2 after mid-search reset");

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $stop;
    end

endmodule: tb_syn_crack
