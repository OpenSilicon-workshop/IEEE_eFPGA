# Mini eFPGA — TinyTapeout (1x2 tiles)

A minimal embedded FPGA fabric: 4 logic cells, each a LUT4 with a registered
output, fully crossbar-connected, configured over a 112-bit serial chain.

## Architecture

Routing bus (8 sources, every cell input can select any of them):

| Bus index | Source           |
|-----------|------------------|
| 0–3       | ui_in[0..3]      |
| 4–7       | cell 0..3 output |

Each cell: 4 routing muxes (3 config bits each) → LUT4 (16 config bits) →
output flip-flop. 28 config bits per cell, 112 total.

### Every output is registered — on purpose

A general FPGA lets LUTs chain combinationally, which means a user bitstream
can create a **combinational loop**. That breaks static timing analysis and
can oscillate on a die shared with hundreds of other designs. Registering
every cell output turns loops into legal synchronous feedback, leaves STA
with only reg-to-reg paths, and keeps the design quiet when not selected.

The cost: each level of logic takes one clock cycle. A 2-level function needs
2 cycles to settle. The testbench allows 3 cycles between applying inputs and
checking outputs for this reason.

## Bitstream format

Shift **MSB of the config word first**. The RTL shifts
`cfg <= {cfg[110:0], cfg_din}`, so the first bit in lands at `cfg[111]`.

Per cell *i* (cell 0 occupies `cfg[27:0]`):

| Bits                | Meaning                                   |
|---------------------|-------------------------------------------|
| `cfg[i*28 + 0 +: 3]`  | input 0 routing select                  |
| `cfg[i*28 + 3 +: 3]`  | input 1 routing select                  |
| `cfg[i*28 + 6 +: 3]`  | input 2 routing select                  |
| `cfg[i*28 + 9 +: 3]`  | input 3 routing select                  |
| `cfg[i*28 + 12 +: 16]`| LUT4 truth table, addr = {in3,in2,in1,in0} |

Generate bitstreams with `tools/gen_bitstream.py`:

```bash
python3 tools/gen_bitstream.py          # prints the demo bitstream
```

or as a library:

```python
from gen_bitstream import Cell, build_bitstream, lut_from_fn
cells = [Cell(inputs=[0,1,0,0], lut=lut_from_fn(lambda a,b,c,d: a and b)), ...]
bits = build_bitstream(cells)
```

## Loading a configuration on hardware

1. Assert reset (clears the chain).
2. Hold `ui_in[4]` (cfg_en) high, present each bit on `ui_in[5]` (cfg_din),
   pulse the clock — 112 times.
3. Drop cfg_en low. The fabric now evaluates.
4. `uo_out[4]` is the far end of the chain, so you can shift the pattern
   through twice and compare for a readback check.

## Before you submit — RUN THESE

This RTL has **not** been simulated by its author. Verify locally first:

```bash
cd test
pip install cocotb
make
```

