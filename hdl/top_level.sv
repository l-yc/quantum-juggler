`timescale 1ns / 1ps
`default_nettype none

module top_level (
    input wire          clk_100mhz,
    output logic [15:0] led,
    // camera bus
    input wire [7:0]    camera_d,  // 8 parallel data wires
    output logic        cam_xclk,  // XC driving camera
    input wire          cam_hsync, // camera hsync wire
    input wire          cam_vsync, // camera vsync wire
    input wire          cam_pclk,  // camera pixel clock
    inout wire          i2c_scl,   // i2c inout clock
    inout wire          i2c_sda,   // i2c inout data
    input wire [15:0]   sw,
    input wire [3:0]    btn,
    output logic [2:0]  rgb0,
    output logic [2:0]  rgb1,
    // seven segment
    output logic [3:0]  ss0_an, // anode control for upper four digits of seven-seg display
    output logic [3:0]  ss1_an, // anode control for lower four digits of seven-seg display
    output logic [6:0]  ss0_c,  // cathode controls for the segments of upper four digits
    output logic [6:0]  ss1_c,  // cathod controls for the segments of lower four digits
    // hdmi port
    output logic [2:0]  hdmi_tx_p, // hdmi output signals (positives) (blue, green, red)
    output logic [2:0]  hdmi_tx_n, // hdmi output signals (negatives) (blue, green, red)
    output logic        hdmi_clk_p, hdmi_clk_n // differential hdmi clock
    );

    // shut up those RGBs
    assign rgb0 = 0;
    assign rgb1 = 0;

    // Clock and Reset Signals
    logic sys_rst_camera;
    logic sys_rst_pixel;
    logic clk_camera;
    logic clk_pixel;
    logic clk_5x;
    logic clk_xc;
    logic clk_100_passthrough;

    // clocking wizards to generate the clock speeds we need for our different domains
    // clk_camera: 200MHz, fast enough to comfortably sample the cameera's PCLK (50MHz)
    cw_hdmi_clk_wiz wizard_hdmi(
        .sysclk(clk_100_passthrough),
        .clk_pixel(clk_pixel),
        .clk_tmds(clk_5x),
        .reset(0));
    cw_fast_clk_wiz wizard_migcam(
        .clk_in1(clk_100mhz),
        .clk_camera(clk_camera),
        .clk_xc(clk_xc),
        .clk_100(clk_100_passthrough),
        .reset(0));

    // assign camera's xclk to pmod port: drive the operating clock of the camera!
    // this port also is specifically set to high drive by the XDC file.
    assign cam_xclk = clk_xc;
    assign sys_rst_camera = btn[0]; //use for resetting camera side of logic
    assign sys_rst_pixel = btn[0]; //use for resetting hdmi/draw side of logic

    // video signal generator signals
    logic        hsync_hdmi;
    logic        vsync_hdmi;
    logic [10:0] hcount_hdmi;
    logic [9:0]  vcount_hdmi;
    logic        active_draw_hdmi;
    logic        new_frame_hdmi;
    logic [5:0]  frame_count_hdmi;
    logic        nf_hdmi;

    // rgb output values
    logic [7:0] red,green,blue;

    // ** Handling input from the camera **

    // synchronizers to prevent metastability
    logic [7:0] camera_d_buf [1:0];
    logic       cam_hsync_buf [1:0];
    logic       cam_vsync_buf [1:0];
    logic       cam_pclk_buf [1:0];

    always_ff @(posedge clk_camera) begin
        camera_d_buf <= {camera_d, camera_d_buf[1]};
        cam_pclk_buf <= {cam_pclk, cam_pclk_buf[1]};
        cam_hsync_buf <= {cam_hsync, cam_hsync_buf[1]};
        cam_vsync_buf <= {cam_vsync, cam_vsync_buf[1]};
    end

    logic [10:0] camera_hcount;
    logic [9:0]  camera_vcount;
    logic [15:0] camera_pixel;
    logic        camera_valid;

    pixel_reconstruct(
        .clk_in(clk_camera),
        .rst_in(sys_rst_camera),
        .camera_pclk_in(cam_pclk_buf[0]),
        .camera_hs_in(cam_hsync_buf[0]),
        .camera_vs_in(cam_vsync_buf[0]),
        .camera_data_in(camera_d_buf[0]),
        .pixel_valid_out(camera_valid),
        .pixel_hcount_out(camera_hcount),
        .pixel_vcount_out(camera_vcount),
        .pixel_data_out(camera_pixel));

    // clock domain cross (from clk_camera to clk_pixel)
    // switching from camera clock domain to pixel clock domain early
    // this lets us do convolution on the 74.25 MHz clock rather than the
    // 200 MHz clock domain that the camera lives on.
    logic empty;
    logic cdc_valid;
    logic [15:0] cdc_pixel;
    logic [10:0] cdc_hcount;
    logic [9:0] cdc_vcount;

    fifo cdc_fifo(
        .wr_clk(clk_camera),
        .full(),
        .din({camera_hcount, camera_vcount, camera_pixel}),
        .wr_en(camera_valid),
        .rd_clk(clk_pixel),
        .empty(empty),
        .dout({cdc_hcount, cdc_vcount, cdc_pixel}),
        .rd_en(1));
    assign cdc_valid = ~empty; //watch when empty. Ready immediately if something there

    logic [10:0] f0_hcount; // hcount from filter0 module
    logic [9:0] f0_vcount;  // vcount from filter0 module
    logic [15:0] f0_pixel;  // pixel data from filter0 module
    logic f0_valid;         // valid signals for filter0 module
    filter #(.HRES(1280),.VRES(720))
    filtern(
        .clk_in(clk_pixel),
        .rst_in(sys_rst_pixel),
        .data_valid_in(cdc_valid),
        .pixel_data_in(cdc_pixel),
        .hcount_in(cdc_hcount),
        .vcount_in(cdc_vcount),
        .data_valid_out(f0_valid),
        .pixel_data_out(f0_pixel),
        .hcount_out(f0_hcount),
        .vcount_out(f0_vcount));

    logic [10:0] ds_hcount; // hcount to downsample
    logic [9:0] ds_vcount;  // vcount to downsample
    logic [15:0] ds_pixel;  // pixel data to downsample
    logic ds_valid;         // valid signals to downsample

    // Either go through (btn[2]=0) or bypass (btn[2]==1) Gaussian blur
    always_comb @(posedge clk_pixel) begin
        if (btn[2]) begin
            ds_hcount = cdc_hcount;
            ds_vcount = cdc_vcount;
            ds_pixel  = cdc_pixel;
            ds_valid  = cdc_valid;
        end else begin
            ds_hcount = f0_hcount;
            ds_vcount = f0_vcount;
            ds_pixel  = f0_pixel;
            ds_valid  = f0_valid;
        end
    end

    localparam FB_DEPTH = 320*180;
    localparam FB_SIZE = $clog2(FB_DEPTH);
    logic [FB_SIZE-1:0] addra; // address to write to in frame buffer
    logic valid_camera_mem;    // enable writing pixel data to frame buffer
    logic [15:0] camera_mem;   // pixel data into frame buffer

    always_ff @(posedge clk_pixel) begin
        valid_camera_mem <= ds_valid;
        if (ds_hcount[1:0] == 0 && ds_vcount[1:0] == 0) begin
            addra <= (ds_hcount >> 2) + (ds_vcount >> 2) * 320;
            camera_mem <= ds_pixel;
        end
    end

    // frame buffer from IP
    blk_mem_gen_0 frame_buffer (
        .addra(addra), //pixels are stored using this math
        .clka(clk_pixel),
        .wea(valid_camera_mem),
        .dina(camera_mem),
        .ena(1'b1),
        .douta(), //never read from this side
        .addrb(addrb),//transformed lookup pixel
        .dinb(16'b0),
        .clkb(clk_pixel),
        .web(1'b0),
        .enb(1'b1),
        .doutb(frame_buff_raw)
    );
    logic [15:0] frame_buff_raw; //data out of frame buffer (565)
    logic [FB_SIZE-1:0] addrb; //used to lookup address in memory for reading from buffer
    logic good_addrb; //used to indicate within valid frame for scaling
    // brought in from lab 5...just do 4X upscale
    always_ff @(posedge clk_pixel)begin
        addrb <= (319-(hcount_hdmi >> 2)) + 320*(vcount_hdmi >> 2);
        good_addrb <= (hcount_hdmi<1280)&&(vcount_hdmi<720);
    end

    //split fame_buff into 3 8 bit color channels (5:6:5 adjusted accordingly)
    //remapped frame_buffer outputs with 8 bits for r, g, b
    logic [7:0] fb_red, fb_green, fb_blue;
    always_ff @(posedge clk_pixel)begin
        fb_red <= good_addrb?{frame_buff_raw[15:11],3'b0}:8'b0;
        fb_green <= good_addrb?{frame_buff_raw[10:5], 2'b0}:8'b0;
        fb_blue <= good_addrb?{frame_buff_raw[4:0],3'b0}:8'b0;
    end
    // Pixel Processing pre-HDMI output

    // RGB to YCrCb

    //output of rgb to ycrcb conversion (10 bits due to module):
    logic [9:0] y_full, cr_full, cb_full; //ycrcb conversion of full pixel
    //bottom 8 of y, cr, cb conversions:
    logic [7:0] y, cr, cb; //ycrcb conversion of full pixel
    //Convert RGB of full pixel to YCrCb
    //See lecture 07 for YCrCb discussion.
    //Module has a 3 cycle latency
    rgb_to_ycrcb rgbtoycrcb_m(
        .clk_in(clk_pixel),
        .r_in(fb_red),
        .g_in(fb_green),
        .b_in(fb_blue),
        .y_out(y_full),
        .cr_out(cr_full),
        .cb_out(cb_full)
    );

    //channel select module (select which of six color channels to mask):
    logic [2:0] channel_sel;
    logic [7:0] selected_channel; //selected channels
    //selected_channel could contain any of the six color channels depend on selection

    //threshold module (apply masking threshold):
    logic [7:0] lower_threshold;
    logic [7:0] upper_threshold;
    logic mask; //Whether or not thresholded pixel is 1 or 0

    //Center of Mass variables (tally all mask=1 pixels for a frame and calculate their center of mass)
    logic [10:0] x_com, x_com_calc; //long term x_com and output from module, resp
    logic [9:0] y_com, y_com_calc; //long term y_com and output from module, resp
    logic new_com; //used to know when to update x_com and y_com ...

    //take lower 8 of full outputs.
    // treat cr and cb as signed numbers, invert the MSB to get an unsigned equivalent ( [-128,128) maps to [0,256) )
    assign y = y_full[7:0];
    assign cr = {!cr_full[7],cr_full[6:0]};
    assign cb = {!cb_full[7],cb_full[6:0]};

    assign channel_sel = {1'b1, sw[4:3]}; //[3:1];
    //modified from before...ignoring red, green, blue
    // * 3'b000: green (not possible now)
    // * 3'b001: red (not possible now)
    // * 3'b010: blue (not possible now)
    // * 3'b011: not valid
    // * 3'b100: y (luminance)
    // * 3'b101: Cr (Chroma Red)
    // * 3'b110: Cb (Chroma Blue)
    // * 3'b111: not valid
    //Channel Select: Takes in the full RGB and YCrCb information and
    // chooses one of them to output as an 8 bit value
    channel_select mcs (
        .sel_in(channel_sel),
        .r_in(fb_red),
        .g_in(fb_green),
        .b_in(fb_blue),
        .y_in(y),
        .cr_in(cr),
        .cb_in(cb),
        .channel_out(selected_channel)
    );

    //threshold values used to determine what value  passes:
    assign lower_threshold = {sw[11:8],4'b0};
    assign upper_threshold = {sw[15:12],4'b0};

    //Thresholder: Takes in the full selected channedl and
    //based on upper and lower bounds provides a binary mask bit
    // * 1 if selected channel is within the bounds (inclusive)
    // * 0 if selected channel is not within the bounds
    threshold mt (
        .clk_in(clk_pixel),
        .rst_in(sys_rst_pixel),
        .pixel_in(selected_channel),
        .lower_bound_in(lower_threshold),
        .upper_bound_in(upper_threshold),
        .mask_out(mask) //single bit if pixel within mask.
    );


    logic [6:0] ss_c;
    //modified version of seven segment display for showing
    // thresholds and selected channel
    // special customized version
    lab05_ssc mssc (
        .clk_in(clk_pixel),
        .rst_in(sys_rst_pixel),
        .lt_in(lower_threshold),
        .ut_in(upper_threshold),
        .channel_sel_in(channel_sel),
        .cat_out(ss_c),
        .an_out({ss0_an, ss1_an})
    );
    assign ss0_c = ss_c; //control upper four digit's cathodes!
    assign ss1_c = ss_c; //same as above but for lower four digits!

    //Center of Mass Calculation: (you need to do)
    //using x_com_calc and y_com_calc values
    //Center of Mass:
    center_of_mass com_m(
        .clk_in(clk_pixel),
        .rst_in(sys_rst_pixel),
        .x_in(hcount_hdmi),
        .y_in(vcount_hdmi),
        .valid_in(mask), //aka threshold
        .tabulate_in((nf_hdmi)),
        .x_out(x_com_calc),
        .y_out(y_com_calc),
        .valid_out(new_com)
    );
    //grab logic for above
    //update center of mass x_com, y_com based on new_com signal
    always_ff @(posedge clk_pixel) begin
        if (sys_rst_pixel) begin
            x_com <= 0;
            y_com <= 0;
        end if (new_com) begin
            x_com <= x_com_calc;
            y_com <= y_com_calc;
        end
    end

    // image_sprite output:
    logic [7:0] img_red, img_green, img_blue;
    assign img_red   = 0;
    assign img_green = 0;
    assign img_blue  = 0;

    // crosshair output:
    logic [7:0] ch_red, ch_green, ch_blue;

    always_comb begin
        ch_red   = ((vcount_hdmi==y_com) || (hcount_hdmi==x_com))?8'hFF:8'h00;
        ch_green = ((vcount_hdmi==y_com) || (hcount_hdmi==x_com))?8'hFF:8'h00;
        ch_blue  = ((vcount_hdmi==y_com) || (hcount_hdmi==x_com))?8'hFF:8'h00;
    end

    // HDMI video signal generator
    video_sig_gen vsg (
        .pixel_clk_in(clk_pixel),
        .rst_in(sys_rst_pixel),
        .hcount_out(hcount_hdmi),
        .vcount_out(vcount_hdmi),
        .vs_out(vsync_hdmi),
        .hs_out(hsync_hdmi),
        .nf_out(nf_hdmi),
        .ad_out(active_draw_hdmi),
        .fc_out(frame_count_hdmi)
    );

    // Video Mux: select from the different display modes based on switch values
    //used with switches for display selections
    logic [1:0] display_choice;
    logic [1:0] target_choice;

    assign display_choice = sw[6:5]; //was [5:4]; not anymore
    assign target_choice =  {1'b0,sw[7]}; //was [7:6]; not anymore

    //choose what to display from the camera:
    // * 'b00:  normal camera out
    // * 'b01:  selected channel image in grayscale
    // * 'b10:  masked pixel (all on if 1, all off if 0)
    // * 'b11:  chroma channel with mask overtop as magenta
    //
    //then choose what to use with center of mass:
    // * 'b00: nothing
    // * 'b01: crosshair
    // * 'b10: sprite on top
    // * 'b11: nothing

    video_mux mvm(
        .bg_in(display_choice), //choose background
        .target_in(target_choice), //choose target
        .camera_pixel_in({fb_red, fb_green, fb_blue}),
        .camera_y_in(y), //luminance
        .channel_in(selected_channel), //current channel being drawn
        .thresholded_pixel_in(mask), //one bit mask signal
        .crosshair_in({ch_red, ch_green, ch_blue}),
        .com_sprite_pixel_in({img_red, img_green, img_blue}),
        .pixel_out({red,green,blue}) //output to tmds
    );

    // HDMI Output: just like before!

    logic [9:0] tmds_10b [0:2]; //output of each TMDS encoder!
    logic       tmds_signal [2:0]; //output of each TMDS serializer!

    //three tmds_encoders (blue, green, red)
    //note green should have no control signal like red
    //the blue channel DOES carry the two sync signals:
    //  * control_in[0] = horizontal sync signal
    //  * control_in[1] = vertical sync signal

    tmds_encoder tmds_red(
        .clk_in(clk_pixel),
        .rst_in(sys_rst_pixel),
        .data_in(red),
        .control_in(2'b0),
        .ve_in(active_draw_hdmi),
        .tmds_out(tmds_10b[2]));

    tmds_encoder tmds_green(
        .clk_in(clk_pixel),
        .rst_in(sys_rst_pixel),
        .data_in(green),
        .control_in(2'b0),
        .ve_in(active_draw_hdmi),
        .tmds_out(tmds_10b[1]));

    tmds_encoder tmds_blue(
        .clk_in(clk_pixel),
        .rst_in(sys_rst_pixel),
        .data_in(blue),
        .control_in({vsync_hdmi,hsync_hdmi}),
        .ve_in(active_draw_hdmi),
        .tmds_out(tmds_10b[0]));

    // tmds_serializers (blue, green, red):
    tmds_serializer red_ser(
        .clk_pixel_in(clk_pixel),
        .clk_5x_in(clk_5x),
        .rst_in(sys_rst_pixel),
        .tmds_in(tmds_10b[2]),
        .tmds_out(tmds_signal[2]));
    tmds_serializer green_ser(
        .clk_pixel_in(clk_pixel),
        .clk_5x_in(clk_5x),
        .rst_in(sys_rst_pixel),
        .tmds_in(tmds_10b[1]),
        .tmds_out(tmds_signal[1]));
    tmds_serializer blue_ser(
        .clk_pixel_in(clk_pixel),
        .clk_5x_in(clk_5x),
        .rst_in(sys_rst_pixel),
        .tmds_in(tmds_10b[0]),
        .tmds_out(tmds_signal[0]));

    //output buffers generating differential signals:
    //three for the r,g,b signals and one that is at the pixel clock rate
    //the HDMI receivers use recover logic coupled with the control signals asserted
    //during blanking and sync periods to synchronize their faster bit clocks off
    //of the slower pixel clock (so they can recover a clock of about 742.5 MHz from
    //the slower 74.25 MHz clock)
    OBUFDS OBUFDS_blue (.I(tmds_signal[0]), .O(hdmi_tx_p[0]), .OB(hdmi_tx_n[0]));
    OBUFDS OBUFDS_green(.I(tmds_signal[1]), .O(hdmi_tx_p[1]), .OB(hdmi_tx_n[1]));
    OBUFDS OBUFDS_red  (.I(tmds_signal[2]), .O(hdmi_tx_p[2]), .OB(hdmi_tx_n[2]));
    OBUFDS OBUFDS_clock(.I(clk_pixel), .O(hdmi_clk_p), .OB(hdmi_clk_n));

    // Nothing To Touch Down Here:
    // register writes to the camera

    logic busy, bus_active;
    logic cr_init_valid, cr_init_ready;

    logic  recent_reset;
    always_ff @(posedge clk_camera) begin
        if (sys_rst_camera) begin
            recent_reset <= 1'b1;
            cr_init_valid <= 1'b0;
        end
        else if (recent_reset) begin
            cr_init_valid <= 1'b1;
            recent_reset <= 1'b0;
        end else if (cr_init_valid && cr_init_ready) begin
            cr_init_valid <= 1'b0;
        end
    end

    logic [23:0] bram_dout;
    logic [7:0]  bram_addr;

    // ROM holding pre-built camera settings to send
    xilinx_single_port_ram_read_first #(
        .RAM_WIDTH(24),
        .RAM_DEPTH(256),
        .RAM_PERFORMANCE("HIGH_PERFORMANCE"),
        .INIT_FILE("rom.mem")
    ) registers
    (
        .addra(bram_addr),     // Address bus, width determined from RAM_DEPTH
        .dina(24'b0),          // RAM input data, width determined from RAM_WIDTH
        .clka(clk_camera),     // Clock
        .wea(1'b0),            // Write enable
        .ena(1'b1),            // RAM Enable, for additional power savings, disable port when not in use
        .rsta(sys_rst_camera), // Output reset (does not affect memory contents)
        .regcea(1'b1),         // Output register enable
        .douta(bram_dout)      // RAM output data, width determined from RAM_WIDTH
    );

    logic [23:0] registers_dout;
    logic [7:0]  registers_addr;
    assign registers_dout = bram_dout;
    assign bram_addr = registers_addr;

    logic con_scl_i, con_scl_o, con_scl_t;
    logic con_sda_i, con_sda_o, con_sda_t;

    // NOTE these also have pullup specified in the xdc file!
    // access our inouts properly as tri-state pins
    IOBUF IOBUF_scl (.I(con_scl_o), .IO(i2c_scl), .O(con_scl_i), .T(con_scl_t) );
    IOBUF IOBUF_sda (.I(con_sda_o), .IO(i2c_sda), .O(con_sda_i), .T(con_sda_t) );

    // provided module to send data BRAM -> I2C
    camera_registers crw (
        .clk_in(clk_camera),
        .rst_in(sys_rst_camera),
        .init_valid(cr_init_valid),
        .init_ready(cr_init_ready),
        .scl_i(con_scl_i),
        .scl_o(con_scl_o),
        .scl_t(con_scl_t),
        .sda_i(con_sda_i),
        .sda_o(con_sda_o),
        .sda_t(con_sda_t),
        .bram_dout(registers_dout),
        .bram_addr(registers_addr));

    // a handful of debug signals for writing to registers
    assign led[0] = crw.bus_active;
    assign led[1] = cr_init_valid;
    assign led[2] = cr_init_ready;
    assign led[15:3] = 0;

endmodule // top_level


`default_nettype wire

