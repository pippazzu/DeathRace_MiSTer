#!/usr/bin/env python3
"""Let MiSTer's arcade_video pass an interlaced VSync.

MiSTer's sys/arcade_video.v latches VSync only on an HSync rising edge:
    if(~HS & hs_fix) VS <= vs_fix;
That snaps the second field's half-line VSync (rtl/deathrac_interlace.v) onto a
whole line, so a TV sees two non-interlaced fields of 262 and 263 lines showing
different rows: no interlace, uneven lines. This copies arcade_video.v, makes
VSync follow the pixel strobe instead, and points the staged sys qip at the
copy. JTFRAME and the MiSTer sys tree are not edited. The edit must match
exactly once, so an updated framework stops the build instead of being patched
wrongly.

Run after tools/jtframe_trigger.py, which writes OUT_DIR/sys_trig_files.qip.
Usage: python tools/jtframe_interlace.py JTFRAME_DIR OUT_DIR
"""
# SPDX-License-Identifier: GPL-3.0-or-later
from pathlib import Path
import re
import sys

OLD = "\t\tif(~HS & hs_fix) VS <= vs_fix;\n"
NEW = ("\t\t// Death Race: VSync follows the pixel strobe so a half-line (interlaced)\n"
       "\t\t// VSync survives (tools/jtframe_interlace.py).\n"
       "\t\tVS <= vs_fix;\n")

def main():
    jtframe, out = Path(sys.argv[1]).resolve(), Path(sys.argv[2])
    sysdir = jtframe / "target/mister/hdl/sys"
    text = (sysdir / "arcade_video.v").read_text().replace("\r\n", "\n")
    if text.count(OLD) != 1:
        raise SystemExit("arcade_video.v: VSync latch not found exactly once")
    patched = out / "arcade_video_il.v"
    patched.write_text(text.replace(OLD, NEW), newline="\n")
    qip_path = out / "sys_trig_files.qip"
    qip = qip_path.read_text()
    entry = re.compile(r'\[file join "[^"]*" arcade_video\.v \]')
    if len(entry.findall(qip)) != 1:
        raise SystemExit("sys_trig_files.qip: arcade_video.v entry not found")
    qip = entry.sub(f'"{patched.resolve().as_posix()}"', qip)
    qip_path.write_text(qip, newline="\n")
    print("interlaced VSync through arcade_video:", patched)

if __name__ == "__main__":
    main()
