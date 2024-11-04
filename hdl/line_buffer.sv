`default_nettype none

module line_buffer (
        input wire clk_in, //system clock
        input wire rst_in, //system reset

        input wire [10:0] hcount_in, //current hcount being read
        input wire [9:0] vcount_in, //current vcount being read
        input wire [15:0] pixel_data_in, //incoming pixel
        input wire data_valid_in, //incoming  valid data signal

        output logic [KERNEL_SIZE-1:0][15:0] line_buffer_out, //output pixels of data
        output logic [10:0] hcount_out, //current hcount being read
        output logic [9:0] vcount_out, //current vcount being read
        output logic data_valid_out //valid data out signal
    );
    parameter HRES = 1280;
    parameter VRES = 720;

    localparam KERNEL_SIZE = 3;

    // Each BRAM takes two cycles to read from, 
    // so there should be two clock cycles of delay
    logic [10:0] hcount_pipe;
    logic [9:0] vcount_pipe;
    logic data_valid_pipe;
    logic write_enable [KERNEL_SIZE:0];
    logic [15:0] read_data [KERNEL_SIZE:0];
    logic [1:0] ram_indices [KERNEL_SIZE:0];
    logic [1:0] ram_indices_pipe [1:0][KERNEL_SIZE:0];
    always_ff @(posedge clk_in) begin
        hcount_pipe <= hcount_in;
        hcount_out <= hcount_pipe;

        data_valid_pipe <= data_valid_in;
        data_valid_out <= data_valid_pipe;

        ram_indices_pipe[0][0] <= ram_indices[0];
        ram_indices_pipe[0][1] <= ram_indices[1];
        ram_indices_pipe[0][2] <= ram_indices[2];
        ram_indices_pipe[1][0] <= ram_indices_pipe[0][0];
        ram_indices_pipe[1][1] <= ram_indices_pipe[0][1];
        ram_indices_pipe[1][2] <= ram_indices_pipe[0][2];

        vcount_pipe <= vcount_in;
        if (vcount_pipe == 0)
            vcount_out <= VRES - 2;
        else if (vcount_pipe == 1)
            vcount_out <= VRES - 1;
        else
            vcount_out <= vcount_pipe - 2;
    end

    always_comb begin
        // The BRAM to read from doesn't immediately change,
        // so must use pipelined ram_indices
        if (data_valid_out) begin
            line_buffer_out[0] = read_data[ram_indices_pipe[1][0]];
            line_buffer_out[1] = read_data[ram_indices_pipe[1][1]];
            line_buffer_out[2] = read_data[ram_indices_pipe[1][2]];
        end else begin
            line_buffer_out[0] = 0;
            line_buffer_out[1] = 0;
            line_buffer_out[2] = 0;
        end

        // When hcount_in is at the end of the line,
        // write_enable should immediately change
        write_enable[ram_indices[0]] = 0;
        write_enable[ram_indices[1]] = 0;
        write_enable[ram_indices[2]] = 0;
        write_enable[ram_indices[3]] = data_valid_in;
    end

    generate
        genvar i;
        for (i=0; i<4; i=i+1) begin
            // event counters for cycling through the bram indices
            evt_counter #(
                .MAX_COUNT(4), .RST_VAL(i)) ram_indices_counter (
                .clk_in(clk_in),
                .rst_in(rst_in),
                .evt_in((hcount_in == HRES-1) && data_valid_in),
                .count_out(ram_indices[i])
            );

            // brams for read/write
            xilinx_true_dual_port_read_first_1_clock_ram #(
                .RAM_WIDTH(16),
                .RAM_DEPTH(HRES),
                .RAM_PERFORMANCE("HIGH_PERFORMANCE")) line_buffer_ram (
                //reading port:
                .clka(clk_in),         // Clock
                .addra(hcount_in),     // Port A address bus
                .dina(),               // Port A RAM input data
                .wea(1'b0),            // Port A write enable
                .ena(1'b1),            // Port A RAM Enable
                .rsta(1'b0),           // Port A output reset
                .regcea(1'b1),         // Port A output register enable
                .douta(read_data[i]),  // Port A RAM output data, width determined from RAM_WIDTH
                //writing port:
                .addrb(hcount_in),     // Port B address bus
                .dinb(pixel_data_in),  // Port B RAM input data, width determined from RAM_WIDTH
                .web(write_enable[i]), // Port B write enable
                .enb(1'b1),            // Port B RAM Enable
                .rstb(1'b0),           // Port B output reset
                .regceb(1'b1),         // Port B output register enable
                .doutb()               // Port B RAM output data
            );
        end
    endgenerate

endmodule

`default_nettype wire

