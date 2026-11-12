`timescale 1ps / 1ps

//Implementing first step of ARC4, where the cipher state S is initialized to [0..255]:
//for i = 0 to 255:
//  s[i] = i
//initializes array to be in increasing numbered order from 0 to 255

module init(input logic clk, input logic rst_n, input logic en, 
            output logic rdy, output logic [7:0] addr, output logic [7:0] wrdata, output logic wren);
    
    //inputs: clk (frequency of iteration through flip flop, 50 MHz) 
    //        rst_n (active-low reset signal for flip flop) 
    //        en (request from the caller which comes from task1)

    //outputs: rdy (tells the caller whether init is able to accept a request on this cycle)
    //         addr (memory address that is being written in the cycle, ie. which entry of S
    //         wrdata (value actually written into the address. connects to data port of mem_s. always same number as the address for init)
    //         wren (write enable. stores wrdata at addr on next rising clock edge, when 0: memory is not written to and remains unchanged)

    //8 bit that represents the array itself
    logic [7:0] i;

    //1 bit logic to check whether rdy is asserted
    //logic internal_rdy;
    //1 bit logic to check whether write enable is on
    //logic internal_wren;

    //can condense above 2 into busy or not. busy = 1 means internal_wren = 1. busy = 0 means internal rdy = 1
    logic busy;

    //asynchronous reset described here in flip flop inputs by including rst_n
    always_ff @(posedge clk or negedge rst_n) begin
        //reset functionality. iterator gets put to 0s and rdy is asserted since nothing is happening
        if (!rst_n) begin
            i <= 8'd0;
            busy <= 0;
        end
        //handshake approved. checks if rdy is asserted --> checks if en is asserted --> then executes memory writing --> resets
        else if (en && !busy) begin
            busy <= 1;
        end
        else if (busy) begin
                i <= i + 1;
                if (i == 255) begin
                    busy <= 0;
                end
        end
    end

    assign rdy = !busy;
    assign wren = busy;
    assign addr = i;
    assign wrdata = i;

endmodule: init