`default_nettype none
module pattern_evaluation
	#(
		parameter THRESHOLD = 512
	)
	(
		input wire clk_in, // TODO what clock rate?
		input wire rst_in,
		input wire nf_in,
		input wire data_valid_in,
		input wire [2:0] num_balls,
		input wire [10:0] model_balls_x[6:0],
		input wire [9:0] model_balls_y[6:0],
		input wire [10:0] real_balls_x[6:0],
		input wire [9:0] real_balls_y[6:0],
		output logic data_valid_out,
		output logic signed [14:0] pattern_error,
		output logic pattern_correct
	);

	// FIXME decide on the bit widths
	logic [22:0] A[6:0][6:0];
	always_comb begin
		for (integer i = 0; i <= 7; ++i) begin
			for (integer j = 0; j <= 7; ++j) begin
				if (i <= num_balls && j <= num_balls) begin
					if (i == 0 || j == 0) begin
						A[i][j] = 0;
					end else begin
						A[i][j] = 
							($signed(model_balls_x[i-1]) - $signed(real_balls_x[j-1])) * ($signed(model_balls_x[i-1]) - $signed(real_balls_x[j-1])) +
							($signed(model_balls_y[i-1]) - $signed(real_balls_y[j-1])) * ($signed(model_balls_y[i-1]) - $signed(real_balls_y[j-1]));
					end
				end
			end
		end
	end

	// state machine
    typedef enum {
		INIT = 0,
		FORI_INIT = 1,
		FORI_CHECK = 2,
		FORI_BODY = 3,
		FORI_UPDATE = 4,
		FORJ1_INIT = 5,
		FORJ1_CHECK = 6,
		FORJ1_BODY = 7,
		FORJ1_UPDATE = 8,
		WHILE1_BODY1 = 9,
		WHILE1_BODY2 = 10,
		WHILE1_CHECK = 11,
		WHILE2_BODY = 12,
		WHILE2_CHECK = 13,
		ANS = 14
	} state_t;
	logic [3:0] prev, state, next;

    logic [22:0] u [7:0];
    logic [22:0] v [7:0];
    logic [2:0] p [7:0];
    logic [2:0] way [7:0];
	logic [2:0] i;
	logic [2:0] j;
	logic [2:0] j0;
    logic signed [22:0] minv [7:0];
    logic used [7:0];
	logic [2:0] i0;
	logic signed [22:0] delta;
	logic [2:0] j1;
    logic [2:0] ans [6:0]; // permutation corr. to best matching

	always_comb begin
        if (rst_in) next = INIT;
        else begin
            case (state)
				INIT: next = (data_valid_in ? FORI_INIT : INIT);
				FORI_INIT: next = FORI_CHECK;
				FORI_CHECK: next = ((i <= num_balls) ? FORI_BODY : ANS);
				FORI_BODY: next = WHILE1_BODY1;
				WHILE1_BODY1: next = FORJ1_INIT;
				FORJ1_INIT: next = FORJ1_CHECK;
				FORJ1_CHECK: next = ((j <= num_balls) ? FORJ1_BODY : WHILE1_BODY2);
				FORJ1_BODY: next = FORJ1_UPDATE;
				FORJ1_UPDATE: next = FORJ1_CHECK;
				WHILE1_BODY2: next = WHILE1_CHECK;
				WHILE1_CHECK: next = ((p[j0] == 0) ? WHILE2_BODY : WHILE1_BODY1);
				WHILE2_BODY: next = WHILE2_CHECK;
				WHILE2_CHECK: next = ((j0 == 0) ? FORI_UPDATE : WHILE2_BODY);
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

				data_valid_out <= 0;
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
				if (used[j] == 0) begin
					if ($signed(A[i0][j]) - $signed(u[i0]) - $signed(v[j]) < $signed(minv[j])) begin
						minv[j] <= $signed(A[i0][j]) - $signed(u[i0]) - $signed(v[j]);
						way[j] <= j0;
						if ($signed(A[i0][j]) - $signed(u[i0]) - $signed(v[j]) < $signed(delta)) begin
							delta <= $signed(A[i0][j]) - $signed(u[i0]) - $signed(v[j]);
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
							v[j2] <= $signed(v[j2]) - $signed(delta);
						end else begin
							minv[j2] <= $signed(minv[j2]) - $signed(delta);
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
				for (integer j2 = 1; j2 <= 7; ++j2) begin
					if (j2 <= num_balls) begin
						ans[p[j2] - 1] <= j2 - 1;
					end
				end

				data_valid_out <= 1;
				pattern_error <= -$signed(v[0]);
				pattern_correct <= (-$signed(v[0]) < $signed(THRESHOLD * num_balls)) ? 1 : 0;
			end
			default: begin end
		endcase

		prev <= state;
		state <= next;
	end

	//logic [31:0] debug_ans0;
	//logic [31:0] debug_ans1;
	//logic [31:0] debug_ans2;
	//logic [31:0] debug_ans3;
	//logic [31:0] debug_ans4;
	//logic [31:0] debug_ans5;
	//logic [31:0] debug_ans6;
	//assign debug_ans0 = ans[0];
	//assign debug_ans1 = ans[1];
	//assign debug_ans2 = ans[2];
	//assign debug_ans3 = ans[3];
	//assign debug_ans4 = ans[4];
	//assign debug_ans5 = ans[5];
	//assign debug_ans6 = ans[6];

	//logic [31:0] debug_u0;
	//logic [31:0] debug_u1;
	//logic [31:0] debug_u2;
	//logic [31:0] debug_u3;
	//logic [31:0] debug_u4;
	//logic [31:0] debug_u5;
	//logic [31:0] debug_u6;
	//assign debug_u0 = u[0];
	//assign debug_u1 = u[1];
	//assign debug_u2 = u[2];
	//assign debug_u3 = u[3];
	//assign debug_u4 = u[4];
	//assign debug_u5 = u[5];
	//assign debug_u6 = u[6];


	//logic [31:0] debug_v0;
	//logic [31:0] debug_v1;
	//logic [31:0] debug_v2;
	//logic [31:0] debug_v3;
	//logic [31:0] debug_v4;
	//logic [31:0] debug_v5;
	//logic [31:0] debug_v6;
	//assign debug_v0 = v[0];
	//assign debug_v1 = v[1];
	//assign debug_v2 = v[2];
	//assign debug_v3 = v[3];
	//assign debug_v4 = v[4];
	//assign debug_v5 = v[5];
	//assign debug_v6 = v[6];

	//logic [32:1] debug_A11;
	//logic [32:1] debug_A12;
	//logic [32:1] debug_A13;
	//logic [32:1] debug_A21;
	//logic [32:1] debug_A22;
	//logic [32:1] debug_A23;
	//logic [32:1] debug_A31;
	//logic [32:1] debug_A32;
	//logic [32:1] debug_A33;
	//assign debug_A11 = A[1][1];
	//assign debug_A12 = A[1][2];
	//assign debug_A13 = A[1][3];
	//assign debug_A21 = A[2][1];
	//assign debug_A22 = A[2][2];
	//assign debug_A23 = A[2][3];
	//assign debug_A31 = A[3][1];
	//assign debug_A32 = A[3][2];
	//assign debug_A33 = A[3][3];
endmodule
`default_nettype wire
