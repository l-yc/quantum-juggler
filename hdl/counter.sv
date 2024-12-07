module counter(     input wire clk_in,
                    input wire rst_in,
                    input wire [31:0] period_in,
                    output logic [31:0] count_out
              );

    //your code here
    always_ff @(posedge clk_in)begin
      count_out <= (count_out+1<period_in) && !rst_in ? count_out+1:0;
    end
endmodule