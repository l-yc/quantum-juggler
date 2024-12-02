import cocotb
import os
import sys
from math import log
import logging
from pathlib import Path
from random import randint
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles, RisingEdge, FallingEdge, ReadOnly,with_timeout
from cocotb.utils import get_sim_time as gst
from cocotb.runner import get_runner

@cocotb.test()
async def test_1(dut):
    dut._log.info("Starting test 1")
    dut.vals_in.value = [2, 3, 1, 2, 2, 5, 2]
    dut.max.value = 5
    await Timer(1, units="ns")
    assert dut.minimum_index.value == 4
    await Timer(1, units="ns")

@cocotb.test()
async def test_2(dut):
    dut._log.info("Starting test 2")
    dut.vals_in.value = [2, 3, 1, 2, 5, 2, 1]
    dut.max.value = 2
    await Timer(1, units="ns")
    assert dut.minimum_index.value == 0
    await Timer(1, units="ns")

@cocotb.test()
async def test_3(dut):
    dut._log.info("Starting test 3")
    dut.vals_in.value = [2, 3, 1, 2, 5, 3, 6]
    dut.max.value = 6
    await Timer(1, units="ns")
    assert dut.minimum_index.value == 4
    await Timer(1, units="ns")

@cocotb.test()
async def test_4(dut):
    dut._log.info("Starting test 4")
    dut.vals_in.value = [2, 3, 1, 4, 5, 3, 6]
    dut.max.value = 4
    await Timer(1, units="ns")
    assert dut.minimum_index.value == 1
    await Timer(1, units="ns")

@cocotb.test()
async def test_5(dut):
    dut._log.info("Starting test 5")
    dut.vals_in.value = [12, 10, 8, 2, 15, 11, 50]
    dut.max.value = 3
    await Timer(1, units="ns")
    assert dut.minimum_index.value == 1
    await Timer(1, units="ns")

def is_runner():
    """Run the TMDS runner. Boilerplate code"""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "minimum.sv"]
    build_test_args = ["-Wall"]
    parameters = {}
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="minimum",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale = ('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="minimum",
        test_module="test_minimum",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    is_runner()
