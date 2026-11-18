"""Run Icarus from a stable workspace temp directory on Windows."""
import os, subprocess, sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
os.chdir(root)
env=os.environ.copy(); env['TMP']=env['TEMP']=str(root/'build')
top=sys.argv[1] if len(sys.argv)>1 else 'tb_board'
variant=sys.argv[2] if len(sys.argv)>2 else '1'
args=sys.argv[3:]
exe=str(root/f'build/{top}-{variant}.vvp')
sources=['rtl/ttl_cells.v','rtl/deathrac_netlist.v','rtl/deathrac_board.v',f'sim/{top}.v']
cmd=['C:/iverilog/bin/iverilog.exe','-g2012','-I','rtl','-s',top,'-P',f'{top}.FPGA={variant}','-o',exe,*sources]
r=subprocess.run(cmd,env=env,capture_output=True,text=True)
print(r.stdout+r.stderr,flush=True)
if r.returncode: raise SystemExit(r.returncode)
r=subprocess.run(['C:/iverilog/bin/vvp.exe',exe,*args],env=env)
raise SystemExit(r.returncode)
