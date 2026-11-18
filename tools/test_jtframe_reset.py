from pathlib import Path
import subprocess,os
root=Path(__file__).resolve().parents[1];os.chdir(root)
sources=['rtl/ttl_cells.v','rtl/deathrac_netlist.v','rtl/deathrac_board.v','rtl/deathrac_fpga.v','rtl/deathrac_audio.v','rtl/deathrac_scream.v','jtcores/modules/jtframe/hdl/jtframe_reset.v','sim/tb_jtframe_reset.v']
subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-Irtl','-s','tb_jtframe_reset','-o','build/reset-test.vvp',*sources],check=True)
subprocess.run(['C:/iverilog/bin/vvp.exe','build/reset-test.vvp'],check=True)
