# Death Race and the shared board

One core, `DeathRace.rbf`, plays both games. Each MRA sends a game id byte and that
game's PROMs at load time (`tools/make_mra.py`), so no ROM data is built into the RBF.
The MRAs take MAME romset zips as they are: `deathrac.zip` for Death Race, `destdrby.zip`
for Destruction Derby (Exidy, the main Derby MRA) and `dmodrbcc.zip` for Demolition Derby
(Chicago Coin, which also accepts `destdrby.zip`; its MRA is in `_alternatives/_Destruction Derby/`). The two Derby sets hold the same 15
dumps under different names, so both send identical data.
Death Race (Exidy DR-1A, updated 6-29-76) is the Chicago model 466 board with the IC
positions moved. The Derby netlist remains the base, and `netlist/deathrace.overrides`
plus `netlist/sheet16.net` hold every difference, selected by the `GAME_DR` net.

Comparison method: each DR-1A sheet was read against the netlist at full resolution,
then any disagreement was read again on the Derby drawing. `tools/check_symmetry.py`
compares the twin sheets (A/C, B/D, G/H, M/N) as graphs.

## Differences that are real

| Sheet | Part | Death Race |
|---|---|---|
| A, C | 7E, 7R 82S123-36 | A0 = 5ECK1 (two walking frames), A1-A3 = heading bits 1-3, A4 ground. Eight headings. |
| K | 13F pins 3, 4 | Grounded: gremlins are never mirrored. |
| K | 11E.5, 14H.2 | Grounded. KKGE and KLGE are marked "Not in use". |
| P | 12J, 13J, 12K, 13K pin 7 | 1TQ14: gremlin serializers shift at twice the car rate. |
| T | 14A pin 9 | 1TQ14: the video latch keeps those half pixels. |
| T | 13R, 14A pin 11 | TNVD = 5TCBL & 1PNVD. |
| G | 4P GTHX | GTHD or HTHD: one crash generator for both cars, sheet Y. |
| L, W | 4S LADO, scream | NAND(5LNCK, 5LMCK) triggers `rtl/deathrac_scream.v`. Fed into both amplifiers (sheet Z). |
| T | R130 | 5.1k, Derby 8.2k. Sync only, not modelled. |
| M, N | Turn inputs | Net names MTNL/MTNR and connector Turn A/B are both swapped. Per physical sensor the equations match, so nothing was changed. If Death Race steers backwards on hardware this is the place to look. |

Sheet K's PROMs are 11M/11L/11K/11J (-97 to -100). Code 0 is the tombstone cross,
drawn for crash RAM entries the same way as the Derby wreck.

## Derby transcription errors found by this comparison

Each was confirmed on the Derby drawing itself, and agrees with DR-1A.

| Sheet | Wrong | Right | Effect |
|---|---|---|---|
| 14 | N3 = NEC7,NEC5; M3.13 = NEC8 | N3 = NEC8,NEC7; M3.13 = NEC5 | Old decode needed BCD 13, which P3 never reaches. Player 2's car should not have drawn. |
| 8, 10 | H7.2 BGLR, B3.2 DGLR | 5BGLR, 5DGLR | Enemy preset condition inverted. |
| 11, 13 | K2 K = 5GHTA, 5HTHA | 5GTHB, 5HTHB | Crash one-shot could stay set. |
| 7, 9 | M10.7 ARTG, F6.7 CRTG | 5ART3, 5CRT3 | Enemy timer counted past its stop bit. |
| 8, 10 | H5 preset 14, B1 preset 14, J6/C2 preset 15 | H5 2, B1 1, J6/C2 1 | Both enemies started on one spot and moved stacked (found 15 November, `docs/ACCURACY.md`). |
| 14 | P3 preset 7 | 2 | Player 2 started on top of player 1. |
| 1 | A13.9 TLC8 | TLCB | TDAM active on half the screen instead of one line carry. |
| 3 | M15.2 SG20 | DIP_2MIN_N | Game time options wrong. |
| 3 | N16 4=5SG20 5=S999 6=OPEN | 4=SG20 5=5SG20 6=S999 | Game time options wrong. |

The side-by-side wreck seen in early builds has not been reproduced. Some of
these fixes touch that logic, but none is claimed to have solved it.

## Video

Pixels now leave at the crystal rate, 14.391 MHz, for both games, and
`JTFRAME_WIDTH` is 768. Derby pixels simply repeat twice. HQ2x is removed because its
line buffers scale with the width.

## Analog triggers

Each player's right trigger (RT) also works the pedal, in every Accelerator axis mode:
whichever of the axis and the trigger is pressed further. It needs a MiSTer Main that
sends triggers (UIO_ATRIG 0x46, unstable builds from 3 November 2026); with an older Main
the trigger reads 0 and changes nothing. The left trigger is not used.

JTFRAME has no wire for triggers. `tools/jtframe_trigger.py` makes patched copies of
`hps_io.sv`, `jtframe_mister.sv`, `jtframe_emu.sv` and `jtframe_game_instance.v` from the
JTFRAME tree at staging time, adding `joytrig_1p` and `joytrig_2p` from hps_io to the game.
JTFRAME itself is not edited, and every stick, paddle and button keeps its own input. The
approach follows the Monaco GP MiSTer core, which puts one trigger on
player 4's right stick instead. Tests: `tools/test_jtframe_trigger.py` (hps_io packets,
right sticks kept), `sim/tb_pedal.v`, `tools/test_mister_integration.py`.

## Not established

- Nothing here has run on MiSTer.
- Analog accelerator and trigger delivery depend on Main_MiSTer sending them, which only
  hardware can show. The core side is tested with the real JTFRAME input modules and the
  patched hps_io.
- Scream pitch and level rest on two assumptions listed in `docs/ANALOG.md`.
