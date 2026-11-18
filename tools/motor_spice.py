"""Nonlinear reference for the motor sound, sheets 15-16: Ebers-Moll transistors,
backward Euler with Newton at 192 kHz. A design reference, slower than real time, used
to judge the linear FPGA model and the timing capacitor value.

Usage: python tools/motor_spice.py OUT.wav C_T_uF [seg_seconds] [wide|band|off] [beta] [twin-T cap scale]
Scenario: stopped, then speeds 12, 13, 14, 15, each seg seconds. Prints stage levels.
"""
import sys, wave, importlib.util
from pathlib import Path
import numpy as np
spec = importlib.util.spec_from_file_location('r', Path(__file__).with_name('audio_ref.py'))
r = importlib.util.module_from_spec(spec); spec.loader.exec_module(r)
d = r.d
FS = 192000; DT = 1/FS; VT = 0.02585; VS = 14.0
IS = 6.7e-15; BF = 150.0; BR = 3.0
TT = 1.0                      # part tolerance on the twin-T capacitors, fitted to recordings
INJ = 1.0                     # scale on R38, the XC1A coupling, fitted to recordings
TTL = 1.0                     # scale on the assumed 1.2 mA flip-flop input current into the timing capacitor
NODES = ['X', 'P', 'Q', 'T', 'R', 'U', 'B', 'N', 'Xn', 'Yn', 'XB', 'B2', 'C2']
ix = {n: i for i, n in enumerate(NODES)}
N = len(NODES)

class Motor:
    """Sheet 15 relaxation oscillator. TTL scales the original model's input current assumption."""
    def __init__(s):
        s.vb = 0.2; s.vc = 0.0; s.q = 1; s.x10 = 0
    def tick(s, m, dt):
        vt, rt = r.dac(*m)
        s.vb += (vt-s.vb)*dt/(rt*33e-6) if rt*33e-6 > dt else (vt-s.vb)
        i = 0.0
        if s.vb > 0.65: i += 1.5*(s.vb-0.65)/10e3
        i += (5-s.vc)/68e3
        if s.vc < r.VTH: i += TTL*max(0.0, (4.25-s.vc)/2.8e3)
        if s.q == 0: i -= max(0.0, s.vc-0.1)/18.0
        s.vc = min(s.vc+i*dt/r.C_T, 5.65)
    def clock(s):
        k = s.vc > r.VTH; xc11 = 1-s.q
        if xc11: s.x10 ^= 1
        s.q = (1-s.q) if k else 1

def build():
    G = np.zeros((N, N)); C = np.zeros((N, N)); I = np.zeros(N)
    def res(a, b, v):
        g = 1/v
        for p, q in ((a, b), (b, a)):
            if p is None: continue
            G[ix[p], ix[p]] += g
            if q is not None: G[ix[p], ix[q]] -= g
    def cap(a, b, v):
        for p, q in ((a, b), (b, a)):
            if p is None: continue
            C[ix[p], ix[p]] += v
            if q is not None: C[ix[p], ix[q]] -= v
    def rv(a, v, e):                  # resistor to a fixed voltage
        G[ix[a], ix[a]] += 1/v; I[ix[a]] += e/v
    # Stage 1. R37 to +5, R38, C26, C64, twin-T, 2.2M bias, R43 collector.
    rv('X', 10e3, 5.0); res('X', 'P', 10e3*INJ); cap('P', None, 0.2e-6); cap('P', 'Q', 0.2e-6)
    cap('Q', 'B', 2.2e-6)
    cap('Q', 'T', 0.047e-6*TT); res('T', None, 680); cap('T', 'U', 0.047e-6*TT)
    res('Q', 'R', 47e3); cap('R', None, 0.1e-6*TT); res('R', 'U', 47e3)
    rv('B', 2.2e6, VS); rv('U', 10e3, VS)
    cap('N', 'B', 330e-12)            # noise source joins through 10k, added at run time
    G[ix['N'], ix['N']] += 1/10e3
    # Stage 2. R45, C34, R48, XC1B pull-up to +15, C33, 1M, 270k, collector 10k, 47k+10k pot.
    res('U', 'Xn', 100e3); cap('Xn', 'Yn', 0.003e-6); res('Yn', 'XB', 100e3)
    rv('XB', 10e3, 15.0)
    cap('Xn', 'B2', 0.1e-6); res('B2', 'C2', 1e6); res('Xn', 'C2', 270e3)
    rv('C2', 10e3, VS); res('C2', None, 57e3)
    # Junction capacitance, order of the 2N3904 data sheet.
    cap('B', None, 8e-12); cap('B', 'U', 4e-12); cap('B2', None, 8e-12); cap('B2', 'C2', 4e-12)
    return G, C, I

