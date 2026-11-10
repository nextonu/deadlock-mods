"""Deadlock Mods: optimeerimine (optimize.ps1). Deadlock mod VPK optimizer: textures bigger than MAX px lose their top mip levels (no re-encoding, exact data kept).
usage: vpkopt.py src.vpk dst.vpk [max=2048]   -> prints a JSON summary. src is never modified."""
import struct, sys, os, zlib, json

BLOCK = {1: 8, 2: 16, 19: 16, 20: 16, 21: 16, 27: 8}          # DXT1, DXT5, BC6H, BC7, ATI2N, ATI1N: bytes per 4x4 block
PIXEL = {4: 4, 28: 4}                                           # RGBA8888, BGRA8888: bytes per pixel

def cstr(b, p):
    e = b.index(b'\0', p)
    return b[p:e].decode('utf-8', 'surrogateescape'), e + 1

def parse(path):
    raw = open(path, 'rb').read()
    sig, ver, tree = struct.unpack_from('<III', raw, 0)
    if sig != 0x55aa1234 or ver not in (1, 2):
        raise ValueError('not a VPK')
    hdr = 28 if ver == 2 else 12
    data0 = hdr + tree
    p = hdr; items = []
    while True:
        ext, p = cstr(raw, p)
        if not ext: break
        while True:
            d, p = cstr(raw, p)
            if not d: break
            while True:
                n, p = cstr(raw, p)
                if not n: break
                crc, pre, arch, off, ln, term = struct.unpack_from('<IHHIIH', raw, p); p += 18
                preload = raw[p:p + pre]; p += pre
                if arch != 0x7fff:
                    raise ValueError('multi-archive VPK not supported')
                items.append([ext, d, n, preload + raw[data0 + off:data0 + off + ln]])
    return items

