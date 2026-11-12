`timescale 1ps / 1ps

//arc4 decryption: runs init, then ksa, then prga on the shared S memory
//reads the encrypted message from CT and writes the decrypted message to PT (both length-prefixed)

module arc4(input logic clk, input logic rst_n,
            input logic en, output logic rdy,
            input logic [23:0] key,
            output logic [7:0] ct_addr, input logic [7:0] ct_rddata,
            output logic [7:0] pt_addr, input logic [7:0] pt_rddata, output logic [7:0] pt_wrdata, output logic pt_wren);

    // inputs: clk, rst_n, en (request from task3), 24 bit key, ct_rddata, pt_rddata
    // outputs: rdy, ct_addr, pt_addr, pt_wrdata, pt_wren (all CT/PT signals come straight from prga)

    // busy = 1 while running, busy = 0 means idle (rdy = 1)
    logic busy;

    // which phase we're on: 0/1 = start/wait init, 2/3 = start/wait ksa, 4/5 = start/wait prga
    logic [2:0] step;

    // copy of the key, captured when en is accepted (the caller may change key afterwards)
    logic [23:0] key_r;

    // init's connections
    logic       init_en, init_rdy, init_wren;
    logic [7:0] init_addr, init_wrdata;

    // ksa's connections
    logic       ksa_en, ksa_rdy, ksa_wren;
    logic [7:0] ksa_addr, ksa_wrdata;

    // prga's connections to S (its CT and PT connections go straight to arc4's ports)
    logic       prga_en, prga_rdy, prga_s_wren;
    logic [7:0] prga_s_addr, prga_s_wrdata;

    // the S memory's connections
    logic       s_wren;
    logic [7:0] s_addr, s_wrdata, s_q;

    //asynchronous reset described here in flip flop inputs by including rst_n
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
            step <= 3'd0;
            key_r <= 24'd0;
        end

        // handshake: idle and a request arrives, so start a new run
        else if (en && !busy) begin
            busy <= 1'b1;
            step <= 3'd0;
            key_r <= key;
        end

        // each phase: start the module once it's ready, then wait until its rdy comes back
        else if (busy) begin
            case (step)
                3'd0: if (init_rdy) step <= 3'd1;   // init_en is high this cycle (below)
                3'd1: if (init_rdy) step <= 3'd2;   // init has finished
                3'd2: if (ksa_rdy)  step <= 3'd3;   // ksa_en is high this cycle
                3'd3: if (ksa_rdy)  step <= 3'd4;   // ksa has finished
                3'd4: if (prga_rdy) step <= 3'd5;   // prga_en is high this cycle
                3'd5: if (prga_rdy) begin           // prga has finished: whole decryption done
                          busy <= 1'b0;
                          step <= 3'd0;
                      end
                default: step <= 3'd0;
            endcase
        end
    end

    assign rdy = !busy;

    // each module gets exactly one request, in its start step, and only while it's ready
    assign init_en = busy && (step == 3'd0) && init_rdy;
    assign ksa_en  = busy && (step == 3'd2) && ksa_rdy;
    assign prga_en = busy && (step == 3'd4) && prga_rdy;

    // S memory mux: whichever module's phase we're in drives S
    always_comb begin
        case (step)
            3'd0, 3'd1: begin s_addr = init_addr;   s_wrdata = init_wrdata;   s_wren = init_wren;   end
            3'd2, 3'd3: begin s_addr = ksa_addr;    s_wrdata = ksa_wrdata;    s_wren = ksa_wren;    end
            default:    begin s_addr = prga_s_addr; s_wrdata = prga_s_wrdata; s_wren = prga_s_wren; end
        endcase
    end

    s_mem s(.address(s_addr), .clock(clk), .data(s_wrdata), .wren(s_wren), .q(s_q));

    init i(.clk(clk), .rst_n(rst_n), .en(init_en), .rdy(init_rdy),
           .addr(init_addr), .wrdata(init_wrdata), .wren(init_wren));

    ksa k(.clk(clk), .rst_n(rst_n), .en(ksa_en), .rdy(ksa_rdy), .key(key_r),
          .addr(ksa_addr), .rddata(s_q), .wrdata(ksa_wrdata), .wren(ksa_wren));

    prga p(.clk(clk), .rst_n(rst_n), .en(prga_en), .rdy(prga_rdy), .key(key_r),
           .s_addr(prga_s_addr), .s_rddata(s_q), .s_wrdata(prga_s_wrdata), .s_wren(prga_s_wren),
           .ct_addr(ct_addr), .ct_rddata(ct_rddata),
           .pt_addr(pt_addr), .pt_rddata(pt_rddata), .pt_wrdata(pt_wrdata), .pt_wren(pt_wren));

endmodule: arc4
