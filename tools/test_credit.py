"""Coin and Start on the whole traced board, through Verilator (Icarus needs 100 s a frame).

Builds sim/vl_credit.v + sim/vl_credit.cpp and plays pad-like press sequences at several
phases of the board's 67 ms credit clock, with deathrac_credit in the path as in deathrac_game.
Each must end the same way at every phase. Needs MSYS2 ucrt64 verilator and g++, and
build/rom_dr.hex (tools/make_mra.py). Usage: python tools/test_credit.py
"""
import os, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
root=Path(__file__).resolve().parents[1]
out=root/'build/vl_credit_test'; out.mkdir(parents=True,exist_ok=True)
ucrt=Path('C:/msys64/ucrt64'); inc=ucrt/'share/verilator/include'
env=os.environ.copy()
env['PATH']=f"{ucrt/'bin'};C:/msys64/usr/bin;"+env['PATH']
env['VERILATOR_ROOT']=(ucrt/'share/verilator').as_posix()
env['TMP']=env['TEMP']=env['TMPDIR']=str(root/'build')   # g++ temporaries, not C:\Windows
def run(*cmd,**kw): return subprocess.run([str(c) for c in cmd],env=env,check=True,**kw)
for old in list(out.glob('Vvl_credit*.cpp'))+list(out.glob('Vvl_credit*.h')): old.unlink()
run(ucrt/'bin/verilator_bin.exe','--cc','-Wno-fatal','-Wno-lint','-Wno-style',
    '--top-module','vl_credit','-Mdir',out.as_posix(),*[(root/f).as_posix() for f in
    ['rtl/ttl_cells.v','rtl/deathrac_netlist.v','rtl/deathrac_board.v','rtl/deathrac_controls.v','sim/vl_credit.v']],
    stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,cwd=root)
model=sorted(p.name for p in out.glob('Vvl_credit*.cpp'))
(out/'all.cpp').write_text(''.join(f'#include "{n}"\n' for n in model))
exe=out/'vl_credit.exe'
run(ucrt/'bin/g++.exe','-O2','-w','-pipe','-static','-faligned-new','-I',out,'-I',inc,'-I',inc/'vltstd',
    out/'all.cpp',root/'sim/vl_credit.cpp',inc/'verilated.cpp',inc/'verilated_threads.cpp','-o',exe,cwd=out)
# script, expected (EGME, E2PL, ESGC) with the conditioner.
cases=[
 ('c100,w1000',                         (1,0,0),'coin alone: one credit, waits for Start'),
 ('c100,s100,w1200',                    (1,0,1),'Start straight after the coin'),
 ('b100,w1200',                         (1,0,1),'coin and Start together'),
 ('c100,s400,w900',                     (1,0,1),'Start held from the coin on'),
 ('c600,w300,s100,w900',                (1,0,1),'coin button held long'),
 ('c80,w60,c80,w60,s80,w1500',          (1,1,1),'two quick coins and Start: two players'),
 ('c80,w60,c80,w60,c80,w60,s80,w1800',  (1,1,1),'a third coin changes nothing'),
 ('c100,w300,s100,w1500,c100,w900',     (1,0,1),'coin during play: game carries on'),
 ('s100,w700,c100,w900',                (1,0,0),'Start with no credit is not kept'),
]
def play(job):
    script,phase=job
    r=subprocess.run([str(exe),script,str(1500+phase),'1','build/rom_dr.hex','1'],cwd=root,capture_output=True,text=True)
    line=[l for l in r.stdout.splitlines() if l.startswith('RESULT')][0].split()
    return tuple(int(f.split('=')[1]) for f in line[1:4])
phases=[0,17,34,51]
jobs=[(c[0],p) for c in cases for p in phases]
with ThreadPoolExecutor(os.cpu_count()) as pool: got=dict(zip(jobs,pool.map(play,jobs)))
bad=0
for script,want,text in cases:
    res=[got[(script,p)] for p in phases]
    ok=all(r==want for r in res); bad+=not ok
    print(('PASS ' if ok else 'FAIL ')+text+('' if ok else f': {script} wanted {want} got {res}'),flush=True)
sys.exit(bad)
