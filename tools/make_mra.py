"""Write the MRA files and, for simulation only, the ROM byte streams.

The byte stream is what MiSTer sends to the core at load time:
  0x000      bit 0: game, 0 Derby, 1 Death Race; bit 1: 1 native progressive picture
  0x020..    seven 32-byte 82S123 PROMs, 0x20 apart
  0x100..    eight 256-byte 82S129 PROMs, 0x100 apart
Order is by board position on the model 466 drawing, as PROM_BASE in
tools/generate_netlist.py. Each entry names the dump that sits in that socket.

Usage: python tools/make_mra.py [deathrac.zip] [destdrby.zip] [dmodrbcc.zip]
Two sets are written. mra/*.mra ask for the board's own progressive picture (17.3 kHz,
for HDMI and multisync monitors); mra/15kHz/* (15kHz).mra ask for interlaced 15.7 kHz,
for TVs and 15 kHz monitors. The OSD option Video output swaps the two.
The MRAs hold only names and CRCs, plus the default pad map: without a <buttons>
tag MiSTer puts Start and Coin on pad Y and L, as JTFRAME's own MRAs avoid.
 ROM data stays in the zips and build/.

Exidy's destdrby and Chicago Coin's dmodrbcc hold the same 15 dumps (same sizes and
CRCs, checked 5 November 2026) under different names, so both give the same stream.
Destruction Derby is the main Derby MRA. The Chicago Coin one, which also accepts
destdrby.zip, goes in _alternatives/_Destruction Derby/ of each set.
"""
import sys, zipfile, zlib
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
DL = Path.home()/'Downloads'

ORDER = ['C15', 'C14', 'N13', 'J10', 'D5', 'G2', 'R1', 'B8', 'C8', 'D8', 'E8', 'H6', 'B2', 'H3', 'N1']
GAMES = {
 # Exidy names follow the board grid like Death Race's. Where two sockets hold the same
 # dump (J10/D5, G2/R1, H6/B2, H3/N1) the pairing is copied from Death Race; the data is
 # identical either way.
 'Destruction Derby': dict(id=0, zip='destdrby.zip', setname='destdrby', year='1975', maker='Exidy',
  hexname='rom_derby.hex', roms={
  'C15': '82s123-31.a11', 'C14': '82s123-32.c12', 'N13': '82s123-33.p14', 'J10': '82s123-34.e7', 'D5': '82s123-34.r7',
  'G2': '82s123-35.t7', 'R1': '82s123-35.g7', 'B8': '82s129-93.m11', 'C8': '82s129-94.l11', 'D8': '82s129-95.k11',
  'E8': '82s129-96.j11', 'H6': '82s129-91.j10', 'B2': '82s129-91.v10', 'H3': '82s129-92.v5', 'N1': '82s129-92.j5'}),
 'Demolition Derby (Chicago Coin)': dict(id=0, sub='_alternatives/_Destruction Derby', zip='dmodrbcc.zip', zips='dmodrbcc.zip|destdrby.zip', setname='dmodrbcc',
  year='1976', maker='Chicago Coin', hexname='rom_derby_cc.hex', roms={
  'C15': 'cdi.c13', 'C14': 'cdi.c14', 'N13': 'cdi.n13', 'J10': 'cdi.j10', 'D5': 'cdi.d5',
  'G2': 'cdi.g2', 'R1': 'cdi.r1', 'B8': 'cdi.b8', 'C8': 'cdi.c8', 'D8': 'cdi.d8', 'E8': 'cdi.e8',
  'H6': 'cdi.h6', 'B2': 'cdi.b2', 'H3': 'cdi.h3', 'N1': 'cdi.n1'}),
 # Sockets are from DR-1A: 11A timing, 12C timing, 14P score, 7E/7R gremlins (sheets
 # A, C), 7T/7G cars (sheets G, H), 11M..11J image (sheet K), 10J/10V, 5V/5J.
 'Death Race': dict(id=1, zip='deathrac.zip', setname='deathrac', year='1976', maker='Exidy',
  hexname='rom_dr.hex', roms={
  'C15': '6331-31.11a', 'C14': '6331-32.12c', 'N13': '6331-33.14p', 'J10': '6331-36.7e', 'D5': '6331-36.7r',
  'G2': '6331-35.7t', 'R1': '6331-35.7g', 'B8': '6301-97.11m', 'C8': '6301-98.11l', 'D8': '6301-99.11k',
  'E8': '6301-100.11j', 'H6': '6301-91.10j', 'B2': '6301-91.10v', 'H3': '6301-92.5v', 'N1': '6301-92.5j'}),
}

def main(paths):
    (ROOT/'mra').mkdir(exist_ok=True); (ROOT/'build').mkdir(exist_ok=True)
    streams = {}
    for title, g in GAMES.items():
        path = paths.get(g['zip'], DL/g['zip'])
        z = zipfile.ZipFile(path)
        stream = bytearray(0x900); stream[0] = g['id']
        parts = ['    <part>@B0@</part>', '    <part repeat="0x1F">00</part>']
        for ref in ORDER:
            name = g['roms'][ref]; data = z.read(name)
            base = (ORDER.index(ref)+1)*0x20 if len(data) == 32 else (ORDER.index(ref)-6)*0x100
            assert len(data) == (32 if ORDER.index(ref) < 7 else 256), name
            stream[base:base+len(data)] = data
            parts.append(f'    <part name="{name}" crc="{zlib.crc32(data):08x}"/>')
        assert len(stream) == 0x900
        mra = f"""<misterromdescription>
  <name>@NAME@</name>
  <setname>{g['setname']}</setname>
  <rbf>DeathRace</rbf>
  <year>{g['year']}</year>
  <manufacturer>{g['maker']}</manufacturer>
  <buttons names="Accelerate,Drive,Reverse,Start,Coin,Pause" default="A,B,X,Start,Select,-"/>
  <rom index="1"><part>00 80</part></rom>
  <rom index="0" zip="{g.get('zips', g['zip'])}" md5="None">
{chr(10).join(parts)}
  </rom>
</misterromdescription>
"""
        sub = g.get('sub', '.')
        for native, name, folder in ((1, title, ROOT/'mra'/sub), (0, f'{title} (15kHz)', ROOT/'mra'/'15kHz'/sub)):
            folder.mkdir(parents=True, exist_ok=True)
            text = mra.replace('@B0@', f'{g["id"] | native << 1:02X}').replace('@NAME@', name)
            (folder/f'{name}.mra').write_text(text, newline='\n')
        (ROOT/'build'/g['hexname']).write_text('\n'.join(f'{b:02x}' for b in stream)+'\n')
        streams[title] = bytes(stream)
        print(title, 'stream', len(stream), 'crc', f'{zlib.crc32(bytes(stream)):08x}')
    assert streams['Destruction Derby'] == streams['Demolition Derby (Chicago Coin)'], 'Derby sets differ'
    print('Destruction Derby and Demolition Derby streams are identical')

if __name__ == '__main__':
    paths = {Path(a).name: Path(a) for a in sys.argv[1:]}
    main(paths)
