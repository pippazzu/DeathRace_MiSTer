"""Generate structural Verilog and a connectivity audit from literal sheet traces.

Run from the project root. No OCR or pinout-based wire inference is performed.
Sheets declare chips and list each wire's pins (MAME netlist style); wire names are
made here from the pins, by the rules in docs/NET_NAMES.md.
"""
import collections, json, re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTS = {
 '74161':[14,13,12,11,15], '74192':[3,2,6,7,12,13],
 '74193':[3,2,6,7,12,13], '74174':[2,5,7,10,12,15],
 '74166':[13], '74151':[5,6], '74153':[7,9],
 '74157':[4,7,9,12], '7442':[1,2,3,4,5,6,7,9,10,11],
 '74S200':[6], 'JK112A':[5,6], 'JK112B':[9,7],
 # Listed LSB first: O1 is data bit 0 (82S123 O1=pin 1; 82S129 O1=pin 12).
 '82S123':[1,2,3,4,5,6,7,9], '82S129':[12,11,10,9],
}
INPUTS = {
 '74161':[1,2,3,4,5,6,7,9,10],
 '74192':[1,4,5,9,10,11,14,15], '74193':[1,4,5,9,10,11,14,15],
 '74174':[1,3,4,6,9,11,13,14],
 '74166':[1,2,3,4,5,6,7,9,10,11,12,14,15],
 '74151':[1,2,3,4,7,9,10,11,12,13,14,15],
 '74153':[1,2,3,4,5,6,10,11,12,13,14,15],
 '74157':[1,2,3,5,6,10,11,13,14,15], '7442':[12,13,14,15],
 '74S200':[1,2,3,4,5,7,9,10,11,12,13,14,15],
 'JK112A':[1,2,3,4,15], 'JK112B':[10,11,12,13,14],
 '82S123':[10,11,12,13,14,15], '82S129':[1,2,3,4,5,6,7,13,14,15],
}
GATES = {'7404':('~',None), '7407':('',None),
 '7400':('~','&'),'7437':('~','&'),'7420':('~','&'),'5420':('~','&'),
 '7410':('~','&'),'7430':('~','&'), '7408':('','&'),'7411':('','&'),
 '7421':('','&'),'7432':('','|'),'7402':('~','|'),'7427':('~','|'),'7486':('','^')}
PROM_FILES = {'C15':'c13','C14':'c14','N13':'n13','J10':'j10','D5':'d5',
 'G2':'g2','R1':'r1','B8':'b8','C8':'c8','D8':'d8','E8':'e8',
 'H6':'h6','B2':'b2','H3':'h3','N1':'n1'}
# Reviewed spelling alias, documented separately; never infer aliases by similarity.
ALIASES = {'TDRG':'TCRG'}
# Gate packages: (output pin, input pins) per gate, from the 74xx DIP-14 pinouts.
_2IN=[(3,[1,2]),(6,[4,5]),(8,[9,10]),(11,[12,13])]
_3IN=[(12,[1,2,13]),(6,[3,4,5]),(8,[9,10,11])]
_4IN=[(6,[1,2,4,5]),(8,[9,10,12,13])]
_INV=[(2,[1]),(4,[3]),(6,[5]),(8,[9]),(10,[11]),(12,[13])]
GATE_PINS = {'7400':_2IN,'7408':_2IN,'7432':_2IN,'7437':_2IN,'7486':_2IN,
 '7402':[(1,[2,3]),(4,[5,6]),(10,[8,9]),(13,[11,12])],
 '7404':_INV,'7407':_INV,'7410':_3IN,'7411':_3IN,'7427':_3IN,
 '7420':_4IN,'5420':_4IN,'7421':_4IN,'7430':[(8,[1,2,3,4,5,6,11,12])]}
# 74112 halves keep their own cell models and instance names (G12_a, G12_b).
JK_HALVES = [('a','JK112A',{1,2,3,4,5,6,15}),('b','JK112B',{7,9,10,11,12,13,14})]
# Pseudo-labels in the sheets, and the tokens the code below has always used for them.
CONST = {'GND':'0','VCC':'1','OPEN':'OPEN','NC':'-'}

