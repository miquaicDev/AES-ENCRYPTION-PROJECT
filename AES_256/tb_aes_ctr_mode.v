`timescale 1ns / 1ps

module tb_aes_ctr_mode;
    parameter CLK_PERIOD = 10;
    parameter NBLK = 4;

    reg clk;
    reg rst_n;
    reg iv_load;
    reg [127:0] iv;
    reg [255:0] key;
    reg valid_in;
    reg [127:0] data_in;
    wire [127:0] data_out;
    wire valid_out;
    wire ready;

    aes_ctr_mode dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .iv_load  (iv_load),
        .iv       (iv),
        .key      (key),
        .valid_in (valid_in),
        .data_in  (data_in),
        .data_out (data_out),
        .valid_out(valid_out),
        .ready    (ready)
    );

    initial clk = 0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    reg [127:0] pt [0:NBLK-1];
    reg [127:0] ct [0:NBLK-1];
    reg [255:0] KEY_V;
    reg [127:0] IV_V;

    reg [127:0] exp_mem [0:NBLK-1];
    integer out_cnt;
    integer err_cnt;
    integer total_checked;

    initial begin
        // NIST SP 800-38A Section F.5.5 (AES-256 CTR)
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

    // Monitor output
    always @(posedge clk) begin
        if (rst_n && valid_out) begin
            total_checked = total_checked + 1;
            if (out_cnt < NBLK) begin
                if (data_out !== exp_mem[out_cnt]) begin
                    err_cnt = err_cnt + 1;
                    $display("[%0t ns] ERROR blk %0d: got %h, expected %h", $time, out_cnt, data_out, exp_mem[out_cnt]);
                end else begin
                    $display("[%0t ns] OK    blk %0d: %h", $time, out_cnt, data_out);
                end
            end else begin
                err_cnt = err_cnt + 1;
                $display("[%0t ns] ERROR: unexpected block index %0d", $time, out_cnt);
            end
            out_cnt = out_cnt + 1;
        end
    end

    task do_reset;
        begin
            rst_n    = 1'b0;
            iv_load  = 1'b0;
            iv       = 128'd0;
            key      = 256'd0;
            valid_in = 1'b0;
            data_in  = 128'd0;
            repeat (4) @(posedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task load_iv;
        input [127:0] v;
        begin
            @(negedge clk);
            iv_load = 1'b1;
            iv      = v;
            @(negedge clk);
            iv_load = 1'b0;
            iv      = 128'd0;
        end
    endtask

    task send_block;
        input [127:0] d;
        begin
            // Wait until core is ready to accept a new block
            while (!ready) @(posedge clk);
            @(negedge clk);
            valid_in = 1'b1;
            data_in  = d;
            key      = KEY_V;
            @(negedge clk);
            valid_in = 1'b0;
            data_in  = 128'd0;
        end
    endtask

    integer i;

    initial begin
        err_cnt       = 0;
        out_cnt       = 0;
        total_checked = 0;

        do_reset;

        //--------------------------------------------------------------
        // Test 1: NIST SP 800-38A Encrypt 4 blocks
        //--------------------------------------------------------------
        $display("==================================================");
        $display("=== Test 1: NIST SP 800-38A AES-256 CTR Encrypt ===");
        $display("==================================================");
        for (i = 0; i < NBLK; i = i + 1) begin
            exp_mem[i] = ct[i];
        end
        out_cnt = 0;
        load_iv(IV_V);

        for (i = 0; i < NBLK; i = i + 1) begin
            send_block(pt[i]);
        end

        // Wait for all outputs
        wait(out_cnt == NBLK);
        repeat (5) @(posedge clk);

        //--------------------------------------------------------------
        // Test 2: NIST SP 800-38A Decrypt (Ciphertext -> Plaintext)
        //--------------------------------------------------------------
        $display("==================================================");
        $display("=== Test 2: NIST SP 800-38A AES-256 CTR Decrypt ===");
        $display("==================================================");
        for (i = 0; i < NBLK; i = i + 1) begin
            exp_mem[i] = pt[i];
        end
        out_cnt = 0;
        load_iv(IV_V);

        for (i = 0; i < NBLK; i = i + 1) begin
            send_block(ct[i]);
        end

        // Wait for all outputs
        wait(out_cnt == NBLK);
        repeat (5) @(posedge clk);

        //--------------------------------------------------------------
        // Summary
        //--------------------------------------------------------------
        $display("==================================================");
        if (err_cnt == 0) begin
            $display("--> ALL TESTS PASSED: %0d blocks verified successfully, 0 errors!", total_checked);
        end else begin
            $display("--> TESTS FAILED: %0d errors encountered!", err_cnt);
        end
        $display("==================================================");

        #100;
        $finish;
    end

    // Watchdog timer
    initial begin
        #(CLK_PERIOD * 5000);
        $display("ERROR: Simulation TIMEOUT!");
        $finish;
    end

endmodule
