# Sound board model (sheets 15-17)

The sheet 15 flip-flops and buffers (U5, U7, U6) are traced logic in
`netlist/sheet15.net`. Everything analog is in `rtl/deathrac_audio.v`, with the
linear networks generated from component values by `tools/design_audio.py`
into `rtl/deathrac_audio_coef.vh`. `tools/audio_ref.py` is a floating-point
reference of the same chain; `sim/tb_audio.v` runs the RTL with the traced
U5/U7 cells.

Values were cross-checked against Exidy *Death Race* DR-1A sheets X/Y/Z,
which carry reference designators (R37-R104, C26-C64, Q6-Q13).

## Motor model revised, 5 November 2026

The Motor VCO and Motor sound sections below describe the original model where they
conflict with this one. The motor was refitted to real cabinet recordings of both games
(not included). Evidence and rejected ideas are in `docs/AUDIT.md`.

- Timing capacitor 33 uF for both games, as Death Race draws it. Derby's drawing prints 2.2.
- The assumed 74S112 input current into that capacitor is removed. Real parts do source this
  current and no circuit reason for its absence has been found, so this is a fit.
- XC1A is then about 6, 20, 33, 68 and 81 Hz, stopped through speed 15. Derby's recording
  shows 78 and 84.5 Hz at speed. The original model gave 247 to 372 Hz.
- Q6 and Q7 switch between conducting and cut-off coefficient sets per sample, from their
  base voltage. Q6's stage then oscillates by itself, as `tools/motor_spice.py` shows the
  nonlinear circuit does, instead of being forced to XC1A.
- Fits: beta 100, r_pi 1k and 4k, twin-T capacitor scale 0.84 (Derby, about 209 Hz, recording
  207 Hz) and 0.97 (Death Race, about 180 Hz). These compensate the switched model as well as
  part tolerance, so they are not component values.
- The noise source keeps the 3 kHz model. Its drawn parts give a narrow band at 313 Hz, but
  that barely reaches the motor and it would change the crash, which already sounds right.


**Motor VCO (sheet 15, per car).** GMC2..0 (7407, from GRPM/GRS1/GRS0) form a
resistor DAC (20k, 1.2k+10k, 1.2k+39k) on a 33 uF node. GMC2 low clamps the
node, so a stopped car idles at the lowest pitch. A 2N3904 (10k emitter)
and 2N3906 (2.2k emitter, 3.3k+diode base) mirror (Vb-0.65)/10k x 1.5 into
a 2.2 uF timing capacitor, which also gets 68k from +5 V and the 74S112 K
input current. U5a (J=1, K=capacitor, clock 2TQLC) sets every line while
the capacitor is below threshold and toggles once above it; its Q drives
the U6 7407 that discharges the capacitor for one line. U5b toggles on
each discharge line, giving the complementary XC1A/XC1B square waves at
half the relaxation rate, locked to the line clock. Integrated at 2 MHz.

**Noise (sheet 16, shared).** A reverse-biased 2N3904 junction amplified by
U8 (LM748, 1M/100 gain, 47k+diode limiting) and clipped by Q12. Modelled as
LFSR noise, one-pole low-pass, then sign to 0.2 V / 13.9 V.

**Motor sound (sheet 16).** Stage 1: XC1A (10k pull-up, 10k, 0.2/0.2 uF)
drives a 2N3904 with a twin-T (47k/47k/0.1 uF and .047/.047 uF/680 ohm) from
collector to base; noise enters through 330 pF. With the drawn 680 ohm the
linear model is a twin-T oscillator (about 210 Hz, unstable for any beta
from 50 to 300); in simulation it locks to the XC1A drive. Stage 2: 100k
input, 270k and 1M feedback, XC1B differentiated through .003 uF/100k, 10k
collector, 47k + 10k volume pot.

**Crash (sheet 16, per car).** GTHE/HTHE is a one-frame pulse (GTHB and not
its delayed copy, 7407 released = high). It charges 2.2 uF through 1.2k and
a diode; the node decays through 270k and the 100k+550k bias path. Node A
is that bias divided by 100k/550k, clamped by a diode to noise+0.6 V, so
the noise gates a level proportional to the envelope. A 2N3904 with a
bridged-T (.01/.01 uF, 33k) collector-base network low-passes it; the output
is the 47k/100k node held below collector+0.6 V by a diode.

**Output (sheet 17).** Crash and motor wipers each go through 22k + 0.1 uF to
a summing node, then 0.1 uF + 22k into 47k, the 150k LM380 input, and the
0.02 uF + tone pot network. EGMC (game active) and EHMC (two-player) are
7407 outputs on the summing node and mute it when low. Two LM380s are
bridged (gain 100), clipped at +/-13 V, into an 8 ohm speaker through
400 uF (50 Hz high-pass). +/-13 V maps to full-scale 16-bit output.

