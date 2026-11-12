`timescale 1ps / 1ps

// Board I/O (DE10-Lite): CLOCK_50 is the 50 MHz clock and KEY[1] is the
// active-low reset (KEY[0] is unused). Keep these port names: the provided
// settings/DE10_Lite.qsf assigns them to the board's pins.
module task1(input logic CLOCK_50, input logic [1:0] KEY, input logic [9:0] SW,
             output logic [6:0] HEX0, output logic [6:0] HEX1, output logic [6:0] HEX2,
             output logic [6:0] HEX3, output logic [6:0] HEX4, output logic [6:0] HEX5,
             output logic [9:0] LEDR);

    // 1 bit connections for enable, rdy and write enable signal
    logic en, rdy, wren;
    // 8 bit connections for address of data, actual data written and q for flip flop output
    logic [7:0] addr, wrdata, q;

    //1 bit connection to remember if init has already been started since last reset
    logic started;

    always_ff @(posedge CLOCK_50 or negedge KEY[1]) begin
        if (!KEY[1]) started <= 1'b0; //reset, haven't started yet
        else if (en) started <= 1'b1; //request has been sent, don't send again 
    end

    assign en = rdy & ~started;

    //init module is connected
    init init(.clk(CLOCK_50), .rst_n(KEY[1]), .en(en), .rdy(rdy), .addr(addr), .wrdata(wrdata), .wren(wren));
    //memory module is connected
    s_mem s(.address(addr), .clock(CLOCK_50), .data(wrdata), .wren(wren), .q(q));

    // unused outputs: displays off (active-low segments), LEDs off. this avoids Quartus warnings/errors
    assign HEX0 = 7'b1111111;
    assign HEX1 = 7'b1111111;
    assign HEX2 = 7'b1111111;
    assign HEX3 = 7'b1111111;
    assign HEX4 = 7'b1111111;
    assign HEX5 = 7'b1111111;
    assign LEDR = 10'b0;

endmodule: task1
