"""Test generated OSD allocation and real JTFRAME input routing into game RTL."""
from pathlib import Path
import re, subprocess
root=Path(__file__).resolve().parents[1]
frame=root/'jtcores/modules/jtframe/hdl'
cfg=bytes.fromhex((root/'jtcores/cores/deathrac/mister/cfgstr.hex').read_text()).split(b'\0')[0].decode()
assert cfg.startswith('DeathRace;;')
owners={}
for item in cfg.split(';'):
    m=re.search(r'([Oo])([0-9A-V]{1,2}),([^,]+)',item)
    if not m: continue
    bits=[int(c,32)+(32 if m[1]=='o' else 0) for c in m[2]]
    for bit in range(bits[0],bits[-1]+1):
        assert bit not in owners,(bit,owners.get(bit),m[3])
        owners[bit]=m[3]
assert [owners[i] for i in (20,21,22,23,24,25,26)]==['Game time']*2+['Shifter']+['Soundboard tone']*2+['Accelerator axis']*2
assert owners[27]=='Video output'
assert 'OR,Video output,As MRA,Other (15kHz/Native);' in cfg
assert 'J1,Accelerate,Drive,Reverse,Start,Coin,Pause;' in cfg
assert 'v,5;' in cfg
qsf=(root/'jtcores/cores/deathrac/mister/DeathRace.qsf').read_text()
assert 'JTFRAME_OSD_NOLOGO' in qsf
print('PASS generated menu: no bit collisions, button labels, new identity, logo disabled',flush=True)

# Tie every physical input to a known value, then override controls under test.
src=(frame/'keyboard/jtframe_inputs.v').read_text().split(');')[0]
src=re.sub(r'//[^\n]*','',src)
conn={}
for decl in re.finditer(r'\binput\s+(.*?)(?=\binput\b|\boutput\b|$)',src,re.S):
    names=re.sub(r'\[[^]]+\]|\bsigned\b','',decl[1])
    for name in re.findall(r'\b[a-zA-Z_]\w*\b',names):conn[name]="'0"
conn.update(rst='reset',clk='clk',board_joy1='raw1',board_joy2='raw2',
    game_joy1='joy1',game_joy2='joy2',game_coin='coin',game_start='start',
    dial_x='dx',dial_y='dy',key_coin='keycoin',key_start='keystart',key_joy1='keyjoy',
    lhbl='hb',lvbl='vb',vs='vb',game_pause='paused')