def npn(vb, vc):
    """Return Ib, Ic and their derivatives for a grounded-emitter NPN."""
    vbe = min(vb, 0.95); vbc = min(vb-vc, 0.95)
    ef = np.exp(vbe/VT); er = np.exp(vbc/VT)
    ibe = IS*(ef-1); ibc = IS*(er-1); gf = IS*ef/VT; gr = IS*er/VT
    ib = ibe/BF+ibc/BR; ic = ibe-ibc*(1+1/BR)
    dib_b = gf/BF+gr/BR; dib_c = -gr/BR
    dic_b = gf-gr*(1+1/BR); dic_c = gr*(1+1/BR)
    return ib, ic, dib_b, dib_c, dic_b, dic_c

def noise_source(n, mode, seed=1):
    """Q12 collector at 48 kHz. 'band' is the LM748 stage from its drawn parts: 22 pF
    compensation (GBW about 1.36 MHz), 1M feedback, 100 ohm + 2.2 uF to ground, peak 313 Hz.
    'wide' is the earlier 3 kHz assumption."""
    rng = np.random.default_rng(seed); w = rng.standard_normal(n)
    if mode == 'off': return np.full(n, 7.0)
    if mode == 'wide':
        y = r.lfilter([0.325], [1, -0.675], w)
    else:
        from scipy.signal import bilinear
        wc = 2*np.pi*1e6*30/22; T = (1e6+100)*2.2e-6; RC = 100*2.2e-6
        b, a = bilinear([wc*T, wc], [T, 1+wc*RC, wc], 48000)
        y = r.lfilter(b, a, w)
    return np.where(y > 0, 13.9, 0.2)

