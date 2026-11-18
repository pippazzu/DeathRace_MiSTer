# Death Race / Derby core timing exceptions. Added to files.qip by tools/prepare_jtframe.py.
#
# game_dr selects Death Race or Derby. It is written once, by the first byte of the MRA
# download, which is also the write that makes JTFRAME assert the game reset
# (jtframe_board.v rom_rst). The reset stays on until the download ends, so game_dr
# never changes while the game runs and no path from it needs to settle in one clock.
set_false_path -from [get_registers {*|deathrac_game:u_game|game_dr}]
