// Board I/O (DE10-Lite): CLOCK_50 is the 50 MHz clock and KEY[1] is the
// active-low reset (KEY[0] is unused). Keep these port names: the provided
// settings/DE10_Lite.qsf assigns them to the board's pins.

`timescale 1ps / 1ps

module task3(input logic CLOCK_50, input logic [1:0] KEY, input logic [9:0] SW,
             output logic [6:0] HEX0, output logic [6:0] HEX1, output logic [6:0] HEX2,
             output logic [6:0] HEX3, output logic [6:0] HEX4, output logic [6:0] HEX5,
             output logic [9:0] LEDR);

    // arc4's handshake
    logic a4_en, a4_rdy;

    // CT memory connections (CT is only read, never written)
    logic [7:0] ct_addr, ct_q;

    // PT memory connections
    logic       pt_wren;
    logic [7:0] pt_addr, pt_wrdata, pt_q;

    // remember whether arc4 has been started since the last reset
    logic started;

    always_ff @(posedge CLOCK_50 or negedge KEY[1]) begin
        if (!KEY[1])  started <= 1'b0;   // reset: haven't started yet
        else if (a4_en) started <= 1'b1; // request sent: never send another
    end

    // start arc4 exactly once after reset, while it's ready
    assign a4_en = a4_rdy & ~started;

    ct_mem ct(.address(ct_addr), .clock(CLOCK_50), .data(8'd0), .wren(1'b0), .q(ct_q));
    pt_mem pt(.address(pt_addr), .clock(CLOCK_50), .data(pt_wrdata), .wren(pt_wren), .q(pt_q));

    // key: SW[9:0] for the low bits, top 14 bits are zero
    arc4 a4(.clk(CLOCK_50), .rst_n(KEY[1]), .en(a4_en), .rdy(a4_rdy), .key({14'b0, SW[9:0]}),
            .ct_addr(ct_addr), .ct_rddata(ct_q),
            .pt_addr(pt_addr), .pt_rddata(pt_q), .pt_wrdata(pt_wrdata), .pt_wren(pt_wren));

    // unused outputs: displays off (active-low), LEDs off
    assign HEX0 = 7'b1111111;
    assign HEX1 = 7'b1111111;
    assign HEX2 = 7'b1111111;
    assign HEX3 = 7'b1111111;
    assign HEX4 = 7'b1111111;
    assign HEX5 = 7'b1111111;
    assign LEDR = 10'b0;

endmodule: task3
