`default_nettype none

module minimum (
    input wire [11:0] vals_in0,
    input wire [11:0] vals_in1,
    input wire [11:0] vals_in2,
    input wire [11:0] vals_in3,
    input wire [11:0] vals_in4,
    input wire [11:0] vals_in5,
    input wire [11:0] vals_in6,
    input wire [11:0] vals_in7,
    input wire [2:0] max,
    output logic [2:0] minimum_index
    );
    logic [11:0] min;
    logic [2:0] index;
    always_comb begin
        minimum_index = 0;
//        min = vals_in0;
//        index = 0;
//        if (max <= 3'b010 && vals_in1 < min) begin
//            min = vals_in1;
//            index = 1;
//        end
//        if (max <= 3'b011 && vals_in2 < min) begin
//            min = vals_in2;
//            index = 2;
//        end
//        if (max <= 3'b100 && vals_in3 < min) begin
//            min = vals_in3;
//            index = 3;
//        end
//        if (max <= 3'b101 && vals_in4 < min) begin
//            min = vals_in4;
//            index = 4;
//        end
//        if (max <= 3'b110 && vals_in5 < min) begin
//            min = vals_in5;
//            index = 5;
//        end
//        if (max <= 3'b111 && vals_in6 < min) begin
//            min = vals_in6;
//            index = 6;
//        end
//        if (max == 3'b111 && vals_in7 < min) begin
//            min = vals_in7;
//            index = 7;
//        end
//        minimum_index = index;
    end
endmodule

`default_nettype wire
