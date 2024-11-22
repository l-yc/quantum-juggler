module cocotb_iverilog_dump();
initial begin
    $dumpfile("/home/toyat/6205/quantum-juggler/sim/sim_build/validate_pattern.fst");
    $dumpvars(0, validate_pattern);
end
endmodule