# Sheets whose counters and flip-flops start from a random power-on state (the seed input)
# instead of zero: the two enemy cars (sheets A-D). On the board nothing clears their turn
# and speed timers. (Their start positions do differ: see the preset pins on sheets 8 and 10.)
SEEDED_SHEETS = (7, 8, 9, 10)
INIT_WIDTH = {'dd_jk112':1, 'dd_74161':4, 'dd_updown':4, 'dd_74174':6}

# Byte stream sent by the MRA: game id at 0, PROMs at fixed offsets. See tools/make_mra.py.
PROM_BASE = {r:0x20*(i+1) for i,r in enumerate(['C15','C14','N13','J10','D5','G2','R1'])}
PROM_BASE.update({r:0x100*(i+1) for i,r in enumerate(['B8','C8','D8','E8','H6','B2','H3','N1'])})

def read_sheets():
    """chip/prom declarations and net lines of every sheet, as written."""
    chips=[]; nets=[]
    for f in sorted((ROOT/'netlist').glob('sheet*.net')):
        sheet=int(f.stem[5:])
        for lineno,line in enumerate(f.read_text().splitlines(),1):
            line=line.split('#')[0].strip()
            if not line: continue
            w=line.split()
            if w[0] in ('chip','prom'): chips.append(dict(sheet=sheet,line=lineno,kind=w[0],chip=w[1],type=w[2]))
            elif w[0]=='net':
                board='BOARD' in w[2:]
                pins=[]
                for tok in w[2:]:
                    if tok=='BOARD': continue
                    c,_,p=tok.rpartition('.')
                    if not c or not p.isdigit(): raise SystemExit(f'ERROR: {f.name}:{lineno}: bad pin {tok!r}')
                    pins.append((c,int(p)))
                nets.append(dict(sheet=sheet,line=lineno,label=w[1],pins=pins,board=board))
            else: raise SystemExit(f'ERROR: {f.name}:{lineno}: unknown line {w[0]!r}')
    return chips,nets

def rows_by_label():
    """Cells and gates with pins mapped to drawing labels (the pre-naming form)."""
    chips,nets=read_sheets(); used={}; board=set()
    declared={(c['sheet'],c['chip']) for c in chips}
    for n in nets:
        label=ALIASES.get(n['label'],n['label'])
        if n['board']: board.add(label)
        for c,p in n['pins']:
            key=(n['sheet'],c,p)
            if (n['sheet'],c) not in declared: raise SystemExit(f"ERROR: sheet {n['sheet']}: {c}.{p} on an undeclared chip")
            if key in used: raise SystemExit(f"ERROR: sheet {n['sheet']}: {c}.{p} is on {used[key]} and {label}")
            used[key]=CONST.get(label,label)
    rows=[]
    for d in chips:
        s,chip,typ=d['sheet'],d['chip'],d['type']
        mine={p:l for (ss,c,p),l in used.items() if ss==s and c==chip}
        base=dict(sheet=s,line=d['line'])
        if typ in GATE_PINS:
            for out,ins in GATE_PINS[typ]:
                pins={p:mine.pop(p) for p in [out,*ins] if p in mine}
                if not pins: continue
                if out not in pins: raise SystemExit(f'ERROR: sheet {s}: {chip} gate {out} has inputs but no output')
                rows.append(dict(base,kind='gate',ref=f'{chip}.{out}',type=typ,pins=pins,outputs=[out]))
        elif typ=='74112':
            for suffix,cell,section in JK_HALVES:
                pins={p:mine.pop(p) for p in sorted(section) if p in mine}
                if pins: rows.append(dict(base,kind='cell',ref=f'{chip}.{suffix}',type=cell,pins=pins,outputs=OUTS[cell]))
        else:
            pins=dict(sorted(mine.items())); mine={}
            rows.append(dict(base,kind=d['kind'],ref=chip,type=typ,pins=pins,outputs=OUTS[typ]))
        if mine: raise SystemExit(f'ERROR: sheet {s}: {chip} {typ} has no pin {sorted(mine)}')
    return rows,board

