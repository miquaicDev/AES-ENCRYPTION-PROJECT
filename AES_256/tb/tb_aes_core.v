`timescale 1ns / 1ps

module tb_aes_core();
    parameter CLK_PERIOD = 10;

    reg clk;
    reg rst_n;
    reg valid_in;
    wire ready_in;
    reg [127:0] plaintext;
    reg [255:0] primekey;
    wire [127:0] ciphertext;
    wire valid_out;

    aes_core dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .valid_in   (valid_in),
        .ready_in   (ready_in),
        .plaintext  (plaintext),
        .primekey   (primekey),
        .ciphertext (ciphertext),
        .valid_out  (valid_out)
    );

    initial clk = 0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // Test vectors
    reg [255:0] KEY0, KEY1;
    reg [127:0] PT0, PT1;
    reg [127:0] EXP_CT0, EXP_CT1;

    initial begin
        // NIST FIPS-197 Appendix C.3
        KEY0    = 256'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f;
        PT0     = 128'h00112233445566778899aabbccddeeff;
        EXP_CT0 = 128'h8ea2b7ca516745bfeafc49904b496089;

        // NIST SP 800-38A Section F.5.1
        KEY1    = 256'h603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4;
        PT1     = 128'h6bc1bee22e409f96e93d7e117393172a;
        EXP_CT1 = 128'hf3eed1bdb5d2a03c064b5a7e3db181f8;
    end

    integer err_cnt = 0;

    task do_reset;
        begin
            rst_n    = 1'b0;
            valid_in = 1'b0;
            plaintext = 128'd0;
            primekey  = 256'd0;
            repeat (4) @(posedge clk);
            #1 rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task send_blk;
        input [127:0] pt;
        input [255:0] key;
        begin
            @(posedge clk);
            while (!ready_in) @(posedge clk);
            #1;
            valid_in  = 1'b1;
            plaintext = pt;
            primekey  = key;
            @(posedge clk); #1;
            valid_in  = 1'b0;
        end
    endtask

    initial begin
        err_cnt = 0;
        do_reset;

        // -------------------------------------------------------------
        // Test 1: Single Block (FIPS-197 App C.3)
        // -------------------------------------------------------------
        $display("==================================================");
        $display("=== Test 1: Single Block (FIPS-197 App C.3) ===");
        $display("==================================================");
        send_blk(PT0, KEY0);

        wait(valid_out);
        #1;
        $display("Plaintext : %h", PT0);
        $display("Primekey  : %h", KEY0);
        $display("Ciphertext: %h", ciphertext);
        $display("Expected  : %h", EXP_CT0);

        if (ciphertext === EXP_CT0) begin
            $display("--> Test 1 PASSED!");
        end else begin
            $display("--> Test 1 FAILED!");
            err_cnt = err_cnt + 1;
        end

        repeat (5) @(posedge clk);

        // -------------------------------------------------------------
        // Test 2: Two Consecutive Blocks (2-way Interleaved Back-to-Back)
        // -------------------------------------------------------------
        $display("==================================================");
        $display("=== Test 2: Two Blocks (2-way Interleaved) ===");
        $display("==================================================");
        send_blk(PT0, KEY0);
        send_blk(PT1, KEY1);

        // Wait for first block
        wait(valid_out);
        #1;
        $display("Block 0 Out: %h (Exp: %h)", ciphertext, EXP_CT0);
        if (ciphertext === EXP_CT0) begin
            $display("--> Block 0 PASSED!");
        end else begin
            $display("--> Block 0 FAILED!");
            err_cnt = err_cnt + 1;
        end

        // Wait for second block (should arrive immediately 1 cycle later!)
        @(posedge clk);
        #1;
        if (valid_out) begin
            $display("Block 1 Out: %h (Exp: %h)", ciphertext, EXP_CT1);
            if (ciphertext === EXP_CT1) begin
                $display("--> Block 1 PASSED!");
            end else begin
                $display("--> Block 1 FAILED!");
                err_cnt = err_cnt + 1;
            end
        end else begin
            // If not immediately 1 cycle later, wait for it
            wait(valid_out);
            #1;
            $display("Block 1 Out: %h (Exp: %h)", ciphertext, EXP_CT1);
            if (ciphertext === EXP_CT1) begin
                $display("--> Block 1 PASSED!");
            end else begin
                $display("--> Block 1 FAILED!");
                err_cnt = err_cnt + 1;
            end
        end

        repeat (5) @(posedge clk);

        $display("==================================================");
        if (err_cnt == 0)
            $display("ALL AES-256 CORE TESTS PASSED!");
        else
            $display("AES-256 CORE TESTS FAILED with %0d errors!", err_cnt);
        $display("==================================================");

        #50;
        $finish;
    end

    // Watchdog
    initial begin
        #(CLK_PERIOD * 2000);
        $display("ERROR: Simulation TIMEOUT!");
        $finish;
    end

endmodule
