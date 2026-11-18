#!/usr/bin/env python3
"""Analog triggers for the MiSTer build, the Monaco GP way.

MiSTer Main sends each pad's analog triggers as UIO_ATRIG 0x46: the player index, then
one word {RT, LT}. JTFRAME's hps_io does not receive it. The Monaco GP MiSTer
core (scripts/mister_overlay.py), whose R trigger works on real hardware, compiles a patched copy of hps_io that puts the triggers on a right-stick
output that already reaches the game. Done the same here, for two players:

  player 1 {RT, LT} -> joystick_r_analog_2 -> the game's joyana_r3
  player 2 RT      -> joystick_r_analog_3[15:8] -> the game's joyana_r4
                      (player 2's LT is not used by the game; [7:0] stays 0)

Death Race has two players, so the right sticks of players 3 and 4 are dropped. Nothing
else changes: no new ports, no patched jtframe_mister, emu top or game instance (the
earlier version of this script added those, and R never worked on hardware).

JTFRAME itself is not edited. Each edit must match exactly once, so an updated JTFRAME
stops the build instead of being patched wrongly.

Usage: python tools/jtframe_trigger.py PROJECT_DIR JTFRAME_DIR OUT_DIR
Writes the patched hps_io into OUT_DIR and points PROJECT_DIR/files.qip at it.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
from pathlib import Path
import re
import sys

def edit(text, edits, what):
    text = text.replace("\r\n", "\n")
    for old, new in edits:
        if text.count(old) != 1:
            raise SystemExit(f"{what}: expected one match of {old!r}")
        text = text.replace(old, new)
    return text

def patch_hps_io(text):
    """hps_io with the 0x46 receiver on right sticks 3 and 4."""
    return edit(text, [
        ("\toutput reg [15:0] joystick_r_analog_2,\n",
         "\toutput reg [15:0] joystick_r_analog_2 = 0, // player 1's {RT, LT} (0x46), 0..255, released at power-up\n"),
        ("\toutput reg [15:0] joystick_r_analog_3,\n",
         "\toutput reg [15:0] joystick_r_analog_3 = 0, // {player 2's RT (0x46), 0}\n"),
        ("\t\t\t\t\t\t\t\t\t\t 2: joystick_r_analog_2 <= io_din;\n", ""),
        ("\t\t\t\t\t\t\t\t\t\t 3: joystick_r_analog_3 <= io_din;\n", ""),
        ("reg  [3:0] stick_idx;\n", "reg  [3:0] stick_idx;\nreg  [7:0] atrig_idx;\n"),
        ("\t\t\t\t// notify image selection\n",
         "\t\t\t\t// 0x46: player, {RT, LT}\n"
         "\t\t\t\t'h46: case(byte_cnt)\n"
         "\t\t\t\t\t\t\t1: atrig_idx <= io_din[7:0];\n"
         "\t\t\t\t\t\t\t2: begin\n"
         "\t\t\t\t\t\t\t\tcase(atrig_idx)\n"
         "\t\t\t\t\t\t\t\t\t0: joystick_r_analog_2 <= io_din;\n"
         "\t\t\t\t\t\t\t\t\t1: joystick_r_analog_3[15:8] <= io_din[15:8];\n"
         "\t\t\t\t\t\t\t\t\tdefault: ;\n"
         "\t\t\t\t\t\t\t\tendcase\n"
         "\t\t\t\t\t\t\tend\n"
         "\t\t\t\t\t\tendcase\n\n"
         "\t\t\t\t// notify image selection\n"),
    ], "hps_io.sv")

def write(path, text):
    path.write_text(text, newline="\n")
    return path.resolve().as_posix()

def main():
    project, jtframe, out = Path(sys.argv[1]), Path(sys.argv[2]).resolve(), Path(sys.argv[3])
    out.mkdir(parents=True, exist_ok=True)
    for stale in ("deathrac_game_instance.v", "jtframe_emu_trig.sv", "jtframe_mister_trig.sv"):
        (out / stale).unlink(missing_ok=True)
    sysdir = jtframe / "target/mister/hdl/sys"
    hps = write(out / "hps_io_trig.sv", patch_hps_io((sysdir / "hps_io.sv").read_text()))
    # sys.qip with hps_io.sv swapped for the patched copy, paths made absolute.
    qip = (sysdir / "sys.qip").read_text()
    entry = re.compile(r"\[file join \$::quartus\(qip_path\) hps_io\.sv \]")
    if len(entry.findall(qip)) != 1:
        raise SystemExit("sys.qip: hps_io.sv entry not found")
    qip = entry.sub("@HPS@", qip).replace("$::quartus(qip_path)", f'"{sysdir.as_posix()}"')
    qip = qip.replace("@HPS@", f'"{hps}"')
    sys_files = write(out / "sys_trig_files.qip", qip)
    pinned = (jtframe / "target/mister/syn/sys.qip").read_text()
    if pinned.count('"../hdl/sys/sys.qip"') != 1:
        raise SystemExit("syn/sys.qip has changed")
    sys_qip = write(out / "sys_trig.qip", pinned.replace('[file join $::quartus(qip_path) "../hdl/sys/sys.qip"]', f'"{sys_files}"'))
    files = project / "files.qip"
    text = files.read_text(encoding="utf-8")
    text, n = re.subn(r"(?m)^(set_global_assignment -name QIP_FILE ).*/target/mister/syn/sys\.qip$", r"\g<1>" + sys_qip, text)
    if n != 1:
        raise SystemExit("files.qip: sys.qip entry not found")
    files.write_text(text, encoding="utf-8", newline="\n")
    print("analog triggers on joyana_r3 (player 1) and joyana_r4 (player 2):", out)

if __name__ == "__main__":
    main()
