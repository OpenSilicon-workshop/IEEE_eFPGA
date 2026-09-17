# cocotb testbench for tt_um_minifpga
#
# Loads a bitstream that configures:
#   cell0 = ui_in[0] AND ui_in[1]
#   cell1 = ui_in[0] OR  ui_in[1]
#   cell2 = ui_in[0] XOR ui_in[1]
#   cell3 = NOT ui_in[0]
# then checks all four input combinations.
#
# Run with `make` in this directory (needs iverilog + cocotb).

import os
import sys

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
from gen_bitstream import build_bitstream, demo_cells, CFGBITS  # noqa: E402

CFG_EN = 4   # ui_in bit
CFG_DIN = 5  # ui_in bit


def pins(fab_in=0, cfg_en=0, cfg_din=0):
    return (fab_in & 0xF) | (cfg_en << CFG_EN) | (cfg_din << CFG_DIN)


async def load_bitstream(dut, bits):
    """Shift the bitstream in, MSB of the config word first."""
    for b in bits:
        dut.ui_in.value = pins(cfg_en=1, cfg_din=b)
        await RisingEdge(dut.clk)
    # Drop cfg_en so the fabric starts evaluating
    dut.ui_in.value = pins()
    await RisingEdge(dut.clk)


@cocotb.test()
async def test_configured_logic(dut):
    """After loading the demo bitstream, the fabric implements AND/OR/XOR/NOT."""

    cocotb.start_soon(Clock(dut.clk, 10, units="us").start())

    dut.ena.value = 1
    dut.uio_in.value = 0
    dut.ui_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)

    bits = build_bitstream(demo_cells())
    assert len(bits) == CFGBITS, f"bitstream should be {CFGBITS} bits"
    await load_bitstream(dut, bits)

    for a in range(2):
        for b in range(2):
            dut.ui_in.value = pins(fab_in=a | (b << 1))
            # Cell outputs are registered, so allow a couple of cycles to settle
            await ClockCycles(dut.clk, 3)

            out = int(dut.uo_out.value)
            got_and = out & 1
            got_or = (out >> 1) & 1
            got_xor = (out >> 2) & 1
            got_not = (out >> 3) & 1

            assert got_and == (a & b), f"AND failed for a={a} b={b}: got {got_and}"
            assert got_or == (a | b), f"OR failed for a={a} b={b}: got {got_or}"
            assert got_xor == (a ^ b), f"XOR failed for a={a} b={b}: got {got_xor}"
            assert got_not == (1 - a), f"NOT failed for a={a}: got {got_not}"


@cocotb.test()
async def test_config_readback(dut):
    """The config chain should shift out what was shifted in, 112 bits later."""

    cocotb.start_soon(Clock(dut.clk, 10, units="us").start())

    dut.ena.value = 1
    dut.uio_in.value = 0
    dut.ui_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)

    bits = build_bitstream(demo_cells())

    # Shift the pattern all the way through and capture what comes out
    readback = []
    for b in bits + bits:  # second pass pushes the first pass out the far end
        dut.ui_in.value = pins(cfg_en=1, cfg_din=b)
        await RisingEdge(dut.clk)
        readback.append((int(dut.uo_out.value) >> 4) & 1)

    # The last CFGBITS samples should be the first pattern we shifted in
    assert readback[CFGBITS:] == bits, "config chain readback mismatch"
