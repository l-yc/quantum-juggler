import cocotb
import os
import sys
import numpy as np
from math import log
import logging
from pathlib import Path
from random import randint, gauss
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles, RisingEdge, FallingEdge, ReadOnly, with_timeout
from cocotb.utils import get_sim_time as gst
from cocotb.runner import get_runner

async def reset(rst, clk):
    """Helper function to issue a reset signal to our module"""
    await ClockCycles(clk, 5)
    rst.value = 1
    await ClockCycles(clk, 5)
    rst.value = 0
    await ClockCycles(clk, 5)

def generate_centroids_and_data(width=412, height=187, k=2):
    """Generate a 2D array with hardcoded centroids and data"""
    if k == 2:
        centroids = [(100, 50), (200, 130)]
        init_centroids = [(120,40), (180,60)]
        data = np.zeros((height, width), dtype=int)
        for x in range(90, 111):
            for y in range(40, 61):
                data[y, x] = 1
        for x in range(190, 211):
            for y in range(120, 141):
                data[y, x] = 1
    elif k == 3:
        centroids = [(50, 50), (150, 100), (250, 150)]
        init_centroids = [(60,40), (130,80), (240,160)]
        data = np.zeros((height, width), dtype=int)
        for x in range(40, 61):
            for y in range(40, 61):
                data[y, x] = 1
        for x in range(140, 161):
            for y in range(90, 111):
                data[y, x] = 1
        for x in range(240, 261):
            for y in range(140, 161):
                data[y, x] = 1
    elif k == 4:
        centroids = [(50, 50), (150, 50), (50, 150), (150, 150)]
        init_centroids = [(120,40), (180,60), (240,80), (300,100)]
        data = np.zeros((height, width), dtype=int)
        for x in range(40, 61):
            for y in range(40, 61):
                data[y, x] = 1
        for x in range(140, 161):
            for y in range(40, 61):
                data[y, x] = 1
        for x in range(40, 61):
            for y in range(140, 161):
                data[y, x] = 1
        for x in range(140, 161):
            for y in range(140, 161):
                data[y, x] = 1
    elif k == 5:
        centroids = [(60, 60), (120, 60), (180, 60), (240, 60), (300, 60)]
        init_centroids = [(120,40), (180,60), (240,80), (300,100), (60,20)]
        data = np.zeros((height, width), dtype=int)
        for x in range(50, 71):
            for y in range(50, 71):
                data[y, x] = 1
        for x in range(110, 131):
            for y in range(50, 71):
                data[y, x] = 1
        for x in range(170, 191):
            for y in range(50, 71):
                data[y, x] = 1
        for x in range(230, 251):
            for y in range(50, 71):
                data[y, x] = 1
        for x in range(290, 311):
            for y in range(50, 71):
                data[y, x] = 1
    elif k == 6:
        centroids = [(50, 50), (150, 50), (250, 50), (50, 150), (150, 150), (250, 150)]
        init_centroids = [(120,40), (180,60), (240,80), (300,100), (60,20), (0,0)]
        data = np.zeros((height, width), dtype=int)
        for x in range(40, 61):
            for y in range(40, 61):
                data[y, x] = 1
        for x in range(140, 161):
            for y in range(40, 61):
                data[y, x] = 1
        for x in range(240, 261):
            for y in range(40, 61):
                data[y, x] = 1
        for x in range(40, 61):
            for y in range(140, 161):
                data[y, x] = 1
        for x in range(140, 161):
            for y in range(140, 161):
                data[y, x] = 1
        for x in range(240, 261):
            for y in range(140, 161):
                data[y, x] = 1
    # elif k == 7:
    #     centroids = [(50, 50), (150, 50), (250, 50), (50, 150), (150, 150), (250, 150), (160, 90)]
    #     init_centroids = [(120,40), (180,60), (240,80), (300,100), (60,20), (0,0), (40,120)]
    #     data = np.zeros((height, width), dtype=int)
    #     for x in range(40, 61):
    #         for y in range(40, 61):
    #             data[y, x] = 1
    #     for x in range(140, 161):
    #         for y in range(40, 61):
    #             data[y, x] = 1
    #     for x in range(240, 261):
    #         for y in range(40, 61):
    #             data[y, x] = 1
    #     for x in range(40, 61):
    #         for y in range(140, 161):
    #             data[y, x] = 1
    #     for x in range(140, 161):
    #         for y in range(140, 161):
    #             data[y, x] = 1
    #     for x in range(240, 261):
    #         for y in range(140, 161):
    #             data[y, x] = 1
    #     for x in range(150, 171):
    #         for y in range(80, 101):
    #             data[y, x] = 1
    else:
        raise ValueError("Unsupported value of k")

    return centroids, data, init_centroids