## Numerical method

Each linear network is written as nodal equations C dv/dt = -G v + B u with
a 10 pF parasitic per node, discretized by zero-order hold at 48 kHz, and
quantized to Q8.24 coefficients with Q16.16 volt states. Open-collector
outputs switch between two precomputed coefficient sets. Transistors are a
0.65 V junction plus r_pi with collector current beta*i_b; saturation and
cutoff are applied by clamping the collector node to 0.15 V..14 V each
sample. One sequential multiply-accumulate unit evaluates all blocks for
both channels (at most 2077 of the 2399 clocks per sample; scalar steps register their
operands once more before the DSP so the operand select meets timing at 115 MHz).

## Assumptions (not taken from the drawing)

| Item | Value | Basis |
|---|---|---|
| 2N3904 current gain | 150 | typical hFE; oscillation holds for 50-300 |
| 74S112 K input current | (4.25-V)/2.8k below 1.5 V | 74S input structure, within I_IL -1.6 mA max |
| 74S112 input threshold | 1.5 V | Schottky TTL typical |
| 7407 saturated output | 0.1 V, ~18-20 ohm | 0.7 V at 40 mA rating |
| Decoupled rail | 14 V | +15 V through 1.0k at ~1 mA |
| Noise bandwidth | 3 kHz one pole | 748 gain-bandwidth at gain 470 |
| Volume pots | motor 0.06, crash 0.05 | set 2026-11-05 because the sound was too loud; 0.20/0.10 sat at -10 dBFS and clipped on crashes |
| Tone rheostat R7 | Warm 0.15 (default), Dark 0, Bright 0.5 | OSD. The old default of 0.5 barely cut treble |
| Cabinet speaker | two 5 kHz one-pole sections | NOT on the schematic. The drawn amplifier is flat and XC1B's edges drive Q7 rail to rail, so a flat output is harsh |
| Sum-node leakage | 10M | node is capacitor-coupled only |
| 566 timing resistors | audio 158.9 Hz/V (8.4k), LFO 15.4 Hz/V | fitted to the reference recording; the LFO value is outside the pot range by the 566 formula, sheet W |
| WSCM pot | +/-3.2 V at the amplifier output | scream level, sheet W |
| Third scream transistor | 2.6 V base when saturated, 0.1 s base decay | beta 150 with 3.3k emitter, 22k collector |

## Scream (Death Race sheet W)

`rtl/deathrac_scream.v` is behavioural. One LADO pulse gives about 0.75 s of sound. The
second transistor's 100k charges the .2uF node through the diode as a ~0.12 mA current
source, so the sound opens within a few ms at the top pitch, which holds while the 6.8uF
node recharges through 1M (0.62 s). The .2uF node then decays through the third
transistor's base (~0.1 s), the pitch falls and the attenuator closes. The LFO 566
modulates the pitch throughout, also while the transistor is saturated.

Pitch, LFO rate and FM depth are fitted to a cabinet recording
(scream over motor sound): 2042 Hz carrier,
sidebands 197.5 Hz either side at -6 and -10 dB, held 0.62 s, then a fall to about
900 Hz in 0.1 s. The model gives 2040 Hz, 197.5 Hz, -8 dB, 0.62 s and 0.1 s. The hold
and fall times come from the drawn parts alone. A second recording
(a clean 1.70 kHz tone of the same length) was not used.

Earlier errors: the attack was a 0.2 s exponential toward 2.6 V; the capacitor was read
as 2uF where the drawing says .2UF; the 6.8uF node lost its fraction bits (hold 0.87 s);
and the LFO was removed while saturated. The MFC6040 is modelled as a gain ramp. It
joins at the amplifier input and is muted with the speaker it feeds.

## Drawing discrepancies

- Crash 1 prints 0.001 uF for the base-side bridged-T capacitor; crash 2
  and Death Race C54 print .01 uF. Both channels use .01 uF.
- Crash 1 prints 550k, crash 2 560k (Death Race R87 550k). Both use 550k.
- U5/U7 output bubbles are drawn on pin 5; the 74S112 pinout has Q on pin
  5. Connectivity follows pin numbers; the drawn polarity cannot oscillate.

## Expected behaviour (reference model; pitch is unaffected by the level changes)

| Car state | XC1A |
|---|---|
| stopped (GMC2 low) | ~243 Hz |
| speed 12 | ~267 Hz |
| speed 13 | ~293 Hz |
| speed 14 | ~355 Hz |
| speed 15 | ~369 Hz |

Pitch glides between speeds with the 33 uF DAC node (about 0.19 s). A crash
peaks within one frame and decays over about half a second.
