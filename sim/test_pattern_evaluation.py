import cocotb
import os
import random
import sys
from math import log
import logging
from pathlib import Path
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles, RisingEdge, FallingEdge, ReadOnly,with_timeout
from cocotb.utils import get_sim_time as gst
from cocotb.runner import get_runner
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.animation as animation

async def init(dut):
    dut._log.info("Starting...")
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    dut._log.info("Holding reset...")
    dut.rst_in.value = 1
    #dut.rx_wire_in.value = 1 # pull high initially
    await ClockCycles(dut.clk_in, 3) #wait three clock cycles
    #assert dut.data_valid_out.value.integer==0, "data_valid_out is not 0 on reset!"
    await FallingEdge(dut.clk_in)
    dut.rst_in.value = 0 #un reset device
    await ClockCycles(dut.clk_in, 3) #wait three clock cycles


@cocotb.test()
async def test_a(dut):
    """cocotb test for """
    await init(dut)

    await FallingEdge(dut.clk_in)
    dut.num_balls = 3;
    await ClockCycles(dut.clk_in, 1)

    dut.data_valid_in.value = 1;
    dut.model_balls_x.value = [0, 0, 0, 0, 500, 100, 0];
    dut.model_balls_y.value = [0, 0, 0, 0, 500, 100, 0];
    dut.real_balls_x.value = [0, 0, 0, 0, 10, 510, 110];
    dut.real_balls_y.value = [0, 0, 0, 0, 10, 510, 110];
    await ClockCycles(dut.clk_in, 1)
    dut.data_valid_in.value = 0;

    await with_timeout(RisingEdge(dut.data_valid_out),5000,'ns')
    await ClockCycles(dut.clk_in, 5)
    pat_err = dut.pattern_error.value.integer
    pat_ok = dut.pattern_correct.value
    print(pat_err, pat_ok)
    assert pat_err == 600
    assert dut.ans[0].value == 2
    assert dut.ans[1].value == 0
    assert dut.ans[2].value == 1


def pattern_evaluation_runner():
    """Simulate the counter using the Python runner."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "pattern_evaluation.sv"]
    sources += [proj_path / "hdl" / "divider.sv"]
    sources += [proj_path / "hdl" / "evt_counter.sv"]
    build_test_args = ["-Wall"]
    parameters = {'THRESHOLD': 1000}
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="pattern_evaluation",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale = ('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="pattern_evaluation",
        test_module="test_pattern_evaluation",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    pattern_evaluation_runner()
