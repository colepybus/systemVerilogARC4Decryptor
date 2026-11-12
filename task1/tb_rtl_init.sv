`timescale 1ps / 1ps

module tb_rtl_init();

    // signals connected to the DUT
    logic clk, rst_n, en;
    logic rdy, wren;
    logic [7:0] addr, wrdata;

    // the module under test: "init" comes from init.sv (the RTL), since we are testing the source code
    init dut(.clk(clk), .rst_n(rst_n), .en(en), .rdy(rdy),
             .addr(addr), .wrdata(wrdata), .wren(wren));

    // clock: 10 ps period
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // model of S: records every write init makes, like the real RAM would
    logic [7:0] S [0:255];
    int num_writes;
    always @(posedge clk) begin
        if (wren) begin
            S[addr] <= wrdata;
            num_writes <= num_writes + 1;
        end
    end

    // error counter and check helper
    int errors = 0;
    task automatic check(input logic cond, input string msg);
        if (!cond) begin
            $display("FAIL @%0t: %s", $time, msg);
            errors++;
        end
    endtask

    // send one request, then wait for init to finish
    task automatic do_request();
        // inputs change on the falling edge, away from the rising edge the DUT samples
        @(negedge clk);
        check(rdy === 1'b1, "rdy should be 1 before a request");
        en = 1'b1;
        @(negedge clk);
        en = 1'b0;
        check(rdy === 1'b0, "rdy should drop the cycle after en");
        // wait for rdy to come back (give up after 1000 cycles)
        for (int c = 0; c < 1000 && rdy !== 1'b1; c++) @(negedge clk);
        check(rdy === 1'b1, "timeout: rdy never returned to 1");
    endtask

    initial begin
        en = 1'b0;
        num_writes = 0;
        for (int k = 0; k < 256; k++) S[k] = 8'hxx;

        // Test 1: reset state
        rst_n = 1'b0;
        #12;
        check(rdy  === 1'b1, "rdy should be 1 during reset");
        check(wren === 1'b0, "wren should be 0 during reset");
        rst_n = 1'b1;
        repeat (3) @(negedge clk);
        check(num_writes == 0, "no writes should happen before en");

        // Test 2: one full run fills S with 0..255
        do_request();
        check(num_writes == 256, $sformatf("expected 256 writes, got %0d", num_writes));
        for (int k = 0; k < 256; k++)
            check(S[k] === k[7:0], $sformatf("S[%0d] = %h, expected %h", k, S[k], k[7:0]));

        // Test 3: idle afterwards, nothing more is written
        repeat (20) @(negedge clk);
        check(wren === 1'b0, "wren should stay 0 after finishing");
        check(num_writes == 256, "no extra writes after finishing");

        // Test 4: a second request works again
        num_writes = 0;
        do_request();
        check(num_writes == 256, "second request should also do 256 writes");

        // Test 5: async reset in the middle of a run
        @(negedge clk); en = 1'b1; @(negedge clk); en = 1'b0;
        repeat (50) @(negedge clk);
        #2 rst_n = 1'b0;          // not on a clock edge: reset must act immediately
        #1;
        check(rdy === 1'b1 && wren === 1'b0, "async reset should return to idle immediately");
        rst_n = 1'b1;

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $stop;
    end

endmodule: tb_rtl_init
