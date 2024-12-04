module draw_trajectory
	#(
		parameter BALL_SIZE = 10
	)
	(
		input wire clk_in,
		input wire rst_in,

		input wire [2:0] num_balls,
		input wire [10:0] traj_x_in[6:0],
		input wire [9:0] traj_y_in[6:0],
		input wire traj_valid,
		input wire [10:0] hand_x_in[1:0],
		input wire [9:0] hand_y_in[1:0],

		input wire [10:0] hcount_in,
		input wire [9:0] vcount_in,
		output logic [7:0] red_out,
		output logic [7:0] green_out,
		output logic [7:0] blue_out
	);

	logic hit[6:0];
	always_comb begin
		hit[0] = num_balls > 0 && (
			(hcount_in+BALL_SIZE > traj_x_in[0] && hcount_in < traj_x_in[0]+BALL_SIZE) &&
			(vcount_in+BALL_SIZE > traj_y_in[0] && vcount_in < traj_y_in[0]+BALL_SIZE)
		);
		hit[1] = num_balls > 1 && (
			(hcount_in+BALL_SIZE > traj_x_in[1] && hcount_in < traj_x_in[1]+BALL_SIZE) &&
			(vcount_in+BALL_SIZE > traj_y_in[1] && vcount_in < traj_y_in[1]+BALL_SIZE)
		);
		hit[2] = num_balls > 2 && (
			(hcount_in+BALL_SIZE > traj_x_in[2] && hcount_in < traj_x_in[2]+BALL_SIZE) &&
			(vcount_in+BALL_SIZE > traj_y_in[2] && vcount_in < traj_y_in[2]+BALL_SIZE)
		);
		hit[3] = num_balls > 3 && (
			(hcount_in+BALL_SIZE > traj_x_in[3] && hcount_in < traj_x_in[3]+BALL_SIZE) &&
			(vcount_in+BALL_SIZE > traj_y_in[3] && vcount_in < traj_y_in[3]+BALL_SIZE)
		);
		hit[4] = num_balls > 4 && (
			(hcount_in+BALL_SIZE > traj_x_in[4] && hcount_in < traj_x_in[4]+BALL_SIZE) &&
			(vcount_in+BALL_SIZE > traj_y_in[4] && vcount_in < traj_y_in[4]+BALL_SIZE)
		);
		hit[5] = num_balls > 5 && (
			(hcount_in+BALL_SIZE > traj_x_in[5] && hcount_in < traj_x_in[5]+BALL_SIZE) &&
			(vcount_in+BALL_SIZE > traj_y_in[5] && vcount_in < traj_y_in[5]+BALL_SIZE)
		);
		hit[6] = num_balls > 6 && (
			(hcount_in+BALL_SIZE > traj_x_in[6] && hcount_in < traj_x_in[6]+BALL_SIZE) &&
			(vcount_in+BALL_SIZE > traj_y_in[6] && vcount_in < traj_y_in[6]+BALL_SIZE)
		);
	end

	always_comb begin
		if (
			traj_valid &&
			(hit[0] || hit[1] || hit[2] || hit[3] || hit[4] || hit[5] || hit[6])
		) begin
			red_out = 8'hFF;
			green_out = 8'h00;
			blue_out = 8'h00;
		end else begin
			red_out = 8'h00;
			green_out = 8'h00;
			blue_out = 8'h00;
		end
	end
endmodule
