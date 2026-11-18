# Verification audit, 5 November 2026

The first transcription and models were treated as unverified and re-checked. Status of
each part. "Read" means compared by eye at full resolution, on both drawings where they differ.

## Wiring (netlist/*.net)

7 errors found and fixed; the table is in `docs/DEATH_RACE.md`. Seven is a floor: errors
were copied onto twin sheets, so `tools/check_symmetry.py` cannot catch that kind.

| Sheets | How checked |
|---|---|
| A, E, G, L, M, S, T, and the lower half and presets of B | Read against the netlist |
| K, P | Read at thumbnail resolution, plus close-ups of the parts that differ |
| Lower half of D | Read |
| C, H, N, upper half of D | By symmetry with the checked twin, plus thumbnails. Not read pin by pin |
| Sheet 18 pedals, sheet 19 cabinet | Not re-read. The pedal order was confirmed from PROM H3 |

## Cell library and generator (rtl/ttl_cells.v, tools/generate_netlist.py)

Pinouts of all 15 part types and the 74192, 74193, 74166, 74151, 74153 and 74S112 logic
were compared with their data sheets from memory of the published tables. No error was
found. Not re-checked against the PDFs themselves: the 74S200 stored-complement claim.

## Benches re-run after the fixes

Passing: `tb_cells`, `tb_score`, `tb_enemy_heading`, `tb_steering`, `tb_pedal`,
`tb_scream`, JTFRAME startup and reset, JTFRAME controls integration.

`tb_gear` prints no PASS line: it ran to `$finish` without an error, and only that much
is established.

Not re-run: event-driven against sampled-FPGA picture comparison. Pending until the
full-game simulations end.

## Integration

| Item | Result |
|---|---|
| Clock | Changed. New PLL `rtl/pll7197`, 115.151515 MHz (50 x 76/33, integer mode). Crystal is exactly that / 8 = 14.394 MHz, 0.02% above the drawn 14.391 MHz. Frame rate 60.07 Hz. Pixels are exactly 8 clocks long. Quartus 20.1, 6 November 2026: the PLL gives 115.151515 MHz (VCO 1266.67 MHz, M 152, N 6, C 11). A12 (74S200) and the image PROMs B8-E8 are read through a register, one 8.7 ns clock late (the parts take about 40-50 ns); tb_game checks the address is steady a clock before every use, and frames and logs of both games match the zero-delay read over 50 frames. All four seeds pass, setup +0.052 to +0.592 ns; seed 3 is used. `rtl/deathrac.sdc` declares game_dr static |
| Audio out | Passed through JTFRAME directly at 48 kHz |
| Video mix | Resistors agree with both drawings, but the brightness mapping was wrong. Fixed, see below |

## Video levels

The background should not be grey. The first model added 5TNVD as positive
grey, but it is an inverted signal: high everywhere including blanking, low only on the
player 2 car. The output is AC coupled, so blanking level is black, and that high level is
black. Now background 0, objects 255, player 2 car 136 (53%), from the same resistors.
This audit first recorded the video mix as correct, because only the resistor values had
been compared. `sim/tb_video.v` checks the levels. Every earlier build had the grey
background and showed the player 2 car wrongly.

## Sound model (tools/design_audio.py, rtl/deathrac_audio.v)

Component values and topology of the motor stages, sheets 15-17, match both drawings.
Problems found in the assumptions:

| Item | First model | Finding | Status |
|---|---|---|---|
| Motor timing capacitor | 2.2 uF | Derby prints 2.2. Death Race C21 and C24 are drawn 33 | Open. Neither render sounds right |
| Transistors | Linear with collector clamps | Both motor stages swing almost rail to rail, far outside a linear model | Open. `tools/motor_spice.py` is the nonlinear reference, not in the RTL |
| Noise source | 3 kHz low-pass | LM748 with its drawn parts peaks at 313 Hz, 254-385 Hz. A warbling square, not hiss | Open. Barely changes the motor. It feeds the crash, which sounds right as it is |
| Volume, tone | Chosen | Changed, see `docs/ANALOG.md`. Still operator settings | Done |

Computed from PROM C14, not yet run: timer counts every 0.80, 1.07 or 1.33 s, so 99 counts
last about 79, 105 or 132 s for the 1, 1 1/2 and 2 minute positions.

## Cabinet recordings (not included)

Provenance and recording chain are not known yet. Both are 20 s, 44.1 kHz, identical left
and right. Measured:

| | Death Race | Derby |
|---|---|---|
| Main low tones | 157-201 Hz, some at 240 Hz | 207 Hz and 219.5 Hz at idle |
| Higher bands | about 510-535 Hz, 860 Hz | 253, 312, 338, 592, 859, 1098 Hz at speed |
| Sub-harmonics | | 78 Hz series on 312 Hz, about 85 Hz series on 338 Hz |
| Waveform | Rounded and irregular, no flat tops, no sharp edges | The same |

Findings:

- Real cabinet recordings. So the speaker and room are part of them.
- Derby's tones at speed are one harmonic series: 84.5 Hz (x3, 4, 5, 7, 8, 11, 13), and 78.1 Hz
  at another speed. The real XC1A is about 80 Hz at speed, not the 345 Hz the first model gave.
- The cause in the model is one assumption, a 1.2 mA flip-flop input current charging the
  timing capacitor. Without it, and with 33 uF, the five speeds give XC1A 6, 20, 33, 68, 81 Hz.
  Both games were run with 33 uF, including Derby, whose drawing prints 2.2.
- **Unexplained:** a real 74S112 input does source current when low. Removing it fits the
  recordings, but no circuit reason for that has been found. Treat it as a fit.
- The first stage oscillates by itself: 207-214 Hz with beta 100 and twin-T capacitors +12.5%
  (Derby), about 182 Hz with +30% (Death Race). It now stays nearly undisturbed at idle, as
  recorded. Those scale factors are fits within the range of part tolerance, the +30% less
  comfortably.
- Tried and rejected on the evidence: weakening the XC1A coupling (the drive tone stays
  dominant even at 100 times R38), and a stage just short of oscillating at high beta (no
  change with drive on).
- Still different: the real recordings carry relatively more energy at 300-1100 Hz at speed.
- Now in the RTL as a switched model. `rtl/deathrac_audio.v` picks on/off coefficients per sample
  from each transistor's base voltage. Measured from Icarus renders of the Verilog, against
  the recordings:

| | Recording | Verilog |
|---|---|---|
| Derby stopped | 207 Hz | 202 Hz |
| Death Race stopped | 169-187 Hz | 177 Hz |
| Derby top speed, lowest tone | 84.5 Hz, inferred from the tone spacing | 81 Hz |
| Death Race idle 3rd harmonic, relative to the strongest tone | -3 to -5 dB | -15 dB |
| Derby top speed, energy below 120 Hz | 1% | 64% |
| Derby top speed, energy at 600-1100 Hz | 28% | 2% |

- The last three rows are real differences that remain. The energy below 120 Hz may come from
  the cabinet speaker or the recording microphone; the recordings cannot separate them.
- Top-speed figures are from the end of the render, after the crash, because speed 15 is still
  settling when the crash starts. Not yet heard on hardware, and Quartus has not been run.

## What cannot be settled from the drawings

Part tolerances on the actual boards, and the speaker and room in the recordings.

The side-by-side wreck has not been reproduced.
