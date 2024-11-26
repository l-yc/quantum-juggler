`timescale 1ns / 1ps
`default_nettype none

module minimum (
    input wire [6:0][8:0] vals_in,
    input wire [2:0] max,
    output logic [2:0] minimum_index
    );

    logic [8:0] min [6:0];
    logic [2:0] index [6:0];
    assign minimum_index = index[max-1];

    always_comb begin
        min[0] = vals_in[0];
        index[0] = 0;
        for (int i=1; i<7; i=i+1) begin
            if (vals_in[i] < min[i-1]) begin
                min[i] = vals_in[i];
                index[i] = i;
            end else begin
                min[i] = min[i-1];
                index[i] = index[i-1];
            end
        end
    end
endmodule

`default_nettype wire
