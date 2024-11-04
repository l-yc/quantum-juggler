`timescale 1ns / 1ps
`default_nettype none


module convolution (
    input wire clk_in,
    input wire rst_in,
    input wire [KERNEL_SIZE-1:0][15:0] data_in,
    input wire [10:0] hcount_in,
    input wire [9:0] vcount_in,
    input wire data_valid_in,
    output logic data_valid_out,
    output logic [10:0] hcount_out,
    output logic [9:0] vcount_out,
    output logic [15:0] line_out
    );
    parameter K_SELECT = 0;
    localparam KERNEL_SIZE = 3;

    logic signed [2:0][2:0][7:0] coeffs;
    logic signed [7:0] shift;
    kernels #(.K_SELECT(K_SELECT)) kernels (
        .rst_in(rst_in),
        .coeffs(coeffs),
        .shift(shift)
    );

    logic [15:0] cache [KERNEL_SIZE-1:0][KERNEL_SIZE-1:0];
    logic signed [12:0] multiply_red_res [KERNEL_SIZE-1:0][KERNEL_SIZE-1:0];
    logic signed [13:0] multiply_green_res [KERNEL_SIZE-1:0][KERNEL_SIZE-1:0];
    logic signed [12:0] multiply_blue_res [KERNEL_SIZE-1:0][KERNEL_SIZE-1:0];
    logic signed [20:0] added_red;
    logic signed [21:0] added_green;
    logic signed [20:0] added_blue;
    logic signed [20:0] shifted_red;
    logic signed [21:0] shifted_green;
    logic signed [20:0] shifted_blue;
    logic [4:0] red_out;
    logic [5:0] green_out;
    logic [4:0] blue_out;
    assign line_out = {red_out, green_out, blue_out};

    // 4-stage pipeline. 2 for waiting for the cache to populate.
    // 1 for multiplying. 1 for adding and shifting.
    logic data_valid_pipe [3:0];
    logic [10:0] hcount_pipe [3:0];
    logic [9:0] vcount_pipe [3:0];
    assign data_valid_out = data_valid_pipe[3];
    assign hcount_out = hcount_pipe[3];
    assign vcount_out = vcount_pipe[3];

    // For debugging
    logic [15:0] center_cache;
    assign center_cache = cache[1][1];

    always_ff @(posedge clk_in) begin
        data_valid_pipe[0] <= data_valid_in;
        hcount_pipe[0] <= hcount_in;
        vcount_pipe[0] <= vcount_in;

        for (integer i=0; i<3; i=i+1) begin
            data_valid_pipe[i+1] <= data_valid_pipe[i];
            hcount_pipe[i+1] <= hcount_pipe[i];
            vcount_pipe[i+1] <= vcount_pipe[i];
        end

        if (rst_in) begin
            for (integer i=0; i<KERNEL_SIZE; i=i+1) begin
                for (integer j=0; j<KERNEL_SIZE; j=j+1) begin
                    cache[i][j] <= 0;
                end
            end
        end else begin
            // Move cache and add next values
            for (integer i=0; i<KERNEL_SIZE; i=i+1) begin
                if (data_valid_in) begin
                    cache[i][0] <= cache[i][1];
                    cache[i][1] <= cache[i][2];
                    cache[i][2] <= data_in[i];
                end
            end

            // Multiplication logic
            for (integer i=0; i<3; i=i+1) begin
                multiply_red_res[0][i]   <= $signed(coeffs[0][i]) * $signed({1'b0, cache[0][i][15:11]});
                multiply_green_res[0][i] <= $signed(coeffs[0][i]) * $signed({1'b0, cache[0][i][10:5]});
                multiply_blue_res[0][i]  <= $signed(coeffs[0][i]) * $signed({1'b0, cache[0][i][4:0]});
                multiply_red_res[1][i]   <= $signed(coeffs[1][i]) * $signed({1'b0, cache[1][i][15:11]});
                multiply_green_res[1][i] <= $signed(coeffs[1][i]) * $signed({1'b0, cache[1][i][10:5]});
                multiply_blue_res[1][i]  <= $signed(coeffs[1][i]) * $signed({1'b0, cache[1][i][4:0]});
                multiply_red_res[2][i]   <= $signed(coeffs[2][i]) * $signed({1'b0, cache[2][i][15:11]});
                multiply_green_res[2][i] <= $signed(coeffs[2][i]) * $signed({1'b0, cache[2][i][10:5]});
                multiply_blue_res[2][i]  <= $signed(coeffs[2][i]) * $signed({1'b0, cache[2][i][4:0]});
            end

            // Negative or overflow check and assign output
            if (shifted_red < 21'sb0) red_out <= 0;
            else if (shifted_red > 21'sd31) red_out <= 31;
            else red_out <= shifted_red[4:0];

            if (shifted_green < 22'sb0) green_out <= 0;
            else if (shifted_green > 22'sd63) green_out <= 63;
            else green_out <= shifted_green[5:0];

            if (shifted_blue < 21'sb0) blue_out <= 0;
            else if (shifted_blue > 21'sd31) blue_out <= 31;
            else blue_out <= shifted_blue[4:0];
        end
    end

    // Addition and shifting logic
    assign added_red = $signed(multiply_red_res[0][0]) + $signed(multiply_red_res[0][1]) + $signed(multiply_red_res[0][2]) +
                       $signed(multiply_red_res[1][0]) + $signed(multiply_red_res[1][1]) + $signed(multiply_red_res[1][2]) +
                       $signed(multiply_red_res[2][0]) + $signed(multiply_red_res[2][1]) + $signed(multiply_red_res[2][2]);
    assign shifted_red = $signed(added_red) >>> shift;

    assign added_green = $signed(multiply_green_res[0][0]) + $signed(multiply_green_res[0][1]) + $signed(multiply_green_res[0][2]) +
                         $signed(multiply_green_res[1][0]) + $signed(multiply_green_res[1][1]) + $signed(multiply_green_res[1][2]) +
                         $signed(multiply_green_res[2][0]) + $signed(multiply_green_res[2][1]) + $signed(multiply_green_res[2][2]);
    assign shifted_green = $signed(added_green) >>> shift;

    assign added_blue = $signed(multiply_blue_res[0][0]) + $signed(multiply_blue_res[0][1]) + $signed(multiply_blue_res[0][2]) +
                        $signed(multiply_blue_res[1][0]) + $signed(multiply_blue_res[1][1]) + $signed(multiply_blue_res[1][2]) +
                        $signed(multiply_blue_res[2][0]) + $signed(multiply_blue_res[2][1]) + $signed(multiply_blue_res[2][2]);
    assign shifted_blue = $signed(added_blue) >>> shift;

endmodule

`default_nettype wire

