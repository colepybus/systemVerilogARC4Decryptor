`timescale 1ps / 1ps

module tb_rtl_task2();

    // Signals connected to the DUT (the board's inputs and outputs)
    logic CLOCK_50;
    logic [1:0] KEY;
    logic [9:0] SW;
    logic [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;
    logic [9:0] LEDR;

    // The module under test: task2 from task2.sv, with init.sv, ksa.sv and s_mem.v inside it
    task2 dut(.CLOCK_50(CLOCK_50), .KEY(KEY), .SW(SW),
              .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2),
              .HEX3(HEX3), .HEX4(HEX4), .HEX5(HEX5), .LEDR(LEDR));

    // The real S memory inside the RAM model (RTL path from the handout)
    `define S_MEM dut.s.altsyncram_component.m_default.altsyncram_inst.mem_data

    // Clock with a 10 ps period
    initial CLOCK_50 = 1'b0;
    always #5 CLOCK_50 = ~CLOCK_50;

    // init takes about 256 cycles and ksa about 1536, so this is a comfortable wait for both
    localparam int RUN_CYCLES = 3000;

    // Expected contents of S after init and then ksa, computed by a software copy of the pseudocode
    logic [7:0] expected [0:255];

    task automatic compute_expected(input logic [23:0] k);
        logic [7:0] kb [0:2];
        logic [7:0] j, tmp;
        kb[0] = k[23:16];   // key is big-endian: key[0] is the top byte
        kb[1] = k[15:8];
        kb[2] = k[7:0];
        for (int i = 0; i < 256; i++) expected[i] = i[7:0];   // init
        j = 8'd0;
        for (int i = 0; i < 256; i++) begin                   // ksa
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

    // Fill S with a junk value, so we can tell whether init and ksa really wrote it
    task automatic fill_junk(input logic [7:0] junk);
        for (int k = 0; k < 256; k++) `S_MEM[k] = junk;
    endtask

    // Compare S against the expected contents and report up to five wrong entries
    task automatic check_S(input string when);
        int bad = 0;
        for (int k = 0; k < 256; k++)
            if (`S_MEM[k][7:0] !== expected[k]) begin
                if (bad < 5) $display("FAIL @%0t: %s: S[%0d] = %h, expected %h", $time, when, k, `S_MEM[k][7:0], expected[k]);
                bad++;
            end
        if (bad > 0) begin
            $display("FAIL @%0t: %s: %0d wrong entries in S", $time, when, bad);
            errors++;
        end
    endtask

    // Press and release the reset button with the switches set to sw, then let init and ksa finish
    task automatic reset_and_run(input logic [9:0] sw);
        SW = sw;
        compute_expected({14'b0, sw});
        KEY[1] = 1'b0;
        repeat (2) @(negedge CLOCK_50);
        KEY[1] = 1'b1;
        repeat (RUN_CYCLES) @(negedge CLOCK_50);
    endtask

    initial begin
        SW  = 10'h33C;
        KEY = 2'b01;    // KEY[1] = 0: hold reset

        // Wait before touching the memory, so we don't race the Altera model's own initial block
        #10;
        fill_junk(8'hAA);

        // Test 1: outputs are off and S is untouched while reset is held
        repeat (3) @(negedge CLOCK_50);
        check(HEX0 === 7'b1111111 && HEX1 === 7'b1111111 && HEX2 === 7'b1111111 &&
              HEX3 === 7'b1111111 && HEX4 === 7'b1111111 && HEX5 === 7'b1111111, "HEX displays should be off");
        check(LEDR === 10'b0, "LEDR should be off");
        check(`S_MEM[0][7:0] === 8'hAA && `S_MEM[255][7:0] === 8'hAA, "S should not be written while reset is held");

        // Test 2: the handout's key (SW = 'h33C), checked in full and against the published first row
        compute_expected(24'h00033C);
        KEY[1] = 1'b1;
        repeat (RUN_CYCLES) @(negedge CLOCK_50);
        check_S("SW = 33C");
        check(`S_MEM[0][7:0] === 8'hb4 && `S_MEM[1][7:0] === 8'h04 && `S_MEM[2][7:0] === 8'h2b &&
              `S_MEM[15][7:0] === 8'h77, "SW = 33C does not match the handout's first row");

        // Test 3: init and ksa each run only once, so nothing writes S afterwards
        fill_junk(8'h55);
        repeat (RUN_CYCLES) @(negedge CLOCK_50);
        check(`S_MEM[0][7:0] === 8'h55 && `S_MEM[128][7:0] === 8'h55 && `S_MEM[255][7:0] === 8'h55,
              "S was written again after init and ksa finished");

        // Test 4: pressing reset re-runs both phases with the current switches
        fill_junk(8'hAA); reset_and_run(10'h018); check_S("SW = 018 after reset");
        fill_junk(8'hAA); reset_and_run(10'h3FF); check_S("SW = 3FF after reset");
        fill_junk(8'hAA); reset_and_run(10'h000); check_S("SW = 000 after reset");

        // Test 5: changing the switches after both phases finished does not change S
        SW = 10'h155;
        repeat (100) @(negedge CLOCK_50);
        check_S("switches changed after finishing");

        // Test 6: asynchronous reset in the middle of ksa, then a full clean run
        fill_junk(8'hAA);
        SW = 10'h33C;
        KEY[1] = 1'b0;
        repeat (2) @(negedge CLOCK_50);
        KEY[1] = 1'b1;
        repeat (800) @(negedge CLOCK_50);   // init done, ksa partway through
        #2 KEY[1] = 1'b0;                   // between clock edges
        repeat (2) @(negedge CLOCK_50);
        KEY[1] = 1'b1;
        compute_expected(24'h00033C);
        repeat (RUN_CYCLES) @(negedge CLOCK_50);
        check_S("after reset in the middle of ksa");

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $stop;
    end

endmodule: tb_rtl_task2
