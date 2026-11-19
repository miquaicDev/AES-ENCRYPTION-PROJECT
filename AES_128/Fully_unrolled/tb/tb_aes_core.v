`timescale 1ns/1ps

module tb_aes_core();
    parameter NUM_BLOCKS = 15;
    reg clk, rst_n, valid_in;
    reg [127:0] plaintext;
    reg [127:0] primekey;
    wire [127:0] ciphertext;
    wire valid_out;

    aes_core dut (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .plaintext(plaintext),
        .primekey(primekey),
        .ciphertext(ciphertext),
        .valid_out(valid_out)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    reg [127:0] pt_mem     [0:NUM_BLOCKS-1];
    reg [127:0] key_mem    [0:NUM_BLOCKS-1];
    reg [127:0] exp_ct_mem [0:NUM_BLOCKS-1];

    integer k;
    integer wait_cnt;
    integer cycle_cnt;
    integer first_in_cycle;
    integer first_out_cycle;
    integer prev_out_cycle;
    integer out_idx;
    integer pass_cnt;
    integer fail_cnt;

    task print_matrix;
        input [127:0] data;
        integer r;
        begin
            for (r = 3; r >= 0; r = r - 1) begin
                $display("|\t%02h\t||\t%02h\t||\t%02h\t||\t%02h\t|",
                    data[r*8+96 +: 8], data[r*8+64 +: 8],
                    data[r*8+32 +: 8], data[r*8    +: 8]);
            end
        end
    endtask

    // FIPS-197 & NIST SP 800-38A
    initial begin
        // Block 0: FIPS-197 Appendix B
        pt_mem[0]     = 128'h3243f6a8885a308d313198a2e0370734;
        key_mem[0]    = 128'h2b7e151628aed2a6abf7158809cf4f3c;
        exp_ct_mem[0] = 128'h3925841d02dc09fbdc118597196a0b32;

        // Block 1: FIPS-197 Appendix C.1 (different prime key)
        pt_mem[1]     = 128'h00112233445566778899aabbccddeeff;
        key_mem[1]    = 128'h000102030405060708090a0b0c0d0e0f;
        exp_ct_mem[1] = 128'h69c4e0d86a7b0430d8cdb78070b4c55a;

        // Block 2..5: NIST SP 800-38A F.1.1
        pt_mem[2]     = 128'h6bc1bee22e409f96e93d7e117393172a;
        key_mem[2]    = 128'h2b7e151628aed2a6abf7158809cf4f3c;
        exp_ct_mem[2] = 128'h3ad77bb40d7a3660a89ecaf32466ef97;

        pt_mem[3]     = 128'hae2d8a571e03ac9c9eb76fac45af8e51;
        key_mem[3]    = 128'h2b7e151628aed2a6abf7158809cf4f3c;
        exp_ct_mem[3] = 128'hf5d3d58503b9699de785895a96fdbaaf;

        pt_mem[4]     = 128'h30c81c46a35ce411e5fbc1191a0a52ef;
        key_mem[4]    = 128'h2b7e151628aed2a6abf7158809cf4f3c;
        exp_ct_mem[4] = 128'h43b1cd7f598ece23881b00e3ed030688;

        pt_mem[5]     = 128'hf69f2445df4f9b17ad2b417be66c3710;
        key_mem[5]    = 128'h2b7e151628aed2a6abf7158809cf4f3c;
        exp_ct_mem[5] = 128'h7b0c785e27e8ad3f8223207104725dd4;

        for (k = 6; k < NUM_BLOCKS; k = k + 1) begin
            pt_mem[k]     = pt_mem[k % 6];
            key_mem[k]    = key_mem[k % 6];
            exp_ct_mem[k] = exp_ct_mem[k % 6];
        end
    end

    initial begin
        rst_n     = 0;
        valid_in  = 0;
        plaintext = 128'd0;
        primekey  = 128'd0;
        #20;
        @(negedge clk);
        rst_n = 1;

        for (k = 0; k < NUM_BLOCKS; k = k + 1) begin
            @(negedge clk);
            valid_in  = 1'b1;
            plaintext = pt_mem[k];
            primekey  = key_mem[k];
        end

        @(negedge clk);
        valid_in  = 1'b0;
        plaintext = 128'd0;
        primekey  = 128'd0;

        for (wait_cnt = 0; wait_cnt < 100 && out_idx < NUM_BLOCKS; wait_cnt = wait_cnt + 1) begin
            @(posedge clk);
        end

        #20;
        $display("=================================================================");
        $display("SUMMARY:");
        $display("  - Latency : %0d cycle", first_out_cycle - first_in_cycle);
        $display("  - Result         : %0d/%0d PASS (%0d FAIL)", pass_cnt, NUM_BLOCKS, fail_cnt);
        $display("=================================================================");
        $stop;
    end

    // MONITOR
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_cnt       <= 0;
            first_in_cycle  <= -1;
            first_out_cycle <= -1;
            prev_out_cycle  <= -1;
            out_idx         <= 0;
            pass_cnt        <= 0;
            fail_cnt        <= 0;
        end else begin
            cycle_cnt <= cycle_cnt + 1;

            if (valid_in && first_in_cycle == -1) begin
                first_in_cycle <= cycle_cnt;
                $display("[Cycle %02d] First block 0 to pipeline...", cycle_cnt);
            end

            if (valid_out && out_idx < NUM_BLOCKS) begin
                if (first_out_cycle == -1) begin
                    first_out_cycle <= cycle_cnt;
                    $display("-----------------------------------------------------------------");
                    $display("[Cycle %02d] Block 0 is here! (Latency = %0d cycle)",
                             cycle_cnt, cycle_cnt - first_in_cycle);
                    $display("-----------------------------------------------------------------");
                end

                if (ciphertext === exp_ct_mem[out_idx]) begin
                    $display("[Cycle %02d | Delta=%0d ck] Block %02d: PASS | CT = %032h",
                             cycle_cnt,
                             (prev_out_cycle == -1) ? 0 : (cycle_cnt - prev_out_cycle),
                             out_idx, ciphertext);
                    pass_cnt <= pass_cnt + 1;
                end else begin
                    $display("[Cycle %02d | Delta=%0d ck] Block %02d: FAIL | Got = %032h | Exp = %032h",
                             cycle_cnt,
                             (prev_out_cycle == -1) ? 0 : (cycle_cnt - prev_out_cycle),
                             out_idx, ciphertext, exp_ct_mem[out_idx]);
                    fail_cnt <= fail_cnt + 1;
                end

                if (out_idx == 0) begin
                    $display("--- Mat of block 0 ---");
                    print_matrix(ciphertext);
                end

                prev_out_cycle <= cycle_cnt;
                out_idx        <= out_idx + 1;
            end
        end
    end

endmodule