`default_nettype none
module trajectory
	#(
		parameter GRAVITY = 9.81,
		parameter CLK_RATE = 100_000000,
		parameter DPI = 96
	)
	(
		input wire clk_in, // TODO what clock rate?
		input wire rst_in,
		input wire [2:0] pattern[6:0],
		input wire pattern_valid,
		input wire [2:0] num_balls,
		input wire [10:0] hand_x_in[1:0],
		input wire [9:0] hand_y_in[1:0],
		input wire [31:0] cyc_per_beat,
		output logic [10:0] traj_x_out[6:0],
		output logic [9:0] traj_y_out[6:0],
		output logic traj_valid
	);

	// Units: pixels / cyc^2
	localparam g = GRAVITY / 0.0254 * DPI / CLK_RATE / CLK_RATE;

	// MARK: calculate look up tables
	logic [31:0] distance;
	assign distance = hand_x_in[1] - hand_x_in[0];

	logic [31:0] max_t[7:0];
	logic [31:0] vx[7:0];
	logic [31:0] vy[7:0];
	logic [7:0] vx_ready;

	generate
		genvar p;

		assign max_t[0] = 0;
		assign vx[0] = 0;
		assign vx_ready[0] = 1;
		assign vy[0] = 0;
		for (p = 1; p < 8; p += 1) begin
			assign max_t[p] = p * cyc_per_beat;
			//assign vx[p] = distance / (p * cyc_per_beat);
			divider vx_divider(
				.clk_in(clk_in),
				.rst_in(rst_in),
				.dividend_in(distance),
				.divisor_in(p * cyc_per_beat),
				.data_valid_in(pattern_valid),
				.quotient_out(vx[p]),
				.remainder_out(),
				.data_valid_out(vx_ready[p]),
				.error_out(),
				.busy_out());
			assign vy[p] = $rtoi(g * p * cyc_per_beat) >> 1;
		end
	endgenerate

	// state machine
    enum {IDLE, INIT, TRANSMIT} prev, state, next;
    always_comb begin
        if (rst_in) next = IDLE;
        else begin
            case (state)
                IDLE: next = INIT;
				INIT: begin
					if (vx_ready == 8'b11111111) begin
						next = TRANSMIT;
					end else begin
						next = INIT;
					end
				end
                TRANSMIT: next = TRANSMIT;
                default: next = IDLE;
            endcase
        end
    end

	// inputs
	logic [2:0] _pattern[6:0];
	logic [2:0] _num_balls;
	logic [10:0] _hand_x_in[1:0];
	logic [9:0] _hand_y_in[1:0];
	logic [14:0] _cyc_per_beat;


	// FIXME think through how many bits we actually need... 
	logic [31:0] t_start[6:0];
	logic [31:0] hand[6:0];
	logic [31:0] throw[6:0];
	logic [31:0] t;
	logic [31:0] hidx;
	logic [31:0] pidx;
	logic [31:0] queue[6:0];
	logic [31:0] counter;
	logic [31:0] maxi;
    always_ff @(posedge clk_in) begin
		case (state)
			IDLE: begin
				// output
				traj_valid <= 0;
				for (integer i = 0; i < 7; i += 1) begin
					traj_x_out[i] <= 0;
					traj_y_out[i] <= 0;
				end
			end
			INIT: begin
				if (pattern_valid) begin
					// input
					for (integer i = 0; i < 7; i += 1) begin
						_pattern[i] <= pattern[i];
					end
					_num_balls <= num_balls;
					for (integer i = 0; i < 2; i += 1) begin
						_hand_x_in[i] <= hand_x_in[i];
						_hand_y_in[i] <= hand_y_in[i];
					end
					_cyc_per_beat <= cyc_per_beat;

					// logic
					for (integer i = 0; i < 7; i += 1) begin
						t_start[i] <= -1;
						hand[i] <= (i&1);
						throw[i] <= 0;
					end

					hidx <= 0;
					pidx <= 0;

					for (integer i = 0; i < 7; i += 1) begin
						if (i < num_balls) begin
							queue[i] <= i;
						end else begin
							queue[i] <= 0;
						end
					end
					counter <= 0;
					maxi <= 0;
					t <= 0;
				end
			end
			TRANSMIT: begin
				if (counter == 0) begin
					t_start[queue[0]] <= t;
					hand[queue[0]] <= hidx;
					hidx <= hidx == 1 ? 0 : 1;
					throw[queue[0]] = _pattern[pidx];
					pidx <= pidx == _num_balls-1 ? 0 : pidx + 1;

					// queue <= [0] + queue[6:1]
					// queue[throw[queue[0]]-1] = queue[0];
					for (integer i = 0; i < 7; i += 1) begin
						if (i == throw[queue[0]]-1) begin
							queue[i] <= queue[0];
						end else if (i == 6) begin
							queue[i] <= 0;
						end else begin
							queue[i] <= queue[i+1];
						end
					end
				end

				counter <= counter+1 == _cyc_per_beat ? 0 : counter + 1;
				t <= t + 1;

				traj_valid <= 1;
				for (integer i = 0; i < 7; i += 1) begin
					if (i < _num_balls && t_start[i] <= t) begin
						// p = thrw[i]
						// dt = t - t_start[i]
						//traj_x_out[i] <= hand[0] == 0 ? 0 : distance;
						//traj_x_out[i] <= throw[i];
						//traj_x_out[i] <= (t - t_start[i]);
						//traj_x_out[i] <= vx[throw[i]];
						traj_x_out[i] <= hand[i] == 0 ? vx[throw[i]] * (t - t_start[i]) : distance - vx[throw[i]] * (t - t_start[i]);
						traj_y_out[i] <= hand_y_in[0] - vy[throw[i]] * (t - t_start[i]) + ($rtoi(g * (t - t_start[i]) * (t - t_start[i])) >> 1);
					end
				end
			end
		endcase
        prev <= state;
        state <= next;
    end


	// debug
	logic [31:0] throw0;
	logic [31:0] throw1;
	logic [31:0] throw2;
	logic [31:0] throw3;
	logic [31:0] throw4;
	logic [31:0] throw5;
	logic [31:0] throw6;
	assign throw0 = throw[0];
	assign throw1 = throw[1];
	assign throw2 = throw[2];
	assign throw3 = throw[3];
	assign throw4 = throw[4];
	assign throw5 = throw[5];
	assign throw6 = throw[6];

	logic [31:0] traj_x_out0;
	logic [31:0] traj_x_out1;
	logic [31:0] traj_x_out2;
	logic [31:0] traj_x_out3;
	logic [31:0] traj_x_out4;
	logic [31:0] traj_x_out5;
	logic [31:0] traj_x_out6;
	assign traj_x_out0 = traj_x_out[0];
	assign traj_x_out1 = traj_x_out[1];
	assign traj_x_out2 = traj_x_out[2];
	assign traj_x_out3 = traj_x_out[3];
	assign traj_x_out4 = traj_x_out[4];
	assign traj_x_out5 = traj_x_out[5];
	assign traj_x_out6 = traj_x_out[6];

	logic [31:0] traj_y_out0;
	logic [31:0] traj_y_out1;
	logic [31:0] traj_y_out2;
	logic [31:0] traj_y_out3;
	logic [31:0] traj_y_out4;
	logic [31:0] traj_y_out5;
	logic [31:0] traj_y_out6;
	assign traj_y_out0 = traj_y_out[0];
	assign traj_y_out1 = traj_y_out[1];
	assign traj_y_out2 = traj_y_out[2];
	assign traj_y_out3 = traj_y_out[3];
	assign traj_y_out4 = traj_y_out[4];
	assign traj_y_out5 = traj_y_out[5];
	assign traj_y_out6 = traj_y_out[6];

	logic [31:0] vx0;
	logic [31:0] vx1;
	logic [31:0] vx2;
	logic [31:0] vx3;
	logic [31:0] vx4;
	logic [31:0] vx5;
	logic [31:0] vx6;
	logic [31:0] vx7;
	assign vx0 = vx[0];
	assign vx1 = vx[1];
	assign vx2 = vx[2];
	assign vx3 = vx[3];
	assign vx4 = vx[4];
	assign vx5 = vx[5];
	assign vx6 = vx[6];
	assign vx7 = vx[7];

	logic [31:0] vy0;
	logic [31:0] vy1;
	logic [31:0] vy2;
	logic [31:0] vy3;
	logic [31:0] vy4;
	logic [31:0] vy5;
	logic [31:0] vy6;
	logic [31:0] vy7;
	assign vy0 = vy[0];
	assign vy1 = vy[1];
	assign vy2 = vy[2];
	assign vy3 = vy[3];
	assign vy4 = vy[4];
	assign vy5 = vy[5];
	assign vy6 = vy[6];
	assign vy7 = vy[7];


	//logic [31:0] queue0;
	//logic [31:0] queue1;
	//logic [31:0] queue2;
	//logic [31:0] queue3;
	//logic [31:0] queue4;
	//logic [31:0] queue5;
	//logic [31:0] queue6;
	//assign queue0 = queue[0];
	//assign queue1 = queue[1];
	//assign queue2 = queue[2];
	//assign queue3 = queue[3];
	//assign queue4 = queue[4];
	//assign queue5 = queue[5];
	//assign queue6 = queue[6];
endmodule
`default_nettype wire
