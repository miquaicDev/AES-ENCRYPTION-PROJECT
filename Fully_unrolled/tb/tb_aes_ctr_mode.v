`timescale 1ns/1ps
// ============================================================================
// Testbench for AES-128 CTR mode (Fully Unrolled)
//
// NIST SP 800-38A test vectors (AES-128 CTR):
//   Key  : 2b7e151628aed2a6abf7158809cf4f3c
//   IV   : f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff
//   PT[0]: 6bc1bee22e409f96e93d7e117393172a -> CT[0]: 874d6191b620e3261bef6864990db6ce
//   PT[1]: ae2d8a571e03ac9c9eb76fac45af8e51 -> CT[1]: 9806f66b7970fdff8617187bb9fffdff
//   PT[2]: 30c81c46a35ce411e5fbc1191a0a52ef -> CT[2]: 5ae4df3edbd5d35e5b4f09020db03eab
//   PT[3]: f69f2445df4f9b17ad2b417be66c3710 -> CT[3]: 1e031dda2fbe03d1792170a0f3009cee
//
// Test scenarios:
//   Test 1: Encrypt 4 blocks back-to-back with separate iv_load (classic mode)
//   Test 2: Encrypt 4 blocks back-to-back with SIMULTANEOUS iv_load + valid_in at Block 0
//   Test 3: Decrypt 4 blocks with SIMULTANEOUS iv_load + valid_in and bubbles
//   Test 4: Reload IV on-the-fly and re-encrypt back-to-back
// ============================================================================
module tb_aes_ctr_mode;

    parameter CLK_PERIOD = 10;
    parameter NBLK       = 4;

    reg         clk;
    reg         rst_n;
    reg         iv_load;
    reg [127:0] iv;
    reg [127:0] key;
    reg         valid_in;
    reg [127:0] data_in;
    wire [127:0] data_out;
    wire         valid_out;

    aes_ctr_mode dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .iv_load  (iv_load),
        .iv       (iv),
        .key      (key),
        .valid_in (valid_in),
        .data_in  (data_in),
        .data_out (data_out),
        .valid_out(valid_out)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -----------------------------------------------------------------------
    // NIST test vectors
    // -----------------------------------------------------------------------
    reg [127:0] pt   [0:NBLK-1];
    reg [127:0] ct   [0:NBLK-1];
    reg [127:0] KEY_V;
    reg [127:0] IV_V;

    // Working arrays for each test
    reg [127:0] in_mem  [0:NBLK-1];
    reg [127:0] exp_mem [0:NBLK-1];

    initial begin
        KEY_V = 128'h2b7e151628aed2a6abf7158809cf4f3c;
        IV_V  = 128'hf0f1f2f3f4f5f6f7f8f9fafbfcfdfeff;

        pt[0] = 128'h6bc1bee22e409f96e93d7e117393172a;
        pt[1] = 128'hae2d8a571e03ac9c9eb76fac45af8e51;
        pt[2] = 128'h30c81c46a35ce411e5fbc1191a0a52ef;
        pt[3] = 128'hf69f2445df4f9b17ad2b417be66c3710;

        ct[0] = 128'h874d6191b620e3261bef6864990db6ce;
        ct[1] = 128'h9806f66b7970fdff8617187bb9fffdff;
        ct[2] = 128'h5ae4df3edbd5d35e5b4f09020db03eab;
        ct[3] = 128'h1e031dda2fbe03d1792170a0f3009cee;
    end

    // -----------------------------------------------------------------------
    // Output checker (always block, runs throughout simulation)
    // -----------------------------------------------------------------------
    integer out_cnt;
    integer err_cnt;
    integer total_checked;

    always @(posedge clk) begin
        if (rst_n && valid_out) begin
            if (out_cnt < NBLK) begin
                total_checked = total_checked + 1;
                if (data_out !== exp_mem[out_cnt]) begin
                    err_cnt = err_cnt + 1;
                    $display("[%0t ns] FAIL blk %0d | got=%032h | exp=%032h",
                             $time, out_cnt, data_out, exp_mem[out_cnt]);
                end else begin
                    $display("[%0t ns] PASS blk %0d | %032h", $time, out_cnt, data_out);
                end
            end else begin
                err_cnt = err_cnt + 1;
                $display("[%0t ns] FAIL: unexpected valid_out (blk %0d)", $time, out_cnt);
            end
            out_cnt = out_cnt + 1;
        end
    end

    // -----------------------------------------------------------------------
    // Tasks
    // -----------------------------------------------------------------------
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

    // Load IV separately (pulse for 1 cycle)
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

    // Send a standard block (iv_load is 0)
    task send_blk;
        input [127:0] d;
        begin
            @(posedge clk); #1;
            iv_load  = 1'b0;
            valid_in = 1'b1;
            data_in  = d;
        end
    endtask

    // Send block 0 with SIMULTANEOUS iv_load and valid_in
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

    // Insert a bubble (idle cycle)
    task send_bubble;
        begin
            @(posedge clk); #1;
            iv_load  = 1'b0;
            valid_in = 1'b0;
            data_in  = 128'hDEAD_BEEF_DEAD_BEEF_DEAD_BEEF_DEAD_BEEF; // garbage
        end
    endtask

    // Drain pipeline and de-assert valid_in
    task drain;
        begin
            @(posedge clk); #1;
            iv_load  = 1'b0;
            valid_in = 1'b0;
            while (out_cnt < NBLK) @(posedge clk);
            repeat (10) @(posedge clk);
        end
    endtask

    // Check that exactly NBLK blocks arrived this phase
    task check_phase;
        input [8*32-1:0] name;
        begin
            if (out_cnt !== NBLK) begin
                err_cnt = err_cnt + 1;
                $display("FAIL %0s: received %0d blocks, expected %0d",
                         name, out_cnt, NBLK);
            end
        end
    endtask

    // -----------------------------------------------------------------------
    // Main stimulus
    // -----------------------------------------------------------------------
    integer i;

    initial begin
        err_cnt       = 0;
        out_cnt       = 0;
        total_checked = 0;

        do_reset;

        // ------------------------------------------------------------------
        // Test 1: Encrypt 4 consecutive blocks with separate iv_load
        // ------------------------------------------------------------------
        $display("=== Test 1: Encrypt back-to-back (Separate iv_load) ===");
        for (i = 0; i < NBLK; i = i + 1) begin
            in_mem[i]  = pt[i];
            exp_mem[i] = ct[i];
        end
        out_cnt = 0;
        load_iv_task(IV_V);
        for (i = 0; i < NBLK; i = i + 1)
            send_blk(in_mem[i]);
        drain;
        check_phase("Test1-Encrypt-SeparateIV");

        // ------------------------------------------------------------------
        // Test 2: Encrypt 4 blocks back-to-back with SIMULTANEOUS iv_load + valid_in
        //         Block 0 has iv_load=1 and valid_in=1 at the exact same edge!
        //         Blocks 1, 2, 3 follow immediately back-to-back without bubbles.
        // ------------------------------------------------------------------
        $display("=== Test 2: Encrypt back-to-back (Simultaneous iv_load + valid_in) ===");
        for (i = 0; i < NBLK; i = i + 1) begin
            in_mem[i]  = pt[i];
            exp_mem[i] = ct[i];
        end
        out_cnt = 0;
        send_blk_with_iv(IV_V, in_mem[0]); // Block 0: iv_load=1 & valid_in=1
        for (i = 1; i < NBLK; i = i + 1)
            send_blk(in_mem[i]);            // Blocks 1..3 back-to-back
        drain;
        check_phase("Test2-Encrypt-SimultaneousIV");

        // ------------------------------------------------------------------
        // Test 3: Decrypt (CT -> PT) with SIMULTANEOUS iv_load + valid_in AND bubbles
        // ------------------------------------------------------------------
        $display("=== Test 3: Decrypt with bubbles (Simultaneous iv_load + valid_in) ===");
        for (i = 0; i < NBLK; i = i + 1) begin
            in_mem[i]  = ct[i];
            exp_mem[i] = pt[i];
        end
        out_cnt = 0;
        send_blk_with_iv(IV_V, in_mem[0]); // Block 0 + IV load simultaneously
        send_bubble;
        send_bubble;
        send_blk(in_mem[1]);
        send_blk(in_mem[2]);
        send_bubble;
        send_blk(in_mem[3]);
        drain;
        check_phase("Test3-Decrypt-Bubbles");

        // ------------------------------------------------------------------
        // Test 4: Reload IV and re-encrypt (Simultaneous iv_load + valid_in)
        // ------------------------------------------------------------------
        $display("=== Test 4: Reload IV, re-encrypt (Simultaneous iv_load + valid_in) ===");
        for (i = 0; i < NBLK; i = i + 1) begin
            in_mem[i]  = pt[i];
            exp_mem[i] = ct[i];
        end
        out_cnt = 0;
        send_blk_with_iv(IV_V, in_mem[0]);
        for (i = 1; i < NBLK; i = i + 1)
            send_blk(in_mem[i]);
        drain;
        check_phase("Test4-ReloadIV-Encrypt");

        // ------------------------------------------------------------------
        // Summary
        // ------------------------------------------------------------------
        $display("--------------------------------------------------");
        if (err_cnt == 0)
            $display("ALL PASS: %0d blocks checked, 0 errors", total_checked);
        else
            $display("FAIL: %0d errors out of %0d blocks", err_cnt, total_checked);
        $display("--------------------------------------------------");
        $finish;
    end

    // Watchdog
    initial begin
        #(CLK_PERIOD * 8000);
        $display("TIMEOUT - simulation did not finish");
        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("tb_aes_ctr_mode.vcd");
        $dumpvars(0, tb_aes_ctr_mode);
    end

endmodule
