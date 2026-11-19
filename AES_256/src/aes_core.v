module aes_core (
    input          clk,
    input          rst_n,
    input          valid_in,
    output         ready_in,
    input  [127:0] plaintext,
    input  [255:0] primekey,
    output [127:0] ciphertext,
    output         valid_out
);
    (* rom_style = "distributed" *) reg [7:0] rcon [7:0];
    initial begin
        rcon[0] = 8'h00;
        rcon[1] = 8'h01;
        rcon[2] = 8'h02;
        rcon[3] = 8'h04;
        rcon[4] = 8'h08;
        rcon[5] = 8'h10;
        rcon[6] = 8'h20;
        rcon[7] = 8'h40;
    end

    // Pipeline stage registers
    reg [127:0] plaintext_reg;
    reg [255:0] primekey_reg;
    reg         valid_in_reg;

    reg         stage1_valid, stage2_valid;
    reg [3:0]   stage1_round, stage2_round;
    reg [127:0] stage1_kprev, stage1_kcur;
    reg [127:0] stage2_kprev, stage2_kcur;
    reg [127:0] stage1_reg, stage2_reg, ciphertext_reg;
    reg         valid_out_reg;

    // 2-way interleaving control logic
    wire stage2_loopback = stage2_valid && (stage2_round < 4'd14);
    assign ready_in      = !valid_in_reg || !stage2_loopback;
    wire stage1_consume  = valid_in_reg && !stage2_loopback;
    wire accept_in       = valid_in && ready_in;

    wire [127:0] after_shiftrows, start_of_round, key_exp_out, state_out;
    wire         bypass_mix = (stage2_round == 4'd14);
    wire [7:0]   rcon_byte  = rcon[stage1_round[3:1]];

    addroundkey addkey_init (
        .state_in  (plaintext_reg),
        .roundkey  (primekey_reg[255:128]),
        .state_out (start_of_round)
    );

    keyexpansion256 keygen (
        .key_prev   (stage1_kprev),
        .key_cur    (stage1_kcur),
        .round      (stage1_round),
        .rcon_byte  (rcon_byte),
        .key_new    (key_exp_out)
    );

    sub_shift stage1 (
        .state_in        (stage1_reg),
        .after_shiftrows (after_shiftrows)
    );

    mix_add stage2 (
        .state_in   (stage2_reg),
        .keyin      (stage2_kcur),
        .bypass_mix (bypass_mix),
        .state_out  (state_out)
    );

    // Holding / Skid input buffer
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            plaintext_reg <= 128'd0;
            primekey_reg  <= 256'd0;
            valid_in_reg  <= 1'b0;
        end else if (accept_in) begin
            plaintext_reg <= plaintext;
            primekey_reg  <= primekey;
            valid_in_reg  <= 1'b1;
        end else if (stage1_consume) begin
            valid_in_reg  <= 1'b0;
        end
    end

    // 2-stage round ping-pong loop (14 rounds)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage1_valid   <= 1'b0;
            stage2_valid   <= 1'b0;
            stage1_round   <= 4'd1;
            stage2_round   <= 4'd1;
            stage1_kprev   <= 128'd0;
            stage1_kcur    <= 128'd0;
            stage2_kprev   <= 128'd0;
            stage2_kcur    <= 128'd0;
            stage1_reg     <= 128'd0;
            stage2_reg     <= 128'd0;
            ciphertext_reg <= 128'd0;
            valid_out_reg  <= 1'b0;
        end else begin
            // Stage 1
            if (stage2_loopback) begin
                stage1_valid <= 1'b1;
                stage1_round <= stage2_round + 4'd1;
                stage1_reg   <= state_out;
                stage1_kprev <= stage2_kprev;
                stage1_kcur  <= stage2_kcur;
            end else if (valid_in_reg) begin
                stage1_valid <= 1'b1;
                stage1_round <= 4'd1;
                stage1_reg   <= start_of_round;
                stage1_kprev <= primekey_reg[255:128]; // RK0
                stage1_kcur  <= primekey_reg[127:0];   // RK1
            end else begin
                stage1_valid <= 1'b0;
            end

            // Stage 2
            if (stage1_valid) begin
                stage2_valid <= 1'b1;
                stage2_round <= stage1_round;
                stage2_reg   <= after_shiftrows;
                if (stage1_round == 4'd1) begin
                    stage2_kprev <= stage1_kprev;
                    stage2_kcur  <= stage1_kcur;
                end else begin
                    stage2_kprev <= stage1_kcur;
                    stage2_kcur  <= key_exp_out;
                end
            end else begin
                stage2_valid <= 1'b0;
            end

            // Output stage
            valid_out_reg <= (stage2_valid && stage2_round == 4'd14);
            if (stage2_valid && stage2_round == 4'd14) begin
                ciphertext_reg <= state_out;
            end
        end
    end

    assign valid_out  = valid_out_reg;
    assign ciphertext = valid_out_reg ? ciphertext_reg : 128'd0;

endmodule
