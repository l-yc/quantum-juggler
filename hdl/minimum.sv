`timescale 1ns / 1ps
`default_nettype none

module minimum (
    input wire [6:0][8:0] vals_in,
    input wire [2:0] max,
    output logic [2:0] minimum_index
    );

    logic [8:0] min_0 [7:0];
    logic [2:0] index_0 [7:0];
    logic [8:0] min_1 [3:0];
    logic [2:0] index_1 [3:0];
    logic [8:0] min_2 [1:0];
    logic [2:0] index_2 [1:0];

    always_comb begin
        for (int i=0; i<7; i=i+1) begin
            min_0[i] = i < max ? vals_in[i] : 9'b1_1111_1111;
            index_0[i] = i;
        end
        min_0[7] = 9'b1_1111_1111;
        index_0[7] = 0;
        for (int j=0; j<4; j=j+1) begin
            if (min_0[2*j] < min_0[2*j+1]) begin
                min_1[j] = min_0[2*j];
                index_1[j] = index_0[2*j];
            end else begin
                min_1[j] = min_0[2*j+1];
                index_1[j] = index_0[2*j+1];
            end
        end
        for (int j=0; j<2; j=j+1) begin
            if (min_1[2*j] < min_1[2*j+1]) begin
                min_2[j] = min_1[2*j];
                index_2[j] = index_1[2*j];
            end else begin
                min_2[j] = min_1[2*j+1];
                index_2[j] = index_1[2*j+1];
            end
        end
        if (min_2[0] < min_2[1]) begin
            minimum_index = index_2[0];
        end else begin
            minimum_index = index_2[1];
        end
    end
endmodule

`default_nettype wire
