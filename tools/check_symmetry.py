"""Compare twin sheets as graphs: any asymmetry is either a real board difference
or a transcription error, and must be settled on the scan.

Sheet pairs: 7/9 (A/C), 8/10 (B/D), 11/13 (G/H), 12/14 (M/N). Nets are renamed
from the left sheet to the right one; IC positions and pin numbers are ignored
except that 74xx input groups are compared as sets per output net.
"""
import re, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

def load(n):
    rows = []
    for line in (ROOT/f'netlist/sheet{n:02d}.net').read_text().splitlines():
        line = line.split('#')[0].strip()
        if not line: continue
        w = line.split(); kind, ref, typ = w[:3]
        pins = dict(p.split('=') for p in w[(4 if kind == 'prom' else 3):])
        rows.append((kind, ref, typ, pins))
    return rows

OUTS = {'JK112A': ('5', '6'), 'JK112B': ('9', '7')}
# Separate gates driven by the same source net, verified on sheets 4, 5, 6: identical signals.
SAME = {'1KQ07': '1LQ07', '1PQ07': '1LQ07', '2KQ07': '2LQ07', '2PQ07': '2LQ07', '6PQ07': '6TQ07', 'BQED': 'BEQD', 'BQEU': 'BEQU'}
def signature(row, rename):
    kind, ref, typ, pins = row
    pins = {k: SAME.get(rename(v), rename(v)) for k, v in pins.items()}
    if kind == 'gate':
        out = next(iter(pins))
        return (pins[out], ('gate', typ.replace('5420', '7420'), tuple(sorted(v for k, v in pins.items() if k != out))))
    if typ in OUTS:
        q, qn = OUTS[typ]
        order = ('1', '2', '3', '4', '15') if typ == 'JK112A' else ('13', '12', '11', '10', '14')
        return (pins.get(q, '-') + '/' + pins.get(qn, '-'), ('jk', tuple(pins.get(k) for k in order)))
    # Key other cells by their first named output, comparing pin-by-pin.
    named = sorted(v for v in pins.values() if v not in ('0', '1', '-', 'OPEN'))
    outs = {'74161': '14 13 12 11 15', '74174': '2 5 7 10 12 15', '74193': '3 2 6 7 13 12',
            '74192': '3 2 6 7 13 12', '74151': '5 6', '82S123': '1', '82S129': '9'}[typ].split()
    key = next((pins[o] for o in outs if pins.get(o, '-') != '-'), named[0])
    return (key, (typ, tuple(sorted(pins.items(), key=lambda kv: int(kv[0])))))

def compare(left, right, a, b):
    """a, b: single-letter prefixes mapped left to right, longest first."""
    def rename(net):
        if net in ('0', '1', '-', 'OPEN'): return net
        return re.sub(a, b, net) if isinstance(a, str) else a(net)
    L, R = {}, {}
    leftovers = ([], [])
    for side, rows, fn in ((L, load(left), rename), (R, load(right), lambda x: x)):
        for r in rows:
            k, v = signature(r, fn)
            k = k or f'{r[1]}'
            side.setdefault(k, []).append((v, r[1]))
    found = 0
    for k in sorted(set(L) | set(R)):
        lv = [x[0] for x in L.get(k, [])]; rv = [x[0] for x in R.get(k, [])]
        if sorted(map(str, lv)) != sorted(map(str, rv)):
            found += 1
            print(f'  {k}:\n    s{left:02d} {L.get(k)}\n    s{right:02d} {R.get(k)}')
    return found

def pairmap(mapping):
    def fn(net):
        m = re.match(r'^(\d?)([A-Z])(.*)$', net)
        if m and m[2] in mapping and not net.startswith(('TLC', 'TEC', 'TQ')):
            return m[1] + mapping[m[2]] + m[3]
        return net
    return fn

total = 0
for l, r, mp in ((7, 9, {'A': 'C', 'B': 'D'}), (8, 10, {'A': 'C', 'B': 'D'}),
                 (11, 13, {'G': 'H', 'M': 'N'}), (12, 14, {'G': 'H', 'M': 'N'})):
    print(f'sheet {l} vs {r}')
    total += compare(l, r, pairmap(mp), None)
print('differences', total)
