`timescale 1ns/1ps

module tb_aes_core();
    reg          clk, rst_n, valid_in;
    reg  [127:0] plaintext;
    reg  [127:0] primekey;
    wire [127:0] ciphertext;
    wire         valid_out;
    wire         ready_in;

    // Block C repeats Block A, Block D repeats Block B
    reg [127:0] pt_mem  [0:3];
    reg [127:0] key_mem [0:3];
    reg [127:0] res_mem [0:3];
    integer tx_idx, rx_idx, cycle_cnt;
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
    always #5 clk = ~clk;

    task print_matrix;
        input [127:0] data;
        integer r;
        begin
            for (r = 3; r >= 0; r = r - 1) begin
                $display(
                    "|\t%02h\t||\t%02h\t||\t%02h\t||\t%02h\t|",
                    data[r*8+96 +: 8], data[r*8+64 +: 8], data[r*8+32 +: 8], data[r*8 +: 8]
                );
            end
        end
    endtask

    // Tracks cycle count and internal stage status on every posedge
    always @(posedge clk) begin
        if (!rst_n) begin
            cycle_cnt <= 0;
        end else begin
            cycle_cnt <= cycle_cnt + 1;
            $display("[Cycle %2d] v_in=%b rdy_in=%b | in_reg_v=%b | S1(v=%b,R%2d) | S2(v=%b,R%2d) | loop=%b | v_out=%b",
                cycle_cnt + 1,
                valid_in, ready_in,
                dut.valid_in_reg,
                dut.stage1_valid, dut.stage1_round,
                dut.stage2_valid, dut.stage2_round,
                dut.stage2_loopback,
                valid_out
            );
        end
    end

    // Captures output ciphertexts independently whenever valid_out is asserted
    always @(posedge clk) begin
        if (!rst_n) begin
            rx_idx <= 0;
        end else if (valid_out && (rx_idx < 4)) begin
            res_mem[rx_idx] <= ciphertext;
            $display("  <<< [RX] Captured Ciphertext for Block %0d!", rx_idx);
            rx_idx <= rx_idx + 1;
        end
    end

    initial begin
        // Initialize 4 test blocks (0: A, 1: B, 2: C, 3: D)
        pt_mem[0]  = 128'h3243f6a8885a308d313198a2e0370734; // Block A
        key_mem[0] = 128'h2b7e151628aed2a6abf7158809cf4f3c;

        pt_mem[1]  = 128'h3243f6a8885a308d313198a2e0370736; // Block B
        key_mem[1] = 128'h2b7e151628aed2a6abf7158809cf4f36;

        pt_mem[2]  = pt_mem[0];                            // Block C (= Block A)
        key_mem[2] = key_mem[0];

        pt_mem[3]  = pt_mem[1];                            // Block D (= Block B)
        key_mem[3] = key_mem[1];

        rst_n     = 0;
        valid_in  = 0;
        plaintext = 128'd0;
        primekey  = 128'd0;
        #20;
        @(negedge clk);
        rst_n = 1;

        // Drive 4 blocks back-to-back using valid_in / ready_in handshake
        tx_idx    = 0;
        valid_in  = 1'b1;
        plaintext = pt_mem[0];
        primekey  = key_mem[0];
        while (tx_idx < 4) begin
            @(posedge clk);
            if (valid_in && ready_in) begin
                // Handshake completed: advance to next block
                $display("  >>> [TX] Accepted Block %0d (A=0, B=1, C=2, D=3)", tx_idx);
                tx_idx = tx_idx + 1;
                @(negedge clk);
                if (tx_idx < 4) begin
                    plaintext = pt_mem[tx_idx];
                    primekey  = key_mem[tx_idx];
                end else begin
                    // All 4 blocks sent; deassert valid_in
                    valid_in  = 1'b0;
                    plaintext = 128'd0;
                    primekey  = 128'd0;
                end
            end else begin
                // Backpressure: DUT is not ready, hold current block
                $display("  ... [TX] Block %0d stalled waiting for ready_in = 1", tx_idx);
            end
        end

        // Wait until RX monitor has collected all 4 ciphertexts before printing summary
        wait (rx_idx == 4);
        #20;

        $display("\n=================== 4-BLOCK SUMMARY ===================");
        $display("--- RESULT BLOCK A (0) ---"); print_matrix(res_mem[0]);
        $display("--- RESULT BLOCK B (1) ---"); print_matrix(res_mem[1]);
        $display("--- RESULT BLOCK C (2) ---"); print_matrix(res_mem[2]);
        $display("--- RESULT BLOCK D (3) ---"); print_matrix(res_mem[3]);

        if ((res_mem[0] === res_mem[2]) && (res_mem[1] === res_mem[3]))
            $display("\n[PASS] Block C matches Block A, and Block D matches Block B!");
        else
            $display("\n[FAIL] Mismatch detected between repeated blocks!");

        #50;
        $stop;
    end
endmodule