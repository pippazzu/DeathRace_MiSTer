# Accuracy contract

Target: Chicago Coin Demolition Derby, model 466, as drawn in the operator's
manual schematics (`DemolitionDerby.pdf`, not included). This is a structural transcription project, not a
gameplay reimplementation. The source PDF is authoritative for wiring.

Source SHA-256:
`12c1da80eab3d2671ba38069720a0bb853124a5a65db6f2176db73a4977df59e`.
Its pages contain 2480 x 3201 pixel raster images. Printed schematic pages
1-19 are PDF pages 3-21. The extracted upright frames are rotated 90 degrees
clockwise and are 3201 x 2480 pixels. No AI reconstruction is used.

## Levels of evidence

- **Transcribed:** visible pin, symbol and wire/label in the source crop.
- **Device model:** Boolean/sequential function obtained from the part data
  sheet, distinct from source wiring evidence.
- **Boundary:** analog circuitry or missing programmed data, exposed rather
  than replaced with guessed logic.
- **Unresolved:** an ambiguous label, omitted input, or conflicting pin.

Standard pinouts detect errors; they do not authorize silently correcting
the drawing. Unused output stubs are not grounded. Undrawn inputs remain
unknown unless a separately documented electrical convention is applied.
Named power-up nodes are distinct until the drawing establishes a tie.

## Modeling scope

The reference Verilog preserves derived clocks, asynchronous controls and
chip boundaries. It is intended for four-state event-driven simulation.
Successful compilation does not establish a playable game or FPGA timing
closure. Retiming into one FPGA clock domain is a separate step that must
be compared against the reference. Target is MiSTer, DE10-Nano Cyclone V
5CSEBA6U23I7.

Crystal oscillators, RC startup nodes, analog steering/speed circuits, sound
and the video resistor network require explicit boundary models. No arbitrary
gate delays may be presented as measured board delays. PROM contents must
come from verified dumps; missing PROM words remain X.

## External references