async def reset(rst, clk):
    """Helper function to issue a reset signal to our module"""
    await ClockCycles(clk, 5)
    rst.value = 1
    await ClockCycles(clk, 5)
    rst.value = 0
    await ClockCycles(clk, 5)

#@cocotb.test()
#async def test_k_means_two_clusters(dut):
#    """Cocotb test for the k_means module with two clusters"""
#    await run_k_means_test(dut, k=2)

@cocotb.test()
async def test_k_means_three_clusters(dut):
    """Cocotb test for the k_means module with three clusters"""
    await run_k_means_test(dut, k=3)

#@cocotb.test()
#async def test_k_means_four_clusters(dut):
#    """Cocotb test for the k_means module with four clusters"""
#    await run_k_means_test(dut, k=4)
#
#@cocotb.test()
#async def test_k_means_five_clusters(dut):
#    """Cocotb test for the k_means module with five clusters"""
#    await run_k_means_test(dut, k=5)
#
#@cocotb.test()
#async def test_k_means_six_clusters(dut):
#    """Cocotb test for the k_means module with six clusters"""
#    await run_k_means_test(dut, k=6)

# @cocotb.test()
# async def test_k_means_seven_clusters(dut):
#     """Cocotb test for the k_means module with seven clusters"""
#     await run_k_means_test(dut, k=7)
    
async def run_k_means_test(dut, k):
    """Parameterized test for different numbers of clusters"""
    # Generate input data with k centroids
    centroids, input_data, init_centroids = generate_centroids_and_data(k=k)

    # Save input data for inspection (optional)
    np.savetxt(f'test_array_{k}_clusters.txt', input_data, fmt='%d')

    # Setup logging
    dut._log.info(f"Starting test_k_means with {k} clusters...")

    # Start the clock
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())

    # Initialize centroids with hardcoded values
    for i, (cx, cy) in enumerate(init_centroids):
        dut.centroids_x_in[i].value = cx
        dut.centroids_y_in[i].value = cy
    dut.num_balls.value = k

    # Reset the DUT
    await reset(dut.rst_in, dut.clk_in)

    # Start feeding input data
    for y in range(input_data.shape[0]):
        for x in range(input_data.shape[1]):
            dut.x_in.value = x
            dut.y_in.value = y
            if (0 <= x < 320 and 0 <= y < 180):
                dut.data_valid_in.value = int(input_data[y, x])
            else:
                dut.data_valid_in.value = 0
            if (x == 320 and y == 180):
                # Indicate a new frame
                dut.new_frame.value = 1
            await RisingEdge(dut.clk_in)
            dut.new_frame.value = 0

    # Wait for output to become valid
    while not dut.data_valid_out.value:
        await RisingEdge(dut.clk_in)

    # Capture output centroids
    centroids_out_x = [dut.centroids_x_out[i].value.integer for i in range(k)]
    centroids_out_y = [dut.centroids_y_out[i].value.integer for i in range(k)]

    # Log results
    dut._log.info(f"Centroids X: {centroids_out_x}")
    dut._log.info(f"Centroids Y: {centroids_out_y}")

    # Verify results
    for cx, cy in zip(centroids_out_x, centroids_out_y):
        assert 0 <= cx < 320, f"Centroid X ({cx}) out of range"
        assert 0 <= cy < 180, f"Centroid Y ({cy}) out of range"
    # for i, (true_cx, true_cy) in enumerate(centroids):
    #     closest = np.argmin(
    #         [np.linalg.norm(np.array([true_cx, true_cy]) - np.array([cx, cy]))
    #          for cx, cy in zip(centroids_out_x, centroids_out_y)]
    #     )
    #     assert np.linalg.norm(
    #         np.array([centroids_out_x[closest], centroids_out_y[closest]]) - np.array([true_cx, true_cy])
    #     ) < 20, f"Centroid {i} position incorrect"


def is_runner():
    """Run the TMDS runner. Boilerplate code"""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "k_means.sv"]
    sources += [proj_path / "hdl" / "divider.sv"]
    sources += [proj_path / "hdl" / "minimum.sv"]
    sources += [proj_path / "hdl" / "xilinx_true_dual_port_read_first_1_clock_ram.v"]
    build_test_args = ["-Wall"]
    parameters = {}
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="k_means",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale=('1ns', '1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="k_means",
        test_module="test_k_means",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    is_runner()
