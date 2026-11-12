`timescale 1ps / 1ps

module tb_rtl_task5();

    // Signals connected to the DUT (the board's inputs and outputs)
    logic CLOCK_50;
    logic [1:0] KEY;
    logic [9:0] SW;
    logic [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;
    logic [9:0] LEDR;

    // The module under test: task5 from task5.sv, with ct_mem and doublecrack inside it
    task5 dut(.CLOCK_50(CLOCK_50), .KEY(KEY), .SW(SW),
              .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2),
              .HEX3(HEX3), .HEX4(HEX4), .HEX5(HEX5), .LEDR(LEDR));

    // The CT memory, doublecrack's shared PT, and each core's PT (RTL paths from the handout)
    `define CT_MEM  dut.ct.altsyncram_component.m_default.altsyncram_inst.mem_data
    `define PT_MEM  dut.dc.pt.altsyncram_component.m_default.altsyncram_inst.mem_data
    `define PT1_MEM dut.dc.c1.pt.altsyncram_component.m_default.altsyncram_inst.mem_data
    `define PT2_MEM dut.dc.c2.pt.altsyncram_component.m_default.altsyncram_inst.mem_data

    // Clock with a 10 ps period
    initial CLOCK_50 = 1'b0;
    always #5 CLOCK_50 = ~CLOCK_50;

    // Expected seven-segment patterns (active-low, bits g f e d c b a), written out independently of task5.sv
    localparam logic [6:0] BLANK = 7'b1111111;
    localparam logic [6:0] DASH  = 7'b0111111;
    logic [6:0] SEG [0:15];
    initial begin
        SEG[0]  = 7'b1000000; SEG[1]  = 7'b1111001; SEG[2]  = 7'b0100100; SEG[3]  = 7'b0110000;
        SEG[4]  = 7'b0011001; SEG[5]  = 7'b0010010; SEG[6]  = 7'b0000010; SEG[7]  = 7'b1111000;
        SEG[8]  = 7'b0000000; SEG[9]  = 7'b0010000; SEG[10] = 7'b0001000; SEG[11] = 7'b0000011;
        SEG[12] = 7'b1000110; SEG[13] = 7'b0100001; SEG[14] = 7'b0000110; SEG[15] = 7'b0001110;
    end

    // Software copy of ARC4: decrypts CT with a key into ref_PT and says whether the result is readable
    logic [7:0] ref_PT [0:255];

    function automatic logic decrypt_readable(input logic [23:0] k);
        logic [7:0] s [0:255];
        logic [7:0] kb [0:2];
        logic [7:0] i, j, tmp, len;
        logic ok;
        len = `CT_MEM[0][7:0];
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
        ref_PT[0] = len;
        for (int x = 1; x <= len; x++) begin
            i = i + 8'd1;
            j = j + s[i];
            tmp = s[i]; s[i] = s[j]; s[j] = tmp;
            ref_PT[x] = s[8'(s[i] + s[j])] ^ `CT_MEM[x][7:0];
            if (ref_PT[x] < 8'h20 || ref_PT[x] > 8'h7E) ok = 1'b0;
        end
        return ok;
    endfunction

    // The key doublecrack should report: its cores try one even and one odd key per round in lock step,
    // so the winner is the first readable key, with the even key (c1) winning a tie in the same round
    function automatic logic [23:0] first_readable_key();
        for (int r = 0; r < 4096; r++) begin
            if (decrypt_readable(2 * r))     return 2 * r;
            if (decrypt_readable(2 * r + 1)) return 2 * r + 1;
        end
        return 24'hFFFFFF;
    endfunction

    // Load a memh file into the real CT memory
    logic [7:0] file_data [0:255];
    task automatic load_CT(input string f);
        $readmemh(f, file_data);
        for (int x = 0; x < 256; x++) `CT_MEM[x] = file_data[x];
    endtask

    // Encrypt a readable message with key k and put it in CT (ARC4 encryption is the same xor as decryption)
    task automatic make_message(input int len, input logic [23:0] k);
        logic unused;
        `CT_MEM[0] = len[7:0];
        for (int x = 1; x <= len; x++) `CT_MEM[x] = 8'h20 + 8'($urandom % 95);
        unused = decrypt_readable(k);
        for (int x = 1; x <= len; x++) `CT_MEM[x] = ref_PT[x];
    endtask

    // Error counter and check helper
    int errors = 0;
    task automatic check(input logic cond, input string msg);
        if (!cond) begin
            $display("FAIL @%0t: %s", $time, msg);
            errors++;
        end
    endtask

    function automatic logic all_blank();
        return HEX5 === BLANK && HEX4 === BLANK && HEX3 === BLANK &&
               HEX2 === BLANK && HEX1 === BLANK && HEX0 === BLANK;
    endfunction

    // Wait (with a timeout) until the displays stop being blank, which means doublecrack has finished;
    // cycles counts how long that took
    int cycles;
    task automatic wait_for_display();
        for (cycles = 0; cycles < 2000000 && all_blank(); cycles++) @(negedge CLOCK_50);
    endtask

    // The six displays should show key k, HEX5 = top hex digit
    task automatic check_display_key(input logic [23:0] k, input string name);
        check(HEX5 === SEG[k[23:20]] && HEX4 === SEG[k[19:16]] && HEX3 === SEG[k[15:12]] &&
              HEX2 === SEG[k[11:8]]  && HEX1 === SEG[k[7:4]]   && HEX0 === SEG[k[3:0]],
              $sformatf("%s: displays should show %h", name, k));
    endtask

    // The shared PT and the PT of the core that tried key k (even = c1, odd = c2) should both hold the plaintext
    task automatic check_PT(input logic [23:0] k, input string name);
        int bad_shared, bad_core;
        logic unused;
        unused = decrypt_readable(k);
        bad_shared = 0;
        bad_core = 0;
        for (int x = 0; x <= `CT_MEM[0][7:0]; x++) begin
            if (`PT_MEM[x][7:0] !== ref_PT[x]) bad_shared++;
            if (k[0] == 1'b0 && `PT1_MEM[x][7:0] !== ref_PT[x]) bad_core++;
            if (k[0] == 1'b1 && `PT2_MEM[x][7:0] !== ref_PT[x]) bad_core++;
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

    // Press and release reset, check the displays are blank while searching, wait for the result,
    // then check the displays and PT against the first readable key
    task automatic reset_and_crack(input string name);
        logic [23:0] exp_key;
        exp_key = first_readable_key();
        KEY[1] = 1'b0;
        repeat (2) @(negedge CLOCK_50);
        KEY[1] = 1'b1;
        repeat (500) @(negedge CLOCK_50);
        check(all_blank(), {name, ": displays should be blank while searching"});
        wait_for_display();
        check_display_key(exp_key, name);
        check_PT(exp_key, name);
    endtask

    initial begin
        SW  = 10'd0;
        KEY = 2'b01;    // KEY[1] = 0: hold reset

        // Wait before touching the memories, so we don't race the Altera models' own initial blocks
        #10;

        // Test 1: CT starts with test2 (from test2.mif); displays blank and LEDs off during reset
        check(`CT_MEM[0][7:0] === 8'd53 && `CT_MEM[1][7:0] === 8'h56, "CT should be initialized from test2.mif");
        repeat (3) @(negedge CLOCK_50);
        check(all_blank(), "displays should be blank during reset");
        check(LEDR === 10'b0, "LEDR should be off");

        // Test 2: test2 cracks with key 000018 about twice as fast as Task 4 (a single crack needs about
        // 57,000 cycles here); the displays then stay on the key
        reset_and_crack("test2");
        check_display_key(24'h000018, "test2 shows 000018");
        check(cycles + 500 < 34000, $sformatf("test2 took about %0d cycles; should be under 34000", cycles + 500));
        repeat (20000) @(negedge CLOCK_50);
        check_display_key(24'h000018, "display still shows 000018 later");

        // Test 3: reset re-runs the search on whatever CT holds: the two handout sentences
        load_CT("sentence1.memh"); reset_and_crack("sentence 1");
        check_display_key(24'h000001, "sentence 1 shows 000001");
        load_CT("sentence2.memh"); reset_and_crack("sentence 2");
        check_display_key(24'h000007, "sentence 2 shows 000007");

        // Test 4: an empty message cracks with key 000000
        `CT_MEM[0] = 8'd0;
        reset_and_crack("empty message");
        check_display_key(24'h000000, "empty message shows 000000");

        // Tests below reach inside the crack cores (key_r) to skip most of the 16 million keys, so they are RTL-only
        // (force/release overrides a register for one cycle; the core keeps the value and counts on from it).
        // The force happens after 1000 cycles, once doublecrack has copied CT and started both cores.
        // Test 5: keys using every hex digit, so every digit pattern gets shown
        make_message(30, 24'h012345);
        KEY[1] = 1'b0; repeat (2) @(negedge CLOCK_50); KEY[1] = 1'b1;
        repeat (1000) @(negedge CLOCK_50);
        force dut.dc.c2.key_r = 24'h012343;     // c2 (odd keys) tries 012345 next
        @(negedge CLOCK_50);
        release dut.dc.c2.key_r;
        wait_for_display();
        check_display_key(24'h012345, "key 012345");
        check_PT(24'h012345, "key 012345");

        make_message(30, 24'h6789AB);
        KEY[1] = 1'b0; repeat (2) @(negedge CLOCK_50); KEY[1] = 1'b1;
        repeat (1000) @(negedge CLOCK_50);
        force dut.dc.c2.key_r = 24'h6789A9;     // c2 tries 6789AB next
        @(negedge CLOCK_50);
        release dut.dc.c2.key_r;
        wait_for_display();
        check_display_key(24'h6789AB, "key 6789AB");

        make_message(30, 24'hCDEF01);
        KEY[1] = 1'b0; repeat (2) @(negedge CLOCK_50); KEY[1] = 1'b1;
        repeat (1000) @(negedge CLOCK_50);
        force dut.dc.c2.key_r = 24'hCDEEFF;     // c2 tries CDEF01 next
        @(negedge CLOCK_50);
        release dut.dc.c2.key_r;
        wait_for_display();
        check_display_key(24'hCDEF01, "key CDEF01");

        // Test 6: no key works: jump to the end of the key space; all six displays should show a dash
        `CT_MEM[0] = 8'd200;
        for (int x = 1; x < 256; x++) `CT_MEM[x] = 8'h00;
        KEY[1] = 1'b0; repeat (2) @(negedge CLOCK_50); KEY[1] = 1'b1;
        repeat (1000) @(negedge CLOCK_50);
        force dut.dc.c1.key_r = 24'hFFFFFA;     // c1 still tries FFFFFC, FFFFFE
        force dut.dc.c2.key_r = 24'hFFFFFB;     // c2 still tries FFFFFD, FFFFFF
        @(negedge CLOCK_50);
        release dut.dc.c1.key_r;
        release dut.dc.c2.key_r;
        wait_for_display();
        check(HEX5 === DASH && HEX4 === DASH && HEX3 === DASH && HEX2 === DASH && HEX1 === DASH && HEX0 === DASH,
              "displays should show dashes when no key works");
        // End of RTL-only tests

        // Test 7: asynchronous reset in the middle of a search, then a full clean run
        load_CT("test2.memh");
        KEY[1] = 1'b0; repeat (2) @(negedge CLOCK_50); KEY[1] = 1'b1;
        repeat (10000) @(negedge CLOCK_50);
        #2 KEY[1] = 1'b0;
        #1;
        check(all_blank(), "displays should be blank right after reset");
        reset_and_crack("test2 after mid-search reset");
        check_display_key(24'h000018, "test2 after mid-search reset shows 000018");

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $stop;
    end

endmodule: tb_rtl_task5