def run(c_t, seg, seed=1, noise='band'):
    G0, C, I0 = build()
    Cdt = C/DT
    A0 = G0+Cdt
    r.C_T = c_t
    mot = Motor(); tline = 0.0
    nsrc = noise_source(int(5*seg*48000)+2, noise, seed); vn = 7.0
    x = np.zeros(N)
    # A settled operating point: bias network alone.
    x[ix['B']] = 0.65; x[ix['U']] = 5.0; x[ix['B2']] = 0.65; x[ix['C2']] = 6.0; x[ix['X']] = 5.0; x[ix['XB']] = 14.0
    b1, c1, b2, c2 = ix['B'], ix['U'], ix['B2'], ix['C2']
    jx, jy, jn = ix['X'], ix['XB'], ix['N']
    steps = int(5*seg*FS); out = np.zeros(steps); u = np.zeros(steps); a_log = np.zeros(steps)
    sub = 0; xa_low = xb_low = 0
    for n in range(steps):
        t = n*DT; k = min(int(t/seg), 4)
        m = (0, 0, 0) if k == 0 else (1, (k-1) >> 1 & 1, (k-1) & 1)
        mot.tick(m, DT); tline += DT
        if tline >= 1/r.FLINE: tline -= 1/r.FLINE; mot.clock()
        xa_low = 1-mot.x10; xb_low = mot.x10
        if n % 4 == 0:
            vn = nsrc[n//4]
        A = A0.copy(); rhs = I0+Cdt@x
        rhs[jn] += vn/10e3
        if xa_low: A[jx, jx] += 1/20.0; rhs[jx] += 0.1/20.0
        if xb_low: A[jy, jy] += 1/20.0; rhs[jy] += 0.1/20.0
        y = x.copy()
        for _ in range(12):
            ib1, ic1, a, b, c, e = npn(y[b1], y[c1])
            ib2, ic2, a2, b_2, c_2, e2 = npn(y[b2], y[c2])
            J = A.copy(); f = A@y-rhs
            f[b1] += ib1; f[c1] += ic1; f[b2] += ib2; f[c2] += ic2
            J[b1, b1] += a; J[b1, c1] += b; J[c1, b1] += c; J[c1, c1] += e
            J[b2, b2] += a2; J[b2, c2] += b_2; J[c2, b2] += c_2; J[c2, c2] += e2
            dy = np.linalg.solve(J, -f)
            dy = np.clip(dy, -0.5, 0.5) if np.abs(dy[[b1, b2]]).max() > 0.5 else dy
            y += dy
            if np.abs(dy).max() < 1e-5: break
        x = y
        out[n] = x[c2]; u[n] = x[c1]; a_log[n] = mot.x10
    return out, u, a_log

def speaker(y):
    """Collector to speaker: pot, mixer at 48 kHz, bridged amp, coupling, speaker roll-off."""
    y48 = y[:len(y)//4*4].reshape(-1, 4).mean(axis=1)
    mx = r.LinBlock([d.mixer(False), d.mixer(True)])
    mx.init([0.0, y48[0]*10e3/57e3*d.POT_MOTOR])
    v = np.array([mx.step([0.0, s*10e3/57e3*d.POT_MOTOR], 0) for s in y48])
    a = np.clip(v*100, -13, 13)
    hp = 0.0; o = np.zeros(len(a))
    k = 2*np.pi*50/48000
    for i, s in enumerate(a):
        hp += (s-hp)*k; o[i] = s-hp
    q = 1-np.exp(-2*np.pi*d.SPK_FC/48000)
    return r.lfilter([q], [1, q-1], r.lfilter([q], [1, q-1], o))

def tone_list(q, n=6):
    from scipy.signal import find_peaks
    P = np.abs(np.fft.rfft(q*np.hanning(len(q))))
    D = 20*np.log10(P+1e-12); F = np.fft.rfftfreq(len(q), 1/48000)
    i, _ = find_peaks(D[F < 1500], prominence=10); i = i[np.argsort(D[i])[::-1]][:n]
    return ' '.join(f'{F[j]:.0f}({D[j]-D[i].max():.0f})' for j in sorted(i, key=lambda j: F[j]))

if __name__ == '__main__':
    path, c_uf = sys.argv[1], float(sys.argv[2])
    seg = float(sys.argv[3]) if len(sys.argv) > 3 else 0.8
    mode = sys.argv[4] if len(sys.argv) > 4 else 'band'
    if len(sys.argv) > 5: BF = float(sys.argv[5])
    if len(sys.argv) > 6: TT = float(sys.argv[6])
    if len(sys.argv) > 7: TTL = float(sys.argv[7])
    c2, c1, xa = run(c_uf*1e-6, seg, noise=mode)
    o = speaker(c2)
    L = int(seg*48000); L192 = L*4
    for s in range(5):
        q = o[s*L+L//4:(s+1)*L]; xs = xa[s*L192+L192//4:(s+1)*L192]
        edges = (np.diff(xs) != 0).sum()/2/(len(xs)/FS)
        sp = np.abs(np.fft.rfft(q*np.hanning(len(q))))**2; f = np.fft.rfftfreq(len(q), 1/48000)
        print(f'seg {s}: XC1A {edges:6.1f} Hz  out rms {20*np.log10(np.sqrt((q**2).mean())/13+1e-9):6.1f} dB  '
              f'top {f[sp.argmax()]:5.0f} Hz  centroid {(sp*f).sum()/sp.sum():5.0f}  >2k {100*sp[f>2000].sum()/sp.sum():4.1f}%  '
              f'tones {tone_list(q)}  Q6 collector {c1[s*L192+L192//4:(s+1)*L192].min():.1f}..{c1[s*L192+L192//4:(s+1)*L192].max():.1f} V', flush=True)
    w = wave.open(path, 'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(48000)
    w.writeframes((np.clip(o/13, -1, 1)*32767).astype('<i2').tobytes()); w.close()
