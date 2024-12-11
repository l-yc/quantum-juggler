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
    dut.hand_x_in.value = [800, 500]
    dut.hand_y_in.value = [600, 700]
    await init(dut)

    await FallingEdge(dut.clk_in)
    dut.nf_in = 0;
    dut.pattern = [0, 0, 0, 0, 1, 3, 5]
    #dut.pattern = [0, 0, 0, 0, 3, 3, 3]
    #dut.pattern = [0, 0, 0, 0, 5, 5, 5]
    #dut.pattern = [0, 0, 0, 0, 3, 2, 4]
    dut.pattern_valid.value = 1
    dut.num_balls.value = 3

    dut.frame_per_beat.value = 3

    await ClockCycles(dut.clk_in, 1) #wait three clock cycles
    dut.pattern_valid.value = 0

    xs = [ [] for _ in range(3) ]
    ys = [ [] for _ in range(3) ]
    for i in range(40 * 5):
        dut.nf_in = 1
        await ClockCycles(dut.clk_in, 1)
        dut.nf_in = 0
        if dut.traj_valid:
            frame_xs = []
            frame_ys = []
            for j in range(7):
                x = dut.traj_x_out[j].value.integer
                y = dut.traj_y_out[j].value.integer
                frame_xs.append(x)
                frame_ys.append(y)
                #print(x, end=' ')
            #print()
            #xs = dut.traj_x_out.value
            #ys = dut.traj_y_out.value
            #print(xs)
            #print(frame_xs)

            for j in range(3):
                xs[j].append(frame_xs[j])
                ys[j].append(frame_ys[j])

        if i == 45:
            dut.frame_per_beat.value = 10
        await ClockCycles(dut.clk_in, 1)


    #for i in range(3):
    #    print(xs[i])
    #    print(ys[i])
    print(xs[0])
    print(xs[1])
    print(xs[2])
    np.savez('model_balls.npz', xs0=xs[0], xs1=xs[1], xs2=xs[2], ys0=ys[0], ys1=ys[1], ys2=ys[2])

    print('ok')
    if True:
        # matploblib stuff

        fig, ax = plt.subplots()
        scat = [ ax.scatter(xs[i], ys[i], s=30, label=f'ball {i}') for i in range(3) ]
        ax.set(xlim=[0, 1280], ylim=[0, np.max(720) + 0.1], xlabel='x [m]', ylabel='y [m]')
        ax.legend()


        def update(frame):
            for i in range(3):
                x = xs[i][frame]
                y = ys[i][frame]

                data = np.stack([x, y]).T
                if i == 0:
                    print('frame', frame, 'data', data)
                scat[i].set_offsets(data)
            return scat[0]

        ani = animation.FuncAnimation(fig=fig, func=update, frames=len(xs[0]), interval=100)
        plt.gca().invert_yaxis()
        plt.show()


    # input wire clk_in, // TODO what clock rate?
    # input wire rst_in,
    # input wire pattern[6:0][2:0],
    # input wire pattern_valid,
    # input wire num_balls[2:0],
    # input wire hand_x_in[1:0][6:0],
    # input wire hand_y_in[1:0][6:0],
    # input wire ms_per_beat[14:0],
    # output logic traj_x_out[6:0][10:0],
    # output logic traj_y_out[6:0][9:0],
    # output logic traj_valid,



#def pack(pixel):
#    assert pixel is not None
#    r, g, b = pixel # pixel is a tuple of values (R,G,B) ranging from 0 to 255
#    packed = int(format(r, '05b')[-5:] + format(g, '06b')[-6:] + format(b, '05b')[-5:], 2)
#    return packed
#
#def pack2(pixel):
#    r, g, b = pixel
#    return (int(r) << 11) | (int(g) << 5) | int(b)


#@cocotb.test()
#async def test_a(dut):
#    """cocotb test for """
#    await init(dut)
#
#    im_input = Image.open("../meme.jpg")
#    im_input = im_input.convert("RGB")
#    im_arr = np.array(im_input)
#    np.save("../im_arr", im_arr)
#    dut._log.info(f"im_input size: {im_arr.shape}")
#
#    im_arr[:,:,0] = np.divide(im_arr[:,:,0], 8) # -3 bits
#    im_arr[:,:,1] = np.divide(im_arr[:,:,1], 4) # -2 bits
#    im_arr[:,:,2] = np.divide(im_arr[:,:,2], 8) # -3 bits
#    np.save("../im_arr", im_arr)
#
#    h, w, _ = im_arr.shape
#    out = []
#    await ClockCycles(dut.clk_in, 3)
#
#    deadcount = 0
#    for y in range(h):
#        for x in range(w):
#            await FallingEdge(dut.clk_in)
#            dut.hcount_in.value = x
#            dut.vcount_in.value = y
#            dut.data_valid_in.value = 1
#            dut.data_in.value = (pack2(im_arr[(y-1) % h, x]) << 32) | (pack2(im_arr[y, x]) << 16) | pack2(im_arr[(y+1) % h, x])
#            try:
#                out.append(dut.line_out.value.integer)
#            except:
#                deadcount += 1
#                print("dead")
#    for _ in range(deadcount):
#        await FallingEdge(dut.clk_in)
#        out.append(int(dut.line_out.value))
#    np.save("../conv_out", out)
#
#    out = np.array(out).reshape((h, w))
#    out_r = out >> 11
#    out_g = (out >> 5) & 63
#    out_b = out & 31
#    im_out = np.stack((out_r * 8, out_g * 4, out_b * 8), axis=-1)
#    np.save("../im_out", im_out)
#    Image.fromarray(im_out.astype("uint8"), "RGB").save("../im_out.png")


def trajectory_generator_runner():
    """Simulate the counter using the Python runner."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "trajectory_generator.sv"]
    sources += [proj_path / "hdl" / "divider.sv"]
    sources += [proj_path / "hdl" / "evt_counter.sv"]
    build_test_args = ["-Wall"]
    parameters = { 'g': 5, 's': 50 }
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="trajectory_generator",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale = ('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="trajectory_generator",
        test_module="test_trajectory_generator",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    trajectory_generator_runner()
