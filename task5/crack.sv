`timescale 1ps / 1ps

//crack (Task 5 version): tries keys key_start, key_start + key_step, key_start + 2*key_step, ... with arc4
//until the decrypted message is readable (every character, not the length byte, between 'h20 and 'h7E)
//compared with Task 4, only ports were added: key_start/key_step choose which keys this core tries,
//stop ends the search early, and pt_rd_addr/pt_rd_data let doublecrack read this core's PT afterwards

module crack(input logic clk, input logic rst_n,
             input logic en, output logic rdy,
             output logic [23:0] key, output logic key_valid,
             output logic [7:0] ct_addr, input logic [7:0] ct_rddata,
             input logic [23:0] key_start, input logic [23:0] key_step,
             input logic stop,
             input logic [7:0] pt_rd_addr, output logic [7:0] pt_rd_data);

    // inputs: clk, rst_n, en, ct_rddata, key_start (first key to try), key_step (how far to jump each time),
    //         stop (give up now, used by doublecrack once the other core has found the key), pt_rd_addr
    // outputs: rdy, key, key_valid, ct_addr, pt_rd_data (PT contents at pt_rd_addr, valid the cycle after)

    // busy = 1 while searching, busy = 0 means idle (rdy = 1)
    logic busy;

    // 0 = start arc4 with the current key, 1 = wait for arc4 to finish and check the result
    logic step;

    // the key currently being tried, and the step size captured when en is accepted
    logic [23:0] key_r, step_r;

    // set as soon as arc4 writes an unreadable character for the current key
    logic bad;

    // arc4's handshake
    logic a4_en, a4_rdy;

    // arc4's PT connections, and the PT memory's actual connections (arc4 or doublecrack's read)
    logic       a4_pt_wren;
    logic [7:0] a4_pt_addr, a4_pt_wrdata, pt_addr, pt_q;

    //asynchronous reset described here in flip flop inputs by including rst_n
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
            step <= 1'b0;
            key_r <= 24'd0;
            step_r <= 24'd1;
            key_valid <= 1'b0;
            bad <= 1'b0;
        end

        // handshake: idle and a request arrives, so start searching from key_start
        else if (en && !busy) begin
            busy <= 1'b1;
            step <= 1'b0;
            key_r <= key_start;
            step_r <= key_step;
            key_valid <= 1'b0;
        end

        // told to give up (the other core found the key): go idle with key_valid = 0
        else if (busy && stop) begin
            busy <= 1'b0;
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
                    if (a4_pt_wren && a4_pt_addr != 8'd0 && (a4_pt_wrdata < 8'h20 || a4_pt_wrdata > 8'h7E))
                        bad <= 1'b1;

                    // arc4 has finished this key
                    if (a4_rdy) begin
                        if (!bad) begin
                            key_valid <= 1'b1;              // readable: found the key, PT holds the plaintext
                            busy <= 1'b0;
                        end else if (key_r > 24'hFFFFFF - step_r) begin
                            busy <= 1'b0;                   // the next key would go past 'hFFFFFF: give up
                        end else begin
                            key_r <= key_r + step_r;        // try the next key
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

    // PT belongs to arc4 while searching; once crack and arc4 are both idle, doublecrack can read it
    assign pt_addr = (!busy && a4_rdy) ? pt_rd_addr : a4_pt_addr;
    assign pt_rd_data = pt_q;

    // this memory must have the length-prefixed plaintext if key_valid
    pt_mem pt(.address(pt_addr), .clock(clk), .data(a4_pt_wrdata), .wren(a4_pt_wren), .q(pt_q));

    arc4 a4(.clk(clk), .rst_n(rst_n), .en(a4_en), .rdy(a4_rdy), .key(key_r),
            .ct_addr(ct_addr), .ct_rddata(ct_rddata),
            .pt_addr(a4_pt_addr), .pt_rddata(pt_q), .pt_wrdata(a4_pt_wrdata), .pt_wren(a4_pt_wren));

endmodule: crack
