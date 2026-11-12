`timescale 1ps / 1ps

module prga(input logic clk, input logic rst_n,
            input logic en, output logic rdy,
            input logic [23:0] key,
            output logic [7:0] s_addr, input logic [7:0] s_rddata, output logic [7:0] s_wrdata, output logic s_wren,
            output logic [7:0] ct_addr, input logic [7:0] ct_rddata,
            output logic [7:0] pt_addr, input logic [7:0] pt_rddata, output logic [7:0] pt_wrdata, output logic pt_wren);

    // inputs: clk, rst_n, en, 24 bit key, s_rddata, ct_rddata, pt_rddata
    // outputs: rdy, s_addr, s_wrdata, s_wren, ct_addr, pt_addr, pt_wrdata, pt_wren
    // key and pt_rddata are not used by prga: the key is already mixed into S by ksa, and PT is only written

    // busy = 1 while decrypting, busy = 0 means idle (rdy = 1)
    logic busy;

    // which part of the work we're on: a few steps to read the length, then about 9 steps per message byte
    logic [3:0] step;

    // the algorithm's two indices into S
    logic [7:0] i, j;

    // which message byte we're on (1..len); also the address in CT and PT for that byte
    logic [7:0] k;

    // message length, read from ct[0] at the start
    logic [7:0] len;

    // saved copies of s[i] and s[j], needed for the swap and for the pad address s[i] + s[j]
    logic [7:0] si, sj;


    //flip flop moves through the steps of decryption in order and updates i, j, k, len, si and sj on each clk edge
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
            step <= 4'd0;
            i <= 8'b0;
            j <= 8'b0;
            k <= 8'b0;
            len <= 8'b0;
            si <= 8'b0;
            sj <= 8'b0;
        end

        // handshake: idle and a request arrives, so start a new run
        else if (en && !busy) begin
            busy <= 1'b1;
            step <= 4'd0;
            i <= 8'd0;
            j <= 8'd0;
        end

        else if (busy) begin
            case (step)
                // read the message length
                4'd0: begin
                    // ct_addr = 0 is driven below; ct[0] arrives next cycle
                    step <= 4'd1;
                end
                4'd1: begin
                    // ct_rddata is the length now; pt[0] = length is written below
                    len <= ct_rddata;
                    if (ct_rddata == 8'd0) begin
                        busy <= 1'b0;       // empty message: nothing to decrypt
                        step <= 4'd0;
                    end else begin
                        k <= 8'd1;          // message bytes start at address 1
                        step <= 4'd2;
                    end
                end

                // one message byte, steps 2 to 10
                4'd2: begin
                    // pseudocode: i = (i + 1) mod 256 (8 bits wrap on their own)
                    i <= i + 8'd1;
                    step <= 4'd3;
                end
                4'd3: begin
                    // s_addr = i is driven below; s[i] arrives next cycle
                    step <= 4'd4;
                end
                4'd4: begin
                    // s_rddata is s[i] now
                    si <= s_rddata;
                    j <= j + s_rddata;      // pseudocode: j = (j + s[i]) mod 256, using s_rddata since si updates at this edge
                    step <= 4'd5;
                end
                4'd5: begin
                    // s_addr = j is driven below; s[j] arrives next cycle
                    step <= 4'd6;
                end
                4'd6: begin
                    // s_rddata is s[j] now
                    sj <= s_rddata;
                    step <= 4'd7;
                end
                4'd7: begin
                    // writing s[i] = sj below
                    step <= 4'd8;
                end
                4'd8: begin
                    // writing s[j] = si below
                    step <= 4'd9;
                end
                4'd9: begin
                    // reading s[si + sj] (the pad) and ct[k] below; both arrive next cycle
                    step <= 4'd10;
                end
                4'd10: begin
                    // pt[k] = pad xor ct[k] is written below
                    if (k == len) begin
                        busy <= 1'b0;       // last byte written: done
                        step <= 4'd0;
                    end else begin
                        k <= k + 8'd1;      // next message byte
                        step <= 4'd2;
                    end
                end

                default: step <= 4'd0;
            endcase
        end
    end

    assign rdy = !busy;

    always_comb begin
        // defaults: no writes, all addresses 0
        s_addr    = 8'd0;
        s_wrdata  = 8'd0;
        s_wren    = 1'b0;
        ct_addr   = 8'd0;
        pt_addr   = 8'd0;
        pt_wrdata = 8'd0;
        pt_wren   = 1'b0;

        if (busy) begin
            case (step)
                4'd0:  ct_addr = 8'd0;                                                   // read ct[0], the length
                4'd1:  begin pt_addr = 8'd0; pt_wrdata = ct_rddata; pt_wren = 1'b1; end // pt[0] = length (not encrypted)
                4'd3:  s_addr = i;                                                       // read s[i]
                4'd5:  s_addr = j;                                                       // read s[j]
                4'd7:  begin s_addr = i; s_wrdata = sj; s_wren = 1'b1; end               // s[i] = old s[j]
                4'd8:  begin s_addr = j; s_wrdata = si; s_wren = 1'b1; end               // s[j] = old s[i]
                4'd9:  begin s_addr = si + sj; ct_addr = k; end                          // read the pad byte and ct[k] together
                4'd10: begin pt_addr = k; pt_wrdata = s_rddata ^ ct_rddata; pt_wren = 1'b1; end // pt[k] = pad xor ct[k]
                default: ;
            endcase
        end
    end

endmodule: prga
