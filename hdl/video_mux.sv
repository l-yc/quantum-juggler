`timescale 1ns / 1ps
`default_nettype none

module video_mux (
    input wire bg_in,                  // choose background
    input wire target_in,              // choose target
    input wire [23:0] camera_pixel_in, // 16 bits from camera 5:6:5
    input wire [7:0] sel_channel_in,   // y channel of ycrcb camera conversion
    input wire thresholded_pixel_in,
    input wire [23:0] trajectory_pixel_in,
    input wire crosshair_in,
    input wire judgment_correct,
    input wire judgment_in,
    output logic [23:0] pixel_out
);

    logic [23:0] l_1;
    always_comb begin
        if (bg_in)
            l_1 = (thresholded_pixel_in != 0) ? 24'hFF77AA : {sel_channel_in, sel_channel_in, sel_channel_in};
        else
            l_1 = camera_pixel_in;
    end

    logic [23:0] l_2;
    always_comb begin
        if (target_in)
			//l_2 = (trajectory_pixel_in > 0) ? trajectory_pixel_in : l_1;
            //l_2 = crosshair_in ? 24'h00FF00 : l_1;
            //l_2 = crosshair_in ? 24'h00FF00 : (trajectory_pixel_in > 0) ? trajectory_pixel_in : l_1;
            l_2 = 
				judgment_in ? (judgment_correct ? 24'h0000FF : 24'hFF0000) :
				crosshair_in ? 24'h00FF00 :
				(trajectory_pixel_in > 0) ? trajectory_pixel_in :
				l_1;
        else
            l_2 = l_1;
    end

    assign pixel_out = l_2;
endmodule

`default_nettype wire
