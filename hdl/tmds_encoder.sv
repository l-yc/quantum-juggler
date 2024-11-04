`timescale 1ns / 1ps
`default_nettype none

module tmds_encoder (
    input wire clk_in,
    input wire rst_in,
    input wire [7:0] data_in,  // video data (red, green or blue)
    input wire [1:0] control_in, //for blue set to {vs,hs}, else will be 0
    input wire ve_in,  // video data enable, to choose between control or video signal
    output logic [9:0] tmds_out
);

    logic [8:0] q_m;
    tm_choice mtm(.data_in(data_in), .qm_out(q_m));

    logic [3:0] n_1, n_0;
    always_comb begin
        n_1 = q_m[0];
        for (integer i=1; i<8; i=i+1) begin
            n_1 = n_1 + q_m[i];
        end
        n_0 = 4'd8 - n_1;
    end

    logic [4:0] cnt;

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            cnt <= 0;
            tmds_out <= 0;
        end else begin
            if (ve_in) begin

                if (cnt == 0 || n_1 == n_0) begin
                    tmds_out <= {~q_m[8], q_m[8], q_m[8] ? q_m[7:0] : ~q_m[7:0]};
                    if (q_m[8] == 0) begin
                        cnt <= cnt + n_0 - n_1;
                    end else begin
                        cnt <= cnt + n_1 - n_0;
                    end
                end else begin
                    if ((cnt[4] == 0 && n_1 > n_0) ||
                        (cnt[4] == 1 && n_0 > n_1)) begin
                        tmds_out <= {1'b1, q_m[8], ~q_m[7:0]};
                        cnt <= q_m[8] ? cnt + 2'b10 + n_0 - n_1 : cnt + n_0 - n_1;
                    end else begin
                        tmds_out <= {1'b0, q_m[8], q_m[7:0]};
                        cnt <= q_m[8] ? cnt + n_1 - n_0 : cnt - 2'b10 + n_1 - n_0;
                    end
                end

            end else begin
                cnt <= 0;
                case (control_in)
                    2'b00: tmds_out <= 10'b1101010100;
                    2'b01: tmds_out <= 10'b0010101011;
                    2'b10: tmds_out <= 10'b0101010100;
                    default: tmds_out <= 10'b1010101011;
                endcase
            end
        end
    end

endmodule //end tmds_encoder
`default_nettype wire
