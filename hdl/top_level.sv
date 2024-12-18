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
    output logic        hdmi_clk_p, hdmi_clk_n, // differential hdmi clock
    // DDR3 ports
    inout wire [15:0]   ddr3_dq,
    inout wire [1:0]    ddr3_dqs_n,
    inout wire [1:0]    ddr3_dqs_p,
    output wire [12:0]  ddr3_addr,
    output wire [2:0]   ddr3_ba,
    output wire         ddr3_ras_n,
    output wire         ddr3_cas_n,
    output wire         ddr3_we_n,
    output wire         ddr3_reset_n,
    output wire         ddr3_ck_p,
    output wire         ddr3_ck_n,
    output wire         ddr3_cke,
    output wire [1:0]   ddr3_dm,
    output wire         ddr3_odt,
    // potentiometer
    input wire cipo,
    output logic dclk,
    output logic copi,
    output logic cs
    );

    // Clock and Reset Signals
    logic sys_rst_camera;
    logic sys_rst_pixel;
    logic clk_camera;
    logic clk_pixel;
    logic clk_5x;
    logic clk_xc;
    logic clk_migref;
    logic sys_rst_migref;
    logic clk_ui;
    logic sys_rst_ui;
    logic clk_100_passthrough;

    // Clocking wizards to generate the clock speeds we need for our different domains
    // clk_camera: 200MHz, fast enough to comfortably sample the cameera's PCLK (50MHz)
    cw_hdmi_clk_wiz wizard_hdmi(
        .sysclk(clk_100_passthrough),
        .clk_pixel(clk_pixel),
        .clk_tmds(clk_5x),
        .reset(0));
    cw_fast_clk_wiz wizard_migcam(
        .clk_in1(clk_100mhz),
        .clk_camera(clk_camera),
        .clk_mig(clk_migref),
        .clk_xc(clk_xc),
        .clk_100(clk_100_passthrough),
        .reset(0));

    // Assign camera's xclk to pmod port: drive the operating clock of the camera
    assign cam_xclk = clk_xc;
    assign sys_rst_camera = btn[0];
    assign sys_rst_pixel = btn[0];
    assign sys_rst_migref = btn[0];

    // Video signal generator signals
    logic        hsync_hdmi;
    logic        vsync_hdmi;
    logic [10:0] hcount_hdmi;
    logic [9:0]  vcount_hdmi;
    logic        active_draw_hdmi;
    logic        new_frame_hdmi;
    logic [5:0]  frame_count_hdmi;
    logic        nf_hdmi;

    // RGB output values
    logic [7:0] red, green, blue;

    //-------------- CAMERA INPUT HANDLING --------------//

    // Synchronizers to prevent metastability
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

    pixel_reconstruct pixel_reconstruct_inst (
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

    logic [15:0] frame_buff_bram; // data out of BRAM frame buffer
    logic [15:0] frame_buff_dram; // data out of DRAM frame buffer

    // Clock domain cross from clk_camera (200 MHz) to clk_pixel (74.25 MHz)
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
    assign cdc_valid = ~empty;

    //-------------- GAUSSIAN BLUR HERE --------------//

    localparam NUM_BLUR = 2; 
    logic [10:0] f_hcount [NUM_BLUR-1:0]; // hcount from filter modules
    logic [9:0] f_vcount [NUM_BLUR-1:0];  // vcount from filter modules
    logic [15:0] f_pixel [NUM_BLUR-1:0];  // pixel data from filter modules
    logic f_valid [NUM_BLUR-1:0];         // valid signals for filter modules
    filter #(.HRES(1280),.VRES(720)) filter_0 (
        .clk_in(clk_pixel),
        .rst_in(sys_rst_pixel),
        .data_valid_in(cdc_valid),
        .pixel_data_in(cdc_pixel),
        .hcount_in(cdc_hcount),
        .vcount_in(cdc_vcount),
        .data_valid_out(f_valid[0]),
        .pixel_data_out(f_pixel[0]),
        .hcount_out(f_hcount[0]),
        .vcount_out(f_vcount[0]));
    generate
        genvar i;
        for (i=1; i<NUM_BLUR; i=i+1) begin
            filter #(.HRES(1280),.VRES(720)) filter (
                .clk_in(clk_pixel),
                .rst_in(sys_rst_pixel),
                .data_valid_in(f_valid[i-1]),
                .pixel_data_in(f_pixel[i-1]),
                .hcount_in(f_hcount[i-1]),
                .vcount_in(f_vcount[i-1]),
                .data_valid_out(f_valid[i]),
                .pixel_data_out(f_pixel[i]),
                .hcount_out(f_hcount[i]),
                .vcount_out(f_vcount[i]));
        end
    endgenerate

    //-------------- END GAUSSIAN BLUR --------------//

    //-------------- BRAM STUFF HERE --------------//

    localparam FB_DEPTH = 320*180;
    localparam FB_SIZE = $clog2(FB_DEPTH);
    logic [FB_SIZE-1:0] addra; // address to write to in frame buffer
    logic [FB_SIZE-1:0] addrb; // address in memory for reading from buffer
    logic good_addrb;          // indicate within valid frame for scaling
    logic valid_camera_mem;    // enable writing pixel data to frame buffer
    logic [15:0] camera_mem;   // pixel data into frame buffer

    // 4X downscale
    always_ff @(posedge clk_pixel) begin
        valid_camera_mem <= f_valid[NUM_BLUR-1];
        if (f_hcount[NUM_BLUR-1][1:0] == 0 && f_vcount[NUM_BLUR-1][1:0] == 0) begin
            addra <= (f_hcount[NUM_BLUR-1] >> 2) + (f_vcount[NUM_BLUR-1] >> 2) * 320;
            camera_mem <= f_pixel[NUM_BLUR-1];
        end
    end

    // Frame buffer from IP
    blk_mem_gen_0 frame_buffer (
        .addra(addra),
        .clka(clk_pixel),
        .wea(valid_camera_mem),
        .dina(camera_mem),
        .ena(1'b1),
        .douta(),
        .addrb(addrb),
        .dinb(16'b0),
        .clkb(clk_pixel),
        .web(1'b0),
        .enb(1'b1),
        .doutb(frame_buff_bram));

    // 4X upscale
    always_ff @(posedge clk_pixel)begin
        addrb <= (hcount_hdmi >> 2) + 320 * (vcount_hdmi >> 2);
        good_addrb <= (hcount_hdmi < 1280) && (vcount_hdmi < 720);
    end

    //-------------- END BRAM STUFF --------------//

    //-------------- DRAM STUFF HERE --------------//

    logic [127:0] camera_chunk;
    logic [127:0] camera_axis_tdata;
    logic         camera_axis_tlast;
    logic         camera_axis_tready;
    logic         camera_axis_tvalid;
    logic         camera_tlast;

    // Takes our 16-bit values and deserialize/stack them into 128-bit messages to write to DRAM
    stacker stacker_inst(
        .clk_in(clk_camera),
        .rst_in(sys_rst_camera),
        .pixel_tvalid(camera_valid),
        .pixel_tready(),
        .pixel_tdata(camera_pixel),
        .pixel_tlast(camera_hcount == 1279 && camera_vcount == 719),
        .chunk_tvalid(camera_axis_tvalid),
        .chunk_tready(camera_axis_tready),
        .chunk_tdata(camera_axis_tdata),
        .chunk_tlast(camera_axis_tlast));

    logic [127:0] camera_ui_axis_tdata;
    logic         camera_ui_axis_tlast;
    logic         camera_ui_axis_tready;
    logic         camera_ui_axis_tvalid;
    logic         camera_ui_axis_prog_empty;

    // FIFO data queue of 128-bit messages, crosses clock domains to the 81.25MHz
    // UI clock of the memory interface
    ddr_fifo_wrap camera_data_fifo(
        .sender_rst(sys_rst_camera),
        .sender_clk(clk_camera),
        .sender_axis_tvalid(camera_axis_tvalid),
        .sender_axis_tready(camera_axis_tready),
        .sender_axis_tdata(camera_axis_tdata),
        .sender_axis_tlast(camera_axis_tlast),
        .receiver_clk(clk_ui),
        .receiver_axis_tvalid(camera_ui_axis_tvalid),
        .receiver_axis_tready(camera_ui_axis_tready),
        .receiver_axis_tdata(camera_ui_axis_tdata),
        .receiver_axis_tlast(camera_ui_axis_tlast),
        .receiver_axis_prog_empty(camera_ui_axis_prog_empty));

    logic [127:0] display_ui_axis_tdata;
    logic         display_ui_axis_tlast;
    logic         display_ui_axis_tready;
    logic         display_ui_axis_tvalid;
    logic         display_ui_axis_prog_full;

    // Signals for MIG IP
    // MIG UI --> generic outputs
    logic [26:0]  app_addr;
    logic [2:0]   app_cmd;
    logic         app_en;
    // MIG UI --> write outputs
    logic [127:0] app_wdf_data;
    logic         app_wdf_end;
    logic         app_wdf_wren;
    logic [15:0]  app_wdf_mask;
    // MIG UI --> read inputs
    logic [127:0] app_rd_data;
    logic         app_rd_data_end;
    logic         app_rd_data_valid;
    // MIG UI --> generic inputs
    logic         app_rdy;
    logic         app_wdf_rdy;
    // MIG UI --> misc
    logic         app_sr_req; 
    logic         app_ref_req;
    logic         app_zq_req; 
    logic         app_sr_active;
    logic         app_ref_ack;
    logic         app_zq_ack;
    logic         init_calib_complete;

    // Traffic generator handles reads/write issued to the MIG IP,
    // which in turn handles the bus to the DDR chip.
    traffic_generator readwrite_looper (
        // outputs
        .app_addr         (app_addr[26:0]),
        .app_cmd          (app_cmd[2:0]),
        .app_en           (app_en),
        .app_wdf_data     (app_wdf_data[127:0]),
        .app_wdf_end      (app_wdf_end),
        .app_wdf_wren     (app_wdf_wren),
        .app_wdf_mask     (app_wdf_mask[15:0]),
        .app_sr_req       (app_sr_req),
        .app_ref_req      (app_ref_req),
        .app_zq_req       (app_zq_req),
        .write_axis_ready (camera_ui_axis_tready),
        .read_axis_data   (display_ui_axis_tdata),
        .read_axis_tlast  (display_ui_axis_tlast),
        .read_axis_valid  (display_ui_axis_tvalid),
        // inputs
        .clk_in               (clk_ui),
        .rst_in               (sys_rst_ui),
        .app_rd_data          (app_rd_data[127:0]),
        .app_rd_data_end      (app_rd_data_end),
        .app_rd_data_valid    (app_rd_data_valid),
        .app_rdy              (app_rdy),
        .app_wdf_rdy          (app_wdf_rdy),
        .app_sr_active        (app_sr_active),
        .app_ref_ack          (app_ref_ack),
        .app_zq_ack           (app_zq_ack),
        .init_calib_complete  (init_calib_complete),
        .write_axis_data      (camera_ui_axis_tdata),
        .write_axis_tlast     (camera_ui_axis_tlast),
        .write_axis_valid     (camera_ui_axis_tvalid),
        .write_axis_smallpile (camera_ui_axis_prog_empty),
        .read_axis_af         (display_ui_axis_prog_full),
        .read_axis_ready      (display_ui_axis_tready));

    // DDR3 MIG IP
    ddr3_mig ddr3_mig_inst (
        .ddr3_dq(ddr3_dq),
        .ddr3_dqs_n(ddr3_dqs_n),
        .ddr3_dqs_p(ddr3_dqs_p),
        .ddr3_addr(ddr3_addr),
        .ddr3_ba(ddr3_ba),
        .ddr3_ras_n(ddr3_ras_n),
        .ddr3_cas_n(ddr3_cas_n),
        .ddr3_we_n(ddr3_we_n),
        .ddr3_reset_n(ddr3_reset_n),
        .ddr3_ck_p(ddr3_ck_p),
        .ddr3_ck_n(ddr3_ck_n),
        .ddr3_cke(ddr3_cke),
        .ddr3_dm(ddr3_dm),
        .ddr3_odt(ddr3_odt),
        .sys_clk_i(clk_migref),
        .app_addr(app_addr),
        .app_cmd(app_cmd),
        .app_en(app_en),
        .app_wdf_data(app_wdf_data),
        .app_wdf_end(app_wdf_end),
        .app_wdf_wren(app_wdf_wren),
        .app_rd_data(app_rd_data),
        .app_rd_data_end(app_rd_data_end),
        .app_rd_data_valid(app_rd_data_valid),
        .app_rdy(app_rdy),
        .app_wdf_rdy(app_wdf_rdy), 
        .app_sr_req(app_sr_req),
        .app_ref_req(app_ref_req),
        .app_zq_req(app_zq_req),
        .app_sr_active(app_sr_active),
        .app_ref_ack(app_ref_ack),
        .app_zq_ack(app_zq_ack),
        .ui_clk(clk_ui), 
        .ui_clk_sync_rst(sys_rst_ui),
        .app_wdf_mask(app_wdf_mask),
        .init_calib_complete(init_calib_complete),
        .sys_rst(!sys_rst_migref));

    logic [127:0] display_axis_tdata;
    logic         display_axis_tlast;
    logic         display_axis_tready;
    logic         display_axis_tvalid;
    logic         display_axis_prog_empty;

    ddr_fifo_wrap pdfifo (
        .sender_rst(sys_rst_ui),
        .sender_clk(clk_ui),
        .sender_axis_tvalid(display_ui_axis_tvalid),
        .sender_axis_tready(display_ui_axis_tready),
        .sender_axis_tdata(display_ui_axis_tdata),
        .sender_axis_tlast(display_ui_axis_tlast),
        .sender_axis_prog_full(display_ui_axis_prog_full),
        .receiver_clk(clk_pixel),
        .receiver_axis_tvalid(display_axis_tvalid),
        .receiver_axis_tready(display_axis_tready),
        .receiver_axis_tdata(display_axis_tdata),
        .receiver_axis_tlast(display_axis_tlast),
        .receiver_axis_prog_empty(display_axis_prog_empty));

    logic frame_buff_tvalid;
    logic frame_buff_tready;
    logic [15:0] frame_buff_tdata;
    logic        frame_buff_tlast;

    unstacker unstacker_inst (
        .clk_in(clk_pixel),
        .rst_in(sys_rst_pixel),
        .chunk_tvalid(display_axis_tvalid),
        .chunk_tready(display_axis_tready),
        .chunk_tdata(display_axis_tdata),
        .chunk_tlast(display_axis_tlast),
        .pixel_tvalid(frame_buff_tvalid),
        .pixel_tready(frame_buff_tready),
        .pixel_tdata(frame_buff_tdata),
        .pixel_tlast(frame_buff_tlast));

    assign frame_buff_dram = frame_buff_tvalid ? frame_buff_tdata : 16'h2277;
    assign frame_buff_tready = active_draw_hdmi && (!frame_buff_tlast || (hcount_hdmi == 1279 && vcount_hdmi == 719));

    //-------------- END DRAM STUFF --------------//

    //-------------- END CAMERA INPUT HANDLING --------------//

    //-------------- PATTERN GENERATION --------------//

    // Debouncer to clean up signal
    logic btn1_clean;
    debouncer btn1_db (
        .clk_in(clk_pixel),
        .rst_in(sys_rst_pixel),
        .dirty_in(btn[1]),
        .clean_out(btn1_clean));

    // Pulse generator for sending new beat
    logic btn1_pulse;
    logic prev_btn1_clean;
    always_ff @(posedge clk_pixel) begin
        btn1_pulse <= !prev_btn1_clean && btn1_clean;
        prev_btn1_clean <= btn1_clean;
    end

    // Debouncer to clean up signal
    logic btn2_clean;
    debouncer btn2_db (
        .clk_in(clk_pixel),
        .rst_in(sys_rst_pixel),
        .dirty_in(btn[2]),
        .clean_out(btn2_clean));

    // Pulse generator for sending new beat
    logic btn2_pulse;
    logic prev_btn2_clean;
    always_ff @(posedge clk_pixel) begin
        btn2_pulse <= !prev_btn2_clean && btn2_clean;
        prev_btn2_clean <= btn2_clean;
    end

    // Pattern generation and seven segment display
    logic [2:0] siteswap_pattern [6:0]; // Most significant 3 bits at index 0
    logic pattern_valid;
    logic [2:0] num_balls;
    logic [6:0] ss_c;
    generate_pattern generate_pattern_inst (
        .clk_in(clk_pixel),
        .rst_in(sys_rst_pixel),
        .new_beat(btn1_pulse),
        .pattern_in(sw[2:0]),
        .pattern_length(sw[5:3]),
        .num_balls_out(num_balls),
        .pattern_out(siteswap_pattern),
        .pattern_valid_out(pattern_valid),
        .cat_out(ss_c),
        .an_out({ss0_an, ss1_an}));
    assign rgb0[2] = pattern_valid;
    assign rgb1[2] = pattern_valid;
    assign ss0_c = ss_c; // control upper four digit's cathodes
    assign ss1_c = ss_c; // same as above but for lower four digits

    //-------------- END PATTERN GENERATION --------------//

    // Split frame_buff into 3 8 bit color channels (5:6:5 adjusted accordingly)
    logic [7:0] fb_red_dram, fb_green_dram, fb_blue_dram;
    logic [7:0] fb_red_bram, fb_green_bram, fb_blue_bram;
    always_ff @(posedge clk_pixel) begin
        fb_red_dram   <= good_addrb ? {frame_buff_dram[15:11],3'b0} : 8'b0;
        fb_green_dram <= good_addrb ? {frame_buff_dram[10:5], 2'b0} : 8'b0;
        fb_blue_dram  <= good_addrb ? {frame_buff_dram[4:0],  3'b0} : 8'b0;
        fb_red_bram   <= good_addrb ? {frame_buff_bram[15:11],3'b0} : 8'b0;
        fb_green_bram <= good_addrb ? {frame_buff_bram[10:5], 2'b0} : 8'b0;
        fb_blue_bram  <= good_addrb ? {frame_buff_bram[4:0],  3'b0} : 8'b0;
    end

    // RGB to YCrCb
    logic [9:0] y_full, cr_full, cb_full; // ycrcb conversion of full pixel
    logic [7:0] y, cr, cb;                // bottom 8 of y, cr, cb conversions
    assign y = y_full[7:0];
    assign cr = {!cr_full[7],cr_full[6:0]};
    assign cb = {!cb_full[7],cb_full[6:0]};
    rgb_to_ycrcb rgbtoycrcb_m (
        .clk_in(clk_pixel),
        .r_in(fb_red_bram),
        .g_in(fb_green_bram),
        .b_in(fb_blue_bram),
        .y_out(y_full),
        .cr_out(cr_full),
        .cb_out(cb_full));

    // Channel select module (select which of six color channels to mask):
    logic [7:0] selected_channel;
    logic [7:0] selected_channel_hands;
    channel_select mcs (
        .sel_in(3'b100), // select y value
        .r_in(fb_red_bram),
        .g_in(fb_green_bram),
        .b_in(fb_blue_bram),
        .y_in(y),
        .cr_in(cr),
        .cb_in(cb),
        .channel_out(selected_channel));
    channel_select mcs_hands (
        .sel_in(3'b101), // select y value
        .r_in(fb_red_bram),
        .g_in(fb_green_bram),
        .b_in(fb_blue_bram),
        .y_in(y),
        .cr_in(cr),
        .cb_in(cb),
        .channel_out(selected_channel_hands));

    // Threshold module (apply masking threshold):
    logic [7:0] lower_threshold;
    logic [7:0] upper_threshold;
    logic [7:0] lower_threshold_hands;
    logic [7:0] upper_threshold_hands;
    logic mask;
    logic mask_hands;
    // assign lower_threshold = {sw[9:6], 4'b0};
    // assign upper_threshold = {sw[13:10], 4'b1111};
    assign lower_threshold = 8'b11110000;
    assign upper_threshold = 8'b11111111;
    assign lower_threshold_hands = {sw[9:6], 4'b0};
    assign upper_threshold_hands = {sw[13:10], 4'b1111};
    // assign lower_threshold_hands = 8'b10100000;
    // assign upper_threshold_hands = 8'b11111111;
    always_ff @(posedge clk_pixel) begin
        mask <= (selected_channel > lower_threshold) && (selected_channel <= upper_threshold);
        mask_hands <= (selected_channel_hands > lower_threshold_hands) && (selected_channel_hands <= upper_threshold_hands);
    end

    //-------------- K MEANS CLUSTERING -------------- {{{ //

    logic [8:0] centroids_x_init [6:0];
    logic [7:0] centroids_y_init [6:0];
    logic k_means_valid;
    logic [8:0] centroids_x_calc [6:0];
    logic [7:0] centroids_y_calc [6:0];
    logic [10:0] centroids_x [6:0];
    logic [9:0] centroids_y [6:0];

    k_means k_means_inst (
        .clk_in(clk_pixel),
        .rst_in(sys_rst_pixel),
        .centroids_x_in(centroids_x_init),
        .centroids_y_in(centroids_y_init),
        .x_in(hcount_hdmi[10:2]),
        .y_in(vcount_hdmi[9:2]),
        .num_balls(num_balls),
        .data_valid_in(mask && hcount_hdmi[1:0] == 0),
        .new_frame(nf_hdmi),
        .data_valid_out(k_means_valid),
        .centroids_x_out(centroids_x_calc),
        .centroids_y_out(centroids_y_calc));

    logic [8:0] centroids_x_init_hands [6:0];
    logic [7:0] centroids_y_init_hands [6:0];
    logic k_means_valid_hands;
    logic [8:0] centroids_x_calc_hands [6:0];
    logic [7:0] centroids_y_calc_hands [6:0];
    logic [10:0] centroids_x_hands [1:0];
    logic [9:0] centroids_y_hands [1:0];
    logic [10:0] ball_stop_x [1:0];
    logic [9:0] ball_stop_y [1:0];

    k_means k_means_inst_hands (
        .clk_in(clk_pixel),
        .rst_in(sys_rst_pixel),
        .centroids_x_in(centroids_x_init_hands),
        .centroids_y_in(centroids_y_init_hands),
        .x_in(hcount_hdmi[10:2]),
        .y_in(vcount_hdmi[9:2]),
        .num_balls(3'b010),
        .data_valid_in(mask_hands && hcount_hdmi[1:0] == 0),
        .new_frame(nf_hdmi),
        .data_valid_out(k_means_valid_hands),
        .centroids_x_out(centroids_x_calc_hands),
        .centroids_y_out(centroids_y_calc_hands));

    always_ff @(posedge clk_pixel) begin
        for (int i=0; i<7; i=i+1) begin
            centroids_x_init[i] <= 20 + 40 * i;
            centroids_y_init[i] <= 90;
        end
        centroids_x_init_hands[0] <= 80;
        centroids_y_init_hands[0] <= 240;
        centroids_x_init_hands[1] <= 90;
        centroids_y_init_hands[1] <= 90;
        for (int i=2; i<7; i=i+1) begin
            centroids_x_init_hands[i] <= 0;
            centroids_y_init_hands[i] <= 0;
        end
        if (k_means_valid) begin
            for (int i=0; i<7; i=i+1) begin
                centroids_x[i] <= {centroids_x_calc[i], 2'b0};
                centroids_y[i] <= {centroids_y_calc[i], 2'b0};
            end
        end
        if (k_means_valid_hands) begin
            for (int i=0; i<2; i=i+1) begin
                centroids_x_hands[i] <= {centroids_x_calc_hands[i], 2'b0};
                centroids_y_hands[i] <= {centroids_y_calc_hands[i], 2'b0};
            end
        end
        if (btn[2]) begin
            ball_stop_x[0] <= centroids_x_hands[0];
            ball_stop_x[1] <= centroids_x_hands[1];
            ball_stop_y[0] <= centroids_y_hands[0];
            ball_stop_y[1] <= centroids_y_hands[1];
        end
    end

   // Crosshair output
    logic is_crosshair;
    assign is_crosshair = (
        ((vcount_hdmi == centroids_y[0] || hcount_hdmi == centroids_x[0]) && num_balls >= 1) ||
        ((vcount_hdmi == centroids_y[1] || hcount_hdmi == centroids_x[1]) && num_balls >= 2) ||
        ((vcount_hdmi == centroids_y[2] || hcount_hdmi == centroids_x[2]) && num_balls >= 3) ||
        ((vcount_hdmi == centroids_y[3] || hcount_hdmi == centroids_x[3]) && num_balls >= 4) ||
        ((vcount_hdmi == centroids_y[4] || hcount_hdmi == centroids_x[4]) && num_balls >= 5) ||
        ((vcount_hdmi == centroids_y[5] || hcount_hdmi == centroids_x[5]) && num_balls >= 6) ||
        ((vcount_hdmi == centroids_y[6] || hcount_hdmi == centroids_x[6]) && num_balls >= 7));
    logic is_crosshair_hands;
    assign is_crosshair_hands = (
        (vcount_hdmi == centroids_y_hands[0] || hcount_hdmi == centroids_x_hands[0]) ||
        (vcount_hdmi == centroids_y_hands[1] || hcount_hdmi == centroids_x_hands[1]));

    logic ball_stop [1:0];
    localparam BALL_STOP_SIZE = 15;
    always_comb begin
        for (int i=0; i<2; i=i+1) begin
            ball_stop[i] = ball_stop_x[i] - BALL_STOP_SIZE < hcount_hdmi && hcount_hdmi < ball_stop_x[i] + BALL_STOP_SIZE &&
                           ball_stop_y[i] - BALL_STOP_SIZE < vcount_hdmi && vcount_hdmi < ball_stop_y[i] + BALL_STOP_SIZE;
        end
    end

    //}}} -------------- END K MEANS CLUSTERING --------------//

	//-------------- POTENTIOMETER STUFF HERE -------------- {{{//
    
    parameter ADC_DATA_WIDTH = 17; 
    parameter ADC_DATA_CLK_PERIOD = 50; 
    parameter ADC_READ_PERIOD = 100_000; //read one channel of ADC every millisec
    
    // SPI interface controls
    logic [ADC_DATA_WIDTH-1:0] spi_write_data;
    logic [ADC_DATA_WIDTH-1:0] spi_read_data;
    logic spi_trigger;
    logic spi_read_data_valid;
    
    spi_con #(
        .DATA_WIDTH(ADC_DATA_WIDTH),
        .DATA_CLK_PERIOD(ADC_DATA_CLK_PERIOD)) my_spi_con (
        .clk_in(clk_pixel),
        .rst_in(sys_rst_pixel),
        .data_in(17'b11000_0000_0000_0000),
        .trigger_in(spi_trigger),
        .data_out(spi_read_data),
        .data_valid_out(spi_read_data_valid),
        .chip_data_out(copi),
        .chip_data_in(cipo),
        .chip_clk_out(dclk),
        .chip_sel_out(cs));

    logic [31:0] select_count;
    counter select_counter (
        .clk_in(clk_pixel),
        .rst_in(sys_rst_pixel),
        .period_in(ADC_READ_PERIOD),
        .count_out(select_count));
    
    logic [7:0] frame_per_beat;
    always_ff @(posedge clk_pixel)begin
        if (sys_rst_pixel) begin
            frame_per_beat <= 5;
        end else begin
            if (spi_read_data_valid) begin
                frame_per_beat <= spi_read_data[9:6];
            end
            if (select_count == 'b1) begin 
                spi_trigger <= 1;
            end else begin
                spi_trigger <= 0;
            end
        end
    end

    //}}} -------------- END POTENTIOMETER --------------//

	// MARK: trajectory modules {{{
	logic [10:0] traj_x_out[6:0];
	logic [9:0] traj_y_out[6:0];
	logic traj_valid;
    logic [3:0] fpb_filtered;
    always_comb begin
        if (frame_per_beat <= 3) fpb_filtered = 3;
        else if (frame_per_beat >= 10) fpb_filtered = 10;
        else fpb_filtered = frame_per_beat[3:0];
    end
    trajectory_generator #(.g(3), .s(50), .MAX_TICK(2)) traj_gen (
        .clk_in(clk_pixel),
        .rst_in(sys_rst_pixel || btn[2]),
        .nf_in(nf_hdmi),
        .pattern(siteswap_pattern),
        .pattern_valid(pattern_valid),
        .num_balls(num_balls),
        .hand_x_in({centroids_x_hands[1], centroids_x_hands[0]}),
        .hand_y_in({centroids_y_hands[1], centroids_y_hands[0]}),
        .frame_per_beat(fpb_filtered),
        .traj_x_out(traj_x_out),
        .traj_y_out(traj_y_out),
        .traj_valid(traj_valid));
	
	logic [7:0] trajectory_red;
	logic [7:0] trajectory_green;
	logic [7:0] trajectory_blue;

    draw_trajectory draw_traj (
        .clk_in(clk_pixel),
        .rst_in(sys_rst_pixel),

        .num_balls(num_balls),
        .traj_x_in(traj_x_out),
        .traj_y_in(traj_y_out),
        .traj_valid(traj_valid),
        .hand_x_in({centroids_x_hands[1], centroids_x_hands[0]}),
        .hand_y_in({centroids_y_hands[1], centroids_y_hands[0]}),

        .hcount_in(hcount_hdmi),
        .vcount_in(vcount_hdmi),
        .red_out(trajectory_red),
        .green_out(trajectory_green),
        .blue_out(trajectory_blue));
    // }}}

	// MARK: pattern eval {{{
	logic eval_out;
	logic [14:0] pattern_error;
	logic pattern_correct;
	pattern_evaluation #(.THRESHOLD(16000)) pattern_evaluator (
		.clk_in(clk_pixel),
		.rst_in(sys_rst_pixel || nf_hdmi),
		.nf_in(nf_hdmi),
		.data_valid_in(traj_valid && k_means_valid),
		.num_balls(num_balls),
		.model_balls_x(traj_x_out),
		.model_balls_y(traj_y_out),
		.real_balls_x(centroids_x),
		.real_balls_y(centroids_y),
		.data_valid_out(eval_out),
		.pattern_error(pattern_error),
		.pattern_correct(pattern_correct));

    logic judgment;
    localparam QUEUE_SIZE = 60;
    localparam QUEUE_LEN_THRESH = 1;
    logic [$clog2(QUEUE_SIZE):0] eval_out_sum;
    logic eval_out_queue [QUEUE_SIZE-1:0];
    always_ff @(posedge clk_pixel) begin
        if (sys_rst_pixel) begin
            eval_out_sum <= 0;
            for (int i=0; i<QUEUE_SIZE; i=i+1) begin
                eval_out_queue[i] <= 0;
            end
        end else if (eval_out) begin
            eval_out_queue[0] <= pattern_correct;
            for (int i=1; i<QUEUE_SIZE; i=i+1) begin
                eval_out_queue[i] <= eval_out_queue[i-1];
            end
            eval_out_sum <= eval_out_sum + pattern_correct - eval_out_queue[QUEUE_SIZE-1];
        end
        if (eval_out_sum > QUEUE_LEN_THRESH) begin
            judgment <= pattern_correct;
        end
    end

    logic is_judgment;
	localparam BORDER = 16;
    assign is_judgment =
		hcount_hdmi < BORDER || hcount_hdmi > 1280 - BORDER || 
		vcount_hdmi < BORDER || vcount_hdmi > 720 - BORDER;
	// }}}

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
        .fc_out(frame_count_hdmi));

    // Video mux: select from the different display modes and output to TMDS
    video_mux mvm(
        .clk_in(clk_pixel),
        .bg_in(sw[14]),
        .target_in(sw[15]),
        .camera_pixel_in({fb_red_dram, fb_green_dram, fb_blue_dram}),
        .sel_channel_in(selected_channel),
        .thresholded_pixel_in(mask),
        .thresholded2_pixel_in(mask_hands),
		.trajectory_pixel_in({trajectory_red, trajectory_blue, trajectory_green}),
        .crosshair_in(is_crosshair),
        .crosshair2_in(is_crosshair_hands),
		.judgment_correct(judgment),
        .judgment_in(is_judgment),
        .ball_stop(ball_stop[0] || ball_stop[1]),
        .pixel_out({red, green, blue}));

    //-------------- HDMI OUTPUT --------------//

    logic [9:0] tmds_10b [0:2];    // output of each TMDS encoder
    logic       tmds_signal [2:0]; // output of each TMDS serializer

    // TMDS encoders (red, green, blue)
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

    // TMDS serializers (red, green, blue):
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

    // Output buffers generating differential signals:
    OBUFDS OBUFDS_blue (.I(tmds_signal[0]), .O(hdmi_tx_p[0]), .OB(hdmi_tx_n[0]));
    OBUFDS OBUFDS_green(.I(tmds_signal[1]), .O(hdmi_tx_p[1]), .OB(hdmi_tx_n[1]));
    OBUFDS OBUFDS_red  (.I(tmds_signal[2]), .O(hdmi_tx_p[2]), .OB(hdmi_tx_n[2]));
    OBUFDS OBUFDS_clock(.I(clk_pixel), .O(hdmi_clk_p), .OB(hdmi_clk_n));

    //-------------- END HDMI OUTPUT --------------//

    //-------------- CAMERA REGISTER WRITE --------------//

    logic busy, bus_active;
    logic cr_init_valid, cr_init_ready;
    logic recent_reset;
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

    // Access our IO properly as tri-state pins
    IOBUF IOBUF_scl (.I(con_scl_o), .IO(i2c_scl), .O(con_scl_i), .T(con_scl_t) );
    IOBUF IOBUF_sda (.I(con_sda_o), .IO(i2c_sda), .O(con_sda_i), .T(con_sda_t) );

    // Provided module to send data BRAM -> I2C
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

    // Debug signals for writing to registers
    assign led[0] = crw.bus_active;
    assign led[1] = cr_init_valid;
    assign led[2] = cr_init_ready;
    assign led[15:3] = 0;

    //-------------- END CAMERA REGISTER WRITE --------------//

endmodule

`default_nettype wire

