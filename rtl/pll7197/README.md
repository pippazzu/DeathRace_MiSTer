# jtframe_pll7197

Copied from JTFRAME's pll7159 with only the output frequencies changed, in pll_0002.v.
115.151515 MHz is 50 MHz x 76 / 33, integer mode like every other JTFRAME PLL. Divided by 8
it gives a 14.393939 MHz crystal, 0.02% above the 14.391 MHz drawn. The IP parameters
stored in pll.qip still describe pll7159: Quartus does not use them to synthesize, but
do not regenerate this PLL from the IP editor without re-entering these frequencies.

Phase shifts. Cyclone V shifts in steps of 1/8 of the VCO period. Quartus puts the VCO at
50 MHz x 76 / 3 = 1266.67 MHz (outputs divide it by 11, 22, 44, 176), so a step is 98.68 ps.
pll7159 used 20 and 50 steps of its 1260 MHz VCO (1984 and 4960 ps). This copy keeps 20 and
50 steps: 1974 ps on outclk_1 and 4934 ps on outclk_5 (the SDRAM clock). The first build kept
4960 ps and the fitter rejected it as illegal.
