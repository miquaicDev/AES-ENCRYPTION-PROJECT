// AES-128 CTR Mode - Fully Unrolled Pipeline
//
// Architecture:
//   aes_core is a fully-unrolled pipeline with 21 register stages:
//     1 input FF (plaintext_reg, valid_in_reg)
//     + 9 × main_round (2 FF each = 18 FF)
//     + 1 × final_round (2 FF)
//     = 21 FF stages → 20 clock-period internal latency
//       (valid_in=1 at edge T → ks_valid wire = 1 after edge T+20)
//
// CTR mode (NIST SP 800-38A):
//   keystream[i] = AES_Encrypt(IV + i)
//   output[i]   = data_in[i] ^ keystream[i]
//
// Features:
//   - Zero-bubble IV Load: Supports asserting iv_load and valid_in simultaneously
//     in the very same cycle! The first block is immediately encrypted using IV,
//     and the counter increments to IV + 1 for subsequent blocks.
//   - Also backward-compatible with separate iv_load (iv_load pulsed before valid_in).
//   - Fully pipelined throughput: 1 block/cycle back-to-back.

module aes_ctr_mode (
    input              clk,
    input              rst_n,
    // IV interface
    input              iv_load,     // pulse: load IV (can be asserted simultaneously with valid_in)
    input      [127:0] iv,
    // Key (assumed stable during operation)
    input      [127:0] key,
    // Data interface (fully pipelined: accept 1 block/cycle)
    input              valid_in,
    input      [127:0] data_in,     // plaintext (encrypt) or ciphertext (decrypt)
    output reg [127:0] data_out,
    output reg         valid_out
);

    // -----------------------------------------------------------------------
    // 1. Counter register with Zero-Bubble IV Load MUX
    //    When iv_load = 1:
    //      - ctr_current is immediately 'iv' for the current cycle's block.
    //      - If valid_in = 1, ctr_reg updates to 'iv + 1' for the next cycle.
    //      - If valid_in = 0, ctr_reg updates to 'iv'.
    //    When iv_load = 0:
    //      - ctr_current is ctr_reg.
    //      - If valid_in = 1, ctr_reg increments by 1.
    // -----------------------------------------------------------------------
    reg  [127:0] ctr_reg;
    wire [127:0] ctr_current = iv_load ? iv : ctr_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ctr_reg <= 128'd0;
        else if (valid_in)
            ctr_reg <= ctr_current + 128'd1;
        else if (iv_load)
            ctr_reg <= iv;
    end

    // -----------------------------------------------------------------------
    // 2. AES core (fully-unrolled pipeline, 20-cycle internal latency)
    // -----------------------------------------------------------------------
    wire [127:0] keystream;
    wire         ks_valid;

    aes_core u_aes_core (
        .clk        (clk),
        .rst_n      (rst_n),
        .valid_in   (valid_in),
        .plaintext  (ctr_current),     // pre-increment counter value for this block
        .primekey   (key),
        .ciphertext (keystream),
        .valid_out  (ks_valid)
    );

    // -----------------------------------------------------------------------
    // 3. Delay line for data_in alignment
    //    AES_LATENCY = 21 entries (dly[0..20]).
    //    Matches 20 internal cycles of aes_core + 1 cycle for output register.
    // -----------------------------------------------------------------------
    localparam AES_LATENCY = 21;

    reg [127:0] dly [0:AES_LATENCY-1];
    integer k;

    always @(posedge clk) begin
        dly[0] <= data_in;
        for (k = 1; k < AES_LATENCY; k = k + 1)
            dly[k] <= dly[k-1];
    end

    // -----------------------------------------------------------------------
    // 4. Output register
    // -----------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out  <= 128'd0;
            valid_out <= 1'b0;
        end else begin
            valid_out <= ks_valid;
            data_out  <= keystream ^ dly[AES_LATENCY-1];
        end
    end

endmodule
