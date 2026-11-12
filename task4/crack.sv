`timescale 1ps / 1ps

//crack: tries every key from 'h000000 upwards with arc4 until the decrypted message is readable
//a message is readable when every character (not the length byte) is between 'h20 and 'h7E

module crack(input logic clk, input logic rst_n,
             input logic en, output logic rdy,
             output logic [23:0] key, output logic key_valid,
             output logic [7:0] ct_addr, input logic [7:0] ct_rddata);

    // inputs: clk, rst_n, en (request from task4), ct_rddata
    // outputs: rdy, key (the key being tried, or the found key), key_valid (1 only if a readable key was found), ct_addr

    // busy = 1 while searching, busy = 0 means idle (rdy = 1)
    logic busy;

    // 0 = start arc4 with the current key, 1 = wait for arc4 to finish and check the result
    logic step;

    // the key currently being tried
    logic [23:0] key_r;

    // set as soon as arc4 writes an unreadable character for the current key
    logic bad;

    // arc4's handshake
    logic a4_en, a4_rdy;

    // PT memory connections (written by arc4)
    logic       pt_wren;
    logic [7:0] pt_addr, pt_wrdata, pt_q;

    //asynchronous reset described here in flip flop inputs by including rst_n
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
            step <= 1'b0;
            key_r <= 24'd0;
            key_valid <= 1'b0;
            bad <= 1'b0;
        end

        // handshake: idle and a request arrives, so start searching from key 0
        else if (en && !busy) begin
            busy <= 1'b1;
            step <= 1'b0;
            key_r <= 24'd0;
            key_valid <= 1'b0;
        end

        else if (busy) begin
            case (step)
                1'b0: begin
                    // a4_en is high this cycle (below); once arc4 accepts, start checking this key's output
                    if (a4_rdy) begin
                        bad <= 1'b0;
                        step <= 1'b1;
                    end
                end
                1'b1: begin
                    // watch every character arc4 writes to PT (address 0 is the length, so skip it)
                    if (pt_wren && pt_addr != 8'd0 && (pt_wrdata < 8'h20 || pt_wrdata > 8'h7E))
                        bad <= 1'b1;

                    // arc4 has finished this key
                    if (a4_rdy) begin
                        if (!bad) begin
                            key_valid <= 1'b1;          // readable: found the key, PT holds the plaintext
                            busy <= 1'b0;
                        end else if (key_r == 24'hFFFFFF) begin
                            busy <= 1'b0;               // tried every key: give up with key_valid = 0
                        end else begin
                            key_r <= key_r + 24'd1;     // try the next key
                            step <= 1'b0;
                        end
                    end
                end
            endcase
        end
    end

    assign rdy = !busy;
    assign key = key_r;

    // start arc4 once per key, only while it's ready
    assign a4_en = busy && (step == 1'b0) && a4_rdy;

    // this memory must have the length-prefixed plaintext if key_valid
    pt_mem pt(.address(pt_addr), .clock(clk), .data(pt_wrdata), .wren(pt_wren), .q(pt_q));

    arc4 a4(.clk(clk), .rst_n(rst_n), .en(a4_en), .rdy(a4_rdy), .key(key_r),
            .ct_addr(ct_addr), .ct_rddata(ct_rddata),
            .pt_addr(pt_addr), .pt_rddata(pt_q), .pt_wrdata(pt_wrdata), .pt_wren(pt_wren));

endmodule: crack
