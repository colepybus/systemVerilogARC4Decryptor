// Board I/O (DE10-Lite): CLOCK_50 is the 50 MHz clock and KEY[1] is the
// active-low reset (KEY[0] is unused). Keep these port names: the provided
// settings/DE10_Lite.qsf assigns them to the board's pins.

`timescale 1ps / 1ps

module task2(input logic CLOCK_50, input logic [1:0] KEY, input logic [9:0] SW,
             output logic [6:0] HEX0, output logic [6:0] HEX1, output logic [6:0] HEX2,
             output logic [6:0] HEX3, output logic [6:0] HEX4, output logic [6:0] HEX5,
             output logic [9:0] LEDR);

    // init's connections
    logic       init_en, init_rdy, init_wren;
    logic [7:0] init_addr, init_wrdata;

    // ksa's connections
    logic       ksa_en, ksa_rdy, ksa_wren;
    logic [7:0] ksa_addr, ksa_wrdata;
    logic [23:0] ksa_key;

    // the S memory's connections
    logic       s_wren;
    logic [7:0] s_addr, s_wrdata, s_q;

    // recall exactly which modules have been started since the last reset
    logic init_started, ksa_started;

    always_ff @(posedge CLOCK_50 or negedge KEY[1]) begin
        if (!KEY[1]) begin
            init_started <= 1'b0;
            ksa_started  <= 1'b0;
        end else begin
            if (init_en) init_started <= 1'b1;
            if (ksa_en)  ksa_started  <= 1'b1;
        end
    end

    // init has finished once it was started and its rdy has come back
    logic init_done;
    assign init_done = init_started & init_rdy;

    // start init once, then start ksa once after init is done
    assign init_en = init_rdy & ~init_started;
    assign ksa_en  = init_done & ksa_rdy & ~ksa_started;

    // key: SW[9:0] for the low bits, top 14 bits are zero
    assign ksa_key = {14'b0, SW[9:0]};

    // mux: init drives S until it's done, then ksa does
    assign s_addr   = init_done ? ksa_addr   : init_addr;
    assign s_wrdata = init_done ? ksa_wrdata : init_wrdata;
    assign s_wren   = init_done ? ksa_wren   : init_wren;

    init i(.clk(CLOCK_50), .rst_n(KEY[1]), .en(init_en), .rdy(init_rdy),
           .addr(init_addr), .wrdata(init_wrdata), .wren(init_wren));

    ksa k(.clk(CLOCK_50), .rst_n(KEY[1]), .en(ksa_en), .rdy(ksa_rdy), .key(ksa_key),
          .addr(ksa_addr), .rddata(s_q), .wrdata(ksa_wrdata), .wren(ksa_wren));

    s_mem s(.address(s_addr), .clock(CLOCK_50), .data(s_wrdata), .wren(s_wren), .q(s_q));

    // unused outputs: displays off (active-low), LEDs off
    assign HEX0 = 7'b1111111;
    assign HEX1 = 7'b1111111;
    assign HEX2 = 7'b1111111;
    assign HEX3 = 7'b1111111;
    assign HEX4 = 7'b1111111;
    assign HEX5 = 7'b1111111;
    assign LEDR = 10'b0;

endmodule: task2
