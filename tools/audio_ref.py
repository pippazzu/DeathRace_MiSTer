"""Floating-point reference of the sound chain, for design checks.

Scenario: idle, speeds 12..15, then a crash. Writes build/audio-ref.wav and
prints per-segment level and dominant frequency.
"""
import numpy as np, wave, importlib.util, sys
from pathlib import Path
spec=importlib.util.spec_from_file_location('d',Path(__file__).with_name('design_audio.py'))
d=importlib.util.module_from_spec(spec); spec.loader.exec_module(d)

from scipy.signal import lfilter
FS=d.FS; TICK=2e6; FLINE=115151515/8/832
C_T=33e-6; VTH=1.5
# Sheet 15 DAC: target base voltage and Thevenin resistance per (GMC1,GMC0) with GMC2 open.
def dac(m2,m1,m0):
    if not m2: return 0.2,20.0
    g=[1/20e3]; v=[5/20e3]
    for bit,r in ((m1,10e3),(m0,39e3)):
        if bit: g.append(1/(r+1.2e3)); v.append(5/(r+1.2e3))
        else: g.append(1/r); v.append(d.VOL/r)
    return sum(v)/sum(g),1/sum(g)

class Motor:
    def __init__(s):
        s.vb=0.2; s.vc=0.0; s.q=1; s.x10=0
    def tick(s,m,dt):
        vt,rt=dac(*m); s.vb+=(vt-s.vb)*dt/(rt*33e-6) if rt*33e-6>dt else (vt-s.vb)
        i=0.0
        if s.vb>0.65: i+=1.5*(s.vb-0.65)/10e3
        i+=(5-s.vc)/68e3
        if s.q==0: i-=max(0.0,s.vc-0.1)/18.0
        s.vc=min(s.vc+i*dt/C_T,5.65)
    def clock(s):                              # 2TQLC falling edge: U5a, U5b
        k=s.vc>VTH; xc11=1-s.q
        if xc11: s.x10^=1
        s.q=(1-s.q) if k else 1

class LinBlock:
    def __init__(s,variants):
        s.mats=[v.discretize() for v in variants]; b=variants[0]; s.b=b
        s.x=np.zeros(len(b.nodes)); s.o=b.nodes.index(b.out)
        s.cl={b.nodes.index(k):v for k,v in b.clamps.items()}
    def init(s,u): s.x=s.b.dc(np.array(u,float)); s.clamp()
    def clamp(s):
        for k,(lo,hi) in s.cl.items(): s.x[k]=min(max(s.x[k],lo),hi)
    def step(s,u,var=0):
        A,B=s.mats[var]; s.x=A@s.x+B@np.array(u,float); s.clamp(); return s.x[s.o]

def run(seg=1.0,seed=1):
    secs=6*seg
    rng=np.random.default_rng(seed)
    m1=LinBlock([d.motor1(x,o,d.TWIN_T[0]) for x in (False,True) for o in (False,True)])
    m2=LinBlock([d.motor2(x,o) for x in (False,True) for o in (False,True)])
    b1=m1.b.nodes.index('B'); b2=m2.b.nodes.index('B2')
    cr=LinBlock([d.crash()]); mx=LinBlock([d.mixer(False),d.mixer(True)])
    m1.b=d.motor1(False,True,d.TWIN_T[0]); m2.b=d.motor2(False,True)
    m1.init([1,7.0]); m2.init([1,m1.x[m1.o]]); cr.init([1,0.0])
    mot=Motor(); vh=0.0; nlp=0.0; hp=0.0; out=[]
    sub=int(TICK//FS); dt=1/TICK; tline=0.0
    for n in range(int(secs*FS)):
        t=n/FS
        k=min(int(t/seg),4)                     # 0 idle, 1..4 speeds 12..15
        m=(0,0,0) if k==0 else (1,(k-1)>>1&1,(k-1)&1)
        gthe= 1 if 4.5*seg<=t<4.5*seg+1/60.058 else 0   # one-frame crash pulse
        xa=0
        for k in range(sub):
            mot.tick(m,dt); tline+=dt
            if tline>=1/FLINE: tline-=1/FLINE; mot.clock()
            xa+=mot.x10
        xc1a_low = 1-mot.x10                    # XC1A follows XC10 (7407 buffer)
        xc1b_low = 1-xc1a_low                   # XC1B follows 5XC10
        # Noise: U8 band ~3 kHz then clipped by Q12 (A).
        nlp+=0.325*(rng.standard_normal()-nlp); vn=13.9 if nlp>0 else 0.2
        # Crash envelope node H (2.2uF): GTHE via 1.2k+diode, 270k || 650k discharge.
        ich=(14.4-vh)/1.2e3 if gthe and vh<14.4 else 0.0
        vh+=(ich-vh/270e3-vh/650e3)/FS/2.2e-6
        va=min((vh*5.5+0.65)/6.5, vn+0.6)
        u1=m1.step([1,vn],xc1a_low*2+int(m1.x[b1]>d.VBE))
        mo=m2.step([1,u1],xc1b_low*2+int(m2.x[b2]>d.VBE))
        co=cr.step([1,va])
        f=min(15*100/147, co+0.6)               # 47k/100k node, diode to collector
        vin=mx.step([f*d.POT_CRASH, mo*10e3/57e3*d.POT_MOTOR],0)
        a=max(-13.0,min(13.0,vin*100))          # LM380 pair, bridged gain 100 (A)
        hp+= (a-hp)*(2*np.pi*50/FS)             # 400uF into 8 ohm
        out.append(a-hp)
    k=1-np.exp(-2*np.pi*d.SPK_FC/FS)            # A: cabinet speaker roll-off
    return lfilter([k],[1,k-1],lfilter([k],[1,k-1],np.array(out)))

if __name__=='__main__':
    SEG=float(sys.argv[1]) if len(sys.argv)>1 else 1.0
    y=run(SEG); L=int(SEG*FS)
    for s in range(6):
        seg=y[s*L+L//4:(s+1)*L]
        sp=np.abs(np.fft.rfft(seg*np.hanning(len(seg)))); f=np.fft.rfftfreq(len(seg),1/FS)
        top=f[np.argsort(sp)[-3:][::-1]]
        print(f'seg {s}: rms {np.sqrt(np.mean(seg**2)):6.3f} V  peak {np.abs(seg).max():6.3f}  top Hz {np.round(top,1)}')
    w=wave.open('build/audio-ref.wav','wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(FS)
    w.writeframes((np.clip(y/13.0,-1,1)*32767).astype('<i2').tobytes()); w.close()
