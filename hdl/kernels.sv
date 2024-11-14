`timescale 1ns / 1ps
`default_nettype none

module kernels (
    input wire rst_in,
    output logic signed [2:0][2:0][7:0] coeffs,
    output logic signed [7:0] shift);

    assign coeffs = { 
        coeffs_i[2][2],
        coeffs_i[2][1],
        coeffs_i[2][0],
        coeffs_i[1][2],
        coeffs_i[1][1],
        coeffs_i[1][0],
        coeffs_i[0][2],
        coeffs_i[0][1],
        coeffs_i[0][0]
    };

    logic signed [7:0] coeffs_i [2:0][2:0];
    always_comb begin
        coeffs_i[0][0] = rst_in ? 8'sd0 : 8'sd1;
        coeffs_i[0][1] = rst_in ? 8'sd0 : 8'sd2;
        coeffs_i[0][2] = rst_in ? 8'sd0 : 8'sd1;
        coeffs_i[1][0] = rst_in ? 8'sd0 : 8'sd2;
        coeffs_i[1][1] = rst_in ? 8'sd0 : 8'sd4;
        coeffs_i[1][2] = rst_in ? 8'sd0 : 8'sd2;
        coeffs_i[2][0] = rst_in ? 8'sd0 : 8'sd1;
        coeffs_i[2][1] = rst_in ? 8'sd0 : 8'sd2;
        coeffs_i[2][2] = rst_in ? 8'sd0 : 8'sd1;
        shift = rst_in ? 8'sd0 : 8'sd4;
    end
endmodule

`default_nettype wire

