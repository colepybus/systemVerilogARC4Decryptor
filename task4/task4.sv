// Board I/O (DE10-Lite): CLOCK_50 is the 50 MHz clock and KEY[1] is the
// active-low reset (KEY[0] is unused). Keep these port names: the provided
// settings/DE10_Lite.qsf assigns them to the board's pins.

`timescale 1ps / 1ps

module task4(input logic CLOCK_50, input logic [1:0] KEY, input logic [9:0] SW,
             output logic [6:0] HEX0, output logic [6:0] HEX1, output logic [6:0] HEX2,
             output logic [6:0] HEX3, output logic [6:0] HEX4, output logic [6:0] HEX5,
             output logic [9:0] LEDR);

    // crack's handshake and results
    logic        c_en, c_rdy, key_valid;
    logic [23:0] key;

    // CT memory connections (CT is only read, never written)
    logic [7:0] ct_addr, ct_q;

    // remember whether crack has been started since the last reset
    logic started;

    always_ff @(posedge CLOCK_50 or negedge KEY[1]) begin
        if (!KEY[1])   started <= 1'b0;  // reset: haven't started yet
        else if (c_en) started <= 1'b1;  // request sent: never send another
    end

    // start crack exactly once after reset, while it's ready
    assign c_en = c_rdy & ~started;

    // crack has finished once it was started and its rdy has come back
    logic done;
    assign done = started & c_rdy;

    ct_mem ct(.address(ct_addr), .clock(CLOCK_50), .data(8'd0), .wren(1'b0), .q(ct_q));

    crack c(.clk(CLOCK_50), .rst_n(KEY[1]), .en(c_en), .rdy(c_rdy),
            .key(key), .key_valid(key_valid),
            .ct_addr(ct_addr), .ct_rddata(ct_q));

    // seven-segment pattern for one hex digit (active-low, bits are g f e d c b a)
    function automatic logic [6:0] hex7(input logic [3:0] d);
        case (d)
            4'h0: hex7 = 7'b1000000;
            4'h1: hex7 = 7'b1111001;
            4'h2: hex7 = 7'b0100100;
            4'h3: hex7 = 7'b0110000;
            4'h4: hex7 = 7'b0011001;
            4'h5: hex7 = 7'b0010010;
            4'h6: hex7 = 7'b0000010;
            4'h7: hex7 = 7'b1111000;
            4'h8: hex7 = 7'b0000000;
            4'h9: hex7 = 7'b0010000;
            4'hA: hex7 = 7'b0001000;
            4'hB: hex7 = 7'b0000011;
            4'hC: hex7 = 7'b1000110;
            4'hD: hex7 = 7'b0100001;
            4'hE: hex7 = 7'b0000110;
            default: hex7 = 7'b0001110;   // F
        endcase
    endfunction

    localparam logic [6:0] BLANK = 7'b1111111;   // all segments off
    localparam logic [6:0] DASH  = 7'b0111111;   // middle segment only

    // blank while searching, the key once found (HEX5 = top digit), dashes if no key worked
    always_comb begin
        if (!done) begin
            {HEX5, HEX4, HEX3, HEX2, HEX1, HEX0} = {6{BLANK}};
        end else if (key_valid) begin
            HEX5 = hex7(key[23:20]);
            HEX4 = hex7(key[19:16]);
            HEX3 = hex7(key[15:12]);
            HEX2 = hex7(key[11:8]);
            HEX1 = hex7(key[7:4]);
            HEX0 = hex7(key[3:0]);
        end else begin
            {HEX5, HEX4, HEX3, HEX2, HEX1, HEX0} = {6{DASH}};
        end
    end

    // unused outputs: LEDs off
    assign LEDR = 10'b0;

endmodule: task4
