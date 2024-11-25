import cocotb
import os
from pathlib import Path
import sys

from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles, FallingEdge
from cocotb.runner import get_runner

#TODO: Make it work without holding reset every time

@cocotb.test()
async def test_1(dut):
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())

    dut._log.info("Holding reset...")
    dut.rst_in.value = 1
    await ClockCycles(dut.clk_in, 3)
    dut.rst_in.value = 0
   
    dut.pattern_length.value = 3
    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 1
    dut.pattern_in.value = 5
    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 0

    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 1
    dut.pattern_in.value = 3
    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 0

    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 1
    dut.pattern_in.value = 1
    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 0

    await ClockCycles(dut.clk_in, 20)
    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 1
    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 0
    await ClockCycles(dut.clk_in, 1)

@cocotb.test()
async def test_2(dut):
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())

    dut.pattern_length.value = 4
    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 1
    dut.pattern_in.value = 7
    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 0

    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 1
    dut.pattern_in.value = 4
    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 0

    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 1
    dut.pattern_in.value = 2
    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 0

    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 1
    dut.pattern_in.value = 3
    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 0

    await ClockCycles(dut.clk_in, 20)
    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 1
    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 0
    await ClockCycles(dut.clk_in, 1)

@cocotb.test()
async def test_3(dut):
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())

    dut.pattern_length.value = 3
    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 1
    dut.pattern_in.value = 4
    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 0

    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 1
    dut.pattern_in.value = 3
    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 0

    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 1
    dut.pattern_in.value = 2
    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 0

    await ClockCycles(dut.clk_in, 20)
    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 1
    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 0
    await ClockCycles(dut.clk_in, 1)

@cocotb.test()
async def test_4(dut):
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
  
    dut.pattern_length.value = 7
    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 1
    dut.pattern_in.value = 7
    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 0

    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 1
    dut.pattern_in.value = 4
    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 0

    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 1
    dut.pattern_in.value = 2
    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 0

    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 1
    dut.pattern_in.value = 3
    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 0

    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 1
    dut.pattern_in.value = 4
    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 0

    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 1
    dut.pattern_in.value = 5
    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 0

    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 1
    dut.pattern_in.value = 3
    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 0

    await ClockCycles(dut.clk_in, 20)
    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 1
    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 0
    await ClockCycles(dut.clk_in, 1)

@cocotb.test()
async def test_5(dut):
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
  
    dut.pattern_length.value = 3
    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 1
    dut.pattern_in.value = 5
    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 0

    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 1
    dut.pattern_in.value = 3
    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 0

    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 1
    dut.pattern_in.value = 1
    await FallingEdge(dut.clk_in)
    dut.new_beat.value = 0

    await ClockCycles(dut.clk_in, 20)

def test_runner():
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = []
    sources.append(proj_path / "hdl" / "validate_pattern.sv")
    sources.append(proj_path / "hdl" / "generate_pattern.sv")
    sources.append(proj_path / "hdl" / "divider.sv")
    build_test_args = ["-Wall"]
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="generate_pattern",
        always=True,
        build_args=build_test_args,
        parameters={},
        timescale = ('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="generate_pattern",
        test_module="test_generate_pattern",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    test_runner()
