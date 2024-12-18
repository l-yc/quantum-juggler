`timescale 1ns / 1ps
`default_nettype none

module generate_pattern (
    input wire clk_in,
    input wire rst_in,
    input wire new_beat,
    input wire [2:0] pattern_in,
    input wire [2:0] pattern_length,
    output logic [2:0] num_balls_out,
    output logic [2:0] pattern_out [6:0],
    output logic pattern_valid_out,
    output logic [6:0] cat_out,
    output logic [7:0] an_out
    );

    // Sum up the values in the output pattern
    logic [5:0] sum_pattern;
    assign sum_pattern = pattern_out[0] + pattern_out[1] + pattern_out[2] + pattern_out[3] + 
                         pattern_out[4] + pattern_out[5] + pattern_out[6];

    // Create pulse for valid pattern
    // 6-stage pipeline for pattern_valid_out to account for division
    logic pattern_valid_pipe [5:0];
    logic pattern_valid_prev;
    logic pattern_valid_pulse;
    assign pattern_valid_out = pattern_valid_pipe[5];
    always_ff @(posedge clk_in) begin
        pattern_valid_pulse <= !pattern_valid_prev && pattern_valid_pipe[0];
        pattern_valid_prev <= pattern_valid_pipe[0];
        for (int i=1; i<6; i=i+1) begin
            pattern_valid_pipe[i] <= pattern_valid_pipe[i-1];
        end
    end

    logic [5:0] num_balls_full;
    assign num_balls_out = num_balls_full[2:0];
    divider #(.WIDTH(6)) ball_calc (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .dividend_in(sum_pattern),
        .divisor_in({3'b0, pattern_length}),
        .data_valid_in(pattern_valid_pulse),
        .quotient_out(num_balls_full),
        .remainder_out(),
        .data_valid_out(),
        .error_out(),
        .busy_out());

    logic [7:0]  segment_state;
    logic [31:0] segment_counter;
    logic [6:0]  led_out;
    logic [3:0]  routed_vals;
    logic [6:0]  bto7s_led_out;

    logic [2:0] pattern_index;
    logic [2:0] pattern_temp [6:0];
    logic pattern_temp_valid;
    validate_pattern validate_pattern_inst (
        .pattern_in(pattern_temp),
        .pattern_length(pattern_length),
        .pattern_valid_out(pattern_temp_valid));

    enum logic {INPUT, VALIDATE} state;
    assign state = pattern_index >= pattern_length ? VALIDATE : INPUT;

    assign cat_out = ~led_out;
    assign an_out = ~segment_state;

//    // For debugging in gtkwave
//    logic [2:0] pattern_out_1, pattern_out_2, pattern_out_3, pattern_out_4, pattern_out_5, pattern_out_6, pattern_out_7;
//    assign pattern_out_1 = pattern_out[0];
//    assign pattern_out_2 = pattern_out[1];
//    assign pattern_out_3 = pattern_out[2];
//    assign pattern_out_4 = pattern_out[3];
//    assign pattern_out_5 = pattern_out[4];
//    assign pattern_out_6 = pattern_out[5];
//    assign pattern_out_7 = pattern_out[6];
//    logic [2:0] pattern_temp_1, pattern_temp_2, pattern_temp_3, pattern_temp_4, pattern_temp_5, pattern_temp_6, pattern_temp_7;
//    assign pattern_temp_1 = pattern_temp[0];
//    assign pattern_temp_2 = pattern_temp[1];
//    assign pattern_temp_3 = pattern_temp[2];
//    assign pattern_temp_4 = pattern_temp[3];
//    assign pattern_temp_5 = pattern_temp[4];
//    assign pattern_temp_6 = pattern_temp[5];
//    assign pattern_temp_7 = pattern_temp[6];

    always_comb begin
        if ((state == VALIDATE && pattern_temp_valid) || state == INPUT) begin
            case (segment_state)
                8'b0000_0001: led_out = pattern_valid_out ? bto7s_led_out : 7'b0;
                8'b0000_0010: led_out = (pattern_index >= 6 && pattern_length > 6) ? bto7s_led_out : 7'b0;
                8'b0000_0100: led_out = (pattern_index >= 5 && pattern_length > 5) ? bto7s_led_out : 7'b0;
                8'b0000_1000: led_out = (pattern_index >= 4 && pattern_length > 4) ? bto7s_led_out : 7'b0;
                8'b0001_0000: led_out = (pattern_index >= 3 && pattern_length > 3) ? bto7s_led_out : 7'b0;
                8'b0010_0000: led_out = (pattern_index >= 2 && pattern_length > 2) ? bto7s_led_out : 7'b0;
                8'b0100_0000: led_out = (pattern_index >= 1 && pattern_length > 1) ? bto7s_led_out : 7'b0;
                8'b1000_0000: led_out = (pattern_index >= 0 && pattern_length > 0) ? bto7s_led_out : 7'b0;
                default:      led_out = 7'b0;
            endcase
        end else begin
            case (segment_state)
                8'b0000_0001: led_out = 7'b1010000;
                8'b0000_0010: led_out = 7'b1010000;
                8'b0000_0100: led_out = 7'b1111001;
                default:      led_out = 7'b0000000;
            endcase
        end

        case (segment_state)
            8'b0000_0001: routed_vals = num_balls_out;
            8'b0000_0010: routed_vals = (pattern_index == 6) ? pattern_in : pattern_temp[6];
            8'b0000_0100: routed_vals = (pattern_index == 5) ? pattern_in : pattern_temp[5];
            8'b0000_1000: routed_vals = (pattern_index == 4) ? pattern_in : pattern_temp[4];
            8'b0001_0000: routed_vals = (pattern_index == 3) ? pattern_in : pattern_temp[3];
            8'b0010_0000: routed_vals = (pattern_index == 2) ? pattern_in : pattern_temp[2];
            8'b0100_0000: routed_vals = (pattern_index == 1) ? pattern_in : pattern_temp[1];
            8'b1000_0000: routed_vals = (pattern_index == 0) ? pattern_in : pattern_temp[0];
            default:      routed_vals = 4'b0;
        endcase
    end

    bto7s mbto7s (.x_in(routed_vals), .s_out(bto7s_led_out));

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            pattern_index <= 0;
            for (int i=0; i<7; i=i+1) begin
                pattern_temp[i] <= 0;
            end
            pattern_valid_pipe[0] <= 0;
            segment_state <= 8'b0000_0001;
            segment_counter <= 0;
        end else begin
            if (segment_counter == 100000) begin
                segment_counter <= 32'd0;
                segment_state <= {segment_state[6:0],segment_state[7]};
            end else begin
                segment_counter <= segment_counter + 1;
            end

            if (new_beat) begin
                if (state == VALIDATE) begin
                    for (int i = 0; i < 7; i = i + 1) begin
                        pattern_temp[i] <= 0;
                    end
                    pattern_valid_pipe[0] <= 0;
                    pattern_index <= 0;
                end else begin
                    pattern_temp[pattern_index] <= pattern_in;
                    pattern_index <= pattern_index + 1;
                end
            end else if (state == VALIDATE) begin
                for (int i=0; i<7; i=i+1) begin
                    pattern_out[i] <= pattern_temp[i];
                end
                pattern_valid_pipe[0] <= pattern_temp_valid;
            end
        end
    end
endmodule

module bto7s (input wire [3:0] x_in, output logic [6:0] s_out);

    logic sa, sb, sc, sd, se, sf, sg;
    assign s_out = {sg, sf, se, sd, sc, sb, sa};

    // Array of bits that are "one hot" with numbers 0 through 15
    logic [15:0] num;

    assign num[0] = ~x_in[3] && ~x_in[2] && ~x_in[1] && ~x_in[0];
    assign num[1] = ~x_in[3] && ~x_in[2] && ~x_in[1] && x_in[0];
    assign num[2] = x_in == 4'd2;
    assign num[3] = x_in == 4'd3;
    assign num[4] = x_in == 4'd4;
    assign num[5] = x_in == 4'd5;
    assign num[6] = x_in == 4'd6;
    assign num[7] = x_in == 4'd7;
    assign num[8] = x_in == 4'd8;
    assign num[9] = x_in == 4'd9;
    assign num[10] = x_in == 4'd10;
    assign num[11] = x_in == 4'd11;
    assign num[12] = x_in == 4'd12;
    assign num[13] = x_in == 4'd13;
    assign num[14] = x_in == 4'd14;
    assign num[15] = x_in == 4'd15;

    assign sa = num[0] || num[2] || num[3] || num[5] || num[6] || num[7] || num[8] || num[9] || num[10] || num[12] ||num[14] ||num[15];
    assign sb = num[0] || num[1] || num[2] || num[3] || num[4] || num[7] || num[8] || num[9] || num[10] || num[13];
    assign sc = num[0] || num[1] || num[3] || num[4] || num[5] || num[6] || num[7] || num[8] || num[9] || num[10] || num[11] || num[13];
    assign sd = num[0] || num[2] || num[3] || num[5] || num[6] || num[8] || num[9] || num[11] || num[12] || num[13] || num[14];
    assign se = num[0] || num[2] || num[6] || num[8] || num[10] || num[11] || num[12] || num[13] || num[14] || num[15];
    assign sf = num[0] || num[4] || num[5] || num[6] || num[8] || num[9] || num[10] || num[11] || num[12] || num[14] || num[15];
    assign sg = num[2] || num[3] || num[4] || num[5] || num[6] || num[8] || num[9] || num[10] || num[11] || num[13] || num[14] ||num[15];
endmodule

`default_nettype wire

