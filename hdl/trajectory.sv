`default_nettype none
module trajectory
	#(
		parameter GRAVITY = 9.81,
		parameter CLK_RATE = 100_000000
	)
	(
		input wire clk_in, // TODO what clock rate?
		input wire rst_in,
		input wire [2:0] pattern[7:0],
		input wire pattern_valid,
		input wire [2:0] num_balls,
		input wire [6:0] hand_x_in[1:0],
		input wire [6:0] hand_y_in[1:0],
		input wire [14:0] cyc_per_beat,
		output logic [10:0] traj_x_out[7:0],
		output logic [9:0] traj_y_out[7:0],
		output logic traj_valid
	);

	// TODO: need to convert meters to pixels
	localparam g = GRAVITY / CLK_RATE / CLK_RATE;

	// MARK: calculate look up tables
	logic [31:0] distance;
	assign distance = hand_x_in[1] - hand_x_in[0];

	logic [31:0] max_t[7:0];
	logic [31:0] vx[7:0];
	logic [31:0] vy[7:0];
	// TODO: replace the constant with the logicvariable cyc_per_beat
	generate
		genvar p;
		for (p = 0; p < 8; p += 1) begin
			assign max_t[p] = p * cyc_per_beat;
			assign vx[p] = distance / p * cyc_per_beat;
			assign vy[p] = $rtoi(g * p * cyc_per_beat) >> 1;
		end
	endgenerate


	// FIXME think through how many bits we actually need... 
    enum {IDLE, INIT, TRANSMIT} prev, state, next;

    always_comb begin
        if (rst_in) next = IDLE;
        else begin
            case (state)
                IDLE: next = INIT;
                INIT: next = TRANSMIT;
				TRANSMIT: next = IDLE;
			default: next = IDLE;
			endcase
		end
    end

    assign traj_valid = state == TRANSMIT; // TODO && something

	logic [31:0] t_start[7:0];
	logic [31:0] hand[7:0];
	logic [31:0] throw[7:0];
	logic [31:0] t;
	logic [31:0] hidx;
	logic [31:0] pidx;
	logic [31:0] queue[7:0];
	logic [31:0] counter;
	logic [31:0] maxi;
    always_ff @(posedge clk_in) begin
        case (state)
            IDLE: begin
				for (integer i = 0; i < 8; i += 1) begin
					t_start[i] <= 0;
					hand[i] <= (i&1);
					throw[i] <= 0;
				end

				hidx <= 0;
				pidx <= 0;

				queue[0] <= 0;
				queue[1] <= 1;
				queue[2] <= 2;
				queue[3] <= 3;
				queue[4] <= 4;
				queue[5] <= 5;
				queue[6] <= 6;
				queue[7] <= 7;

				counter <= 0;
				maxi <= 0;
            end
			INIT: begin
			end
			TRANSMIT: begin
				if (counter == 0) begin
					t_start[queue[0]] <= t;
					hand[queue[0]] <= hidx;
					hidx <= hidx == 1 ? 0 : 1;
					throw[queue[0]] = pattern[pidx];
					pidx <= pidx == num_balls-1 ? 0 : pidx + 1;

					// need to figure out how to write this
					// queue <= {0,queue[7:1]};
					// queue[throw[queue[0]]-1] <= queue[0];
				end

				counter <= counter+1 == cyc_per_beat ? 0 : counter + 1;

				for (integer i = 0; i < 8; i += 1) begin
					// p = thrw[i]
					// dt = t - t_start[i]
					traj_x_out[i] <= hand[0] == 0 ? 0 : distance;
					//traj_x_out[i] <= hand[i] == 0 ? vx[throw[i]] : dist - vx[throw[i]] * (t - t_start[i]);
					traj_y_out[i] <= vy[throw[i]] * (t - t_start[i]) - ($rtoi(g * (t - t_start[i]) * (t - t_start[i])) >> 1);
				end
			end
        endcase
        prev <= state;
        state <= next;
    end
endmodule
`default_nettype wire
