"""Stage the JTFRAME core and compile it with the Quartus version JTCORES pins.

Usage: python tools/build_quartus.py [--quartus DIR]
Default is C:/intelFPGA_lite/20.1 (Quartus Prime Lite 20.1.1). Prints
resource use and per-clock setup/hold slack; the log is build/jtframe-quartus.log.
"""
import argparse, re, subprocess, sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
ap=argparse.ArgumentParser()
ap.add_argument('--quartus',default='C:/intelFPGA_lite/20.1')
a=ap.parse_args()
qsh=Path(a.quartus)/'quartus/bin64/quartus_sh.exe'
if not qsh.exists(): sys.exit(f'quartus_sh not found at {qsh}')
subprocess.run([sys.executable,str(root/'tools/prepare_jtframe.py')],check=True,stdout=subprocess.DEVNULL)
proj=root/'jtcores/cores/deathrac/mister'
# Compilation databases are version specific; this is always a full compile.
import shutil
for d in ('db','incremental_db'): shutil.rmtree(proj/d,ignore_errors=True)
log=root/'build/jtframe-quartus.log'
with log.open('w') as f:
    r=subprocess.run([str(qsh),'--flow','compile','DeathRace'],cwd=proj,stdout=f,stderr=subprocess.STDOUT)
text=log.read_text(errors='ignore')
print(re.search(r'Version [^\n]+',text).group(0) if 'Version' in text else '')
for line in text.splitlines():
    if 'Fatal' in line or line.startswith('Error ('): print(line)
out=proj/'output_files'
if r.returncode: sys.exit(f'compile failed ({r.returncode}); see {log}')
for line in (out/'DeathRace.fit.summary').read_text().splitlines():
    if re.match(r'(Logic utilization|Total block memory|Total DSP)',line): print(line)
sta=(out/'DeathRace.sta.rpt').read_text(errors='ignore')
for m in re.finditer(r'Worst-case (\w[\w ]*?) slack is (-?[\d.]+)',sta): print(f'{m.group(1):22} {m.group(2)}')
rbf=out/'DeathRace.rbf'
print(rbf, rbf.stat().st_size if rbf.exists() else 'missing')
