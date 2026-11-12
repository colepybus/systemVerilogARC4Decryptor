//key scheduling algorithm
//objective: spread the key entropy evenly across S to prevent statistical correlations in generated ciphertext which could be used to break the cipher
//method: swapping values of the S array at various indices with following function (pseudocode)

// j = 0
// for i = 0 to 255
//     j = (j + s[i] key[i mod keylength]) mod 256 (keylength in this case is 3)
//     swap values of s[i] and s[j]

`timescale 1ps / 1ps

module ksa(input logic clk, input logic rst_n,
           input logic en, output logic rdy,
           input logic [23:0] key,
           output logic [7:0] addr, input logic [7:0] rddata, output logic [7:0] wrdata, output logic wren);

    // inputs: clk (50MHz, 1 bit), rst_n (KEY[1], 1 bit), en (Enable from task2 start logic, 1 bit)), key (Key to be used for algorithm, 24 bits), rddata (data read from S, 8 bits)
    // outputs: rdy (1 bit), 8 bit address, 8 bit write data, 1 bit write enable

    //can condense above 2 into busy or not. busy = 1 means wren = 1. busy = 0 means internal rdy = 1
    logic busy;

    //i and j are now both needed as 8-bit connectors, since both are being stored
    logic [7:0] i, j;

    //rotating copy of key, will take the top 8 bits each iteration of i and then shift everyhing by 8 bits
    logic [23:0] key_r;

    //assigning the top 8 bits to our key_byte for each iteration. since it is big-endian
    logic [7:0] key_byte;
    assign key_byte = key_r[23:16];

    //current step counter and saved copy that represents s[i]
    logic [2:0] step;
    logic [7:0] si, sj;

    //asynchronous reset described here in flip flop inputs by including rst_n
    always_ff @(posedge clk or negedge rst_n) begin

        //reset functionality. i and j iterators get reset to zero and rdy is asserted since nothing is happening
        if (!rst_n) begin
            busy <= 0;
            i <= 8'd0;
            j <= 8'd0;
            key_r <= 24'd0;
            step <= 3'd0;
            si <= 8'd0;
            sj <= 8'd0;
        end

        //handshake approved. checks if enable and rdy is asserted then sets wren to high through busy logic
        else if (en && !busy) begin
            busy <= 1;
            key_r <= key;       //capture the key in the same cycle as en
            i <= 8'd0;          //start every run from i = 0 just in case
            j <= 8'd0;          //j = 0 before the loop as well, fully ensuring proper following of algorithm
            step <= 3'd0;
        end

        //handshake has been approved so it starts working through the algorithmS
        else if (busy) begin
            case(step)
                3'd0: begin //request s[i], addr = i gets driven below, nothing to store yet
                    step <= 3'd1;
                end
                3'd1: begin
                    // rddata is s[i] now
                    si   <= rddata;
                    j    <= j + rddata + key_byte;
                    step <= 3'd2;
                end
                3'd2: begin
                    // request s[j]: address = j (j was updated at end of step 1)
                    step <= 3'd3;
                end
                3'd3: begin
                    // rddata is s[j] now
                    sj <= rddata;
                    step <= 3'd4;
                end
                3'd4: begin
                    //write s[i] = old s[j] (addr = i, wrdata = sj, wren = 1 below)
                    step <= 3'd5;
                end
                3'd5: begin
                    i <= i + 1;
                    key_r <= {key_r[15:0], key_r[23:16]};   //rotate left by 8: next key byte moves to the top
                    step <= 3'd0;
                    if (i == 255) begin
                        busy <= 0;      //that was the last i, go back to idle
                    end
                end
                default: step <= 3'd0;
                //STILL TO FILL IN: STEPS FOR READING S[J] and THEN THE TWO WRITES
                //LAST STEP IS WHERE I <= I + 1, key rotation and the i = 255 check can go
            endcase
        end
    end

    assign rdy = !busy;

    //memory signals depend on which step we're on
    always_comb begin
        addr = i;
        wrdata = 8'd0;
        wren = 1'b0;
        if (busy) begin
            case (step)
                3'd0: addr = i;                                     // read s[i]
                3'd2: addr = j;                                     // read s[j]
                3'd4: begin addr = i; wrdata = sj; wren = 1'b1; end // s[i] = old s[j]
                3'd5: begin addr = j; wrdata = si; wren = 1'b1; end // s[j] = old s[i]
                default: addr = i;
            endcase
        end
    end

endmodule: ksa
