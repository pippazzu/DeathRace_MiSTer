"""Import your own dmodrbcc PROMs, checking independent MAME identities."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile
import zlib

EXPECTED = {
    'b2': (256, 'c3823f0b', '42fe8c1e0f54b3f968a630dd564a8941410c5d86'),
    'b8': (256, '9f65c1df', 'e367cc418b34005198f9b958592573986d37274a'),
    'c8': (256, '5e27fc7c', 'bae31e7f0ff7a5ebfe4a12fc537249ee24a4cf4b'),
    'd8': (256, '93dc096c', 'b89a478ef731024eb24a79f9e82a5ef779e8e3d0'),
    'e8': (256, 'ddbb0cc7', '6f169566cb09c78090cec2e375013c0eb2656890'),
    'h3': (256, '82d7d25f', 'd4b3a6655f91647545d493c2ff996daa66df0395'),
    'h6': (256, 'c3823f0b', '42fe8c1e0f54b3f968a630dd564a8941410c5d86'),
    'n1': (256, '82d7d25f', 'd4b3a6655f91647545d493c2ff996daa66df0395'),
    'c13': (32, 'f304a1fb', '0f029274bb99723ebcc271d761e1500ca50b2738'),
    'c14': (32, 'f8dbd779', '55bdaf9eb1ba6185e20512c4874ebb625861508e'),
    'd5': (32, 'e9af4217', '813e126b1263e13f1684d700c5c4bec34d063b38'),
    'n13': (32, '2e83bf80', '02fcc1e879c06759a21ef4f004fe7aa790814112'),
    'g2': (32, '5ed8cdd2', 'd193d819ad634c43d648ce49073799b4df6dfd2f'),
    'j10': (32, 'e9af4217', '813e126b1263e13f1684d700c5c4bec34d063b38'),
    'r1': (32, '5ed8cdd2', 'd193d819ad634c43d648ce49073799b4df6dfd2f'),
}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('archive', type=Path)
    ap.add_argument('--out', type=Path, default=Path('roms'))
    args = ap.parse_args()
    records = []
    # Validate everything before writing anything; only known flat names used.
    with zipfile.ZipFile(args.archive) as archive:
        data = {part: archive.read('cdi.' + part) for part in EXPECTED}
    for part, raw in data.items():
        actual = len(raw), f'{zlib.crc32(raw):08x}', hashlib.sha1(raw).hexdigest()
        if actual != EXPECTED[part]:
            raise ValueError(f'Unexpected ROM identity: cdi.{part}: {actual}')
    args.out.mkdir(exist_ok=True, parents=True)
    for part, raw in data.items():
        target = args.out / ('cdi.' + part + '.hex')
        target.write_text(''.join(f'{b:02x}\n' for b in raw), encoding='ascii')
        records.append(dict(file='cdi.' + part, size=len(raw),
                            crc32=f'{zlib.crc32(raw):08x}',
                            sha1=hashlib.sha1(raw).hexdigest(),
                            sha256=hashlib.sha256(raw).hexdigest(),
                            hex_file=target.name,
                            upper_nibble_values=sorted(set(b >> 4 for b in raw))))
    manifest = dict(archive_sha256=hashlib.sha256(args.archive.read_bytes()).hexdigest(),
                    reference='mamedev/mame chicago.cpp ab8a0bb68884bf3c2b95355abfafeb1a41fc7dd2',
                    roms=records)
    (args.out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Validated and converted {len(records)} PROMs.')

if __name__ == '__main__':
    main()
