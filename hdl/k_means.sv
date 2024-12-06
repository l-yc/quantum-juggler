`timescale 1ns / 1ps
`default_nettype none

module k_means #(parameter MAX_ITER = 20) (
    input wire clk_in,
    input wire rst_in,
    input wire [8:0] centroids_x_in [6:0],
    input wire [7:0] centroids_y_in [6:0],
    input wire [8:0] x_in,
    input wire [7:0] y_in,
    input wire [2:0] num_balls,
    input wire data_valid_in,
    input wire new_frame,
    output logic data_valid_out,
    output logic [8:0] centroids_x_out [6:0],
    output logic [7:0] centroids_y_out [6:0]
);

    localparam WIDTH = 320;
    localparam HEIGHT = 180;
    localparam BRAM_WIDTH = 64;
    localparam SUM_WIDTH = 4;

    enum logic [1:0] {
        STORE = 0,
        UPDATE = 1,
        DIVIDE = 2,
        IDLE = 3
    } state;

    logic [$clog2(BRAM_WIDTH/SUM_WIDTH+3)-1:0] update_state;

    logic [8:0] x_read;
    logic [7:0] y_read;

    logic [13:0] div_ready;
    always_ff @(posedge clk_in) begin
        for (int i=1; i<14; i=i+1) begin
            div_ready[i] <= div_ready[i-1];
        end
    end

    logic [23:0] x_sum [6:0];
    logic [23:0] y_sum [6:0];
    logic [23:0] total_mass [6:0];
    logic [23:0] x_div [6:0];
    logic [23:0] y_div [6:0];

    logic [6:0] x_ready;
    logic [6:0] y_ready;
    logic [6:0] current_iteration;

    generate
        genvar l;
        for (l=0; l<7; l=l+1) begin
            divider #(.WIDTH(24)) div_x (
                .clk_in(clk_in),
                .rst_in(rst_in),
                .dividend_in(x_sum[l]),
                .divisor_in(total_mass[l]),
                .data_valid_in(div_ready[0]),
                .quotient_out(x_div[l]),
                .remainder_out(),
                .data_valid_out(),
                .error_out(),
                .busy_out());
            divider #(.WIDTH(24)) div_y (
                .clk_in(clk_in),
                .rst_in(rst_in),
                .dividend_in(y_sum[l]),
                .divisor_in(total_mass[l]),
                .data_valid_in(div_ready[0]),
                .quotient_out(y_div[l]),
                .remainder_out(),
                .data_valid_out(),
                .error_out(),
                .busy_out());
            end
    endgenerate
   
    // Create the BRAMs for storing mask data
    logic [BRAM_WIDTH-1:0] bram_data_in;
    logic [BRAM_WIDTH-1:0] bram_data_out [4:0];
    logic [BRAM_WIDTH-1:0] curr_bram_data_out;
    logic [4:0] write_enable;
    generate
        genvar k;
        for (k=0; k<5; k=k+1) begin
            xilinx_true_dual_port_read_first_1_clock_ram #(
                .RAM_WIDTH(BRAM_WIDTH),
                .RAM_DEPTH(HEIGHT),
                .RAM_PERFORMANCE("HIGH_PERFORMANCE")) mask_ram (
                // Reading port:
                .clka(clk_in),            // Clock
                .addra(y_read),           // Port A address bus
                .dina(64'b0),             // Port A RAM input data
                .wea(1'b0),               // Port A write enable
                .ena(1'b1),               // Port A RAM Enable
                .rsta(1'b0),              // Port A output reset
                .regcea(1'b1),            // Port A output register enable
                .douta(bram_data_out[k]), // Port A RAM output data, width determined from RAM_WIDTH
                // Writing port:
                .addrb(y_in),             // Port B address bus
                .dinb(bram_data_in),      // Port B RAM input data, width determined from RAM_WIDTH
                .web(write_enable[k]),    // Port B write enable
                .enb(1'b1),               // Port B RAM Enable
                .rstb(1'b0),              // Port B output reset
                .regceb(1'b1),            // Port B output register enable
                .doutb()                  // Port B RAM output data
            );
        end
    endgenerate

    logic [8:0] prev_x;
    always_ff @(posedge clk_in) begin
        prev_x <= x_in;
    end

    // Enable write if x is divisible by 64, mask is in frame, and state is STORE
    always_comb begin
        if (state == STORE && 0 < x_in && x_in <= WIDTH && 0 < y_in && y_in <= HEIGHT && x_in[5:0] == 0 && x_in != prev_x) begin
            case (x_in >> 6)
                1: write_enable = 5'b00001;
                2: write_enable = 5'b00010;
                3: write_enable = 5'b00100;
                4: write_enable = 5'b01000;
                5: write_enable = 5'b10000;
                default: write_enable = 5'b00000;
            endcase
        end else begin
            write_enable = 0;
        end
    end

    // Minimum module
    logic [2:0] min_index [SUM_WIDTH-1:0];
    logic [6:0][8:0] centroid_distance [SUM_WIDTH-1:0];
    generate
        genvar j;
        for (j=0; j<SUM_WIDTH; j=j+1) begin
            minimum min(
                .clk_in(clk_in),
                .vals_in(centroid_distance[j]),
                .max(num_balls),
                .minimum_index(min_index[j]));
        end
    endgenerate
 
    // Sum up all the values 
    logic [8:0] x_sum_1 [1:0][6:0];
    logic [3:0] total_mass_1 [1:0][6:0];
    logic [8:0] x_sum_2 [6:0];
    logic [3:0] total_mass_2 [6:0];

    always_comb begin
        for (int j=0; j<7; j=j+1) begin
            x_sum_2[j] = x_sum_1[0][j] + x_sum_1[1][j];
            total_mass_2[j] = total_mass_1[0][j] + total_mass_1[1][j];
        end
    end

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            for (integer i=0; i<7; i=i+1) begin
                x_sum[i] <= 0;
                y_sum[i] <= 0;
                total_mass[i] <= 0;
                centroids_x_out[i] <= centroids_x_in[i];
                centroids_y_out[i] <= centroids_y_in[i];
            end
            data_valid_out <= 0;
            current_iteration <= 0;
            div_ready[0] <= 0;
            update_state <= 0;
            state <= STORE;
        end else begin
            case (state) 
                STORE: begin
                    // Store incoming pixels in BRAMs
                    if (0 <= x_in && x_in < WIDTH && 0 <= y_in && y_in < HEIGHT) begin
                        if (x_in[5:0] == 0) begin
                            // Divisible by 64, using a new BRAM
                            bram_data_in <= data_valid_in << (x_in & 63);
                        end else begin
                            // Using the same BRAM
                            bram_data_in <= bram_data_in | (data_valid_in << (x_in & 63));
                        end
                    end
                    if (new_frame) begin
                        state <= UPDATE;
                        update_state <= 0;
                        x_read <= 0;
                        y_read <= 0;
                    end
                end
                UPDATE: begin
                    if (y_read == HEIGHT) begin
                        state <= DIVIDE;
                        div_ready[0] <= 1;
                    end

                    // Cycle update state
                    update_state <= update_state == BRAM_WIDTH/SUM_WIDTH+3 ? 0 : update_state + 1;
                    curr_bram_data_out <= bram_data_out[x_read>>6];

                    // Calculate centroid distances
                    if (update_state < BRAM_WIDTH/SUM_WIDTH) begin
                        for (int i=0; i<SUM_WIDTH; i=i+1) begin
                            for (int j=0; j<7; j=j+1) begin
                                centroid_distance[i][j] <= (
                                    ((x_read + i + update_state*SUM_WIDTH > centroids_x_out[j]) ? 
                                        x_read + i + update_state*SUM_WIDTH - centroids_x_out[j] : centroids_x_out[j] - x_read - i - update_state*SUM_WIDTH) + 
                                    ((y_read > centroids_y_out[j]) ? y_read - centroids_y_out[j] : centroids_y_out[j] - y_read)
                                );
                            end
                        end
                    end

                    // Initialize x sum
                    if (3 <= update_state && update_state < BRAM_WIDTH/SUM_WIDTH+3) begin
                        for (int i=0; i<SUM_WIDTH/2; i=i+1) begin
                            for (int j=0; j<7; j=j+1) begin
                                x_sum_1[i][j] <= (
                                    ((curr_bram_data_out[2*i+(update_state-3)*SUM_WIDTH] == 1'b1 && j == min_index[2*i]) ? 2*i+(update_state-3)*SUM_WIDTH : 0) + 
                                    ((curr_bram_data_out[2*i+(update_state-3)*SUM_WIDTH+1] == 1'b1 && j == min_index[2*i+1]) ? 2*i+(update_state-3)*SUM_WIDTH+1 : 0)
                                );
                                total_mass_1[i][j] <= (
                                    (curr_bram_data_out[2*i+(update_state-3)*SUM_WIDTH] && j == min_index[2*i]) + 
                                    (curr_bram_data_out[2*i+(update_state-3)*SUM_WIDTH+1] && j == min_index[2*i+1])
                                );
                            end
                        end
                    end

                    // Accumulate x sum
                    if (4 <= update_state && update_state <= BRAM_WIDTH/SUM_WIDTH+3) begin
                        for (int i=0; i<7; i=i+1) begin
                            x_sum[i] <= x_sum_2[i] + x_read * total_mass_2[i] + x_sum[i];
                            y_sum[i] <= total_mass_2[i] * y_read + y_sum[i];
                            total_mass[i] <= total_mass_2[i] + total_mass[i];
                        end
                    end

                    // Move to next line
                    if (update_state == BRAM_WIDTH/SUM_WIDTH+3) begin
                        if (x_read == 256) begin
                            x_read <= 0;
                            y_read <= y_read + 1;
                        end else begin
                            x_read <= x_read + 64;
                        end
                    end
                end
                DIVIDE: begin
                    update_state <= 0;
                    div_ready[0] <= 0;
                    if (div_ready[13]) begin
                        for (int i=0; i<7; i=i+1) begin
                            centroids_x_out[i] <= x_div[i];
                            centroids_y_out[i] <= y_div[i];
                        end
                        x_read <= 0;
                        y_read <= 0;
                        if (current_iteration < MAX_ITER - 1) begin
                            current_iteration <= current_iteration + 1;
                            state <= UPDATE;
                        end else begin
                            current_iteration <= 0;
                            data_valid_out <= 1;
                            state <= IDLE;
                        end
                    end
                end
                IDLE: begin
                    data_valid_out <= 0;
                    for (integer i=0; i<7; i=i+1) begin
                        x_sum[i] <= 0;
                        y_sum[i] <= 0;
                        total_mass[i] <= 0;
                    end
                    if (new_frame) begin
                        state <= STORE;
                    end
                end
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule

`default_nettype wire
