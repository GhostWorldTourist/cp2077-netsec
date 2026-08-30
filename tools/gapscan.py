"""
NetSec gap scanner - find map tiles that hold gateable devices but no access point.

Reads .streamingsector files as RAW BYTES. Depot paths survive uncompressed in the
CR2W header, so this needs no serialization: 148 sectors in about a second, where
`convert serialize` would be ~3s and 3.6MB of JSON each.

A tile is named by its sector: exterior_<x>_<y>_<level>_<variant>.

DO NOT TRUST THE COORDINATES THIS PRINTS as world positions. Sectors come in
more than one size and the name does not say which: exterior_-8_10_0_0 is a
128m grid (its content sits around -1019, 1380, exactly where 128 predicts),
while exterior_-17_20_0_0 holds content at about -1074, 1284 - which only makes
sense on a 64m grid. Multiplying the tile index by any single constant is
therefore wrong for some fraction of the map, and it was wrong on the first
location this tool was ever used to find.

The tile figures below are kept because they are a stable IDENTIFIER and are
fine for sorting, grouping and neighbourhood tests. To get a real position,
serialize the sector and read node positions out of nodeData:

    WolvenKit.CLI.exe convert serialize <sector> -o <dir>

That is authoritative, and it is the only thing that should ever be handed to
somebody as a place to go.
"""
import re, sys, os, json, collections

SECTOR_RE = re.compile(r'^(exterior|interior|quest)_(-?\d+)_(-?\d+)_(-?\d+)_(\d+)\.streamingsector$')
PATH_RE   = re.compile(rb'[\x20-\x7E]{10,}')
TILE      = 128.0

# NetSec never gates these, so their presence is not evidence of a gap.
#   vending machines - the corner shop, explicitly exempt in Devices.reds
#   vehicles         - Vehicle Security Rework owns them
EXEMPT = ('vending_machines',)

# Things NetSec DOES gate, grouped so the report says what kind of hole it is.
FAMILIES = {
    'security':   ('cameras', 'turrets', 'security'),
    'access':     ('doors', 'elevator', 'locks'),
    'terminal':   ('computers', 'terminals', 'datatermina', 'netrunner'),
    'utility':    ('fuse', 'electric', 'maintenance', 'generator'),
    'comms':      ('antenna', 'intercom', 'radio', 'speaker', 'distraction'),
    'ad':         ('advertising', 'street_signs'),
    'light':      ('lighting',),
}

def family(path):
    low = path.lower()
    for fam, keys in FAMILIES.items():
        if any(k in low for k in keys):
            return fam
    return 'other'

def scan(root):
    rows = []
    for dirpath, _, files in os.walk(root):
        for fn in files:
            m = SECTOR_RE.match(fn)
            if not m:
                continue
            kind, tx, ty, level, variant = m.group(1), int(m.group(2)), int(m.group(3)), int(m.group(4)), int(m.group(5))
            raw = open(os.path.join(dirpath, fn), 'rb').read()
            paths = {s.decode() for s in PATH_RE.findall(raw) if b'.ent' in s and b'\\' in s}

            aps      = [p for p in paths if 'access_points' in p]
            devices  = [p for p in paths if '\\devices\\' in p.lower()]
            gateable = [p for p in devices
                        if not any(e in p.lower() for e in EXEMPT)
                        and 'access_points' not in p]

            rows.append(dict(
                file=fn, kind=kind, tx=tx, ty=ty, level=level, variant=variant,
                # NOT a world position - see the module docstring. Kept only
                # as a rough locator for sorting and neighbourhood tests.
                cx=tx * TILE + TILE / 2, cy=ty * TILE + TILE / 2,
                aps=sorted(aps), devices=sorted(devices), gateable=sorted(gateable),
                families=sorted({family(p) for p in gateable}),
            ))
    return rows

# A street lamp is gateable and nobody cares. Weight the families by whether a
# netrunner would ever have a reason to be on that network, so the worklist is
# ranked by "should this be defended" and not by "how much furniture is here".
WEIGHT = {'security': 5, 'terminal': 5, 'utility': 3, 'comms': 3,
          'access': 2, 'other': 1, 'ad': 0, 'light': 0}

def score(row):
    return sum(WEIGHT[family(p)] for p in row['gateable'])

if __name__ == '__main__':
    root = sys.argv[1]
    rows = scan(root)
    for r in rows:
        r['score'] = score(r)

    # A NETWORK DOES NOT STOP AT A TILE EDGE, and treating it as though it does
    # is how this scan manufactures gaps that are not gaps. A camera in one tile
    # is routinely wired to an access point in the tile next door - the sector
    # grid is a streaming convenience, not a network boundary.
    #
    # So coverage is judged over the 3x3 neighbourhood: a tile counts as served
    # if it, or any tile touching it, holds an access point. At 128m tiles that
    # is a 384m box, comfortably wider than any real network and wider than
    # NetSec's own 50m adoption radius - which biases toward calling a tile
    # covered. That is the right direction to be wrong in: a missed gap costs
    # nothing, a false one costs a placement trip.
    have_ap = {(r['tx'], r['ty'], r['level']) for r in rows if r['aps']}
    for r in rows:
        r['ap_nearby'] = any((r['tx'] + dx, r['ty'] + dy, r['level']) in have_ap
                             for dx in (-1, 0, 1) for dy in (-1, 0, 1))

    gaps = [r for r in rows if not r['ap_nearby'] and r['score'] > 0]
    gaps.sort(key=lambda r: (-r['score'], r['tx'], r['ty']))

    isolated = [r for r in rows if not r['aps'] and r['ap_nearby'] and r['score'] > 0]

    print(f"scanned {len(rows)} sectors")
    print(f"  with an access point   : {sum(1 for r in rows if r['aps'])}")
    print(f"  with gateable devices  : {sum(1 for r in rows if r['gateable'])}")
    print(f"  served by a neighbour  : {len(isolated)}  (no AP of their own - not gaps)")
    print(f"  GAPS worth filling     : {len(gaps)}")
    print()
    print("tile indices below are identifiers, NOT world coordinates - serialize")
    print("the sector and read nodeData to get a position worth walking to.
")
    print(f"{'tile':>12}  {'approx (x,y)':>18}  {'score':>5} {'n':>3}  families")
    for r in gaps[:20]:
        print(f"{r['tx']:>5},{r['ty']:<6}  {r['cx']:>8.0f},{r['cy']:<8.0f}  {r['score']:>5} {len(r['gateable']):>3}  {','.join(f for f in r['families'] if WEIGHT[f])}")

    out = os.path.join(os.path.dirname(root), 'gapscan.json')
    json.dump(rows, open(out, 'w', encoding='utf-8'), indent=1)
    print(f"\nfull results -> {out}")

    fam = collections.Counter(f for r in gaps for f in r['families'])
    print("\ngap families:", dict(fam.most_common()))