def overrides_by_label(rows):
    """(row ref, pin) -> label on Death Race."""
    where=collections.defaultdict(list)
    for r in rows:
        for pin in r['pins']: where[(r['ref'].split('.')[0],pin)].append(r['ref'])
    table={}
    for line in (ROOT/'netlist/deathrace.overrides').read_text().splitlines():
        line=line.split('#')[0].strip()
        if not line: continue
        tok,label=line.split(); chip,_,pin=tok.rpartition('.'); pin=int(pin)
        refs=where.get((chip,pin),[])
        if len(refs)!=1: raise SystemExit(f'ERROR: override of {tok}: pin is on {len(refs)} traced gates or cells')
        table[(refs[0],pin)]=CONST.get(label,label)
    return table

def wire_names(rows,dr,board):
    """Drawing label -> wire name, by the rules in docs/NET_NAMES.md."""
    drv=collections.defaultdict(list); ld=collections.defaultdict(set)
    for r in rows:
        chip=r['ref'].split('.')[0]
        for pin,label in r['pins'].items():
            if label in ('0','1','-','OPEN'): continue
            if pin in r['outputs']: drv[label].append(f'{chip}_pin{pin}')
            else: ld[label].add(f'{chip}_pin{pin}')
    for (ref,pin),label in dr.items():
        if label not in ('0','1'): ld[label].add(f"{ref.split('.')[0]}_pin{pin}")
    names={'GAME_DR':'GAME_DR'}
    for label in sorted(set(drv)|set(ld)):
        d=drv.get(label,[]); loads=sorted(ld.get(label,()))
        if len(d)>1: raise SystemExit(f'ERROR: multiple drivers on {label}: {d}')
        if not d: names[label]=label                       # board input: label kept
        elif label in board or len(loads)>1: names[label]=f'{d[0]}_{label}'
        elif not loads: names[label]=f'{d[0]}_NC'
        else: names[label]=f'{d[0]}_{loads[0]}'
    if len(set(names.values()))!=len(names): raise SystemExit('ERROR: two wires got one name')
    return names

def parse():
    rows,board=rows_by_label(); dr=overrides_by_label(rows); names=wire_names(rows,dr,board)
    for r in rows: r['pins']={p:names.get(l,l) for p,l in r['pins'].items()}
    return rows,{k:names.get(v,v) for k,v in dr.items()}