- [TI 74161 family, SDLS060](https://www.ti.com/lit/ds/symlink/sn74ls161a.pdf):
  pinout, asynchronous clear, synchronous load/count and carry.
- [TI 74S112/74LS112, SDLS011](https://www.ti.com/lit/gpn/SN54LS112A):
  negative clock edge, J/K, asynchronous preset/clear. Both controls low
  assert both outputs; release from that condition is not a valid stored bit.
- [TI 74174 family, SDLS068A](https://www.ti.com/lit/gpn/sn74ls174):
  positive-edge D register with asynchronous clear.
- [Signetics bipolar memory handbook](https://www.bitsavers.org/components/signetics/_dataBooks/1973_Bipolar_Memory.pdf):
  PROM organization and pin functions.
- [MAME chicago.cpp](https://github.com/mamedev/mame/blob/ab8a0bb68884bf3c2b95355abfafeb1a41fc7dd2/src/mame/misc/chicago.cpp):
  PROM inventory only. This driver is a skeleton and explicitly labels its
  copied Pong timing as inaccurate. Those timing constants are not evidence
  for this implementation. MAME's C13 dump label conflicts with the drawing's
  C15 timing PROM location; any mapping must be recorded explicitly.

## Sheet 1 analog/passive boundary

- B16 pins 1-4, crystal printed 14.391 MHz (literal reading), two 470-ohm
  resistors and a .01 / 100 capacitor form the oscillator. Do not substitute
  the common 14.31818 MHz frequency without resolving the printed value.
- B16.6 (`1TQ14`) is the oscillator boundary input to the digital netlist.
- B16.8 (`T999`) and G15.4 (`T998`) each have a 6.8 capacitor to ground;
  their inverter inputs are grounded. They are exposed separately as
  startup/analog boundary inputs, not treated as an added board reset.
- A14.15 (`TLCA`) has .001 to ground, not modeled as a Boolean connection.
- G15.8 through 4.7k, G15.10 through 8.2k and G15.12 through 2.2k meet
  at the video summing node. That node has 1.2k to ground and a series 6.8
  capacitor to B-20 VIDEO. B-20 has 39k to B-21 VIDEO RETURN/ground.
  Capacitance units follow drawing convention but are not printed at every
  instance. Electrical voltage/loading and coupling response are not yet
  represented by a one-bit video output.

## Source-reading notes

Sheet 1 A15 and A14 data inputs 3-6 are drawn as open stubs. Their load
controls are inactive in normal operation, but those stubs are not ground.
B15 data pins 3 and 6 are grounded; pins 4 and 5 are tied to its
inverted ninth counter bit. B14 differs: pin 3 is grounded and pins 4, 5,
AND 6 are tied to 5TLC9. This was corrected on the second native-crop audit.
This distinction affects reloads and the vertical period.
Net names are normalized to ASCII; leading numeric polarity/buffer prefixes
are retained. A leading `n_` is added only in generated Verilog identifiers.

## Pre-build audit, 2026-11-02

Second witness: Exidy *Death Race* logic diagram DR-1A (19 pages, scanned
upside down). Its sheet letters match this board's (E game control, T timing
and video, X/Y/Z sound). It is a cleaner redraw and is consulted only where
the Chicago drawing is ambiguous; each use is named below.

- **82S129 output order (fixed, affects 8 PROMs).** The generator listed
  outputs O4..O1 as bits 0..3. Signetics 82S129: O1 = pin 12 = data bit 0.
  Verified two ways: B8/C8/D8/E8 decode as clean car bitmaps only with
  O1 = bit 0, and H3/N1 then decode as a coherent speed controller
  (counter range 12-15, reload value 12, reverse only at speed 12, crash
  caps speed). Affects B8, C8, D8, E8, H6, B2, H3, N1. Frame captures made
  before this fix are invalid.
- **H11.4 / B7.4 (fixed).** Traced as OPEN; the drawings clearly connect
  C10.11 BCNG (sheet 8) and E9.6 DCNG (sheet 10) to these 7421 inputs.
  BCNG/DCNG were therefore listed as unused outputs.
- **C10 duplicate designator.** Sheet 6 C10 is a 74166 that uses every pin.
  Sheet 8 also labels the BCNG 7408 "C10" (verified in the source raster).
  This is a drafting error; the gate is modelled as drawn and its physical
  location is unknown. The sheet 10 twin is E9.
- **R5, sheet 2 (fixed).** Pin 4/5 leads overlap where E999 meets the
  ground bus; output stubs 14, 13 and 11 end in T-bars, leaving pin 12 as
  5ECKS. Death Race 3R draws power-good clearly crossing ground to pin 5
  and SECKS from pin 12. Now: 3=ACT3, 4=0, 5=E999, 6=0, 12=5ECKS (reload
  value 4/5 and period 5/4 ECKC counts, previously 2/3 and 3/2). The
  junction dot where ACT3 crosses the pin-9 line is a drafting slip; Death
  Race shows a plain crossing, and a junction would short two outputs.
- **K14 (added).** 7407 EGME->EGMC and E2PL->EHMC are the sheet 17 speaker
  mute inputs (Death Race 5W/5K agree). K14.4 EPOG remains the power-on
  boundary input. 4EGME drives the GAME OVER lamp triac to cabinet B-19.
- **TDRG alias.** C15 pin 2 is labelled "TCRG (BD)"; every TDRG use is on
  sheets B (8) and D (10). Alias confirmed.
- **C15 PROM = MAME cdi.c13.** Decoded with that mapping, THBL is one
  contiguous 6-entry run containing the 2-entry THSC. Mapping confirmed.
- **Crystal.** Native-resolution crop reads "14.391MHZ"; retained.
- **OPEN inputs re-checked.** L12/M12/N12/P12 pins 1 and 12, N16.6,
  N10.12 and E6.12 are visible unterminated stubs; C12/E12 pin 14 feeds an
  unused register bit. Modelled as floating-high TTL inputs.
- **Undrawn inputs** A15/A14/H16 pins 3-6: load is tied to the power-good
  node, so these counters never load while running; clear dominates in reset.
- **Remaining unused outputs** all leave the logic board: GMC/HMC/GTHE/
  HTHE/EGMC/EHMC (sound, sheets 15-17), 1TBVD/5TNVD/6TCSC (video summing
  node), 4EGME (lamp); 2AQT0, 5ECK1 and 6TQGY end without a destination.
- **Sheet 18 (pulse generators).** Each steering wheel and gas pedal is a
  466-250x assembly: two phototransistors, each buffered by a 7400 latch
  with 10M hysteresis feedback. Steering is quadrature (MTTA/MTTB, decoded
  by P7/P8). The pedal is a 2-bit position; H3/N1 show the travel sequence
  00 (stopped), 01, 11, 10 (fastest).
- **Sheet 19** is cabinet wiring (power, coin meter, slam switch, speakers,
  lamps, reverse switches); no board logic.
- **Sound (sheets 15-17).** Sheet 15 U5/U7/U6 are now traced
  (`netlist/sheet15.net`). The analog circuits are modelled from component
  values; see `docs/ANALOG.md`. The previous model triggered the crash
  envelope on GTHE low, which is the idle state, and played constant noise.

## Start positions (corrected 2026-11-15)

Each car's position counters are preset by a 999 line and a ground bus drawn over the
preset pins. On five chips the 999 line crosses the bus without a junction dot and ends on
one pin only; the trace had put the neighbouring pins on 999 as well. Both drawings agree
(Derby sheets 8, 10, 14; DR-1A sheets B, D, N).

| Chip (DR-1A) | Was | Is | Meaning |
|---|---|---|---|
| H5 (10K) | 15=0, 1/10/9=999: 14 | 1=999, 15/10/9=0: 2 | Enemy A column, tens digit |
| B1 (10W) | 15=0, 1/10/9=999: 14 | 15=999, 1/10/9=0: 1 | Enemy C column, tens digit |
| J6 (10H), C2 (10U) | all four 999: 15 | 15=999, 1/10/9=0: 1 | Enemy line, high nibble |
| P3 (6A) | 15/1/10=999, 9=0: 7 | 1=999, 15/10/9=0: 2 | Player 2 column, tens digit |

N4 (6L, player 1) was right: pins 15, 1, 10 on M999, pin 9 on its own ground, 7.

With the old values both enemies were preset to one spot (14 is not even a BCD digit), and
so were both players. They share one design, so they also moved together: the stacked
enemies seen on MiSTer. Now the enemies start at opposite sides of the field and the
players at the bottom, left and right. `sim/vl_spawn.cpp` runs the whole board through
coin and start, prints the counters at each preset and counts frames with the two enemies
on the same position and heading.

## Power-on state of the enemy cars

The two enemy cars (sheets A-D) share one design. Nothing on the board clears their turn
and speed timers (M10/F6, K12/J12, D6/C6, J11/C5, the 74112s) or, before the first coin,
their position counters, so on a real board those power up in different states. Clearing
them to zero at reset made both cars identical in attract mode. Every 74161, 74174,
74193/74192 and 74112 on sheets 7-10 now takes its reset
value from `seed` in `rtl/deathrac_board.v`, a free-running LFSR sampled while reset is held
(`SEEDED_SHEETS` in `tools/generate_netlist.py`).
