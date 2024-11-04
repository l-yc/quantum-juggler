`default_nettype none
module center_of_mass (
    input wire clk_in,
    input wire rst_in,
    input wire [10:0] x_in,
    input wire [9:0]  y_in,
    input wire valid_in,
    input wire tabulate_in,
    output logic [10:0] x_out,
    output logic [9:0] y_out,
    output logic valid_out
    );

    logic [31:0] sum_x_pos;
    logic [31:0] tally_x;
    logic [31:0] quotient_x;
    logic data_valid_x_in;
    logic data_valid_x_out;
    logic x_validated;

    logic [31:0] sum_y_pos;
    logic [31:0] tally_y;
    logic [31:0] quotient_y;
    logic data_valid_y_in;
    logic data_valid_y_out;
    logic y_validated;

    divider x_divider(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .dividend_in(sum_x_pos),
        .divisor_in(tally_x),
        .data_valid_in(data_valid_x_in),
        .quotient_out(quotient_x),
        .remainder_out(),
        .data_valid_out(data_valid_x_out),
        .error_out(),
        .busy_out());

    divider y_divider(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .dividend_in(sum_y_pos),
        .divisor_in(tally_y),
        .data_valid_in(data_valid_y_in),
        .quotient_out(quotient_y),
        .remainder_out(),
        .data_valid_out(data_valid_y_out),
        .error_out(),
        .busy_out());

    enum {IDLE, COLLECT_DATA, CALCULATE, TRANSMIT} prev, state, next;

    assign data_valid_x_in = prev != CALCULATE && state == CALCULATE;
    assign data_valid_y_in = prev != CALCULATE && state == CALCULATE;

    always_comb begin
        if (rst_in) next = IDLE;
        else begin
            case (state)
                IDLE: next = COLLECT_DATA;
                COLLECT_DATA: begin
                    if (tabulate_in) next = CALCULATE;
                    else next = COLLECT_DATA;
                end CALCULATE: begin
                    if (sum_x_pos == 0 || sum_y_pos == 0) next = IDLE;
                    else if (x_validated && y_validated) next = TRANSMIT;
                    else next = CALCULATE;
                end TRANSMIT: next = IDLE;
                default: next = IDLE;
            endcase
        end
    end

    assign valid_out = state == TRANSMIT;

    always_ff @(posedge clk_in) begin
        case (state)
            IDLE: begin
                sum_x_pos <= 0;
                tally_x <= 0;
                sum_y_pos <= 0;
                tally_y <= 0;
                x_validated <= 0;
                y_validated <= 0;
            end COLLECT_DATA: begin
                if (0 <= x_in && x_in < 1280 && valid_in) begin
                    sum_x_pos = sum_x_pos + x_in;
                    tally_x = tally_x + 1;
                end
                if (0 <= y_in && y_in < 720 && valid_in) begin
                    sum_y_pos = sum_y_pos + y_in;
                    tally_y = tally_y + 1;
                end
            end CALCULATE: begin
                if (data_valid_x_out) begin
                    x_out <= quotient_x;
                    x_validated <= 1;
                end
                if (data_valid_y_out) begin
                    y_out <= quotient_y;
                    y_validated <= 1;
                end
            end
        endcase
        prev <= state;
        state <= next;
    end
endmodule
`default_nettype wire
