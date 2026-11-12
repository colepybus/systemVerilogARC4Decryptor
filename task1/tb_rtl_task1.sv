`timescale 1ps / 1ps

module tb_rtl_task1();

    // signals connected to the DUT (the board's inputs and outputs)
    logic CLOCK_50;
    logic [1:0] KEY;
    logic [9:0] SW;
    logic [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;
    logic [9:0] LEDR;

    // the module under test: task1 from task1.sv, with init.sv and s_mem.v inside it
    task1 dut(.CLOCK_50(CLOCK_50), .KEY(KEY), .SW(SW),
              .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2),
              .HEX3(HEX3), .HEX4(HEX4), .HEX5(HEX5), .LEDR(LEDR));

    // the real S memory inside the RAM model (RTL path from the handout)
    `define S_MEM dut.s.altsyncram_component.m_default.altsyncram_inst.mem_data

    // clock: 10 ps period
    initial CLOCK_50 = 1'b0;
    always #5 CLOCK_50 = ~CLOCK_50;

    // error counter and check helper
    int errors = 0;
    task automatic check(input logic cond, input string msg);
        if (!cond) begin
            $display("FAIL @%0t: %s", $time, msg);
            errors++;
        end
    endtask

    // fill S with a junk value, so we can tell whether init really wrote it
    task automatic fill_junk(input logic [7:0] junk);
        for (int k = 0; k < 256; k++) `S_MEM[k] = junk;
    endtask

    // check that S holds 0..255
    task automatic check_S(input string when);
        int bad = 0;
        for (int k = 0; k < 256; k++)
            if (`S_MEM[k] !== k[7:0]) begin
                if (bad < 5) $display("FAIL @%0t: %s: S[%0d] = %h, expected %h", $time, when, k, `S_MEM[k], k[7:0]);
                bad++;
            end
        if (bad > 0) begin
            $display("FAIL @%0t: %s: %0d wrong entries in S", $time, when, bad);
            errors++;
        end
    endtask

    initial begin
        SW  = 10'b0;
        KEY = 2'b01;              // KEY[1] = 0: hold reset

        // wait before touching the memory, so we don't race the Altera model's own initial block
        #10;
        fill_junk(8'hAA);

        // Test 1: outputs while in reset
        repeat (3) @(negedge CLOCK_50);
        check(HEX0 === 7'b1111111 && HEX5 === 7'b1111111, "HEX displays should be off");
        check(LEDR === 10'b0, "LEDR should be off");
        check(`S_MEM[0] === 8'hAA, "S should not be written while reset is held");

        // Test 2: release reset, init should run once and fill S with 0..255
        KEY[1] = 1'b1;
        repeat (300) @(negedge CLOCK_50);
        check_S("after first run");

        // Test 3: nothing writes S after init finishes
        fill_junk(8'h55);
        repeat (300) @(negedge CLOCK_50);
        check(`S_MEM[0] === 8'h55 && `S_MEM[128] === 8'h55 && `S_MEM[255] === 8'h55,
              "S was written again after init finished");

        // Test 4: pressing reset again re-runs init
        KEY[1] = 1'b0;
        repeat (2) @(negedge CLOCK_50);
        KEY[1] = 1'b1;
        repeat (300) @(negedge CLOCK_50);
        check_S("after second reset");

        // Test 5: reset in the middle of a run, then a full run afterwards
        fill_junk(8'hAA);
        KEY[1] = 1'b0;
        repeat (2) @(negedge CLOCK_50);
        KEY[1] = 1'b1;
        repeat (100) @(negedge CLOCK_50);   // init is only partway through
        #2 KEY[1] = 1'b0;                   // async reset, between clock edges
        repeat (2) @(negedge CLOCK_50);
        KEY[1] = 1'b1;
        repeat (300) @(negedge CLOCK_50);
        check_S("after reset mid-run");

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $stop;
    end

endmodule: tb_rtl_task1