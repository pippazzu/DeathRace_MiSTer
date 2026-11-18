"""Discretize the sheet 16/17 sound circuits from their component values.

Each linear section is written as nodal equations (Cm dv/dt = -G v + B u),
given a 10 pF parasitic per node so Cm is invertible, discretized with a
zero-order hold at FS and quantized to Q8.24. Bipolar transistors are a
0.65 V junction plus r_pi with collector current beta*i_b; saturation and
cutoff are applied by clamping the collector node after each step. Two
coefficient variants per switched block select the open-collector state.

Writes rtl/deathrac_audio_coef.vh and prints a parameter summary. Run from the
project root. Assumptions are listed in docs/ANALOG.md.
"""
import numpy as np
from scipy.linalg import expm
from pathlib import Path

FS = 48000
QC = 24                      # coefficient fraction bits
QS = 16                      # state fraction bits (volts)
BETA = 100.0                 # A: 2N3904 current gain, fitted to the recordings
VT = 0.02585
VBE = 0.65
CP = 10e-12                  # parasitic node capacitance (numerical only)
VS = 14.0                    # A: decoupled +15 V rail after 1.0k (stage current ~1 mA)
VOL = 0.1                    # 7407 saturated output, low state

class Block:
    def __init__(s, name, nodes, inputs):
        s.name=name; s.nodes=nodes; s.inputs=inputs
        n=len(nodes); m=len(inputs)
        s.G=np.zeros((n,n)); s.C=np.eye(n)*CP; s.B=np.zeros((n,m))
        s.clamps={}
    def i(s,a): return s.nodes.index(a)
    def R(s,a,b,r):
        g=1/r
        for x,y in ((a,b),(b,a)):
            if x in s.nodes:
                s.G[s.i(x),s.i(x)]+=g
                if y in s.nodes: s.G[s.i(x),s.i(y)]-=g
                elif y!='gnd': s.B[s.i(x),s.inputs.index(y)]+=g
    def RV(s,a,r,v):         # resistor from node a to a fixed voltage v
        s.G[s.i(a),s.i(a)]+=1/r; s.B[s.i(a),s.inputs.index('one')]+=v/r
    def Cap(s,a,b,c):
        ia=s.i(a); s.C[ia,ia]+=c
        if b!='gnd':
            ib=s.i(b); s.C[ib,ib]+=c; s.C[ia,ib]-=c; s.C[ib,ia]-=c
    def Q(s,b,c,rpi):        # NPN, emitter grounded
        ib,ic,io=s.i(b),s.i(c),s.inputs.index('one')
        s.G[ib,ib]+=1/rpi; s.B[ib,io]+=VBE/rpi
        s.G[ic,ib]+=BETA/rpi; s.B[ic,io]+=BETA*VBE/rpi
    def discretize(s):
        Ac=-np.linalg.solve(s.C,s.G); Bc=np.linalg.solve(s.C,s.B)
        n,m=Bc.shape; M=np.zeros((n+m,n+m)); M[:n,:n]=Ac; M[:n,n:]=Bc
        E=expm(M/FS); return E[:n,:n],E[:n,n:]
    def dc(s,u):
        return np.linalg.solve(s.G,s.B@u)

def rpi_at(ic): return BETA*VT/ic

# Motor transistors are switched: each stage has an "on" and "off" coefficient set,
# chosen per sample from its base voltage, so the first stage can oscillate by itself as
# tools/motor_spice.py shows it does. RPI values are fitted to that nonlinear reference.
RPI_Q6=1000.0; RPI_Q7=4000.0
# A: twin-T capacitor scale per game, fitted to the idle tone in the cabinet recordings:
# Derby 207 Hz, Death Race about 180 Hz. Compensates the switched model as well as tolerance.
TWIN_T=(0.84,0.97)

def motor1(xc_low,on,tt):
    b=Block('motor1',['X','P','Q','T','R','U','B','N'],['one','noise'])
    b.RV('X',10e3,5.0)                       # 7407 pull-up to +5
    if xc_low: b.RV('X',20.0,VOL)            # A: 7407 sink ~20 ohm
    b.R('X','P',10e3); b.Cap('P','gnd',0.2e-6); b.Cap('P','Q',0.2e-6)
    b.Cap('Q','B',2.2e-6)
    b.Cap('Q','T',0.047e-6*tt); b.R('T','gnd',680); b.Cap('T','U',0.047e-6*tt)
    b.R('Q','R',47e3); b.Cap('R','gnd',0.1e-6*tt); b.R('R','U',47e3)
    b.RV('B',2.2e6,VS); b.RV('U',10e3,VS)
    b.R('noise','N',10e3); b.Cap('N','B',330e-12)   # noise collector is 10k
    if on: b.Q('B','U',RPI_Q6)
    b.clamps={'U':(0.15,VS)}; b.out='U'; b.base='B'
    return b

