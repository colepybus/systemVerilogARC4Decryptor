`timescale 1ps / 1ps

//doublecrack: two crack cores search at the same time, c1 tries the even keys (0, 2, 4, ...) and c2 the odd keys (1, 3, 5, ...)
//sharing the single CT port: before searching, CT is copied into a private memory (ct2) for c2,
//then c1 reads the real CT through doublecrack's port and c2 reads its copy, so they never compete
//when a core finds the key, the other core is stopped and the winner's PT is copied into doublecrack's shared PT

module doublecrack(input logic clk, input logic rst_n,
             input logic en, output logic rdy,
             output logic [23:0] key, output logic key_valid,
             output logic [7:0] ct_addr, input logic [7:0] ct_rddata);

    // inputs: clk, rst_n, en (request from task5), ct_rddata
    // outputs: rdy, key (the found key), key_valid (1 only if a readable key was found), ct_addr

    // busy = 1 while working, busy = 0 means idle (rdy = 1)
    logic busy;

    // which phase we're on (see the case statement below)
    logic [2:0] step;

    // address counter for the two copy loops (CT into ct2, then the winner's PT into pt)
    logic [7:0] cnt;

    // which core found the key: 0 = c1, 1 = c2
    logic winner;

    // the found key
    logic [23:0] key_r;

    // the two cores' connections
    logic        c1_en, c1_rdy, c1_valid, c1_stop;
    logic        c2_en, c2_rdy, c2_valid, c2_stop;
    logic [23:0] c1_key, c2_key;
    logic [7:0]  c1_ct_addr, c2_ct_addr, c1_pt_rd, c2_pt_rd;

    // the private CT copy for c2
    logic       ct2_wren;
    logic [7:0] ct2_addr, ct2_q;

    // the shared PT memory
    logic       pt_wren;
    logic [7:0] pt_q;

    localparam logic [2:0] COPY_CT_RD = 3'd0,   // read CT[cnt]
                           COPY_CT_WR = 3'd1,   // write it into ct2[cnt]
                           START      = 3'd2,   // start both cores together
                           SEARCH     = 3'd3,   // wait for a key, or for both cores to give up
                           COPY_PT_RD = 3'd4,   // read the winner's PT[cnt]
                           COPY_PT_WR = 3'd5;   // write it into the shared pt[cnt]

    //asynchronous reset described here in flip flop inputs by including rst_n
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
            step <= COPY_CT_RD;
            cnt <= 8'd0;
            winner <= 1'b0;
            key_r <= 24'd0;
            key_valid <= 1'b0;
        end

        // handshake: idle and a request arrives, so start by copying CT
        else if (en && !busy) begin
            busy <= 1'b1;
            step <= COPY_CT_RD;
            cnt <= 8'd0;
            key_valid <= 1'b0;
        end

        else if (busy) begin
            case (step)
                COPY_CT_RD: step <= COPY_CT_WR;                     // ct_addr = cnt below; data arrives next cycle
                COPY_CT_WR: begin                                   // ct2[cnt] = ct_rddata below
                    if (cnt == 8'd255) step <= START;
                    else begin
                        cnt <= cnt + 8'd1;
                        step <= COPY_CT_RD;
                    end
                end
                START: if (c1_rdy && c2_rdy) step <= SEARCH;        // c1_en and c2_en are high this cycle
                SEARCH: begin
                    if (c1_rdy && c1_valid) begin                   // c1 found it (c1 wins a tie)
                        winner <= 1'b0;
                        key_r <= c1_key;
                        cnt <= 8'd0;
                        step <= COPY_PT_RD;
                    end else if (c2_rdy && c2_valid) begin          // c2 found it
                        winner <= 1'b1;
                        key_r <= c2_key;
                        cnt <= 8'd0;
                        step <= COPY_PT_RD;
                    end else if (c1_rdy && c2_rdy) begin            // both gave up: no key works
                        busy <= 1'b0;
                    end
                end
                COPY_PT_RD: step <= COPY_PT_WR;                     // winner's pt_rd_addr = cnt below
                COPY_PT_WR: begin                                   // pt[cnt] = winner's pt_rd_data below
                    if (cnt == 8'd255) begin
                        key_valid <= 1'b1;                          // shared PT is complete: done
                        busy <= 1'b0;
                    end else begin
                        cnt <= cnt + 8'd1;
                        step <= COPY_PT_RD;
                    end
                end
                default: step <= COPY_CT_RD;
            endcase
        end
    end

    assign rdy = !busy;
    assign key = key_r;

    // both cores start in the same cycle, once both are ready
    assign c1_en = busy && (step == START) && c1_rdy && c2_rdy;
    assign c2_en = c1_en;

    // once one core has found the key, stop the other one
    assign c1_stop = busy && (step == SEARCH) && c2_rdy && c2_valid;
    assign c2_stop = busy && (step == SEARCH) && c1_rdy && c1_valid;

    // CT port: doublecrack uses it while copying, then it belongs to c1
    assign ct_addr = (step == COPY_CT_RD || step == COPY_CT_WR) ? cnt : c1_ct_addr;

    // ct2: written while copying, then read by c2
    assign ct2_wren = busy && (step == COPY_CT_WR);
    assign ct2_addr = (step == COPY_CT_WR) ? cnt : c2_ct_addr;

    // shared PT: written with the winner's PT, one byte per read/write pair
    assign pt_wren = busy && (step == COPY_PT_WR);

    // c2's private copy of CT
    ct_mem ct2(.address(ct2_addr), .clock(clk), .data(ct_rddata), .wren(ct2_wren), .q(ct2_q));

    // this memory must have the length-prefixed plaintext if key_valid
    pt_mem pt(.address(cnt), .clock(clk), .data(winner ? c2_pt_rd : c1_pt_rd), .wren(pt_wren), .q(pt_q));

    // for this task only, you may ADD ports to crack
    crack c1(.clk(clk), .rst_n(rst_n), .en(c1_en), .rdy(c1_rdy), .key(c1_key), .key_valid(c1_valid),
             .ct_addr(c1_ct_addr), .ct_rddata(ct_rddata),
             .key_start(24'd0), .key_step(24'd2), .stop(c1_stop),
             .pt_rd_addr(cnt), .pt_rd_data(c1_pt_rd));

    crack c2(.clk(clk), .rst_n(rst_n), .en(c2_en), .rdy(c2_rdy), .key(c2_key), .key_valid(c2_valid),
             .ct_addr(c2_ct_addr), .ct_rddata(ct2_q),
             .key_start(24'd1), .key_step(24'd2), .stop(c2_stop),
             .pt_rd_addr(cnt), .pt_rd_data(c2_pt_rd));

endmodule: doublecrack
