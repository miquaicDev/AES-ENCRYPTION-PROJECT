`timescale 1ns / 1ps
// ============================================================================
// Testbench for AES-256 CTR mode (Iterative Core)
//
// NIST SP 800-38A Section F.5.5 test vectors (AES-256 CTR):
//   Key  : 603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4
//   IV   : f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff
//   PT[0]: 6bc1bee22e409f96e93d7e117393172a -> CT[0]: 601ec313775789a5b7a7f504bbf3d228
//   PT[1]: ae2d8a571e03ac9c9eb76fac45af8e51 -> CT[1]: f443e3ca4d62b59aca84e990cacaf5c5
//   PT[2]: 30c81c46a35ce411e5fbc1191a0a52ef -> CT[2]: 2b0930daa23de94ce87017ba2d84988d
//   PT[3]: f69f2445df4f9b17ad2b417be66c3710 -> CT[3]: dfc9c58db67aada613c2dd08457941a6
//
// Test scenarios:
//   Test 1: Encrypt 4 blocks (Separate iv_load, then send blocks with ready_in)
//   Test 2: Encrypt 4 blocks with SIMULTANEOUS iv_load + valid_in at Block 0
//   Test 3: Decrypt 4 blocks with SIMULTANEOUS iv_load + valid_in (CT -> PT)
//   Test 4: Reload IV on-the-fly and re-encrypt
// ============================================================================
module tb_aes_ctr_mode;

    parameter CLK_PERIOD = 10;
    parameter NBLK       = 4;

    reg         clk;
    reg         rst_n;
    reg         iv_load;
    reg [127:0] iv;
    reg [255:0] key;
    reg         valid_in;
    wire        ready_in;
    reg [127:0] data_in;
    wire [127:0] data_out;
    wire         valid_out;

    aes_ctr_mode_iter dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .iv_load  (iv_load),
        .iv       (iv),
        .key      (key),
        .valid_in (valid_in),
        .ready_in (ready_in),
        .data_in  (data_in),
        .data_out (data_out),
        .valid_out(valid_out)
    );

    initial clk = 0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // -----------------------------------------------------------------------
    // NIST test vectors
    // -----------------------------------------------------------------------
    reg [127:0] pt   [0:NBLK-1];
    reg [127:0] ct   [0:NBLK-1];
    reg [255:0] KEY_V;
    reg [127:0] IV_V;
    reg [127:0] in_mem  [0:NBLK-1];
    reg [127:0] exp_mem [0:NBLK-1];

    initial begin
        KEY_V = 256'h603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4;
        IV_V  = 128'hf0f1f2f3f4f5f6f7f8f9fafbfcfdfeff;

        pt[0] = 128'h6bc1bee22e409f96e93d7e117393172a;
        pt[1] = 128'hae2d8a571e03ac9c9eb76fac45af8e51;
        pt[2] = 128'h30c81c46a35ce411e5fbc1191a0a52ef;
        pt[3] = 128'hf69f2445df4f9b17ad2b417be66c3710;

        ct[0] = 128'h601ec313775789a5b7a7f504bbf3d228;
        ct[1] = 128'hf443e3ca4d62b59aca84e990cacaf5c5;
        ct[2] = 128'h2b0930daa23de94ce87017ba2d84988d;
        ct[3] = 128'hdfc9c58db67aada613c2dd08457941a6;
    end

    // -----------------------------------------------------------------------
    // Output checker
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

    // Load IV separately
    task load_iv_task;
        input [127:0] v;
        begin
            @(posedge clk);
            while (!ready_in) @(posedge clk);
            #1;
            iv_load = 1'b1;
            iv      = v;
            @(posedge clk); #1;
            iv_load = 1'b0;
            iv      = 128'd0;
        end
    endtask

    // Send one block: wait for ready_in, then assert valid_in for 1 cycle
    task send_blk;
        input [127:0] d;
        begin
            @(posedge clk);
            while (!ready_in) @(posedge clk);
            #1;
            valid_in = 1'b1;
            data_in  = d;
            @(posedge clk); #1;
            valid_in = 1'b0;
            data_in  = 128'd0;
        end
    endtask

    // Send block 0 with SIMULTANEOUS iv_load and valid_in asserted at the same clock edge
    task send_blk_with_iv;
        input [127:0] v;
        input [127:0] d;
        begin
            @(posedge clk);
            while (!ready_in) @(posedge clk);
            #1;
            iv_load  = 1'b1;
            iv       = v;
            valid_in = 1'b1;
            data_in  = d;
            @(posedge clk); #1;
            iv_load  = 1'b0;
            iv       = 128'd0;
            valid_in = 1'b0;
            data_in  = 128'd0;
        end
    endtask

    // Drain: wait until all outputs have arrived
    task drain;
        begin
            while (out_cnt < NBLK) @(posedge clk);
            repeat (10) @(posedge clk);
        end
    endtask

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
        // Test 1: Encrypt 4 blocks (Separate iv_load, then send_blk)
        // ------------------------------------------------------------------
        $display("=== Test 1: Encrypt 4 blocks (Separate iv_load) ===");
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
        // Test 2: Encrypt 4 blocks with SIMULTANEOUS iv_load + valid_in at Block 0
        // ------------------------------------------------------------------
        $display("=== Test 2: Encrypt 4 blocks (Simultaneous iv_load + valid_in) ===");
        for (i = 0; i < NBLK; i = i + 1) begin
            in_mem[i]  = pt[i];
            exp_mem[i] = ct[i];
        end
        out_cnt = 0;
        // Block 0 with simultaneous iv_load + valid_in
        send_blk_with_iv(IV_V, in_mem[0]);
        // Remaining blocks
        for (i = 1; i < NBLK; i = i + 1)
            send_blk(in_mem[i]);
        drain;
        check_phase("Test2-Encrypt-SimultaneousIV");

        // ------------------------------------------------------------------
        // Test 3: Decrypt 4 blocks with SIMULTANEOUS iv_load + valid_in (CT -> PT)
        // ------------------------------------------------------------------
        $display("=== Test 3: Decrypt 4 blocks (Simultaneous iv_load + valid_in) ===");
        for (i = 0; i < NBLK; i = i + 1) begin
            in_mem[i]  = ct[i];
            exp_mem[i] = pt[i];
        end
        out_cnt = 0;
        send_blk_with_iv(IV_V, in_mem[0]);
        for (i = 1; i < NBLK; i = i + 1)
            send_blk(in_mem[i]);
        drain;
        check_phase("Test3-Decrypt-SimultaneousIV");

        // ------------------------------------------------------------------
        // Test 4: Reload IV on-the-fly and re-encrypt
        // ------------------------------------------------------------------
        $display("=== Test 4: Reload IV, re-encrypt ===");
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
        #(CLK_PERIOD * 30000);
        $display("TIMEOUT");
        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("tb_aes_ctr_mode.vcd");
        $dumpvars(0, tb_aes_ctr_mode);
    end

endmodule
