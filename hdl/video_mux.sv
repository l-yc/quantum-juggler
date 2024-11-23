`timescale 1ns / 1ps
`default_nettype none

module video_mux (
    input wire [1:0] bg_in, // choose background
    input wire target_in,   // choose target
    input wire [23:0] camera_pixel_in, // 16 bits from camera 5:6:5
    input wire [7:0] camera_y_in,      // y channel of ycrcb camera conversion
    input wire [7:0] channel_in,       // the channel from selection module
    input wire thresholded_pixel_in,
    input wire [23:0] trajectory_pixel_in,
    input wire crosshair_in,
    output logic [23:0] pixel_out
);

    logic [23:0] l_1;
    always_comb begin
        case (bg_in)
            2'b00:   l_1 = camera_pixel_in;
            2'b01:   l_1 = {channel_in, channel_in, channel_in};
            2'b10:   l_1 = (thresholded_pixel_in != 0) ? 24'hFFFFFF : 24'h000000;
            default: l_1 = (thresholded_pixel_in != 0) ? 24'hFF77AA : {camera_y_in, camera_y_in, camera_y_in};
        endcase
    end

    logic [23:0] l_2;
    always_comb begin
        case (target_in)
            1'b00:   l_2 = l_1;
            //default: l_2 = crosshair_in ? 24'h00FF00 : l_1;
            default: l_2 = (trajectory_pixel_in > 0) ? trajectory_pixel_in : l_1;
        endcase
    end

    assign pixel_out = l_2;
endmodule

`default_nettype wire
