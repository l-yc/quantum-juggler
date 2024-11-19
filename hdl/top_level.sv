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
    output wire         ddr3_odt
    );

    // Shut up those RGBs
    assign rgb0 = 0;
    assign rgb1 = 0;

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

    logic [15:0] frame_buff_bram; // data out of BRAM frame buffer
    logic [15:0] frame_buff_dram; // data out of DRAM frame buffer
    logic [15:0] frame_buff_raw;  // select between the two!
    assign frame_buff_raw = sw[0] ? frame_buff_dram : frame_buff_bram;

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

    localparam NUM_BLUR = 3; 
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
            ds_hcount = f_hcount[NUM_BLUR-1];
            ds_vcount = f_vcount[NUM_BLUR-1];
            ds_pixel  = f_pixel[NUM_BLUR-1];
            ds_valid  = f_valid[NUM_BLUR-1];
        end
    end

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
        valid_camera_mem <= ds_valid;
        if (ds_hcount[1:0] == 0 && ds_vcount[1:0] == 0) begin
            addra <= (ds_hcount >> 2) + (ds_vcount >> 2) * 320;
            camera_mem <= ds_pixel;
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

    // Split frame_buff into 3 8 bit color channels (5:6:5 adjusted accordingly)
    logic [7:0] fb_red, fb_green, fb_blue;
    always_ff @(posedge clk_pixel)begin
        fb_red   <= good_addrb ? {frame_buff_raw[15:11],3'b0} : 8'b0;
        fb_green <= good_addrb ? {frame_buff_raw[10:5], 2'b0} : 8'b0;
        fb_blue  <= good_addrb ? {frame_buff_raw[4:0],3'b0}   : 8'b0;
    end

    // RGB to YCrCb
    logic [9:0] y_full, cr_full, cb_full; // ycrcb conversion of full pixel
    logic [7:0] y, cr, cb;                // bottom 8 of y, cr, cb conversions
    assign y = y_full[7:0];
    assign cr = {!cr_full[7],cr_full[6:0]};
    assign cb = {!cb_full[7],cb_full[6:0]};
    rgb_to_ycrcb rgbtoycrcb_m (
        .clk_in(clk_pixel),
        .r_in(fb_red),
        .g_in(fb_green),
        .b_in(fb_blue),
        .y_out(y_full),
        .cr_out(cr_full),
        .cb_out(cb_full)
    );

    // Channel select module (select which of six color channels to mask):
    logic [2:0] channel_sel;
    logic [7:0] selected_channel;
    assign channel_sel = {1'b1, sw[4:3]};
    channel_select mcs (
        .sel_in(channel_sel),
        .r_in(fb_red),
        .g_in(fb_green),
        .b_in(fb_blue),
        .y_in(y),
        .cr_in(cr),
        .cb_in(cb),
        .channel_out(selected_channel));

    // Threshold module (apply masking threshold):
    logic [7:0] lower_threshold;
    logic [7:0] upper_threshold;
    logic mask;
    assign lower_threshold = {sw[11:8],4'b0};
    assign upper_threshold = {sw[15:12],4'b0};
    threshold mt (
        .clk_in(clk_pixel),
        .rst_in(sys_rst_pixel),
        .pixel_in(selected_channel),
        .lower_bound_in(lower_threshold),
        .upper_bound_in(upper_threshold),
        .mask_out(mask)
    );

    // Seven-segment module
    logic [6:0] ss_c;
    lab05_ssc mssc (
        .clk_in(clk_pixel),
        .rst_in(sys_rst_pixel),
        .lt_in(lower_threshold),
        .ut_in(upper_threshold),
        .channel_sel_in(channel_sel),
        .cat_out(ss_c),
        .an_out({ss0_an, ss1_an}));
    assign ss0_c = ss_c; // control upper four digit's cathodes
    assign ss1_c = ss_c; // same as above but for lower four digits

    // Center of mass (tally all mask=1 pixels for a frame and calculate their center of mass)
    logic [10:0] x_com, x_com_calc; // long term x_com and output from module, resp
    logic [9:0] y_com, y_com_calc;  // long term y_com and output from module, resp
    logic new_com;                  // used to know when to update x_com and y_com
    center_of_mass com_m(
        .clk_in(clk_pixel),
        .rst_in(sys_rst_pixel),
        .x_in(hcount_hdmi),
        .y_in(vcount_hdmi),
        .valid_in(mask),
        .tabulate_in((nf_hdmi)),
        .x_out(x_com_calc),
        .y_out(y_com_calc),
        .valid_out(new_com));

    // Update center of mass x_com, y_com based on new_com signal
    always_ff @(posedge clk_pixel) begin
        if (sys_rst_pixel) begin
            x_com <= 0;
            y_com <= 0;
        end if (new_com) begin
            x_com <= x_com_calc;
            y_com <= y_com_calc;
        end
    end

    // Image sprite output TODO: REMOVE THIS
    logic [7:0] img_red, img_green, img_blue;
    assign img_red   = 0;
    assign img_green = 0;
    assign img_blue  = 0;

    // Crosshair output
    logic [7:0] ch_red, ch_green, ch_blue;
    always_comb begin
        ch_red   = ((vcount_hdmi==y_com) || (hcount_hdmi==x_com)) ? 8'hFF : 8'h00;
        ch_green = ((vcount_hdmi==y_com) || (hcount_hdmi==x_com)) ? 8'hFF : 8'h00;
        ch_blue  = ((vcount_hdmi==y_com) || (hcount_hdmi==x_com)) ? 8'hFF : 8'h00;
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
        .fc_out(frame_count_hdmi));

    // Video Mux: select from the different display modes based on switch values
    logic [1:0] display_choice;
    logic [1:0] target_choice;

    assign display_choice = sw[6:5];
    assign target_choice  = {1'b0,sw[7]};
    video_mux mvm(
        .bg_in(display_choice),    // choose background
        .target_in(target_choice), // choose target
        .camera_pixel_in({fb_red, fb_green, fb_blue}),
        .camera_y_in(y),
        .channel_in(selected_channel), // current channel being drawn
        .thresholded_pixel_in(mask),   // one bit mask signal
        .crosshair_in({ch_red, ch_green, ch_blue}),
        .com_sprite_pixel_in({img_red, img_green, img_blue}),
        .pixel_out({red, green, blue}) // output to tmds
    );

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

