`timescale 1ns / 1ps
`default_nettype none

module divider #(parameter WIDTH = 32) (input wire clk_in,
                input wire rst_in,
                input wire[WIDTH-1:0] dividend_in,
                input wire[WIDTH-1:0] divisor_in,
                input wire data_valid_in,
                output logic[WIDTH-1:0] quotient_out,
                output logic[WIDTH-1:0] remainder_out,
                output logic data_valid_out,
                output logic error_out,
                output logic busy_out);
  logic [WIDTH-1:0] quotient, dividend;
  logic [WIDTH-1:0] divisor;
  logic [5:0] count;
  logic [31:0] p;
  enum {RESTING, DIVIDING} state;
  always_ff @(posedge clk_in)begin
    if (rst_in)begin
      quotient <= 0;
      dividend <= 0;
      divisor <= 0;
      remainder_out <= 0;
      busy_out <= 1'b0;
      error_out <= 1'b0;
      state <= RESTING;
      data_valid_out <= 1'b0;
      count <= 0;
    end else begin
      case (state)
        RESTING: begin
          if (data_valid_in)begin
            state <= DIVIDING;
            quotient <= 0;
            dividend <= dividend_in;
            divisor <= divisor_in;
            busy_out <= 1'b1;
            error_out <= 1'b0;
            count <= 31;//load all up
            p <= 0;
          end
          data_valid_out <= 1'b0;
        end
        DIVIDING: begin
          if (count==1)begin
            state <= RESTING;
            if ({p_temp[30:0],div_temp[31]}>=divisor[31:0])begin
              remainder_out <= {p_temp[30:0],div_temp[31]} - divisor[31:0];
              quotient_out <= {div_temp[30:0],1'b1};
            end else begin
              remainder_out <= {p_temp[30:0],div_temp[31]};
              quotient_out <= {div_temp[30:0],1'b0};
            end
            busy_out <= 1'b0; //tell outside world i'm done
            error_out <= 1'b0;
            data_valid_out <= 1'b1; //good stuff!
          end else begin
            if ({p_temp[30:0],div_temp[31]}>=divisor[31:0])begin
              p <= {p_temp[30:0],div_temp[31]} - divisor[31:0];
              dividend <= {div_temp[30:0],1'b1};
            end else begin
              p <= {p_temp[30:0],div_temp[31]};
              dividend <= {div_temp[30:0],1'b0};
            end
            count <= count-2;
          end
        end
      endcase
    end
  end
  //extra:
  logic [31:0] p_temp;
  logic [31:0] div_temp;
  always_comb begin
    if ({p[30:0],dividend[31]}>=divisor[31:0])begin
      p_temp = {p[30:0],dividend[31]} - divisor[31:0];
      div_temp = {dividend[30:0],1'b1};
    end else begin
      p_temp = {p[30:0],dividend[31]};
      div_temp = {dividend[30:0],1'b0};
    end
  end
endmodule

`default_nettype wire
