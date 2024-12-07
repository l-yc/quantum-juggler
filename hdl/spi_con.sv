module spi_con
     #(parameter DATA_WIDTH = 8,
       parameter DATA_CLK_PERIOD = 100
      )
      (input wire   clk_in, //system clock (100 MHz)
       input wire   rst_in, //reset in signal
       input wire   [DATA_WIDTH-1:0] data_in, //data to send
       input wire   trigger_in, //start a transaction
       output logic [DATA_WIDTH-1:0] data_out, //data received!
       output logic data_valid_out, //high when output data is present.
 
       output logic chip_data_out, //(COPI)
       input wire   chip_data_in, //(CIPO)
       output logic chip_clk_out, //(DCLK)
       output logic chip_sel_out // (CS)
      );
  //your code here
    parameter DATA_COUNTER_SIZE = $clog2(DATA_WIDTH);
    parameter CLK_COUNTER_SIZE = $clog2(DATA_CLK_PERIOD);
    logic [DATA_COUNTER_SIZE:0] data_counter;
    logic [CLK_COUNTER_SIZE:0] clk_counter; 
    logic [DATA_WIDTH-1:0] current_data;

    always_ff @(posedge clk_in)begin
        if (data_valid_out) begin
            data_valid_out <= 0;
        end
        if (rst_in) begin
            data_out <= 0;
            data_valid_out <= 0;
            chip_data_out <= 0;
            chip_clk_out <= 0;
            chip_sel_out <= 1;
        end else if (chip_sel_out == 0) begin
            if (clk_counter >= DATA_CLK_PERIOD-2) begin
                clk_counter <= 0;
                if (chip_clk_out == 1) begin
                    if (data_counter == DATA_WIDTH) begin
                        chip_sel_out <= 1;
                        data_valid_out <= 1;
                    end else begin
                        chip_data_out <= current_data[DATA_WIDTH-1];
                        current_data <= {current_data[DATA_WIDTH-2:0], 1'b0}; 
                    end
                    chip_clk_out <= 0;
                end else begin
                    data_out <= {data_out[DATA_WIDTH-2:0], chip_data_in};
                    data_counter <= data_counter + 1;
                    chip_clk_out <= 1;
                end
            end else begin
                clk_counter <= clk_counter + 2;
            end
        end else if (trigger_in) begin
            chip_sel_out <= 0;
            chip_data_out <= data_in[DATA_WIDTH-1];
            current_data <= {data_in[DATA_WIDTH-2:0], 1'b0}; 
            data_counter <= 0;
            clk_counter <= 0;
            chip_clk_out <= 0;
            data_out <= 0;
        end
    end
endmodule