def mip_size(fmt, w, h):
    if fmt in BLOCK: return max(1, (w + 3) // 4) * max(1, (h + 3) // 4) * BLOCK[fmt]
    return w * h * PIXEL[fmt]

_masks = {}
def _avg(a, c):
    """baitide kaupa keskmine kahest võrdse pikkusega baitijadast (suured täisarvud: kiire ilma numpyta)"""
    n = len(a)
    m = _masks.get(n)
    if m is None: m = _masks[n] = int.from_bytes(b'\xfe' * n, 'little')
    x = int.from_bytes(a, 'little'); y = int.from_bytes(c, 'little')
    return ((x & y) + (((x ^ y) & m) >> 1)).to_bytes(n, 'little')

def half_pixels(px, w, h):
    """4 baiti pikslis (BGRA/RGBA), read ülevalt alla -> pool laiust ja kõrgust"""
    stride = w * 4; w2 = max(1, w // 2); h2 = max(1, h // 2); out = bytearray()
    for y in range(h2):
        r0 = px[2 * y * stride:(2 * y + 1) * stride]
        r1 = px[(2 * y + 1) * stride:(2 * y + 2) * stride] if 2 * y + 1 < h else r0
        v = memoryview(_avg(r0, r1)).cast('I')
        ev = v[0:2 * w2:2].tobytes(); od = v[1:2 * w2:2].tobytes() if w > 1 else ev
        out += _avg(ev, od)
    return bytes(out), w2, h2

def shrink_vtex(b, maxdim):
    """returns (new bytes, (w,h)->(w2,h2)) or (b, None) if left as is"""
    fsize, hv, v, boff, bcount = struct.unpack_from('<IHHII', b, 0)
    pos = 8 + boff; d0 = None; dsz = 0
    for _ in range(bcount):
        typ = b[pos:pos + 4]; ro, sz = struct.unpack_from('<II', b, pos + 4)
        if typ == b'DATA': d0 = pos + 4 + ro; dsz = sz
        pos += 12
    if d0 is None: return b, None
    ver, flags = struct.unpack_from('<HH', b, d0)
    w, h, dep = struct.unpack_from('<HHH', b, d0 + 20); fmt, mips = b[d0 + 26], b[d0 + 27]
    xo, xc = struct.unpack_from('<II', b, d0 + 32)
    if ver != 1 or dep != 1 or (flags & 0x4) or fmt not in BLOCK and fmt not in PIXEL or max(w, h) <= maxdim:
        return b, None
    # lisaandmed: tihendatud mipid / mittekahe astme suurus -> jäta puutumata (ei tea täpset paigutust)
    xp = d0 + 32 + xo
    for _ in range(xc):
        t, = struct.unpack_from('<I', b, xp)
        if t in (3, 4): return b, None
        xp += 12
    start = d0 + dsz
    if mips < 2:
        # ilma väiksemate versioonideta (nt kangelase taustapilt 4096x2312, tihendamata): päris vähendamine 2x2 keskmisega
        if fmt not in PIXEL or len(b) - start != w * h * 4: return b, None
        px = b[start:]; w0, h0 = w, h
        while max(w, h) > maxdim and w > 1 and h > 1:
            px, w, h = half_pixels(px, w, h)
        nb = bytearray(b[:start]) + px
        struct.pack_into('<HH', nb, d0 + 20, w, h)
        return bytes(nb), (w0, h0, w, h)
    sizes = []; ww, hh = w, h
    for _ in range(mips): sizes.append(mip_size(fmt, ww, hh)); ww = max(1, ww // 2); hh = max(1, hh // 2)
    if sum(sizes) != len(b) - start: return b, None          # ootamatu paigutus: ohutum mitte puutuda
    drop = 0
    while max(w >> drop, h >> drop) > maxdim and mips - drop > 1: drop += 1
    if drop == 0: return b, None
    cut = sum(sizes[:drop])                                    # suurimad mipid on lõpus
    nb = bytearray(b[:len(b) - cut])
    w2, h2 = max(1, w >> drop), max(1, h >> drop)
    struct.pack_into('<HH', nb, d0 + 20, w2, h2); nb[d0 + 27] = mips - drop
    return bytes(nb), (w, h, w2, h2)

def write(items, dst):
    tree = bytearray(); data = bytearray()
    by_ext = {}
    for ext, d, n, blob in items: by_ext.setdefault(ext, {}).setdefault(d, []).append((n, blob))
    for ext, dirs in by_ext.items():
        tree += ext.encode('utf-8', 'surrogateescape') + b'\0'
        for d, files in dirs.items():
            tree += d.encode('utf-8', 'surrogateescape') + b'\0'
            for n, blob in files:
                tree += n.encode('utf-8', 'surrogateescape') + b'\0'
                tree += struct.pack('<IHHIIH', zlib.crc32(blob) & 0xffffffff, 0, 0x7fff, len(data), len(blob), 0xffff)
                data += blob
            tree += b'\0'
        tree += b'\0'
    tree += b'\0'
    with open(dst, 'wb') as f:
        f.write(struct.pack('<IIIIIII', 0x55aa1234, 2, len(tree), len(data), 0, 0, 0))
        f.write(tree); f.write(data)

def main():
    src, dst = sys.argv[1], sys.argv[2]
    maxdim = int(sys.argv[3]) if len(sys.argv) > 3 else 2048
    items = parse(src); changed = []
    for it in items:
        if it[0] == 'vtex_c':
            nb, info = shrink_vtex(it[3], maxdim)
            if info: changed.append({'file': f"{it[1]}/{it[2]}.vtex_c", 'from': info[:2], 'to': info[2:], 'saved': len(it[3]) - len(nb)}); it[3] = nb
    # kasutamata andmed (nt eemaldatud osad, mille andmed jäid faili): mitte miski ei viita neile -> välja
    with open(src, 'rb') as f:
        sig, ver, tree = struct.unpack('<III', f.read(12))
    hdr = 28 if ver == 2 else 12
    unused = os.path.getsize(src) - hdr - tree - sum(len(it[3]) for it in items)
    compact = unused > 1_000_000
    if not changed and not compact:
        print(json.dumps({'changed': 0, 'before': os.path.getsize(src), 'after': os.path.getsize(src)})); return
    if dst == '-':
        print(json.dumps({'changed': len(changed), 'unused': max(0, unused), 'before': os.path.getsize(src), 'after': os.path.getsize(src) - sum(c['saved'] for c in changed) - max(0, unused)})); return
    write(items, dst)
    # kontroll: uus fail loeb tagasi sama failide nimekirjaga
    back = {(a[0], a[1], a[2]): a[3] for a in parse(dst)}
    want = {(a[0], a[1], a[2]): a[3] for a in items}
    if back != want:
        os.remove(dst); raise SystemExit('verify failed: rewritten VPK does not read back the same')
    print(json.dumps({'changed': len(changed) + (1 if compact else 0), 'textures_changed': len(changed), 'unused': max(0, unused), 'before': os.path.getsize(src), 'after': os.path.getsize(dst), 'textures': changed}))

if __name__ == '__main__':
    main()
