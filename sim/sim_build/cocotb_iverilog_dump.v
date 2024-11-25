module cocotb_iverilog_dump();
initial begin
    $dumpfile("/home/lyc/Dropbox/Main/School/MIT/Fall_2024/6.2050/quantum-juggler/sim/sim_build/trajectory_generator.fst");
    $dumpvars(0, trajectory_generator);
end
endmodule
