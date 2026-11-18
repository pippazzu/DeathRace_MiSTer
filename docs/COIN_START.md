# Coin and Start on a pad

10 November 2026. The pad map was right (Coin = Select, Start = Start, JTFRAME bits 8
and 7 with three action buttons). What looked random is sheet 2 itself, which expects a
coin switch and a player who presses Start some time later. Measured on the whole traced
board (`tools/test_credit.py`, Verilator, 115 MHz cell models):

- The credit chain K16/K15 runs on 1ECK0, one falling edge every four frames (67 ms).
  EGME comes up 67 to 133 ms after the coin.
- J15.a (Start latch) is held clear until EGME, so Start before that is lost.
- J15.a has K=ECDG. Start held while a coin is going through gives J=K=1 at 7 MHz: the
  latch toggles and lands either way. Coin and Start pressed together started the game
  at two of four phases of 1ECK0.
- A coin after Start clears ESGB: the game stops, the timer reloads 99 and the board
  waits for Start. One more coin at that point sets E2PL: a two-player game.
- A second coin while waiting for Start is the two-player coin, as drawn.

`deathrac_credit` (rtl/deathrac_controls.v, used in deathrac_game.v) sits between the buttons
and ECDA/ESGA. The board is not changed. It reads EGME and ESGC back.

- Each coin press is queued and played as 100 ms on, 250 ms off; two per game at most.
- Start is remembered if a credit is there or on its way, and held, once the coins are
  through and EGME is up, until ESGC answers.
- Coin presses from the Start press to game over are dropped: a coin no longer stops
  the game.
- 500 ms of quiet after reset and after game over, when STAA can still hold STGO.

So: Coin, Start is one player. Coin, Coin, Start is two players. Order and speed of the
presses within that do not matter. Start before any coin does nothing.

Tests: `sim/tb_credit.v` (the module alone, Icarus), `tools/test_credit.py` (whole board,
nine press sequences at four clock phases), `tools/test_mister_integration.py` (JTFRAME
routing into the conditioner).
