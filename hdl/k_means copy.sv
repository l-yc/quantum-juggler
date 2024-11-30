`timescale 1ns / 1ps
`default_nettype none

module k_means #(parameter MAX_ITER = 7) (
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
    localparam FOURTH_BRAM_WIDTH = 16;
    localparam HALF_BRAM_WIDTH = 32;
    localparam THREE_FOURTH_BRAM_WIDTH = 48;

    enum logic [1:0] {
        STORE = 0,
        UPDATE = 1,
        DIVIDE = 2
    } state;

    logic [2:0] update_state;

    logic [8:0] x_read;
    logic [7:0] y_read;
    logic [4:0] write_enable;
    logic [BRAM_WIDTH-1:0] bram_data_out [4:0];

    logic div_ready;

    logic [23:0] x_sum [6:0];
    logic [23:0] y_sum [6:0];
    logic [23:0] total_mass [6:0];
    logic [23:0] x_div [6:0];
    logic [23:0] y_div [6:0];

    // for debugging in gtkwave
    // logic [23:0] x_sum_1, x_sum_2, x_sum_3, x_sum_4, x_sum_5, x_sum_6, x_sum_7;
    // logic [23:0] y_sum_1, y_sum_2, y_sum_3, y_sum_4, y_sum_5, y_sum_6, y_sum_7;
    // logic [23:0] total_mass_1, total_mass_2, total_mass_3, total_mass_4, total_mass_5, total_mass_6, total_mass_7;
    // logic [23:0] x_div_1, x_div_2, x_div_3, x_div_4, x_div_5, x_div_6, x_div_7;
    // logic [23:0] y_div_1, y_div_2, y_div_3, y_div_4, y_div_5, y_div_6, y_div_7;
    // assign x_sum_1 = x_sum[0];
    // assign x_sum_2 = x_sum[1];
    // assign x_sum_3 = x_sum[2];
    // assign x_sum_4 = x_sum[3];
    // assign x_sum_5 = x_sum[4];
    // assign x_sum_6 = x_sum[5];
    // assign x_sum_7 = x_sum[6];
    // assign y_sum_1 = y_sum[0];
    // assign y_sum_2 = y_sum[1];
    // assign y_sum_3 = y_sum[2];
    // assign y_sum_4 = y_sum[3];
    // assign y_sum_5 = y_sum[4];
    // assign y_sum_6 = y_sum[5];
    // assign y_sum_7 = y_sum[6];
    // assign total_mass_1 = total_mass[0];
    // assign total_mass_2 = total_mass[1];
    // assign total_mass_3 = total_mass[2];
    // assign total_mass_4 = total_mass[3];
    // assign total_mass_5 = total_mass[4];
    // assign total_mass_6 = total_mass[5];
    // assign total_mass_7 = total_mass[6];
    // assign x_div_1 = x_div[0];
    // assign x_div_2 = x_div[1];
    // assign x_div_3 = x_div[2];
    // assign x_div_4 = x_div[3];
    // assign x_div_5 = x_div[4];
    // assign x_div_6 = x_div[5];
    // assign x_div_7 = x_div[6];
    // assign y_div_1 = y_div[0];
    // assign y_div_2 = y_div[1];
    // assign y_div_3 = y_div[2];
    // assign y_div_4 = y_div[3];
    // assign y_div_5 = y_div[4];
    // assign y_div_6 = y_div[5];
    // assign y_div_7 = y_div[6];

    logic [23:0] x_sum_temp [FOURTH_BRAM_WIDTH-1:0][6:0];
    logic [23:0] y_sum_temp [FOURTH_BRAM_WIDTH-1:0][6:0];
    logic [23:0] total_mass_temp [FOURTH_BRAM_WIDTH-1:0][6:0];

    logic [6:0] data_valid_out_x;
    logic [6:0] data_valid_out_y;
    
    logic [6:0] x_ready;
    logic [6:0] y_ready;

    logic [6:0][8:0] centroid_distance [FOURTH_BRAM_WIDTH-1:0];
    logic [2:0] index [FOURTH_BRAM_WIDTH-1:0];
    
    logic [6:0] current_iteration;

    generate
        genvar l;
        for (l=0; l<7; l=l+1) begin
            divider #(.WIDTH(24)) div_x (
                .clk_in(clk_in),
                .rst_in(rst_in),
                .dividend_in(x_sum[l]),
                .divisor_in(total_mass[l]),
                .data_valid_in(div_ready),
                .quotient_out(x_div[l]),
                .remainder_out(),
                .data_valid_out(data_valid_out_x[l]),
                .error_out(),
                .busy_out());
            divider #(.WIDTH(24)) div_y (
                .clk_in(clk_in),
                .rst_in(rst_in),
                .dividend_in(y_sum[l]),
                .divisor_in(total_mass[l]),
                .data_valid_in(div_ready),
                .quotient_out(y_div[l]),
                .remainder_out(),
                .data_valid_out(data_valid_out_y[l]),
                .error_out(),
                .busy_out());
            end
    endgenerate
   
    // Create the BRAMs for storing mask data
    logic [BRAM_WIDTH-1:0] bram_data_in;
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

    // Enable write if x is divisible by 64, mask is in frame, and state is STORE
    always_comb begin
        if (state == STORE && 0 < x_in && x_in <= WIDTH && 0 < y_in && y_in <= HEIGHT && x_in[5:0] == 0) begin
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

    // Combinational minimum module
    generate
        genvar m;
        for (m=0; m<FOURTH_BRAM_WIDTH; m=m+1) begin
            minimum min(
                .vals_in(centroid_distance[m]),
                .max(num_balls),
                .minimum_index(index[m])
            );
        end
    endgenerate
 
    // Sum up all the values 
    always_comb begin
        case (update_state) 
            1: begin
                for (int j=0; j<7; j=j+1) begin
                    if (bram_data_out[x_read>>6][0] == 1'b1 && j == index[0]) begin
                        // There is a mask at this (x,y)
                        x_sum_temp[0][j] = x_read;
                        y_sum_temp[0][j] = y_read;
                        total_mass_temp[0][j] = 1;
                    end else begin
                        // There is no mask at this (x,y)
                        x_sum_temp[0][j] = 0;
                        y_sum_temp[0][j] = 0;
                        total_mass_temp[0][j] = 0;
                    end
                end
                for (int i=1; i<FOURTH_BRAM_WIDTH; i=i+1) begin
                    for (int j=0; j<7; j=j+1) begin
                        if (bram_data_out[x_read>>6][i] == 1'b1 && j == index[i]) begin
                            // There is a mask at this (x,y)
                            x_sum_temp[i][j] = x_sum_temp[i-1][j] + x_read + i;
                            y_sum_temp[i][j] = y_sum_temp[i-1][j] + y_read;
                            total_mass_temp[i][j] = total_mass_temp[i-1][j] + 1;
                        end else begin
                            // There is no mask at this (x,y)
                            x_sum_temp[i][j] = x_sum_temp[i-1][j];
                            y_sum_temp[i][j] = y_sum_temp[i-1][j];
                            total_mass_temp[i][j] = total_mass_temp[i-1][j];
                        end
                    end
                end
            end
            2: begin
                for (int j=0; j<7; j=j+1) begin
                    if (bram_data_out[x_read>>6][FOURTH_BRAM_WIDTH] == 1'b1 && j == index[0]) begin
                        // There is a mask at this (x,y)
                        x_sum_temp[0][j] = x_read + FOURTH_BRAM_WIDTH;
                        y_sum_temp[0][j] = y_read;
                        total_mass_temp[0][j] = 1;
                    end else begin
                        // There is no mask at this (x,y)
                        x_sum_temp[0][j] = 0;
                        y_sum_temp[0][j] = 0;
                        total_mass_temp[0][j] = 0;
                    end
                end
                for (int i=1; i<FOURTH_BRAM_WIDTH; i=i+1) begin
                    for (int j=0; j<7; j=j+1) begin
                        if (bram_data_out[x_read>>6][i+FOURTH_BRAM_WIDTH] == 1'b1 && j == index[i]) begin
                            // There is a mask at this (x,y)
                            x_sum_temp[i][j] = x_sum_temp[i-1][j] + x_read + FOURTH_BRAM_WIDTH + i;
                            y_sum_temp[i][j] = y_sum_temp[i-1][j] + y_read;
                            total_mass_temp[i][j] = total_mass_temp[i-1][j] + 1;
                        end else begin
                            // There is no mask at this (x,y)
                            x_sum_temp[i][j] = x_sum_temp[i-1][j];
                            y_sum_temp[i][j] = y_sum_temp[i-1][j];
                            total_mass_temp[i][j] = total_mass_temp[i-1][j];
                        end
                    end
                end
            end
            3: begin
                for (int j=0; j<7; j=j+1) begin
                    if (bram_data_out[x_read>>6][HALF_BRAM_WIDTH] == 1'b1 && j == index[0]) begin
                        // There is a mask at this (x,y)
                        x_sum_temp[0][j] = x_read + HALF_BRAM_WIDTH;
                        y_sum_temp[0][j] = y_read;
                        total_mass_temp[0][j] = 1;
                    end else begin
                        // There is no mask at this (x,y)
                        x_sum_temp[0][j] = 0;
                        y_sum_temp[0][j] = 0;
                        total_mass_temp[0][j] = 0;
                    end
                end
                for (int i=1; i<FOURTH_BRAM_WIDTH; i=i+1) begin
                    for (int j=0; j<7; j=j+1) begin
                        if (bram_data_out[x_read>>6][i+HALF_BRAM_WIDTH] == 1'b1 && j == index[i]) begin
                            // There is a mask at this (x,y)
                            x_sum_temp[i][j] = x_sum_temp[i-1][j] + x_read + HALF_BRAM_WIDTH + i;
                            y_sum_temp[i][j] = y_sum_temp[i-1][j] + y_read;
                            total_mass_temp[i][j] = total_mass_temp[i-1][j] + 1;
                        end else begin
                            // There is no mask at this (x,y)
                            x_sum_temp[i][j] = x_sum_temp[i-1][j];
                            y_sum_temp[i][j] = y_sum_temp[i-1][j];
                            total_mass_temp[i][j] = total_mass_temp[i-1][j];
                        end
                    end
                end
            end
            4: begin
                for (int j=0; j<7; j=j+1) begin
                    if (bram_data_out[x_read>>6][THREE_FOURTH_BRAM_WIDTH] == 1'b1 && j == index[0]) begin
                        // There is a mask at this (x,y)
                        x_sum_temp[0][j] = x_read + THREE_FOURTH_BRAM_WIDTH;
                        y_sum_temp[0][j] = y_read;
                        total_mass_temp[0][j] = 1;
                    end else begin
                        // There is no mask at this (x,y)
                        x_sum_temp[0][j] = 0;
                        y_sum_temp[0][j] = 0;
                        total_mass_temp[0][j] = 0;
                    end
                end
                for (int i=1; i<FOURTH_BRAM_WIDTH; i=i+1) begin
                    for (int j=0; j<7; j=j+1) begin
                        if (bram_data_out[x_read>>6][i+THREE_FOURTH_BRAM_WIDTH] == 1'b1 && j == index[i]) begin
                            // There is a mask at this (x,y)
                            x_sum_temp[i][j] = x_sum_temp[i-1][j] + x_read + THREE_FOURTH_BRAM_WIDTH + i;
                            y_sum_temp[i][j] = y_sum_temp[i-1][j] + y_read;
                            total_mass_temp[i][j] = total_mass_temp[i-1][j] + 1;
                        end else begin
                            // There is no mask at this (x,y)
                            x_sum_temp[i][j] = x_sum_temp[i-1][j];
                            y_sum_temp[i][j] = y_sum_temp[i-1][j];
                            total_mass_temp[i][j] = total_mass_temp[i-1][j];
                        end
                    end
                end
            end
            default: begin
                for (int i=0; i<FOURTH_BRAM_WIDTH; i=i+1) begin
                    for (int j=0; j<7; j=j+1) begin
                        x_sum_temp[i][j] <= 0;
                        y_sum_temp[i][j] <= 0;
                        total_mass_temp[i][j] <= 0;
                    end
                end
            end
        endcase
    end

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            for (integer i =0; i<7; i=i+1) begin
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
            div_ready <= 0;
            update_state <= 0;
            state <= STORE;
            write_enable <= 0;
        end else begin
            case (state) 
                STORE: begin
                    // Store incoming pixels in BRAMs
                    data_valid_out <= 0;
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
                    // Finds x_sum, y_sum, total_mass for divide, should do 30x update->div->up->div...

                    // 0: ask bram to read row y_read
                    // 1: wait a cycle
                    // 2: read off current_row & calculate argmin for each pixel in row and update x_sum and y_sum
                    write_enable <= 0;
                    if (y_read == HEIGHT) begin
                        state <= DIVIDE;
                        div_ready <= 1;
                    end

                    case (update_state) 
                        0: begin
                            update_state <= 1;
                            for (int i=0; i<FOURTH_BRAM_WIDTH; i=i+1) begin
                                for (int j=0; j<7; j=j+1) begin
                                    centroid_distance[i][j] <= (
                                        ((x_read + i > centroids_x_out[j]) ? x_read + i - centroids_x_out[j] : centroids_x_out[j] - x_read - i) + 
                                        ((y_read > centroids_y_out[j]) ? y_read - centroids_y_out[j] : centroids_y_out[j] - y_read)
                                    );
                                end
                            end
                        end
                        1: begin
                            for (int i=FOURTH_BRAM_WIDTH; i<HALF_BRAM_WIDTH; i=i+1) begin
                                for (int j=0; j<7; j=j+1) begin
                                    centroid_distance[i-FOURTH_BRAM_WIDTH][j] <= (
                                        ((x_read + i > centroids_x_out[j]) ? x_read + i - centroids_x_out[j] : centroids_x_out[j] - x_read - i) + 
                                        ((y_read > centroids_y_out[j]) ? y_read - centroids_y_out[j] : centroids_y_out[j] - y_read)
                                    );
                                end
                            end
                            for (int i=0; i<7; i=i+1) begin
                                x_sum[i] <= x_sum_temp[FOURTH_BRAM_WIDTH-1][i] + x_sum[i];
                                y_sum[i] <= y_sum_temp[FOURTH_BRAM_WIDTH-1][i] + y_sum[i];
                                total_mass[i] <= total_mass_temp[FOURTH_BRAM_WIDTH-1][i] + total_mass[i];
                            end
                            update_state <= 2;
                        end
                        2: begin
                            for (int i=HALF_BRAM_WIDTH; i<THREE_FOURTH_BRAM_WIDTH; i=i+1) begin
                                for (int j=0; j<7; j=j+1) begin
                                    centroid_distance[i-HALF_BRAM_WIDTH][j] <= (
                                        ((x_read + i > centroids_x_out[j]) ? x_read + i - centroids_x_out[j] : centroids_x_out[j] - x_read - i) + 
                                        ((y_read > centroids_y_out[j]) ? y_read - centroids_y_out[j] : centroids_y_out[j] - y_read)
                                    );
                                end
                            end
                            for (int i=0; i<7; i=i+1) begin
                                x_sum[i] <= x_sum_temp[FOURTH_BRAM_WIDTH-1][i] + x_sum[i];
                                y_sum[i] <= y_sum_temp[FOURTH_BRAM_WIDTH-1][i] + y_sum[i];
                                total_mass[i] <= total_mass_temp[FOURTH_BRAM_WIDTH-1][i] + total_mass[i];
                            end
                            update_state <= 3;
                        end
                        3: begin
                            for (int i=THREE_FOURTH_BRAM_WIDTH; i<BRAM_WIDTH; i=i+1) begin
                                for (int j=0; j<7; j=j+1) begin
                                    centroid_distance[i-THREE_FOURTH_BRAM_WIDTH][j] <= (
                                        ((x_read + i > centroids_x_out[j]) ? x_read + i - centroids_x_out[j] : centroids_x_out[j] - x_read - i) + 
                                        ((y_read > centroids_y_out[j]) ? y_read - centroids_y_out[j] : centroids_y_out[j] - y_read)
                                    );
                                end
                            end
                            for (int i=0; i<7; i=i+1) begin
                                x_sum[i] <= x_sum_temp[FOURTH_BRAM_WIDTH-1][i] + x_sum[i];
                                y_sum[i] <= y_sum_temp[FOURTH_BRAM_WIDTH-1][i] + y_sum[i];
                                total_mass[i] <= total_mass_temp[FOURTH_BRAM_WIDTH-1][i] + total_mass[i];
                            end
                            update_state <= 4;
                        end
                        4: begin
                            for (int i=0; i<7; i=i+1) begin
                                x_sum[i] <= x_sum_temp[FOURTH_BRAM_WIDTH-1][i] + x_sum[i];
                                y_sum[i] <= y_sum_temp[FOURTH_BRAM_WIDTH-1][i] + y_sum[i];
                                total_mass[i] <= total_mass_temp[FOURTH_BRAM_WIDTH-1][i] + total_mass[i];
                            end
                            update_state <= 0;
                            if (x_read == 256) begin
                                x_read <= 0;
                                y_read <= y_read + 1;
                            end else begin
                                x_read <= x_read + 64;
                            end
                        end
                        default: begin
                            update_state <= 0;
                            x_read <= 0;
                            y_read <= 0;
                        end
                    endcase           
                end
                DIVIDE: begin
                    update_state <= 0;
                    div_ready <= 0;
                    if (x_ready == 7'b1111111 && y_ready == 7'b1111111) begin
                        for (int i =0; i<7; i=i+1) begin
                            x_ready[i] <= 0;
                            y_ready[i] <= 0;
                            x_sum[i] <= 0;
                            y_sum[i] <= 0;
                            total_mass[i] <= 0;
                        end
                        x_read <= 0;
                        y_read <= 0;
                        if (current_iteration < MAX_ITER - 1) begin
                            current_iteration <= current_iteration + 1;
                            state <= UPDATE;
                        end else begin
                            data_valid_out <= 1;
                            current_iteration <= 0;
                            state <= STORE;
                        end
                    end else begin
                        for (integer i=0; i<7; i=i+1) begin
                            if (total_mass[i] == 0) begin
                                x_ready[i] <= 1;
                                y_ready[i] <= 1;
                            end else begin
                                if (data_valid_out_x[i]) begin
                                    x_ready[i] <= 1;
                                    centroids_x_out[i] <= x_div[i];
                                end
                                if (data_valid_out_y[i]) begin
                                    y_ready[i] <= 1;
                                    centroids_y_out[i] <= y_div[i];
                                end
                            end
                        end
                    end 
                end
                default: begin
                    state <= STORE;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
