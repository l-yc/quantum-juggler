import cocotb
import os
from pathlib import Path
import sys

from cocotb.triggers import Timer
from cocotb.runner import get_runner

@cocotb.test()
async def test_1(dut):
    dut._log.info("Starting test 1 (531->VALID)")
    dut.pattern_in.value = int("000000000000001011101", 2)
    dut.pattern_length.value = 3
    await Timer(1, units="ns")
    assert dut.pattern_valid_out.value == 1
    await Timer(1, units="ns")

@cocotb.test()
async def test_2(dut):
    dut._log.info("Starting test 2 (432->INVALID)")
    dut.pattern_in.value = int("000000000000010011100", 2)
    dut.pattern_length.value = 3
    await Timer(1, units="ns")
    assert dut.pattern_valid_out.value == 0
    await Timer(1, units="ns")

@cocotb.test()
async def test_3(dut):
    dut._log.info("Starting test 3 (7423->VALID)")
    dut.pattern_in.value = int("000000000011010100111", 2)
    dut.pattern_length.value = 4
    await Timer(1, units="ns")
    assert dut.pattern_valid_out.value == 1
    await Timer(1, units="ns")

@cocotb.test()
async def test_4(dut):
    dut._log.info("Starting test 4 (7423453->VALID)...")
    dut.pattern_in.value = int("011101100011010100111", 2)
    dut.pattern_length.value = 7
    await Timer(1, units="ns")
    assert dut.pattern_valid_out.value == 1
    await Timer(1, units="ns")

@cocotb.test()
async def test_5(dut):
    dut._log.info("Starting test 5 (7423152->INVALID)...")
    dut.pattern_in.value = int("010101001011010100111", 2)
    dut.pattern_length.value = 7
    await Timer(1, units="ns")
    assert dut.pattern_valid_out.value == 0
    await Timer(1, units="ns")

def test_runner():
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = []
    sources.append(proj_path / "hdl" / "validate_pattern.sv")
    build_test_args = ["-Wall"]
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="validate_pattern",
        always=True,
        build_args=build_test_args,
        parameters={},
        timescale = ('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="validate_pattern",
        test_module="test_validate_pattern",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    test_runner()
