module aes_core (
    input          clk,
    input          rst_n,
    input          valid_in,
    output         ready_in,     // Xuất trực tiếp trạng thái sẵn sàng nhận block mới
    input  [127:0] plaintext,
    input  [127:0] primekey,
    output [127:0] ciphertext,
    output         valid_out
);
    (* rom_style = "distributed" *) reg [7:0] rcon [10:1];
    initial begin
        rcon[1]  = 8'h01; rcon[2]  = 8'h02;
        rcon[3]  = 8'h04; rcon[4]  = 8'h08;
        rcon[5]  = 8'h10; rcon[6]  = 8'h20;
        rcon[7]  = 8'h40; rcon[8]  = 8'h80;
        rcon[9]  = 8'h1b; rcon[10] = 8'h36;
    end

    // Thanh ghi trạng thái các tầng
    reg [127:0] plaintext_reg, primekey_reg;
    reg         valid_in_reg;
    reg         stage1_valid, stage2_valid;
    reg [3:0]   stage1_round, stage2_round;
    reg [127:0] stage1_key, stage2_key;
    reg [127:0] stage1_reg, stage2_reg, ciphertext_reg;
    reg         valid_out_reg;

    // Logic điều khiển luồng 2-way interleaving
    wire stage2_loopback = stage2_valid && (stage2_round < 4'd10);
    wire stage1_consume  = valid_in_reg && !stage2_loopback;

    assign ready_in = !valid_in_reg || !stage2_loopback;
    wire   fire_in  = valid_in && ready_in;

    // Khối tổ hợp AES
    wire [127:0] after_shiftrows, start_of_round, key_exp_out, state_out;
    wire         bypass_mix = (stage2_round == 4'd10);
    wire [31:0]  round_rcon = {rcon[stage1_round], 24'h000000};

    addroundkey addkey_init (
        .state_in  (plaintext_reg),
        .roundkey  (primekey_reg),
        .state_out (start_of_round)
    );

    keyexpansion keygen (
        .keyin      (stage1_key),
        .round_rcon (round_rcon),
        .keyout     (key_exp_out)
    );

    sub_shift stage1 (
        .state_in        (stage1_reg),
        .after_shiftrows (after_shiftrows)
    );

    mix_add stage2 (
        .state_in   (stage2_reg),
        .keyin      (stage2_key),
        .bypass_mix (bypass_mix),
        .state_out  (state_out)
    );

    // 1. Tầng đệm đầu vào (Holding register: giữ dữ liệu nếu stage1 đang bận)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            plaintext_reg <= 128'd0;
            primekey_reg  <= 128'd0;
            valid_in_reg  <= 1'b0;
        end else if (fire_in) begin
            plaintext_reg <= plaintext;
            primekey_reg  <= primekey;
            valid_in_reg  <= 1'b1;
        end else if (stage1_consume) begin
            valid_in_reg  <= 1'b0;
        end
    end

    // 2. Đường lặp 2 tầng (stage1 <-> stage2)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage1_valid   <= 1'b0;
            stage2_valid   <= 1'b0;
            stage1_round   <= 4'd1;
            stage2_round   <= 4'd1;
            stage1_key     <= 128'd0;
            stage2_key     <= 128'd0;
            stage1_reg     <= 128'd0;
            stage2_reg     <= 128'd0;
            ciphertext_reg <= 128'd0;
            valid_out_reg  <= 1'b0;
        end else begin
            // Stage 1: ưu tiên dữ liệu đang chạy dở từ stage 2
            if (stage2_loopback) begin
                stage1_valid <= 1'b1;
                stage1_round <= stage2_round + 4'd1;
                stage1_reg   <= state_out;
                stage1_key   <= stage2_key;
            end else if (valid_in_reg) begin
                stage1_valid <= 1'b1;
                stage1_round <= 4'd1;
                stage1_reg   <= start_of_round;
                stage1_key   <= primekey_reg;
            end else begin
                stage1_valid <= 1'b0;
            end

            // Stage 2
            if (stage1_valid) begin
                stage2_valid <= 1'b1;
                stage2_round <= stage1_round;
                stage2_reg   <= after_shiftrows;
                stage2_key   <= key_exp_out;
            end else begin
                stage2_valid <= 1'b0;
            end

            // Đầu ra
            valid_out_reg <= (stage2_valid && stage2_round == 4'd10);
            if (stage2_valid && stage2_round == 4'd10)
                ciphertext_reg <= state_out;
        end
    end

    assign valid_out  = valid_out_reg;
    assign ciphertext = valid_out_reg ? ciphertext_reg : 128'd0;

endmodule