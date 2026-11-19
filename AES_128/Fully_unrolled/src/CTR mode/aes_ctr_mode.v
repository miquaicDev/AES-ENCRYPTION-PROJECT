module aes_ctr_mode (
    input              clk,
    input              rst_n,
    //load IV can be asserted simultaneously with valid_in
    input              iv_load,     
    input      [127:0] iv,
    input      [127:0] key,
    input              valid_in,
    input      [127:0] data_in,
    output reg [127:0] data_out,
    output reg         valid_out
);

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

    wire [127:0] keystream;
    wire         ks_valid;
    aes_core u_aes_core (
        .clk        (clk),
        .rst_n      (rst_n),
        .valid_in   (valid_in),
        .plaintext  (ctr_current),
        .primekey   (key),
        .ciphertext (keystream),
        .valid_out  (ks_valid)
    );

    localparam AES_LATENCY = 21;
    //shift reg rather than ptr method in iterative mode
    reg [127:0] dly [0:AES_LATENCY-1];
    integer k;
    always @(posedge clk) begin
        dly[0] <= data_in;
        for (k = 1; k < AES_LATENCY; k = k + 1)
            dly[k] <= dly[k-1];
    end

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
