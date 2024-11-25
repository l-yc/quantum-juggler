`timescale 1ns / 1ps
`default_nettype none

module validate_pattern (
    input wire [2:0] pattern_in [6:0],
    input wire [2:0] pattern_length,
    output logic pattern_valid_out
    );

    // Since 7 is the maximum number in our pattern, 14 is the maximum number
    // of beats we need to check
    logic [13:0][2:0] pattern_repeated; // Input pattern repeated twice to compare
    logic [13:0][2:0] countdown [6:0];  // 7 14x3 packed array of countdowns
    logic [13:0] countdown_valid [6:0]; // 1 if we need to check value, 0 for ignore

    // For debugging in gtkwave
    logic [13:0][2:0] countdown_1, countdown_2, countdown_3, countdown_4, countdown_5, countdown_6, countdown_7;
    logic [13:0] countdown_valid_1, countdown_valid_2, countdown_valid_3, countdown_valid_4, countdown_valid_5, countdown_valid_6, countdown_valid_7;
    assign countdown_1 = countdown[0];
    assign countdown_2 = countdown[1];
    assign countdown_3 = countdown[2];
    assign countdown_4 = countdown[3];
    assign countdown_5 = countdown[4];
    assign countdown_6 = countdown[5];
    assign countdown_7 = countdown[6];
    assign countdown_valid_1 = countdown_valid[0];
    assign countdown_valid_2 = countdown_valid[1];
    assign countdown_valid_3 = countdown_valid[2];
    assign countdown_valid_4 = countdown_valid[3];
    assign countdown_valid_5 = countdown_valid[4];
    assign countdown_valid_6 = countdown_valid[5];
    assign countdown_valid_7 = countdown_valid[6];

    // Memoization block for checking if all values are valid
    logic [97:0] cumulative_valid;
    assign pattern_valid_out = cumulative_valid[97];

    always_comb begin
        // Repeat input pattern
        for (int i=0; i<14; i=i+1) begin
            for (int j=0; j<7; j=j+1) begin
                if (j < pattern_length && i * pattern_length + j < 14)
                    pattern_repeated[i*pattern_length+j] = pattern_in[j];
            end
        end

        // Perform countdown

        // Iterate on which countdown we are calculating
        for (int i=0; i<7; i=i+1) begin
            // Iterate on index of the ith countdown
            for (int j=0; j<14; j=j+1) begin
                if (i < pattern_length && i == j) begin
                    // Initialize countdown value
                    countdown[i][j] = pattern_in[i];
                    countdown_valid[i][j] = 0;
                end else if (i < pattern_length && j > i && countdown[i][j-1] > 0) begin
                    // Countdown
                    countdown[i][j] = countdown[i][j-1] - 1;
                    countdown_valid[i][j] = 1;
                end else begin
                    // Value can be ignored
                    countdown[i][j] = 0;
                    countdown_valid[i][j] = 0;
                end
            end
        end

        // Perform comparisons
        for (int i=0; i<7; i=i+1) begin
            for (int j=0; j<14; j=j+1) begin
                if (i == 0 && j == 0) begin
                    cumulative_valid[i*14+j] = !countdown_valid[i][j] || (pattern_repeated[j] != countdown[i][j]);
                end else begin
                    cumulative_valid[i*14+j] = cumulative_valid[i*14+j-1] && (!countdown_valid[i][j] || (pattern_repeated[j] != countdown[i][j]));
                end
            end
        end
    end
endmodule

`default_nettype wire
