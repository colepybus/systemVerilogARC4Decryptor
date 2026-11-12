`timescale 1ps / 1ps

module tb_rtl_task3();

    // Signals connected to the DUT (the board's inputs and outputs)
    logic CLOCK_50;
    logic [1:0] KEY;
    logic [9:0] SW;
    logic [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;
    logic [9:0] LEDR;

    // The module under test: task3 from task3.sv, with ct_mem, pt_mem and arc4 inside it
    task3 dut(.CLOCK_50(CLOCK_50), .KEY(KEY), .SW(SW),
              .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2),
              .HEX3(HEX3), .HEX4(HEX4), .HEX5(HEX5), .LEDR(LEDR));

    // The real CT and PT memories inside the RAM models (RTL paths from the handout)
    `define CT_MEM dut.ct.altsyncram_component.m_default.altsyncram_inst.mem_data
    `define PT_MEM dut.pt.altsyncram_component.m_default.altsyncram_inst.mem_data

    // Clock with a 10 ps period
    initial CLOCK_50 = 1'b0;
    always #5 CLOCK_50 = ~CLOCK_50;

    // init + ksa take about 1800 cycles and prga about 9 per byte, so this covers even a 255-byte message
    localparam int RUN_CYCLES = 6000;

    // Copy of CT taken before a run, and the expected plaintext computed from it
    logic [7:0] ct_copy [0:255];
    logic [7:0] exp_PT [0:255];

    task automatic compute_expected(input logic [23:0] k);
        logic [7:0] s [0:255];
        logic [7:0] kb [0:2];
        logic [7:0] i, j, tmp;
        for (int x = 0; x < 256; x++) ct_copy[x] = `CT_MEM[x][7:0];
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
        exp_PT[0] = ct_copy[0];
        for (int x = 1; x <= ct_copy[0]; x++) begin
            i = i + 8'd1;
            j = j + s[i];
            tmp = s[i]; s[i] = s[j]; s[j] = tmp;
            exp_PT[x] = s[8'(s[i] + s[j])] ^ ct_copy[x];
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

    // Fill PT with a marker value, so we can tell exactly which entries were written
    task automatic fill_PT(input logic [7:0] junk);
        for (int x = 0; x < 256; x++) `PT_MEM[x] = junk;
    endtask

    // Check PT against the expected plaintext, entries past the message are untouched, and CT is unchanged
    task automatic check_PT(input string when);
        int len, bad;
        len = ct_copy[0];
        bad = 0;
        for (int x = 0; x <= len; x++)
            if (`PT_MEM[x][7:0] !== exp_PT[x]) begin
                if (bad < 5) $display("FAIL @%0t: %s: PT[%0d] = %h, expected %h", $time, when, x, `PT_MEM[x][7:0], exp_PT[x]);
                bad++;
            end
        for (int x = len + 1; x < 256; x++)
            if (`PT_MEM[x][7:0] !== 8'hEE) bad++;
        for (int x = 0; x < 256; x++)
            if (`CT_MEM[x][7:0] !== ct_copy[x]) bad++;
        if (bad > 0) begin
            $display("FAIL @%0t: %s: %0d wrong entries in PT or CT", $time, when, bad);
            errors++;
        end
    endtask

    // Press and release the reset button with the switches set to sw, then let the decryption finish
    task automatic reset_and_run(input logic [9:0] sw);
        SW = sw;
        compute_expected({14'b0, sw});
        fill_PT(8'hEE);
        KEY[1] = 1'b0;
        repeat (2) @(negedge CLOCK_50);
        KEY[1] = 1'b1;
        repeat (RUN_CYCLES) @(negedge CLOCK_50);
    endtask

    initial begin
        SW  = 10'h018;
        KEY = 2'b01;    // KEY[1] = 0: hold reset

        // Wait before touching the memories, so we don't race the Altera models' own initial blocks
        #10;

        // Test 1: CT starts with test2 (from test2.mif, 53 characters); outputs are off; PT is untouched during reset
        check(`CT_MEM[0][7:0] === 8'd53 && `CT_MEM[1][7:0] === 8'h56 && `CT_MEM[53][7:0] === 8'h91,
              "CT should be initialized from test2.mif");
        fill_PT(8'hEE);
        compute_expected(24'h000018);
        repeat (3) @(negedge CLOCK_50);
        check(HEX0 === 7'b1111111 && HEX1 === 7'b1111111 && HEX2 === 7'b1111111 &&
              HEX3 === 7'b1111111 && HEX4 === 7'b1111111 && HEX5 === 7'b1111111, "HEX displays should be off");
        check(LEDR === 10'b0, "LEDR should be off");
        check(`PT_MEM[0][7:0] === 8'hEE, "PT should not be written while reset is held");

        // Test 2: the board demo: SW = 'h018 decrypts test2 into PT
        KEY[1] = 1'b1;
        repeat (RUN_CYCLES) @(negedge CLOCK_50);
        check_PT("SW = 018, test2");

        // Test 3: arc4 runs only once, so nothing writes PT afterwards
        fill_PT(8'h55);
        repeat (RUN_CYCLES) @(negedge CLOCK_50);
        check(`PT_MEM[0][7:0] === 8'h55 && `PT_MEM[1][7:0] === 8'h55 && `PT_MEM[255][7:0] === 8'h55,
              "PT was written again after the decryption finished");

        // Test 4: pressing reset runs it again, and a wrong key still writes a length-prefixed result
        reset_and_run(10'h018); check_PT("SW = 018 after reset");
        reset_and_run(10'h019); check_PT("SW = 019 (wrong key)");

        // Test 5: a different message in CT, the largest switch key, and the longest message
        for (int x = 0; x < 256; x++) `CT_MEM[x] = 8'($urandom);
        `CT_MEM[0] = 8'd40;
        reset_and_run(10'h3FF); check_PT("40-byte message, SW = 3FF");
        `CT_MEM[0] = 8'd255;
        reset_and_run(10'h2A5); check_PT("255-byte message, SW = 2A5");
        `CT_MEM[0] = 8'd0;
        reset_and_run(10'h000); check_PT("empty message, SW = 000");

        // Test 6: asynchronous reset in the middle of a run, then a full clean run
        `CT_MEM[0] = 8'd100;
        SW = 10'h0AB;
        KEY[1] = 1'b0;
        repeat (2) @(negedge CLOCK_50);
        KEY[1] = 1'b1;
        repeat (2000) @(negedge CLOCK_50);  // partway through prga
        #2 KEY[1] = 1'b0;                   // between clock edges
        reset_and_run(10'h0AB);
        check_PT("after reset in the middle of a run");

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $stop;
    end

endmodule: tb_rtl_task3
