`default_nettype none
module pattern_evaluation
	#(
		parameter THRESHOLD = 100
	)
	(
		input wire clk_in, // TODO what clock rate?
		input wire rst_in,
		input wire [2:0] num_balls,
		input wire [10:0] model_balls_x[6:0],
		input wire [9:0] model_balls_y[6:0],
		input wire [10:0] real_balls_x[6:0],
		input wire [9:0] real_balls_y[6:0],
		output logic data_valid_out,
		output logic [14:0] pattern_error,
		output logic pattern_correct
	);

	// FIXME decide on the bit widths
	logic [31:0] A[6:0][6:0];
	always_comb begin
		for (integer i = 0; i <= 7; ++i) begin
			for (integer j = 0; j <= 7; ++j) begin
				if (i <= num_balls && j <= num_balls) begin
					if (i == 0 || j == 0) begin
						A[i][j] = 0;
					end else begin
						A[i][j] = 
							(model_balls_x[i-1] - real_balls_x[j-1]) * (model_balls_x[i-1] - real_balls_x[j-1]) +
							(model_balls_y[i-1] - real_balls_y[j-1]) * (model_balls_y[i-1] - real_balls_y[j-1]);
					end
				end
			end
		end
	end

	// state machine
    typedef enum {
		INIT,
		FORI_INIT,
		FORI_CHECK,
		FORI_BODY,
		FORI_UPDATE,
		FORJ1_INIT,
		FORJ1_CHECK,
		FORJ1_BODY,
		FORJ1_UPDATE,
		WHILE1_BODY1,
		WHILE1_BODY2,
		WHILE1_CHECK,
		WHILE2_BODY,
		WHILE2_CHECK,
		ANS
	} state_t;
	state_t prev, state, next;

    logic [31:0] u [7:0];
    logic [31:0] v [7:0];
    logic [31:0] p [7:0];
    logic [31:0] way [7:0];
	logic [31:0] i;
	logic [31:0] j;
	logic [31:0] j0;
    logic signed [31:0] minv [7:0];
    logic used [7:0];
	logic [31:0] i0;
	logic signed [31:0] delta;
	logic [31:0] j1;
	logic signed [31:0] cur;
    logic [2:0] ans [6:0]; // permutation corr. to best matching

	always_comb begin
        if (rst_in) next = INIT;
        else begin
            case (state)
                INIT: next = FORI_INIT;
				FORI_INIT: next = FORI_CHECK;
				FORI_CHECK: next = state_t'((i <= num_balls) ? FORI_BODY : ANS);
				FORI_BODY: next = WHILE1_BODY1;
				WHILE1_BODY1: next = FORJ1_INIT;
				FORJ1_INIT: next = FORJ1_CHECK;
				FORJ1_CHECK: next = state_t'((j <= num_balls) ? FORJ1_BODY : WHILE1_BODY2);
				FORJ1_BODY: next = FORJ1_UPDATE;
				FORJ1_UPDATE: next = FORJ1_CHECK;
				WHILE1_BODY2: next = WHILE1_CHECK;
				WHILE1_CHECK: next = state_t'((p[j0] == 0) ? WHILE2_BODY : WHILE1_BODY1);
				WHILE2_BODY: next = WHILE2_CHECK;
				WHILE2_CHECK: next = state_t'((j0 == 0) ? FORI_UPDATE : WHILE2_BODY);
				FORI_UPDATE: next = FORI_CHECK;
				ANS: next = ANS;
                default: next = INIT;
            endcase
		end
	end

	always_ff @(posedge clk_in) begin
		case (state)
			INIT: begin
				for (integer x = 0; x <= 7; ++x) begin
					if (x <= num_balls) begin
						u[x] <= 0;
						v[x] <= 0;
						p[x] <= 0;
						way[x] <= 0;
					end
				end
			end
			FORI_INIT: begin
				i <= 1;
			end
			FORI_CHECK: begin end
			FORI_BODY: begin
				p[0] <= i;
				j0 <= 0;
				for (integer x = 0; x <= 7; ++x) begin
					if (x <= num_balls) begin
						minv[x] <= 1000000000; // INF
						used[x] <= 0;
					end
				end
			end
			WHILE1_BODY1: begin
				used[j0] <= 1;
				i0 <= p[j0];
				delta <= 1000000000;
				//j1 <= None	
			end
			FORJ1_INIT: begin
				j <= 1;
			end
			FORJ1_CHECK: begin end
			FORJ1_BODY: begin
				if (!used[j]) begin
					cur <= $signed(A[i0][j]) - $signed(u[i0]) - $signed(v[j]);
					if ($signed(cur) < $signed(minv[j])) begin
						minv[j] <= cur;
						way[j] <= j0;
						if ($signed(cur) < $signed(delta)) begin
							delta <= cur;
							j1 <= j;
						end
					end else begin
						if ($signed(minv[j]) < $signed(delta)) begin
							delta <= minv[j];
							j1 <= j;
						end
					end
				end
			end
			FORJ1_UPDATE: begin
				j <= j + 1;
			end
			WHILE1_BODY2: begin
				for (integer j2 = 0; j2 <= 7; ++j2) begin
					if (j2 <= num_balls) begin
						if (used[j2]) begin
							u[p[j2]] <= $signed(u[p[j2]]) + $signed(delta);
							v[j2] <= $signed(v[j]) - $signed(delta);
						end else begin
							minv[j] <= $signed(minv[j]) - $signed(delta);
						end
					end
				end
				j0 <= j1;
			end
			WHILE1_CHECK: begin end
			WHILE2_BODY: begin
				j1 <= way[j0];
				p[j0] <= p[j1];
				j0 <= j1;
			end
			WHILE2_CHECK: begin end
			FORI_UPDATE: begin
				i <= i + 1;
			end
			ANS: begin
				for (integer j2 = 0; j2 <= 7; ++j2) begin
					if (j2 <= num_balls) begin
						ans[p[j] - 1] <= j2 - 1;
					end
				end

				//data_valid_out <= 1;
				pattern_error <= -$signed(v[0]);
				pattern_correct <= (-$signed(v[0]) < THRESHOLD) ? 1 : 0;
			end
			default: begin end
		endcase

		prev <= state;
		state <= next;
	end

	assign data_valid_out = (state == ANS);
endmodule
`default_nettype wire
