`timescale 1ns / 1ps

module tb_aes_core();
    reg clk;
    reg rst_n;
    reg valid_in;
    reg [127:0] plaintext;
    reg [255:0] primekey;
    wire [127:0] ciphertext;
    wire valid_out;
    wire ready;

    aes_core dut(
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .plaintext(plaintext),
        .primekey(primekey),
        .ciphertext(ciphertext),
        .valid_out(valid_out),
        .ready(ready)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    reg [127:0] expected_ct;
    integer i;

    initial begin
        rst_n = 0;
        valid_in = 0;
        plaintext = 128'd0;
        primekey = 256'd0;
        expected_ct = 128'h8ea2b7ca516745bfeafc49904b496089;

        #30;
        @(negedge clk);
        rst_n = 1;

        #20;
        @(negedge clk);
        valid_in = 1;
        plaintext = 128'h00112233445566778899aabbccddeeff;
        primekey  = 256'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f;

        @(negedge clk);
        valid_in = 0;

        // Wait for core to complete all 14 rounds
        wait(valid_out);
        @(posedge clk);

        $display("------------------- AES-256 RESULT -------------------");
        $display("Plaintext : %h", plaintext);
        $display("Primekey  : %h", primekey);
        $display("Ciphertext: %h", ciphertext);
        $display("Expected  : %h", expected_ct);

        if (ciphertext === expected_ct) begin
            $display("--> TEST PASSED: Ciphertext matches expected value!");
        end else begin
            $display("--> TEST FAILED: Ciphertext mismatch!");
        end
        $display("------------------------------------------------------");

        #50;
        $stop;
    end

endmodule
