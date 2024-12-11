`default_nettype none

module trajectory_generator
	#(
		parameter g = 6, // pixels / frame^2
		parameter s = 20,
        parameter MAX_TICK = 2
	)
	(
		input wire clk_in, // TODO what clock rate?
		input wire rst_in,
		input wire nf_in,
		input wire [2:0] pattern[6:0],
		input wire pattern_valid,
		input wire [2:0] num_balls,
		input wire [10:0] hand_x_in[1:0],
		input wire [9:0] hand_y_in[1:0],
		input wire [3:0] frame_per_beat,
		output logic [10:0] traj_x_out[6:0],
		output logic [9:0] traj_y_out[6:0],
		output logic traj_valid
	);

	// MARK: calculate look up tables
	logic [10:0] distance;
	assign distance = _hand_x_in[1] - _hand_x_in[0];

	logic [7:0][10:0] vx;
	logic [7:0][20:0] vy;
	logic [7:0] vx_ready;
    always_comb begin
        vx[0] = 0;
        vx_ready[0] = 1;
        vy[0] = 0;
        for (int p = 1; p < 8; p=p+1) begin
			vy[p] = (p == 2) ? 0 : (g * p * _frame_per_beat) >> 1;
        end
    end

	logic needs_divide;
	generate
		genvar p;
		for (p = 1; p < 8; p += 1) begin
			divider #(.WIDTH(22)) vx_divider(
				.clk_in(clk_in),
				.rst_in(rst_in),
				.dividend_in((p&1) == 0 ? 2 * s : distance),
				.divisor_in(p * _frame_per_beat),
				.data_valid_in(needs_divide),
				.quotient_out(vx[p]),
				.remainder_out(),
				.data_valid_out(vx_ready[p]),
				.error_out(),
				.busy_out());
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

    logic [$clog2(MAX_TICK)-1:0] tick_count;
    logic [$clog2(MAX_TICK)-1:0] prev_tick_count;
    evt_counter #(
        .MAX_COUNT(MAX_TICK),
		.RST_VAL(0)
	) tick_counter (
		.clk_in(clk_in),
		.rst_in(rst_in),
		.evt_in(nf_in),
		.count_out(tick_count)
	);

    // Pulse for new time tick
    logic tick;
    always_ff @(posedge clk_in) begin
        tick <= prev_tick_count == MAX_TICK - 2 && tick_count == MAX_TICK - 1;
        prev_tick_count <= tick_count;
    end


	// inputs
	evt_counter #(
		.MAX_COUNT(4096),
		.RST_VAL(0)
	) t_counter (
		.clk_in(clk_in),
		.rst_in(rst_in),
		.evt_in(tick),
		.count_out(t)
	);

	logic [2:0] _pattern[6:0];
	logic [2:0] _num_balls;
	logic [10:0] _hand_x_in[1:0];
	logic [9:0] _hand_y_in[1:0];
	logic [3:0] _frame_per_beat;

//	always_comb begin
//		if (hand_x_in[0] < hand_x_in[1]) begin
//			_hand_x_in[0] = hand_x_in[0];
//			_hand_x_in[1] = hand_x_in[1];
//			_hand_y_in[0] = hand_y_in[0];
//			_hand_y_in[1] = hand_y_in[1];
//		end else begin
//			_hand_x_in[0] = hand_x_in[1];
//			_hand_x_in[1] = hand_x_in[0];
//			_hand_y_in[0] = hand_y_in[1];
//			_hand_y_in[1] = hand_y_in[0];
//		end
//	end

	// FIXME think through how many bits we actually need... 
	logic [11:0] t_start[6:0];
	logic hand[6:0];
	logic [2:0] throw[6:0];
	logic [11:0] t;
	logic hidx;
	logic [2:0] pidx;
	logic [2:0] queue[6:0];
	logic [14:0] counter;
    always_ff @(posedge clk_in) begin
		case (state)
			IDLE: begin
				// output
				traj_valid <= 0;
				for (integer i = 0; i < 7; i += 1) begin
					traj_x_out[i] <= 0;
					traj_y_out[i] <= 0;
				end
				needs_divide <= 0;

                if (hand_x_in[0] < hand_x_in[1]) begin
                    _hand_x_in[0] <= hand_x_in[0];
                    _hand_x_in[1] <= hand_x_in[1];
                    _hand_y_in[0] <= hand_y_in[0];
                    _hand_y_in[1] <= hand_y_in[1];
                end else begin
                    _hand_x_in[0] <= hand_x_in[1];
                    _hand_x_in[1] <= hand_x_in[0];
                    _hand_y_in[0] <= hand_y_in[1];
                    _hand_y_in[1] <= hand_y_in[0];
                end
			end
			INIT: begin
				if (pattern_valid) begin
					// input
					for (integer i = 0; i < 7; i += 1) begin
						_pattern[i] <= pattern[i];
					end
					_num_balls <= num_balls;
					_frame_per_beat <= frame_per_beat;
					needs_divide <= 1;

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
							queue[i] <= num_balls;
						end
					end

					counter <= 0;
				end else begin
					needs_divide <= 0;
				end
			end
			TRANSMIT: begin
				if (tick == 1) begin
					if (counter == 0) begin
						t_start[queue[0]] <= t+1;
						hand[queue[0]] <= hidx;
						hidx <= hidx == 1 ? 0 : 1;
						throw[queue[0]] <= _pattern[pidx];
						pidx <= pidx == _num_balls-1 ? 0 : pidx + 1;

						// queue <= [0] + queue[6:1]
						// queue[throw[queue[0]]-1] = queue[0];
						for (integer i = 0; i < 7; i += 1) begin
							if (queue[0] < _num_balls && i == _pattern[pidx]-1) begin
								queue[i] <= queue[0];
							end else if (i == 6) begin
								queue[i] <= _num_balls;
							end else begin
								queue[i] <= queue[i+1];
							end
						end
					end
					counter <= counter+1 < _frame_per_beat ? counter+1 : 0;

					traj_valid <= 1;
					for (integer i = 0; i < 7; i += 1) begin
						if (i < _num_balls && t_start[i] <= t) begin
							if ((throw[i] & 1) == 0) begin
								traj_x_out[i] <= hand[i] == 0 ? _hand_x_in[0] + s - vx[throw[i]] * (t - t_start[i]) : _hand_x_in[1] - s + vx[throw[i]] * (t - t_start[i]);
							end else begin
								traj_x_out[i] <= hand[i] == 0 ? _hand_x_in[0] + s + vx[throw[i]] * (t - t_start[i]) : _hand_x_in[1] - s - vx[throw[i]] * (t - t_start[i]);
							end
							traj_y_out[i] <= _hand_y_in[0] - vy[throw[i]] * (t - t_start[i]) + ((g * (t - t_start[i]) * (t - t_start[i])) >> 1);
						end
					end
				end
			end
		endcase
        prev <= state;
        state <= next;
    end


	// debug
	logic [31:0] debug0;
	logic [10:0] debug1;
	logic [31:0] debug2;
	logic [31:0] debug3;
	logic [31:0] debug4;
	logic [31:0] debug5;
	logic [31:0] debug6;
	assign debug0 = hand[0]; // 32 bits
	assign debug1 = _hand_x_in[0]; // 11 bits
	assign debug2 = _hand_x_in[1]; // 11 bits
	assign debug3 = vx[throw[0]]; // 32 bits
	assign debug4 = t - t_start[0]; // 32 bits
	assign debug5 = _hand_x_in[0] + vx[throw[0]] * (t - t_start[0]);
	assign debug6 = hand[0] == 0 ? _hand_x_in[0] + vx[throw[0]] * (t - t_start[0]) : _hand_x_in[1] - vx[throw[0]] * (t - t_start[0]);


	logic [31:0] t_start0;
	logic [31:0] t_start1;
	logic [31:0] t_start2;
	logic [31:0] t_start3;
	logic [31:0] t_start4;
	logic [31:0] t_start5;
	logic [31:0] t_start6;
	assign t_start0 = t_start[0];
	assign t_start1 = t_start[1];
	assign t_start2 = t_start[2];
	assign t_start3 = t_start[3];
	assign t_start4 = t_start[4];
	assign t_start5 = t_start[5];
	assign t_start6 = t_start[6];

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

	//logic [31:0] vy0;
	//logic [31:0] vy1;
	//logic [31:0] vy2;
	//logic [31:0] vy3;
	//logic [31:0] vy4;
	//logic [31:0] vy5;
	//logic [31:0] vy6;
	//logic [31:0] vy7;
	//assign vy0 = vy[0];
	//assign vy1 = vy[1];
	//assign vy2 = vy[2];
	//assign vy3 = vy[3];
	//assign vy4 = vy[4];
	//assign vy5 = vy[5];
	//assign vy6 = vy[6];
	//assign vy7 = vy[7];


	logic [31:0] queue0;
	logic [31:0] queue1;
	logic [31:0] queue2;
	logic [31:0] queue3;
	logic [31:0] queue4;
	logic [31:0] queue5;
	logic [31:0] queue6;
	assign queue0 = queue[0];
	assign queue1 = queue[1];
	assign queue2 = queue[2];
	assign queue3 = queue[3];
	assign queue4 = queue[4];
	assign queue5 = queue[5];
	assign queue6 = queue[6];



	logic [31:0] hand0;
	logic [31:0] hand1;
	logic [31:0] hand2;
	logic [31:0] hand3;
	logic [31:0] hand4;
	logic [31:0] hand5;
	logic [31:0] hand6;
	assign hand0 = hand[0];
	assign hand1 = hand[1];
	assign hand2 = hand[2];
	assign hand3 = hand[3];
	assign hand4 = hand[4];
	assign hand5 = hand[5];
	assign hand6 = hand[6];
endmodule
`default_nettype wire
