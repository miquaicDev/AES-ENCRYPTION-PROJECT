`timescale 1ns/1ps

module tb_aes_ctr_mode;

    parameter CLK_PERIOD = 10;
    parameter NBLK       = 16;

    reg          clk;
    reg          rst_n;
    reg          iv_load;
    reg  [127:0] iv;
    reg  [127:0] key;
    reg          valid_in;
    reg  [127:0] data_in;
    wire [127:0] data_out;
    wire         valid_out;

    aes_ctr_mode dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .iv_load   (iv_load),
        .iv        (iv),
        .key       (key),
        .valid_in  (valid_in),
        .data_in   (data_in),
        .data_out  (data_out),
        .valid_out (valid_out)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;


    // NIST SP 800-38A F.5.1 test vectors & 16-block buffers
    reg [127:0] pt_nist [0:3];
    reg [127:0] ct_nist [0:3];
    reg [127:0] KEY_V;
    reg [127:0] IV_V;

    reg [127:0] orig_pt     [0:NBLK-1];
    reg [127:0] cap_ct      [0:NBLK-1];
    reg [127:0] in_mem      [0:NBLK-1];
    reg [127:0] exp_mem     [0:NBLK-1];
    reg         check_exact [0:NBLK-1];

    integer k;
    initial begin
        KEY_V = 128'h2b7e151628aed2a6abf7158809cf4f3c;
        IV_V  = 128'hf0f1f2f3f4f5f6f7f8f9fafbfcfdfeff;

        pt_nist[0] = 128'h6bc1bee22e409f96e93d7e117393172a;
        pt_nist[1] = 128'hae2d8a571e03ac9c9eb76fac45af8e51;
        pt_nist[2] = 128'h30c81c46a35ce411e5fbc1191a0a52ef;
        pt_nist[3] = 128'hf69f2445df4f9b17ad2b417be66c3710;

        ct_nist[0] = 128'h874d6191b620e3261bef6864990db6ce;
        ct_nist[1] = 128'h9806f66b7970fdff8617187bb9fffdff;
        ct_nist[2] = 128'h5ae4df3edbd5d35e5b4f09020db03eab;
        ct_nist[3] = 128'h1e031dda2fbe03d1792170a0f3009cee;

        // First 4 blocks use NIST vectors; remaining 12 blocks use distinct per-block patterns
        for (k = 0; k < 4; k = k + 1)
            orig_pt[k] = pt_nist[k];
        for (k = 4; k < NBLK; k = k + 1)
            orig_pt[k] = 128'h11223344_55667788_99aabbcc_ddeeff00 ^ {96'd0, k[31:0]};
    end

    // Synchronous monitor on posedge clk
    integer phase_id;
    integer prev_phase_id;
    integer start_cycle;
    integer cycle_cnt;
    integer out_cnt;
    integer err_cnt;
    integer total_checked;
    integer first_out_cycle;
    integer prev_out_cycle;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_cnt       <= 0;
            prev_phase_id   <= 0;
            out_cnt         <= 0;
            err_cnt         <= 0;
            total_checked   <= 0;
            first_out_cycle <= -1;
            prev_out_cycle  <= -1;
        end else begin
            cycle_cnt <= cycle_cnt + 1;

            if (phase_id != prev_phase_id) begin
                prev_phase_id   <= phase_id;
                out_cnt         <= 0;
                first_out_cycle <= -1;
                prev_out_cycle  <= -1;
            end else if (valid_out) begin
                if (out_cnt < NBLK) begin
                    if (first_out_cycle == -1) begin
                        first_out_cycle <= cycle_cnt;
                        $display("  --> [Cycle %03d] Block 00 appeared (Latency = %0d cycles)",
                                 cycle_cnt, cycle_cnt - start_cycle);
                    end

                    if (phase_id == 1)
                        cap_ct[out_cnt] <= data_out;

                    if (check_exact[out_cnt]) begin
                        total_checked <= total_checked + 1;
                        if (data_out !== exp_mem[out_cnt]) begin
                            err_cnt <= err_cnt + 1;
                            $display("  [Cycle %03d | Delta=%0d ck] FAIL blk %02d | got=%032h | exp=%032h",
                                     cycle_cnt,
                                     (prev_out_cycle == -1) ? 0 : (cycle_cnt - prev_out_cycle),
                                     out_cnt, data_out, exp_mem[out_cnt]);
                        end else begin
                            $display("  [Cycle %03d | Delta=%0d ck] PASS blk %02d | out=%032h",
                                     cycle_cnt,
                                     (prev_out_cycle == -1) ? 0 : (cycle_cnt - prev_out_cycle),
                                     out_cnt, data_out);
                        end
                    end else begin
                        $display("  [Cycle %03d | Delta=%0d ck] CAPT blk %02d | out=%032h",
                                 cycle_cnt,
                                 (prev_out_cycle == -1) ? 0 : (cycle_cnt - prev_out_cycle),
                                 out_cnt, data_out);
                    end
                end else begin
                    err_cnt <= err_cnt + 1;
                    $display("  [Cycle %03d] FAIL: Unexpected extra valid_out pulse (blk %02d)",
                             cycle_cnt, out_cnt);
                end

                prev_out_cycle <= cycle_cnt;
                out_cnt        <= out_cnt + 1;
            end
        end
    end

    task do_reset;
        begin
            rst_n    = 1'b0;
            iv_load  = 1'b0;
            iv       = 128'd0;
            key      = KEY_V;
            valid_in = 1'b0;
            data_in  = 128'd0;
            repeat (4) @(posedge clk);
            #1 rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task load_iv_task;
        input [127:0] v;
        begin
            @(posedge clk); #1;
            iv_load = 1'b1;
            iv      = v;
            @(posedge clk); #1;
            iv_load = 1'b0;
            iv      = 128'd0;
        end
    endtask

    task send_blk;
        input [127:0] d;
        begin
            @(posedge clk); #1;
            iv_load  = 1'b0;
            valid_in = 1'b1;
            data_in  = d;
        end
    endtask

    task send_blk_with_iv;
        input [127:0] v;
        input [127:0] d;
        begin
            @(posedge clk); #1;
            iv_load  = 1'b1;
            iv       = v;
            valid_in = 1'b1;
            data_in  = d;
        end
    endtask

    task drain;
        input [8*32-1:0] name;
        integer wait_ck;
        begin
            @(posedge clk); #1;
            iv_load  = 1'b0;
            valid_in = 1'b0;
            data_in  = 128'd0;

            for (wait_ck = 0; wait_ck < 120 && out_cnt < NBLK; wait_ck = wait_ck + 1)
                @(posedge clk);

            repeat (5) @(posedge clk);

            if (out_cnt !== NBLK) begin
                $display("  FAIL %0s: Received %0d/%0d blocks!", name, out_cnt, NBLK);
            end
        end
    endtask


    integer i;
    initial begin
        phase_id    = 0;
        start_cycle = 0;
        do_reset;
        // TEST 1: Stream 16 blocks continuously for Encrypt (separate iv_load)
        $display("\n=== TEST 1: Encrypt %0d blocks continuously (Separate iv_load) ===", NBLK);
        for (i = 0; i < NBLK; i = i + 1) begin
            in_mem[i]      = orig_pt[i];
            exp_mem[i]     = (i < 4) ? ct_nist[i] : 128'd0;
            check_exact[i] = (i < 4) ? 1'b1 : 1'b0;
        end
        phase_id = 1;
        load_iv_task(IV_V);
        start_cycle = cycle_cnt;
        for (i = 0; i < NBLK; i = i + 1)
            send_blk(in_mem[i]);
        drain("Test1-Encrypt-16Blk");

        // TEST 2: Stream 16 blocks continuously for Decrypt (simultaneous iv_load + valid_in)
        $display("\n=== TEST 2: Decrypt %0d blocks continuously (Simultaneous iv_load + valid_in) ===", NBLK);
        for (i = 0; i < NBLK; i = i + 1) begin
            in_mem[i]      = cap_ct[i];
            exp_mem[i]     = orig_pt[i];
            check_exact[i] = 1'b1;
        end
        phase_id = 2;
        start_cycle = cycle_cnt;
        send_blk_with_iv(IV_V, in_mem[0]);
        for (i = 1; i < NBLK; i = i + 1)
            send_blk(in_mem[i]);
        drain("Test2-Decrypt-16Blk");


        // Test summary
        $display("\n=================================================================");
        if (err_cnt == 0 && total_checked == (4 + NBLK))
            $display("ALL PASS: Verified %0d blocks successfully with 0 errors!", total_checked);
        else
            $display("FAIL: Encountered %0d errors (%0d blocks checked)", err_cnt, total_checked);
        $display("=================================================================");
        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("tb_aes_ctr_mode.vcd");
        $dumpvars(0, tb_aes_ctr_mode);
    end

endmodule