def motor2(xc_low,on):
    b=Block('motor2',['Xn','Yn','XB','B2','C2'],['one','u1'])
    b.R('u1','Xn',100e3); b.Cap('Xn','Yn',0.003e-6); b.R('Yn','XB',100e3)
    b.RV('XB',10e3,15.0)                     # 7407 pull-up to +15
    if xc_low: b.RV('XB',20.0,VOL)
    b.Cap('Xn','B2',0.1e-6); b.R('B2','C2',1e6); b.R('Xn','C2',270e3)
    b.RV('C2',10e3,VS); b.R('C2','gnd',57e3)  # 47k + 10k volume pot
    if on: b.Q('B2','C2',RPI_Q7)
    b.clamps={'C2':(0.15,VS)}; b.out='C2'; b.base='B2'
    return b

def crash():
    b=Block('crash',['D','B3','M','C3'],['one','va'])
    b.R('va','B3',550e3); b.R('va','D',150e3); b.Cap('D','B3',0.1e-6)
    # Crash 1 prints 0.001 here; crash 2 and Death Race C54 print .01.
    b.Cap('B3','M',0.01e-6); b.R('M','gnd',33e3); b.Cap('M','C3',0.01e-6)
    b.RV('C3',10e3,VS)
    b.Q('B3','C3',rpi_at(0.5e-3)); b.clamps={'C3':(0.15,VS)}; b.out='C3'
    return b

# A: cabinet pot settings, undrawn operator adjustments. Chosen 2026-11-05 because
# the sound was too loud and shrieky: 0.20/0.10 put idle at
# -10 dBFS and clipped the amplifier on crashes.
POT_CRASH=0.05; POT_MOTOR=0.06
# R7 tone rheostat fractions selectable from the OSD, in status order.
TONES=(0.15,0.0,0.5); POT_TONE=TONES[0]
# A: cabinet speaker roll-off, NOT on the schematic. Two one-pole sections.
SPK_FC=5000.0
def mixer(mute,tone=POT_TONE):
    b=Block('mixer',['N1','N2','S','S2','I','Tn'],['crash','motor'])
    b.R('crash','N1',22e3); b.Cap('N1','S',0.1e-6)
    b.R('motor','N2',22e3); b.Cap('N2','S',0.1e-6)
    b.R('S','gnd',10e6)                      # A: leakage of the cap-only sum node
    if mute: b.R('S','gnd',20.0)             # EGMC/EHMC 7407 low clamps the sum
    b.Cap('S','S2',0.1e-6); b.R('S2','I',22e3); b.R('I','gnd',47e3)
    b.R('I','gnd',150e3)                     # LM380 input resistance
    # Sheet 17: rheostat 0..100k. 20 ohm represents contact resistance
    # at the minimum stop; there is no extra 1k series resistor drawn.
    b.Cap('I','Tn',0.02e-6); b.R('Tn','gnd',max(20.0,100e3*tone))
    b.clamps={}; b.out='I'
    return b

def q(x,bits): return int(round(x*(1<<bits)))

def blocks():
    """Engine order. Each entry: tag, variants, input names as wired in RTL."""
    # Variant order: M1 game*4 + XC1A low*2 + Q6 on; M2 XC1B low*2 + Q7 on.
    return [('M1',[motor1(x,o,t) for t in TWIN_T for x in (False,True) for o in (False,True)]),
            ('M2',[motor2(x,o) for x in (False,True) for o in (False,True)]),
            ('CR',[crash()]),('MX',[mixer(m,t) for t in TONES for m in (False,True)])]

