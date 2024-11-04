`timescale 1ns / 1ps
`default_nettype none

module pixel_reconstruct
    #(parameter HCOUNT_WIDTH = 11,
	  parameter VCOUNT_WIDTH = 10
	 )
     (input wire clk_in,
      input wire rst_in,
      input wire camera_pclk_in,
      input wire camera_hs_in,
      input wire camera_vs_in,
      input wire [7:0] camera_data_in,
      output logic pixel_valid_out,
      output logic [HCOUNT_WIDTH-1:0] pixel_hcount_out,
      output logic [VCOUNT_WIDTH-1:0] pixel_vcount_out,
      output logic [15:0] pixel_data_out
	 );

	 // previous value of PCLK
	 logic pclk_prev;

	 // true when pclk transitions from 0 to 1
	 logic camera_sample_valid;
	 assign camera_sample_valid = ~pclk_prev & camera_pclk_in;
	 
	 // previous value of camera data, from last valid sample!
	 // should NOT update on every cycle of clk_in, only
	 // when samples are valid.
	 logic [7:0] last_sampled_data;

	 // flag indicating whether the last byte has been transmitted or not.
	 logic half_pixel_ready;
     logic first_horz;
     logic first_vert;

	 always_ff @(posedge clk_in) begin
        pixel_valid_out <= 0;
        if (rst_in) begin
            pixel_valid_out <= 0;
            pixel_hcount_out <= 0;
            pixel_vcount_out <= 0;
            pixel_data_out <= 0;
            half_pixel_ready <= 0;
            first_horz <= 1;
            first_vert <= 1;
        end else if (camera_sample_valid) begin
            if (camera_hs_in && camera_vs_in) begin
                half_pixel_ready <= !half_pixel_ready;
                if (half_pixel_ready) begin
                    pixel_data_out <= {last_sampled_data, camera_data_in};
                    pixel_valid_out <= 1;
                    pixel_hcount_out <= pixel_hcount_out + 1;
                    if (first_horz) begin
                        pixel_hcount_out <= 0;
                        first_horz <= 0;
                        pixel_vcount_out <= pixel_vcount_out + 1;
                        if (first_vert) begin
                            pixel_vcount_out <= 0;
                            first_vert <= 0;
                        end
                    end
                end
            end else if (!camera_vs_in) begin
                half_pixel_ready <= 0;
                first_horz <= 1;
                first_vert <= 1;
            end else if (!camera_hs_in) begin
                half_pixel_ready <= 0;
                first_horz <= 1;
            end

            last_sampled_data <= camera_data_in; 
        end
        pclk_prev <= camera_pclk_in;
	 end

endmodule

`default_nettype wire
