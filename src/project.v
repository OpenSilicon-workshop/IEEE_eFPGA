/*
 * tt_um_minifpga.v
 *
 * A minimal embedded FPGA (eFPGA) fabric for TinyTapeout.
 *
 * Architecture
 * ------------
 *   4 logic cells. Each cell is:
 *     - 4 inputs, each chosen by an 8:1 routing mux from a shared bus
 *     - a LUT4 (16 config bits) implementing any 4-input boolean function
 *     - an output flip-flop (ALWAYS registered - see note below)
 *
 *   Routing bus (8 sources, visible to every cell input):
 *     bus[3:0] = ui_in[3:0]   (external fabric inputs)
 *     bus[7:4] = cell 0..3 outputs (full crossbar - any cell can feed any cell)
 *
 * Why every cell output is registered
 * -----------------------------------
 *   A general FPGA lets you chain LUTs combinationally. That allows a user
 *   bitstream to create a combinational LOOP, which breaks static timing
 *   analysis and can oscillate on a shared TinyTapeout die. By forcing every
 *   cell output through a flip-flop, loops become legal synchronous feedback
 *   instead, STA sees only reg-to-reg paths, and the design stays quiet while
 *   it is not selected. Cost: multi-level logic takes one clock per level.
 *   This is the right trade-off for a first fabric.
 *
 * Configuration
 * -------------
 *   112 config bits in one shift register, clocked by the main clk while
 *   cfg_en is high. Shift MSB-first: the FIRST bit you shift in ends up at
 *   cfg[111], the LAST bit at cfg[0]. While cfg_en is high the fabric flops
 *   are frozen, so loading is glitch-free.
 *
 *   Bit layout, per cell i (28 bits each, cell 0 at cfg[27:0]):
 *     cfg[i*28 +  0 +: 3]  input 0 routing select
 *     cfg[i*28 +  3 +: 3]  input 1 routing select
 *     cfg[i*28 +  6 +: 3]  input 2 routing select
 *     cfg[i*28 +  9 +: 3]  input 3 routing select
 *     cfg[i*28 + 12 +: 16] LUT4 truth table (bit k = output for addr k,
 *                          where addr = {in3,in2,in1,in0})
 *
 * Pinout
 * ------
 *   ui_in[3:0]   fabric external inputs
 *   ui_in[4]     cfg_en   - high to shift configuration
 *   ui_in[5]     cfg_din  - configuration data in
 *   ui_in[7:6]   unused
 *   uo_out[3:0]  cell 0..3 outputs
 *   uo_out[4]    cfg_dout - end of config chain (for readback / verification)
 *   uo_out[7:5]  unused
 *   uio_*        unused
 */

`default_nettype none

module tt_um_minifpga (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

  localparam integer NCELLS   = 4;
  localparam integer NEXT_IN  = 4;                  // external fabric inputs
  localparam integer NSRC     = NEXT_IN + NCELLS;   // 8 routing sources
  localparam integer SELW     = 3;                  // log2(NSRC)
  localparam integer CELLBITS = 4 * SELW + 16;      // 28 bits per cell
  localparam integer CFGBITS  = NCELLS * CELLBITS;  // 112 bits total

  // ------------------------------------------------------------------
  // Pin decode
  // ------------------------------------------------------------------
  wire [3:0] fab_in  = ui_in[3:0];
  wire       cfg_en  = ui_in[4];
  wire       cfg_din = ui_in[5];

  // ------------------------------------------------------------------
  // Configuration shift register
  // ------------------------------------------------------------------
  reg [CFGBITS-1:0] cfg;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cfg <= {CFGBITS{1'b0}};
    end else if (ena && cfg_en) begin
      cfg <= {cfg[CFGBITS-2:0], cfg_din};
    end
  end

  wire cfg_dout = cfg[CFGBITS-1];

  // ------------------------------------------------------------------
  // Routing bus: external inputs in the low bits, cell outputs above
  // ------------------------------------------------------------------
  wire [NCELLS-1:0] cell_q;
  wire [NSRC-1:0]   bus = {cell_q, fab_in};

  // ------------------------------------------------------------------
  // Logic cells
  // ------------------------------------------------------------------
  genvar i, j;
  generate
    for (i = 0; i < NCELLS; i = i + 1) begin : cell
      wire [CELLBITS-1:0] c = cfg[i*CELLBITS +: CELLBITS];

      // Four input routing muxes
      wire [3:0] lut_addr;
      for (j = 0; j < 4; j = j + 1) begin : inmux
        wire [SELW-1:0] sel = c[j*SELW +: SELW];
        assign lut_addr[j] = bus[sel];
      end

      // LUT4
      wire [15:0] lut     = c[4*SELW +: 16];
      wire        lut_out = lut[lut_addr];

      // Output flip-flop. Frozen while configuration is shifting.
      reg q;
      always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          q <= 1'b0;
        end else if (ena && !cfg_en) begin
          q <= lut_out;
        end
      end

      assign cell_q[i] = q;
    end
  endgenerate

  // ------------------------------------------------------------------
  // Outputs
  // ------------------------------------------------------------------
  assign uo_out  = {3'b000, cfg_dout, cell_q};
  assign uio_out = 8'h00;
  assign uio_oe  = 8'h00;

  // Silence unused-signal lint warnings
  wire _unused = &{uio_in, ui_in[7:6], 1'b0};

endmodule