bench='''`timescale 1ns/1ps
module tb_integration;
reg clk=0,reset=1;
always #5 clk=~clk;
reg [15:0] raw1=0,raw2=0;
reg [31:0] status=0;
reg [3:0] keycoin=0,keystart=0;
reg [9:0] keyjoy=0;
reg hb=0,vb=0;
reg [15:0] ana_l1=0,ana_l2=0,ana_r1=0,ana_r2=0,trig1=0,trig2=0;
wire paused;
integer moves=0, divided_moves=0;
reg [1:0] previous_dx,previous_steer;
wire [9:0] joy1,joy2;
wire [3:0] coin,start;
wire [1:0] dx,dy;
wire [12:0] arx,ary;
wire flip=0;
'''
bench+='jtframe_inputs #(.BUTTONS(3)) inputs('+','.join(f'.{k}({v})' for k,v in conn.items())+');\n'
bench+='''
deathrac_game game(.clk(clk),.rst(reset),.status(status),.coin(coin),.cab_1p(start),
 .joystick1(joy1[6:0]),.joystick2(joy2[6:0]),.joyana_l1(ana_l1),.joyana_l2(ana_l2),.joyana_r1(ana_r1),.joyana_r2(ana_r2),.joyana_r3(trig1),.joyana_r4(trig2),.field(),.dial_x(dx),.dial_y(dy),.ioctl_rom(1'b0),.ioctl_wr(1'b0),.ioctl_addr(26'd0),.ioctl_dout(8'd0));
jtframe_dip display(.clk(clk),.status({32'd0,status}),.game_pause(1'b1),
 .vertical(1'b0),.dipflip_xor(1'b0),.osd_shown(1'b0),.game_test(1'b1),
 .dip_flip(flip),.hdmi_arx(arx),.hdmi_ary(ary));
integer tone,mode,aspect;
initial begin
 // Quartus powers these unreset framework counters up at zero. Icarus
 // otherwise leaves them X, including the idle mouse/spinner pulse source.
 inputs.u_dial.cnt1=0;inputs.u_dial.cnt2=0;
 inputs.u_dial.u_dial_mouse_x.mouse_cnt=0;
 inputs.u_dial.u_dial_mouse_y.mouse_cnt=0;
 inputs.u_dial.u_dial_mouse_x.mouse_sel=0;
 inputs.u_dial.u_dial_mouse_y.mouse_sel=0;
 #100;reset=0;#200;
 if(coin!==15 || start!==15 || joy1!==1023)$fatal(1,"idle controls invalid");
 raw1=16'h100;#200;if(game.credit.coin_btn!==1)$fatal(1,"coin button lost");
 raw1=16'h80;#200;if(game.credit.start_btn!==1)$fatal(1,"start button lost");
 raw1=16'h10;#200;if(game.gas1!==2'b10)$fatal(1,"accelerator lost");
 raw1=0;#200;if(game.gas1!==0)$fatal(1,"accelerator release lost");
 raw1=16'h40;#200;if(game.gear1!==1)$fatal(1,"reverse button lost");
 raw1=0;#200;if(game.gear1!==1)$fatal(1,"reverse did not latch");
 raw1=16'h20;#200;if(game.gear1!==0)$fatal(1,"drive button lost");
 raw1=0;status[22]=1;#200;raw1=16'h20;#200;if(game.gear1!==1)$fatal(1,"drive toggle lost");
 raw1=0;status[22]=0;#200;
 raw1=0;
 raw2=16'h150;#200;
 if(game.gas2!==2'b10 || game.gear2!==1 || coin[1]!==0)$fatal(1,"player 2 controls lost");
 raw2=0;#200;
 keycoin=1;keystart=1;keyjoy=16;#200;
 if(game.credit.coin_btn!==1 || game.credit.start_btn!==1 || game.gas1!==2'b10)$fatal(1,"keyboard controls lost");
 keycoin=0;keystart=0;keyjoy=0;#200;
 // Framework dial emulation needs frame and line strobes to consume input.
 raw1=1;vb=1;#200;vb=0;previous_dx=dx;previous_steer=game.steer1;
 repeat(8) begin
  hb=1;#200;hb=0;#200;
  if(dx!=previous_dx)moves=moves+1;previous_dx=dx;
  if(game.steer1!=previous_steer)divided_moves=divided_moves+1;previous_steer=game.steer1;
 end
 if(moves==0) begin
  $display("steer joy=%h dx=%b count=%h pulse=%b inc=%b sel=%b lines=%h",joy1,dx,inputs.u_dial.cnt1,inputs.u_dial.up_1p,inputs.u_dial.inc_1p,inputs.u_dial.sel,inputs.u_dial.line_cnt);
  $fatal(1,"steering did not reach quadrature output");
 end
 if(divided_moves!=moves/3)$fatal(1,"steering divider input=%0d output=%0d",moves,divided_moves);
 raw1=0;
 // Analog accelerator through the real game wrapper, both players, every axis mode.
 ana_r1=16'h8000;#200;if(game.gas1!==2'b10 || game.gas2!==0)$fatal(1,"right stick P1 lost");
 ana_r1=0;#200;if(game.gas1!==0)$fatal(1,"right stick P1 release");
 ana_r2=16'h8000;#200;if(game.gas2!==2'b10 || game.gas1!==0)$fatal(1,"right stick P2 lost");
 ana_r2=0;#200;
 status[26:25]=1;ana_l1=16'h8000;#200;if(game.gas1!==2'b10)$fatal(1,"left stick mode lost");
 ana_l1=0;#200;
 status[26:25]=2;ana_r1=16'h7F00;#200;if(game.gas1!==0)$fatal(1,"pedal rest not released");
 ana_r1=16'h8000;#200;if(game.gas1!==2'b10)$fatal(1,"pedal floor lost");
 status[26:25]=0;ana_r1=0;ana_r2=0;#200;
 // Right triggers {RT, LT}: each player's own, RT only, in stick and pedal modes.
 trig1=16'hFF00;#200;if(game.gas1!==2'b10 || game.gas2!==0)$fatal(1,"P1 right trigger lost");
 trig1=16'h00FF;#200;if(game.gas1!==0)$fatal(1,"P1 left trigger took the pedal");
 trig1=0;trig2=16'hFF00;#200;if(game.gas2!==2'b10 || game.gas1!==0)$fatal(1,"P2 right trigger lost");
 trig2=0;status[26:25]=3;ana_l1=16'h7F00;trig1=16'hFF00;#200;if(game.gas1!==2'b10)$fatal(1,"trigger lost in pedal mode");
 trig1=0;#200;if(game.gas1!==0)$fatal(1,"trigger release in pedal mode");
 status[26:25]=0;ana_l1=0;#200;
 for(aspect=0;aspect<4;aspect=aspect+1)
 for(mode=0;mode<2;mode=mode+1)
 for(tone=0;tone<3;tone=tone+1) begin
  status=0;status[17:16]=aspect;status[22]=mode;status[24:23]=tone;#200;
  if(game.game.tone!==tone[1:0])$fatal(1,"tone decode incorrect");
  if(game.shifter1.separate!==!mode[0])$fatal(1,"gear mode decode incorrect");
  if(aspect==0 && (arx!=4 || ary!=3))$fatal(1,"game option changed aspect ratio");
  if(aspect!=0 && (arx!=aspect-1 || ary!=0))$fatal(1,"aspect decode changed");
  raw1=16'h110;#200;
  if(game.gas1!==2'b10 || game.credit.coin_btn!==1)$fatal(1,"options broke controls");
  raw1=0;#200;
 end
 // The video selector defaults to interlaced and retains an exact native bypass.
 force game.native_ce=1'b1;
 force game.native_ce2=1'b1;
 force game.native_vb=1'b1;
 force game.native_hb=1'b0;
 force game.native_hs=1'b1;
 force game.native_vs=1'b0;
 force game.native_mono=8'd136;
 status[27]=1;
 repeat(3) @(negedge clk);
 if(game.native_mode!==1 || game.field!==0 || game.red!==136 || game.HS!==1 || game.VS!==0 || game.LHBL!==1 || game.LVBL!==0)
  $fatal(1,"native video bypass lost");
 status[27]=0;
 repeat(3) @(negedge clk);
 if(game.native_mode!==0 || game.red!==game.il_mono || game.HS!==game.il_hs || game.VS!==game.il_vs || game.pxl_cen!==game.il_ce || game.field!==game.il_field)
  $fatal(1,"interlaced video selection lost");
 release game.native_ce;release game.native_ce2;release game.native_vb;
 release game.native_hb;release game.native_hs;release game.native_vs;release game.native_mono;
 // Speakers: mixed (saturating) on both channels by default, one per player on bit 29.
 force game.amp1=16'sd1000;force game.amp2=-16'sd300;#20;
 if(game.snd_left!==16'sd700 || game.snd_right!==16'sd700) $fatal(1,"mixed speakers lost");
 force game.amp1=16'sd30000;force game.amp2=16'sd10000;#20;
 if(game.snd_left!==16'sh7fff || game.snd_right!==16'sh7fff) $fatal(1,"mix does not saturate high");
 force game.amp1=-16'sd30000;force game.amp2=-16'sd10000;#20;
 if(game.snd_left!==-16'sh8000 || game.snd_right!==-16'sh8000) $fatal(1,"mix does not saturate low");
 status[29]=1;force game.amp1=16'sd1000;force game.amp2=-16'sd300;#20;
 if(game.snd_left!==16'sd1000 || game.snd_right!==-16'sd300) $fatal(1,"one speaker per player lost");
 status[29]=0;release game.amp1;release game.amp2;
 $display("PASS real JTFRAME controls + game wrapper + aspect ratio, 24 option combinations, interlaced/native output selection, speakers mixed/per player");$finish;
end
endmodule
'''
(root/'build/tb_integration.v').write_text(bench)
# Recursively select actual framework modules, avoiding unrelated CPU cores.
library={}
for f in frame.rglob('*.v'):
    for module in re.findall(r'^module\s+(\w+)',f.read_text(errors='replace'),re.M):library[module]=f
selected=set();queue=['jtframe_inputs','jtframe_dip']
while queue:
    f=library[queue.pop()]
    if f in selected:continue
    selected.add(f)
    queue += [m for m in re.findall(r'^\s*(jt\w+)\s+(?:#|\w+\s*\()',f.read_text(),re.M) if m in library]
args=['C:/iverilog/bin/iverilog.exe','-g2012','-Irtl','-I'+str(frame/'inc'),
 '-DMISTER','-DJTFRAME_STEREO','-DJTFRAME_BUTTONS=3','-DJTFRAME_COLORW=8','-DJTFRAME_DIALEMU_LEFT=0','-DJTFRAME_INTERLACED',
 '-s','tb_integration','-o','build/integration.vvp','build/tb_integration.v',
 *map(str,selected),*map(str,(root/'jtcores/modules').rglob('jt4701_dialemu.v')),*map(str,(root/'rtl').glob('*.v'))]
subprocess.run(args,cwd=root,check=True)
subprocess.run(['C:/iverilog/bin/vvp.exe','build/integration.vvp'],cwd=root,check=True)