def generate():
    rows,dr=parse(); drivers=collections.defaultdict(list); users=collections.defaultdict(list)
    known={(r['ref'],pin) for r in rows for pin in r['pins']}
    for key,net in dr.items():
        if key not in known: raise SystemExit(f'ERROR: override of an unknown pin {key}')
        if net not in ('0','1'): users[net].append(f'dr:{key[0]}:{key[1]}')
    users['GAME_DR'].append('deathrace.overrides')
    missing=[]; packages=collections.defaultdict(set)
    for r in rows:
        packages[r['ref'].split('.')[0]].add(r['type'].replace('JK112A','74112').replace('JK112B','74112'))
        for pin,net in r['pins'].items():
            net=ALIASES.get(net,net)
            if net in ('0','1','-','OPEN'): continue
            (drivers if pin in r['outputs'] else users)[net].append(f"s{r['sheet']:02d}:{r['ref']}:{pin}")
        for p in INPUTS.get(r['type'],[]):
            if p not in r['pins']: missing.append(f"s{r['sheet']:02d}:{r['ref']}:{p}")
    boundary=sorted(set(users)-set(drivers)); nets=sorted(set(users)|set(drivers))
    audit=dict(cells=len(rows),nets=len(nets),boundary_inputs=boundary,
      multiple_drivers={n:v for n,v in drivers.items() if len(v)>1},
      undrawn_inputs=missing,package_type_conflicts={n:sorted(v) for n,v in packages.items() if len(v)>1},
      aliases=ALIASES,unused_outputs=sorted(set(drivers)-set(users)))
    (ROOT/'docs/connectivity-audit.json').write_text(json.dumps(audit,indent=2)+'\n')
    (ROOT/'output/trace/connectivity.json').write_text(json.dumps(rows,indent=2)+'\n')
    # All driven nets are output ports to allow independent sheet-level probing.
    ports=['input wire clk_sys','input wire reset','input wire prom_wr','input wire [11:0] prom_addr','input wire [7:0] prom_din',
      'input wire [SEED_BITS-1:0] seed']  # power-on state of the SEEDED_SHEETS cells, used while reset is held
    seed_bits=0
    ports += [('input' if n in boundary else 'output')+' wire n_'+n for n in nets]
    code=['// GENERATED by tools/generate_netlist.py. Edit netlist/sheet*.net instead.',
      '// FPGA=0: event-driven reference. FPGA=1: sampled sequential cells.',
      '// OPEN_LEVEL models a visibly floating TTL input; missing inputs stay X.',
      '// Wire names: n_ + driver pin, then load pin or drawing label. See docs/NET_NAMES.md.',
      '`default_nettype none',
      'module deathrac_netlist #(parameter FPGA=1, parameter OPEN_LEVEL=1\'b1) (',
      ',\n'.join('    '+p for p in ports),');']
    doc=['# Sheet connectivity','', 'Generated from the pin trace. Coordinates and exceptions are in the trace evidence bundle.', '']
    for i,r in enumerate(rows):
        pins=r['pins']; typ=r['type']; ref=r['ref']; sheet=r['sheet']; inst=f"s{sheet:02d}_{ref.replace('.','_')}"
        def p(pin):
            n=pins.get(pin)
            if n is None: return "1'bx"
            if n=='-':
                stub=f'unused_{i}_{pin}'
                code.append('wire '+stub+';')
                return stub
            def name(x): return {'0':"1'b0",'1':"1'b1",'OPEN':'OPEN_LEVEL'}.get(x,'n_'+ALIASES.get(x,x))
            if (ref,pin) in dr: return f"(n_GAME_DR ? {name(dr[(ref,pin)])} : {name(n)})"
            return name(n)
        def bus(numbers): return '{'+', '.join(p(x) for x in reversed(numbers))+'}'
        code.append(f"// PDF {sheet+2}, sheet {sheet}, {ref} {typ}; netlist/sheet{sheet:02d}.net:{r['line']}")
        doc.append(f"- Sheet {sheet}, {ref}, {typ}: "+', '.join(f'{k}={v}' for k,v in pins.items()))
        con={}; module=''; params='.FPGA(FPGA)'
        if r['kind']=='gate':
            op,join=GATES[typ]; out=r['outputs'][0]; ins=[p(x) for x in pins if x!=out]
            # Wire names end in the drawing label when a net has several loads.
            label=pins[out].rsplit('_',1)[-1]
            if label in ('MTNR','MTNL','NTNR','NTNL'):
                a,b=('MTTA','MTTB') if label.startswith('M') else ('NTTA','NTTB')
                if label.endswith('L'): a,b=b,a
                code.append(f'dd_feedback #(.FPGA(FPGA)) {inst} (.clk_sys(clk_sys), .reset(reset), .a(n_{a}), .b(n_{b}), .q({p(out)}));')
            else:
                expr=ins[0] if join is None else '('+f' {join} '.join(ins)+')'
                code.append(f'assign {p(out)} = {op}{expr};')
            continue
        if typ in ('JK112A','JK112B'):
            order=[1,3,2,4,15,5,6] if typ.endswith('A') else [13,11,12,10,14,9,7]
            module='dd_jk112'; con=dict(zip(['ck','j','k','pre_n','clr_n','q','qn'],map(p,order)))
        elif typ=='74161':
            module='dd_74161'; con=dict(ck=p(2),clr_n=p(1),load_n=p(9),enp=p(7),ent=p(10),d=bus([3,4,5,6]),q=bus([14,13,12,11]),carry=p(15))
        elif typ in ('74192','74193'):
            module='dd_updown'; params+=f", .BCD({int(typ=='74192')})"
            con=dict(down=p(4),up=p(5),load_n=p(11),clear=p(14),d=bus([15,1,10,9]),q=bus([3,2,6,7]),co_n=p(12),bo_n=p(13))
        elif typ=='74174':
            module='dd_74174'; con=dict(ck=p(9),clr_n=p(1),d=bus([3,4,6,11,13,14]),q=bus([2,5,7,10,12,15]))
        elif typ=='74166':
            module='dd_74166'; con=dict(ck=p(7),inhibit=p(6),clr_n=p(9),load_n=p(15),serial=p(1),d=bus([2,3,4,5,10,11,12,14]),q=p(13))
        elif typ=='74S200':
            module='dd_74s200'; con=dict(a=bus([1,2,15,7,9,10,11,14]),ce_n='('+p(3)+' | '+p(4)+' | '+p(5)+')',we_n=p(12),d=p(13),q_n=p(6))
        elif r['kind']=='prom':
            module='dd_prom'; params=f'.AW({5 if typ=="82S123" else 8}), .DW({8 if typ=="82S123" else 4}), .BASE({PROM_BASE[ref]}), .ROM_FILE("roms/cdi.{PROM_FILES[ref]}.hex")'
            # Image PROMs: registered read for timing (see dd_prom in rtl/ttl_cells.v).
            if ref in ('B8','C8','D8','E8'): params+=', .REG(1), .FPGA(FPGA)'
            con=dict(a=bus([10,11,12,13,14] if typ=='82S123' else [5,6,7,4,3,2,1,15]),
              enable_n=p(15) if typ=='82S123' else '('+p(13)+' | '+p(14)+')',q=bus(OUTS[typ]),
              clk_sys='clk_sys',prom_wr='prom_wr',prom_addr='prom_addr',prom_din='prom_din')
        elif typ=='74151':
            code += [f'wire [7:0] {inst}_d = {bus([4,3,2,1,15,14,13,12])};',
              f'assign {p(5)} = ~{p(7)} & {inst}_d[{bus([11,10,9])}];',f'assign {p(6)} = ~{p(5)};']; continue
        elif typ=='74153':
            for lane,dp,en,out in [(0,[6,5,4,3],1,7),(1,[10,11,12,13],15,9)]:
                code += [f'wire [3:0] {inst}_d{lane} = {bus(dp)};',f'assign {p(out)} = ~{p(en)} & {inst}_d{lane}[{bus([14,2])}];']
            continue
        elif typ=='74157':
            for a,b,y in [(2,3,4),(5,6,7),(11,10,9),(14,13,12)]:
                code.append(f'assign {p(y)} = ~{p(15)} & ({p(1)} ? {p(b)} : {p(a)});')
            continue
        elif typ=='7442':
            for value,pin in enumerate(OUTS[typ]): code.append(f'assign {p(pin)} = ({bus([15,14,13,12])} != 4\'d{value});')
            continue
        else: raise ValueError(typ)
        if r['kind']!='prom':
            con={'clk_sys':'clk_sys','reset':'reset',**con}
            w=INIT_WIDTH.get(module)
            if w is None: pass
            elif sheet in SEEDED_SHEETS: con['init']=f'seed[{seed_bits+w-1}:{seed_bits}]' if w>1 else f'seed[{seed_bits}]'; seed_bits+=w
            else: con['init']=f"{w}'d0"
        code.append(f'{module} #({params}) {inst} ('+', '.join(f'.{k}({v})' for k,v in con.items())+');')
    code=[c.replace('SEED_BITS-1',str(seed_bits-1)) for c in code]
    m=re.search(r'localparam SEED_BITS=(\d+);',(ROOT/'rtl/deathrac_board.v').read_text())
    if not m or int(m[1])!=seed_bits: raise SystemExit(f'ERROR: set SEED_BITS={seed_bits} in rtl/deathrac_board.v')
    code += ['endmodule','`default_nettype wire','']
    (ROOT/'rtl/deathrac_netlist.v').write_text('\n'.join(code))
    (ROOT/'docs/CONNECTIVITY.md').write_text('\n'.join(doc)+'\n')
    print(json.dumps(audit,indent=2))
    if audit['multiple_drivers']: raise SystemExit('ERROR: multiple drivers')

if __name__=='__main__': generate()
