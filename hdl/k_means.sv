`default_nettype none

`ifdef SYNTHESIS
`define FPATH(X) `"X`"
`else /* ! SYNTHESIS */
`define FPATH(X) `"../data/X`"
`endif  /* ! SYNTHESIS */

module k_means #(
    parameter MAX_ITER = 60
) (
    input wire clk_in,
    input wire rst_in,
    input wire [10:0] centroids_x_in [7:0],
    input wire [9:0] centroids_y_in [7:0],
    input wire [10:0] x_in,
    input wire [9:0]  y_in,
    input wire [2:0]  num_balls,
    input wire data_valid_in,
    input wire new_frame,
    output logic data_valid_out,
    output logic [10:0] centroids_x_out [7:0],
    output logic [9:0] centroids_y_out [7:0]
);

    localparam WIDTH = 320;
    localparam HEIGHT = 180;
    localparam BRAM_WIDTH = 64;

    typedef enum logic [1:0] {
        STORE = 0,
        UPDATE = 1,
        DIVIDE = 2
    } state_t;
    state_t state;

    logic [1:0][10:0] x_current;
    logic [1:0][9:0] y_current;
    logic [BRAM_WIDTH-1:0] current_data;
    logic [BRAM_WIDTH-1:0] bram_data_in;
    logic [2:0] current_bram;
    logic [4:0] wea;
    logic [BRAM_WIDTH-1:0] bram_data_out [4:0];
    logic [BRAM_WIDTH-1:0] bdo0 = bram_data_out[0];
    logic [BRAM_WIDTH-1:0] bdo1 = bram_data_out[1];
    logic [BRAM_WIDTH-1:0] bdo2 = bram_data_out[2];
    logic [BRAM_WIDTH-1:0] bdo3 = bram_data_out[3];
    logic [BRAM_WIDTH-1:0] bdo4 = bram_data_out[4];

    logic min_ready;
    logic div_ready;

    logic [31:0] x_sum [7:0];
    logic [31:0] y_sum [7:0];
    logic [31:0] total_mass [7:0];
    logic [31:0] x_div [7:0];
    logic [31:0] y_div [7:0];
    logic [31:0] remainder_out_x [7:0];
    logic [7:0] data_valid_out_x;
    logic [7:0] error_out_x;
    logic [7:0] busy_out_x;
    logic [31:0] remainder_out_y [7:0];
    logic [7:0] data_valid_out_y;
    logic [7:0] error_out_y;
    logic [7:0] busy_out_y;
    
    logic [7:0] x_ready;
    logic [7:0] y_ready;
    logic x_ready_all;
    logic y_ready_all;
    
    logic [11:0] centroid_distance0 [63:0];
    logic [11:0] centroid_distance1 [63:0];
    logic [11:0] centroid_distance2 [63:0];
    logic [11:0] centroid_distance3 [63:0];
    logic [11:0] centroid_distance4 [63:0];
    logic [11:0] centroid_distance5 [63:0];
    logic [11:0] centroid_distance6 [63:0];
    logic [11:0] centroid_distance7 [63:0];
    logic [63:0][2:0] index;
    logic [63:0] update_pixel;
    logic [10:0] x_temp_data;
    logic [10:0] x_temp_min;
    logic [31:0] x_temp_sum [7:0];
    logic [31:0] y_temp_sum [7:0];
    logic [31:0] temp_total_mass [7:0];
    
    logic [31:0] current_iteration;

    generate
        genvar l;
        for (l=0; l<8; l=l+1) begin
            divider #(.WIDTH(32)) 
            div_x (.clk_in(clk_in),
                .rst_in(rst_in),
                .dividend_in(x_sum[l]),
                .divisor_in(total_mass[l]),
                .data_valid_in(div_ready&&total_mass[l]>0),
                .quotient_out(x_div[l]),
                .remainder_out(remainder_out_x[l]),
                .data_valid_out(data_valid_out_x[l]),
                .error_out(error_out_x[l]),
                .busy_out(busy_out_x[l]));
            divider #(.WIDTH(32)) 
            div_y (.clk_in(clk_in),
                .rst_in(rst_in),
                .dividend_in(y_sum[l]),
                .divisor_in(total_mass[l]),
                .data_valid_in(div_ready&&total_mass[l]>0),
                .quotient_out(y_div[l]),
                .remainder_out(remainder_out_y[l]),
                .data_valid_out(data_valid_out_y[l]),
                .error_out(error_out_y[l]),
                .busy_out(busy_out_y[l]));
            end
    endgenerate

    generate
        genvar j;
        for (j=0; j<64; j=j+1) begin
            minimum min(
                .vals_in0(centroid_distance0[j]),
                .vals_in1(centroid_distance1[j]),
                .vals_in2(centroid_distance2[j]),
                .vals_in3(centroid_distance3[j]),
                .vals_in4(centroid_distance4[j]),
                .vals_in5(centroid_distance5[j]),
                .vals_in6(centroid_distance6[j]),
                .vals_in7(centroid_distance7[j]),
                .max(num_balls),
                .minimum_index(index[j])
            );
        end
    endgenerate
    

    generate
        genvar k;
        for (k=0; k<5; k=k+1) begin
            xilinx_single_port_ram_read_first #(
                .RAM_WIDTH(BRAM_WIDTH),                 // 64 pixels
                .RAM_DEPTH(HEIGHT),                    // 180 rows
                .RAM_PERFORMANCE("HIGH_PERFORMANCE"),   // Register the BRAM output
                .INIT_FILE(`FPATH(zeros.mem))           // 0s memory initialization file
            ) mask_bram (
                .addra(y_current[0] < HEIGHT ? y_current[0] : 8'b0), // ROM address calculated in the module
                .dina(bram_data_in),       // No write, so data input set to zero
                .clka(clk_in),// Clock input
                .wea(wea[k]),         // Disable writes
                .ena(1'b1),         // Enable the BRAM
                .rsta(rst_in),      // System reset
                .regcea(1'b1),      // Enable the output register
                .douta(bram_data_out[k])  // ROM output
            );
        end
    endgenerate

    always_comb begin
        for (integer i=0; i<8; i=i+1) begin
            x_temp_sum[i] = 0;
            y_temp_sum[i] = 0;
            temp_total_mass[i] = 0;
        end
        for (integer i=0; i<64; i= i+1) begin
            if (update_pixel[i] == 1'b1) begin
                x_temp_min = x_current[1] + i;
                x_temp_sum[index[i]] = x_temp_sum[index[i]] + x_temp_min;
                y_temp_sum[index[i]] = y_temp_sum[index[i]] + y_current[1];
                temp_total_mass[index[i]] = temp_total_mass[index[i]] + 1;
            end
        end
        x_ready_all = x_ready[0] && x_ready[1] && x_ready[2] && x_ready[3] && x_ready[4] && x_ready[5] && x_ready[6] && x_ready[7];
        y_ready_all = y_ready[0] && y_ready[1] && y_ready[2] && y_ready[3] && y_ready[4] && y_ready[5] && y_ready[6] && y_ready[7];
    end
    

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            for (integer i =0; i<8; i= i+1) begin
                centroids_x_out[i] <= centroids_x_in[i];
                centroids_y_out[i] <= centroids_y_in[i];
                x_sum[i] <= 0;
                y_sum[i] <= 0;
                total_mass[i] <= 0;
                x_ready[i] <= 0;
                y_ready[i] <= 0;
            end
            data_valid_out <= 0;
            current_iteration <= 0;
            x_current[0] <= 0;
            x_current[1] <= 0;
            y_current[0] <= 0;
            y_current[1] <= 0;
            min_ready <= 0;
            div_ready <= 0;
            state <= STORE;
            current_data <= 0;
            bram_data_in <= 0;
            current_bram <= 0;
            wea <= 0;
        end else begin
            if (div_ready) begin
                div_ready <= 0;
            end
            case (state) 
                STORE: begin
                    data_valid_out <= 0;
                    if (data_valid_in && x_in != x_current[0]) begin
                        if (y_in == y_current[0] && current_bram == x_in >> 6) begin
                            current_data <= current_data + 1 << (x_in & 63);
                            wea <= 0;
                        end else begin
                            current_data <= 1 << (x_in & 63);
                            bram_data_in <= current_data;
                            case (current_bram)
                                0: wea <= 5'b00001;
                                1: wea <= 5'b00010;
                                2: wea <= 5'b00100;
                                3: wea <= 5'b01000;
                                4: wea <= 5'b10000;
                                default: wea <= 5'b00000;
                            endcase
                        end
                        x_current[0] <= x_in;
                        y_current[0] <= y_in;
                        current_bram <= x_in >> 6;
                    end else begin
                        wea <= 0;
                    end
                    if (new_frame) begin
                        state <= UPDATE;
                        x_current[0] <= 0;
                        y_current[0] <= 0;
                        current_bram <= 0;
                    end
                end
                UPDATE: begin
                    data_valid_out <= 0;
                    x_current[1] <= x_current[0];
                    y_current[1] <= y_current[0];
                    wea <= 0;
                    if (y_current[0] == HEIGHT) begin
                        state <= DIVIDE;
                        div_ready <= 1;
                    end
                    if (current_bram == 4) begin
                        current_bram <= 0;
                        x_current[0] <= 0;
                        y_current[0] <= y_current[0] + 1;
                    end else begin
                        current_bram <= current_bram + 1;
                        x_current[0] <= ((current_bram+1) << 6);
                    end
                    if (bram_data_out[current_bram] != 0) begin
                        update_pixel <= bram_data_out[current_bram];
                        for (integer i=0; i<64; i= i+1) begin
                            if (bram_data_out[current_bram][i] == 1'b1) begin
                                x_temp_data = x_current[0] + i;
                                centroid_distance0[i] <= ((x_temp_data > centroids_x_out[0]) ? x_temp_data - centroids_x_out[0] : centroids_x_out[0] - x_temp_data) + ((y_current[1] > centroids_y_out[0]) ? y_current[1] - centroids_y_out[0] : centroids_y_out[0] - y_current[1]);
                                centroid_distance1[i] <= ((x_temp_data > centroids_x_out[1]) ? x_temp_data - centroids_x_out[1] : centroids_x_out[1] - x_temp_data) + ((y_current[1] > centroids_y_out[1]) ? y_current[1] - centroids_y_out[1] : centroids_y_out[1] - y_current[1]);
                                centroid_distance2[i] <= ((x_temp_data > centroids_x_out[2]) ? x_temp_data - centroids_x_out[2] : centroids_x_out[2] - x_temp_data) + ((y_current[1] > centroids_y_out[2]) ? y_current[1] - centroids_y_out[2] : centroids_y_out[2] - y_current[1]);
                                centroid_distance3[i] <= ((x_temp_data > centroids_x_out[3]) ? x_temp_data - centroids_x_out[3] : centroids_x_out[3] - x_temp_data) + ((y_current[1] > centroids_y_out[3]) ? y_current[1] - centroids_y_out[3] : centroids_y_out[3] - y_current[1]);
                                centroid_distance4[i] <= ((x_temp_data > centroids_x_out[4]) ? x_temp_data - centroids_x_out[4] : centroids_x_out[4] - x_temp_data) + ((y_current[1] > centroids_y_out[4]) ? y_current[1] - centroids_y_out[4] : centroids_y_out[4] - y_current[1]);
                                centroid_distance5[i] <= ((x_temp_data > centroids_x_out[5]) ? x_temp_data - centroids_x_out[5] : centroids_x_out[5] - x_temp_data) + ((y_current[1] > centroids_y_out[5]) ? y_current[1] - centroids_y_out[5] : centroids_y_out[5] - y_current[1]);
                                centroid_distance6[i] <= ((x_temp_data > centroids_x_out[6]) ? x_temp_data - centroids_x_out[6] : centroids_x_out[6] - x_temp_data) + ((y_current[1] > centroids_y_out[6]) ? y_current[1] - centroids_y_out[6] : centroids_y_out[6] - y_current[1]);
                                centroid_distance7[i] <= ((x_temp_data > centroids_x_out[7]) ? x_temp_data - centroids_x_out[7] : centroids_x_out[7] - x_temp_data) + ((y_current[1] > centroids_y_out[7]) ? y_current[1] - centroids_y_out[7] : centroids_y_out[7] - y_current[1]);
                            end
                        end
                        min_ready <= 1;
                    end else begin
                        min_ready <= 0;
                    end

                    if (min_ready) begin
                        for (integer i=0; i<8; i= i+1) begin
                            x_sum[i] <= x_sum[i] + x_temp_sum[i];
                            y_sum[i] <= y_sum[i] + y_temp_sum[i];
                            total_mass[i] <= total_mass[i] + temp_total_mass[i];
                        end
                    end
                end
                DIVIDE: begin
                    if (x_ready_all && y_ready_all) begin
                        for (integer i =0; i<8; i= i+1) begin
                            x_ready[i] <= 0;
                            y_ready[i] <= 0;
                            x_sum[i] <= 0;
                            y_sum[i] <= 0;
                            total_mass[i] <= 0;
                        end
                        y_current[0] <= 0;
                        x_current[0] <= 0;
                        y_current[1] <= 0;
                        x_current[1] <= 0;
                        if (current_iteration < MAX_ITER - 1) begin
                            current_iteration <= current_iteration + 1;
                            state <= UPDATE;
                        end else begin
                            data_valid_out <= 1;
                            current_iteration <= 0;
                            state <= STORE;
                        end
                    end else begin
                        for (integer i =0; i<8; i= i+1) begin
                            if (total_mass[i] == 0) begin
                                x_ready[i] <= 1;
                                y_ready[i] <= 1;
                            end else begin
                                if (data_valid_out_x[i] && !error_out_x[i]) begin
                                    x_ready[i] <= 1;
                                    centroids_x_out[i] <= x_div[i];
                                end
                                if (data_valid_out_y[i] && !error_out_y[i]) begin
                                    y_ready[i] <= 1;
                                    centroids_y_out[i] <= y_div[i];
                                end
                            end
                        end
                    end 
                end
                default: begin
                    state <= UPDATE;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
