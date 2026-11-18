"""Stage the traced game as a JTFRAME core; generate Quartus files on Windows."""
from pathlib import Path
import os, subprocess, shutil, sys
root=Path(__file__).resolve().parents[1]
jt=root/'jtcores'; frame=jt/'modules/jtframe'; core=jt/'cores/deathrac'
for sub in ['hdl','cfg','mister']: (core/sub).mkdir(parents=True,exist_ok=True)
for name in ['deathrac.sdc','ttl_cells.v','deathrac_netlist.v','deathrac_board.v','deathrac_fpga.v','deathrac_interlace.v','deathrac_audio.v','deathrac_scream.v','deathrac_audio_coef.vh','deathrac_game.v','deathrac_controls.v']:
    shutil.copy2(root/'rtl'/name,core/'hdl'/name)
# No ROM data goes near the Quartus project: the PROMs arrive from the MRA at load time.
# The roms/*.hex dumps are for the Icarus benches only and are read under translate_off.
shutil.rmtree(core/'mister/roms',ignore_errors=True)
shutil.copytree(root/'rtl/pll7197',core/'hdl/pll7197',dirs_exist_ok=True)
for name in ['macros.def','files.yaml']: shutil.copy2(root/'jtframe'/name,core/'cfg'/name)
env=os.environ.copy()
env['JTBIN']=(jt/'release').as_posix()
env.update(JTROOT=jt.as_posix(),JTFRAME=frame.as_posix(),CORES=(jt/'cores').as_posix(),MODULES=(jt/'modules').as_posix())
def run(*args):
    p=subprocess.run([str(root/'tools/jtframe.exe'),*args],env=env,cwd=core/'mister',capture_output=True,text=True)
    if p.returncode: raise RuntimeError(p.stdout+p.stderr)
    return p.stdout
for ext in ['qpf','qsf']:
    run('parse','deathrac',str(frame/f'target/mister/mister.{ext}'),'--target=mister','--output',str(core/f'mister/DeathRace.{ext}'))
# The upstream qpf template retains a literal shell variable in its revision.
# Use the standalone project's name explicitly; do not expose a jt prefix.
(core/'mister/DeathRace.qpf').write_text('QUARTUS_VERSION = "20.1"\nPROJECT_REVISION = "DeathRace"\n')
qsf=core/'mister/DeathRace.qsf'
with qsf.open('a') as f: f.write('\n'+run('cfgstr','deathrac','--target=mister','--output','quartus')+'\nset_global_assignment -name NUM_PARALLEL_PROCESSORS 4\nset_global_assignment -name SEED '+os.environ.get('DEATHRAC_SEED','1')+'\n')
# Seed 1: on 18 November 2026, with JTFRAME_RELEASE, setup +0.205 ns (seed 6 missed by 0.045 ns).
# Before that, seed 6: on 18 November 2026, with the Speakers option, setup +0.126 ns; without it +0.386 ns. With the audio
# scalar operands registered (seeds 1-8 had missed
# by 0.28-0.75 ns in that operand select). Before that, seed 6 on 16 November 2026, with the start-position fix, +0.259 ns.
# Before that, seed 4: on 12 November 2026, with the interlace and enemy fixes, seeds 1-3 missed setup
# and seed 4 gave +0.201 ns. Before that, seed 1: on 10 November 2026, with the scream fix, seed 3 missed setup by 0.28 ns in the
# audio mixer and seed 1 passed. Earlier, on 5 November 2026, with A12 and the image PROMs B8-E8 read through a register,
# seeds 1-4 all passed: setup +0.214, +0.052, +0.592, +0.239 ns at 115.15 MHz.
run('cfgstr','deathrac','--target=mister','--output','cfgstr')  # writes mister/cfgstr.hex
run('files','syn','deathrac','--target=mister')
qip=core/'mister/files.qip'
qip.write_text(qip.read_text().replace('\\','/')
    +f'set_global_assignment -library "pll" -name QIP_FILE {(core/"hdl/pll7197/pll.qip").as_posix()}\n'
    +f'set_global_assignment -name SDC_FILE {(core/"hdl/deathrac.sdc").as_posix()}\n')
# Analog triggers: patched copies of hps_io, jtframe_mister, the emu top and the game
# instance, made from this JTFRAME tree (tools/jtframe_trigger.py). JTFRAME is not edited.
p=subprocess.run([sys.executable,str(root/'tools/jtframe_trigger.py'),str(core/'mister'),str(frame),str(core/'hdl/jtframe_trig')],capture_output=True,text=True)
if p.returncode: raise RuntimeError(p.stdout+p.stderr)
# Interlaced output: a patched arcade_video copy that keeps the half-line VSync
# (tools/jtframe_interlace.py). Must run after jtframe_trigger.py writes the sys qip.
p=subprocess.run([sys.executable,str(root/'tools/jtframe_interlace.py'),str(frame),str(core/'hdl/jtframe_trig')],capture_output=True,text=True)
if p.returncode: raise RuntimeError(p.stdout+p.stderr)
for src in [frame/'bin/font0.hex',* (frame/'hdl/sound').glob('*.hex'),frame/'hdl/video/logodata.hex',frame/'hdl/video/logomap.hex']:
    if src.exists(): shutil.copy2(src,core/'mister'/src.name)
print(core/'mister/DeathRace.qpf')
