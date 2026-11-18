module aes_ctr_mode_iter (
    input              clk,
    input              rst_n,
    // IV interface (có thể kích đồng thời với block đầu tiên ngay sau reset)
    input              iv_load,
    input      [127:0] iv,
    // Key
    input      [127:0] key,
    // Data interface (ready_in nối trực tiếp từ aes_core)
    input              valid_in,
    output             ready_in,
    input      [127:0] data_in,
    output reg [127:0] data_out,
    output reg         valid_out
);

    wire push = valid_in && ready_in;

    // -----------------------------------------------------------------------
    // 1. Bộ đếm Counter + MUX nạp IV tức thời (Zero-Bubble IV Load)
    // -----------------------------------------------------------------------
    reg  [127:0] ctr_reg;
    wire [127:0] ctr_current = iv_load ? iv : ctr_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ctr_reg <= 128'd0;
        else if (push)
            ctr_reg <= ctr_current + 128'd1;
        else if (iv_load)
            ctr_reg <= iv;
    end

    // -----------------------------------------------------------------------
    // 2. Lõi AES Core (tự quản lý luồng 2-way và xuất ready_in)
    // -----------------------------------------------------------------------
    wire [127:0] keystream;
    wire         ks_valid;

    aes_core u_aes_core (
        .clk        (clk),
        .rst_n      (rst_n),
        .valid_in   (valid_in),
        .ready_in   (ready_in),
        .plaintext  (ctr_current),
        .primekey   (key),
        .ciphertext (keystream),
        .valid_out  (ks_valid)
    );

    // -----------------------------------------------------------------------
    // 3. Bộ đệm vòng 4 thanh ghi 128-bit giữ data_in
    //    Khớp với tối đa 3 block trong aes_core + 1 tầng thanh ghi đầu ra
    // -----------------------------------------------------------------------
    reg [127:0] data_buf [0:3];
    reg [1:0]   wr_ptr;
    reg [1:0]   rd_ptr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_buf[0] <= 128'd0;
            data_buf[1] <= 128'd0;
            data_buf[2] <= 128'd0;
            data_buf[3] <= 128'd0;
            wr_ptr      <= 2'd0;
        end else if (push) begin
            data_buf[wr_ptr] <= data_in;
            wr_ptr           <= wr_ptr + 2'd1;
        end
    end

    // -----------------------------------------------------------------------
    // 4. Thanh ghi đầu ra
    // -----------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out  <= 128'd0;
            valid_out <= 1'b0;
            rd_ptr    <= 2'd0;
        end else begin
            valid_out <= ks_valid;
            if (ks_valid) begin
                data_out <= keystream ^ data_buf[rd_ptr];
                rd_ptr   <= rd_ptr + 2'd1;
            end
        end
    end

endmodule