# Sheet 15 VCO, integrated at TICK_HZ. Voltages Q8.24; dv = (dV*K)>>>32.
# 33 uF as drawn on Death Race C21/C24, used for both games: at speed the Derby recording
# has XC1A near 85 Hz, which its printed 2.2 uF cannot give. The flip-flop input current
# assumed by the first model is left out because the recordings exclude it; see docs/AUDIT.md.
TICK_HZ=2000000; C_T=33e-6; VB_EVERY=64
def vco_params():
    k=lambda g: q(g*(1/TICK_HZ)/C_T,36)
    o=[f'localparam integer TICK_HZ={TICK_HZ}, VB_EVERY={VB_EVERY};',
       f'localparam signed [31:0] V_065={q(0.65,24)}, V_5={q(5.0,24)}, V_TH={q(1.5,24)},',
       f'  V_01={q(0.1,24)}, V_MAX={q(5.65,24)}, V_IDLE={q(0.2,24)};',
       f'localparam signed [31:0] K_SRC={k(1.5/10e3)}, K_68K={k(1/68e3)}, K_DIS={k(1/18.0)};']
    for m1 in (0,1):
        for m0 in (0,1):
            g=[1/20e3]; v=[5/20e3]
            for bit,r in ((m1,10e3),(m0,39e3)):
                if bit: g.append(1/(r+1.2e3)); v.append(5/(r+1.2e3))
                else: g.append(1/r); v.append(VOL/r)
            vt=sum(v)/sum(g); rt=1/sum(g); a=VB_EVERY/TICK_HZ/(rt*33e-6)
            o.append(f'localparam signed [31:0] VB_T{m1}{m0}={q(vt,24)}, VB_A{m1}{m0}={q(a,24)}; // {vt:.3f} V, {rt:.0f} ohm')
    dtc=1/FS/2.2e-6
    o+=[f'localparam signed [31:0] ENV_CH={q(dtc/1.2e3,24)}, ENV_DIS={q(dtc*(1/270e3+1/650e3),24)}, V_144={q(14.4,QS)};',
        f'localparam signed [31:0] VA_K={q(5.5/6.5,24)}, VA_0={q(0.65/6.5,QS)}, V_06={q(0.6,QS)}, V_F={q(15*100/147,QS)};',
        f'localparam signed [31:0] VN_HI={q(13.9,QS)}, VN_LO={q(0.2,QS)}, NOISE_A={q(0.325,24)};',
        f'localparam signed [31:0] K_CRASH={q(POT_CRASH,24)}, K_MOTOR={q(10/57*POT_MOTOR,24)}, ONE={1<<QS};',
        f'localparam signed [31:0] AMP_GAIN=100, AMP_CLIP={q(13.0,QS)}, HP_K={q(2*np.pi*50/FS,24)}, OUT_K={q(32767/13.0,QS)};',
        f'localparam signed [31:0] SPK_K={q(1-np.exp(-2*np.pi*SPK_FC/FS),24)};',
        f'localparam signed [31:0] V_BE={q(VBE,QS)};',
        f'localparam signed [31:0] CL_LO={q(0.15,QS)}, CL_HI={q(VS,QS)};']
    return o

def main():
    rom=[]; out=['// GENERATED by tools/design_audio.py from sheet 15-17 component values.',
         f'// FS={FS} Hz, coefficients Q8.{QC}, states Q{32-QS}.{QS} volts.']
    init=[]; sbase=0; dc_u1=0.0
    for tag,vs in blocks():
        b=vs[0]; n=len(b.nodes); m=len(b.inputs); bases=[]
        for v in vs:
            Ad,Bd=v.discretize(); M=np.hstack([Ad,Bd])
            assert np.abs(M).max()<127,(tag,np.abs(M).max())
            bases.append(len(rom)); rom+=[q(x,QC) for x in M.ravel()]
            print(f'{tag} variant base={bases[-1]} n={n} m={m} |pole|max={np.abs(np.linalg.eigvals(Ad)).max():.6f}')
        u=np.zeros(m)
        if 'one' in b.inputs: u[b.inputs.index('one')]=1.0
        if 'noise' in b.inputs: u[b.inputs.index('noise')]=7.0
        if 'u1' in b.inputs: u[b.inputs.index('u1')]=dc_u1
        # Start the switched stages from their conducting bias point.
        v=(vs[1] if tag in ('M1','M2') else b).dc(u) if 'one' in b.inputs else np.zeros(n)
        for node,(lo,hi) in b.clamps.items(): v[b.nodes.index(node)]=min(max(v[b.nodes.index(node)],lo),hi)
        if tag=='M1': dc_u1=v[b.nodes.index('U')]
        init+=list(v)
        cl=sbase+b.nodes.index(list(b.clamps)[0]) if b.clamps else 31
        out.append(f'// {tag}: {b.nodes} inputs {b.inputs} out {b.out}')
        out.append(f'localparam integer {tag}_N={n}, {tag}_M={m}, {tag}_S={sbase}, {tag}_B0={bases[0]}, '
                   f'{tag}_B1={bases[min(1,len(bases)-1)]}, {tag}_OUT={sbase+b.nodes.index(b.out)}, {tag}_CL={cl};')
        if hasattr(b,'base'): out.append(f'localparam integer {tag}_BN={sbase+b.nodes.index(b.base)};')
        for variant in range(2,len(bases)):
            out.append(f'localparam integer {tag}_B{variant}={bases[variant]};')
        sbase+=n
    out.append(f'localparam integer NSTATE={sbase}, COEF_N={len(rom)};')
    out.append('function automatic signed [31:0] coef(input [10:0] a);\n case(a)')
    for k,v in enumerate(rom): out.append(f"  {k}: coef={v};" if v>=0 else f"  {k}: coef=-{-v};")
    out.append(" default: coef=0;\n endcase\nendfunction")
    out.append('function automatic signed [31:0] init_state(input [4:0] i);\n case(i)')
    for k,v in enumerate(init): out.append(f"  {k}: init_state={q(v,QS)};")
    out.append(" default: init_state=0;\n endcase\nendfunction")
    out+=vco_params()
    Path('rtl/deathrac_audio_coef.vh').write_text('\n'.join(out)+'\n')
    print('ROM words',len(rom),'states',sbase)

if __name__=='__main__': main()
