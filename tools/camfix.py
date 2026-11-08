"""Deadlock camera fix for skins built before the 2026-10-16 update.

python -I camfix.py <mod.vmdl_c> <vanilla.vmdl_c> <out.vmdl_c>

That update turned every hero's root_motion attachment frame by 120 degrees
(standing_pivot rotation (-.5,-.5,-.5,.5) -> identity). Old skins keep the old
frame, so the camera sits in the wrong place. Same math as Deadlock Mod Manager
(apps/desktop/src-tauri/.../camera_attachment_frame.rs): for every attachment
bound only to root_motion, offset (x,y,z) -> (z,x,y) and rotation q -> convert(q).

Only numbers inside the MDAT (render mesh) KV3 blocks change. Values are written
back into the same lane slots, so every other byte of the KV3 data stays as it was;
the buffer is re-wrapped as a literal-only LZ4 block and the resource blocks are
re-laid out with the original 16-byte alignment.
"""
import math, struct, sys

# ---------- LZ4 block ----------

def lz4_decompress(src, size):
    out = bytearray(); i = 0; n = len(src)
    while i < n:
        tok = src[i]; i += 1
        lit = tok >> 4
        if lit == 15:
            while True:
                b = src[i]; i += 1; lit += b
                if b != 255: break
        out += src[i:i + lit]; i += lit
        if i >= n: break
        off = src[i] | (src[i + 1] << 8); i += 2
        ml = tok & 15
        if ml == 15:
            while True:
                b = src[i]; i += 1; ml += b
                if b != 255: break
        ml += 4
        start = len(out) - off
        assert off > 0 and start >= 0, "bad lz4 offset"
        for k in range(ml):
            out.append(out[start + k])
    assert len(out) == size, (len(out), size)
    return out


def lz4_literal_block(data):
    """A valid LZ4 block made of one literal-only sequence."""
    n = len(data); out = bytearray()
    if n >= 15:
        out.append(0xF0); r = n - 15
        while r >= 255: out.append(255); r -= 255
        out.append(r)
    else:
        out.append(n << 4)
    out += data
    return bytes(out)

# ---------- KV3 v5 ----------

NULL, BOOLEAN, INT64, UINT64, DOUBLE, STRING, BLOB, ARRAY, OBJECT, ARRAY_TYPED, INT32, UINT32, \
    B_TRUE, B_FALSE, I64_0, I64_1, D_0, D_1, FLOAT, INT16, UINT16, INT8, UINT8, ARR_BYTELEN, ARR_AUX, U32_0, U32_1 = range(1, 28)
WIDTH = {BOOLEAN: 1, INT8: 1, UINT8: 1, INT16: 2, UINT16: 2, INT32: 4, UINT32: 4, FLOAT: 4,
         INT64: 8, UINT64: 8, DOUBLE: 8}
FMT = {BOOLEAN: '<B', INT8: '<b', UINT8: '<B', INT16: '<h', UINT16: '<H', INT32: '<i', UINT32: '<I',
       FLOAT: '<f', INT64: '<q', UINT64: '<Q', DOUBLE: '<d'}
CONST = {NULL: None, B_TRUE: True, B_FALSE: False, I64_0: 0, I64_1: 1, D_0: 0.0, D_1: 1.0, U32_0: 0, U32_1: 1}

HDR = struct.Struct('<I16sIHHiiiiHHiiiiiiiiiiiiiiiiii')
H_NAMES = ('magic guid comp dict frame cb1 cb4 cb8 ctypes cobj carr unc_total comp_total cblocks sblobs '
           'cb2 sblocksizes unc1 comp1 unc2 comp2 cb1b2 cb2b2 cb4b2 cb8b2 cnodes cobjb2 carr2 carrel').split()


def align(x, a): return (x + a - 1) // a * a


class Num:
    """A number with where it lives: lane (buf, offset, type) and its own type byte (or None if packed)."""
    __slots__ = ('v', 't', 'buf', 'off', 'tpos')
    def __init__(s, v, t, buf, off, tpos): s.v, s.t, s.buf, s.off, s.tpos = v, t, buf, off, tpos
    def __repr__(s): return repr(s.v)


class Lanes:
    def __init__(s, buf, o1, o2, o4, o8):
        s.buf = buf; s.pos = {1: o1, 2: o2, 4: o4, 8: o8}
    def take(s, w):
        p = s.pos[w]; s.pos[w] += w; return p


class KV3:
    def __init__(s, raw):
        h = dict(zip(H_NAMES, HDR.unpack_from(raw, 0)))
        assert h['magic'] == 0x4B563305, hex(h['magic'])
        assert h['cblocks'] == 0, "binary blobs not supported"
        s.h, s.raw = h, raw
        p = HDR.size
        if h['comp'] == 0:   # uncompressed blocks may leave the compressed sizes at 0
            h['comp1'] = h['comp1'] or h['unc1']; h['comp2'] = h['comp2'] or h['unc2']
        c1 = raw[p:p + h['comp1']]; c2 = raw[p + h['comp1']:p + h['comp1'] + h['comp2']]
        s.tail = raw[p + h['comp1'] + h['comp2']:]
        if h['comp'] == 1:
            s.b1 = lz4_decompress(c1, h['unc1']); s.b2 = lz4_decompress(c2, h['unc2'])
        elif h['comp'] == 0:
            s.b1 = bytearray(c1); s.b2 = bytearray(c2)
        else:
            raise SystemExit("zstd KV3 not supported")
        # buffer 1: strings in bytes1, then aux lanes
        o = 0; o1 = o; o += h['cb1']
        o2 = align(o, 2) if h['cb2'] else o; o = o2 + h['cb2'] * 2
        o4 = align(o, 4) if h['cb4'] else o; o = o4 + h['cb4'] * 4
        o8 = align(o, 8) if h['cb8'] else o; o = o8 + h['cb8'] * 8
        nstr = struct.unpack_from('<i', s.b1, o4)[0]
        s.strings = []; q = o1
        for _ in range(nstr):
            e = s.b1.index(0, q); s.strings.append(s.b1[q:e].decode('utf-8', 'replace')); q = e + 1
        s.aux = Lanes(s.b1, q, o2, o4 + 4, o8)
        # buffer 2
        o = h['cobjb2'] * 4; s.objlen = 0
        p1 = o; o += h['cb1b2']
        p2 = align(o, 2) if h['cb2b2'] else o; o = p2 + h['cb2b2'] * 2
        p4 = align(o, 4) if h['cb4b2'] else o; o = p4 + h['cb4b2'] * 4
        p8 = align(o, 8) if h['cb8b2'] else o; o = p8 + h['cb8b2'] * 8
        s.main = Lanes(s.b2, p1, p2, p4, p8)
        s.tpos = o; s.tend = o + h['ctypes']
        assert struct.unpack_from('<I', s.b2, s.tend)[0] == 0xFFEEDD00, "types trailer"
        t, _ = s.rtype()
        s.root = s.value(t, s.main)
        assert s.tpos == s.tend, (s.tpos, s.tend)

    def rtype(s):
        at = s.tpos; b = s.b2[s.tpos]; s.tpos += 1
        if b & 0x80: s.tpos += 1
        if b & 0x40: s.tpos += 1
        return b & 0x3F, at

    def scalar(s, t, lane, tpos):
        w = WIDTH[t]; off = lane.take(w)
        return Num(struct.unpack_from(FMT[t], lane.buf, off)[0], t, lane.buf, off, tpos)

    def value(s, t, lane, tpos=None):
        if t in CONST: return Num(CONST[t], t, None, None, tpos)
        if t in WIDTH: return s.scalar(t, lane, tpos)
        m = s.main
        if t == STRING:
            i = struct.unpack_from('<i', m.buf, m.take(4))[0]
            return s.strings[i] if 0 <= i < len(s.strings) else ''
        if t == ARRAY:
            n = struct.unpack_from('<i', m.buf, m.take(4))[0]
            out = []
            for _ in range(n):
                et, ep = s.rtype(); out.append(s.value(et, m, ep))
            return out
        if t in (ARRAY_TYPED, ARR_BYTELEN, ARR_AUX):
            if t == ARRAY_TYPED: n = struct.unpack_from('<i', m.buf, m.take(4))[0]
            else: n = m.buf[m.take(1)]
            st, sp = s.rtype()
            el = s.aux if t == ARR_AUX else m
            return [s.value(st, el, None) for _ in range(n)]   # packed: no own type byte
        if t == OBJECT:
            n = struct.unpack_from('<i', s.b2, s.objlen)[0]; s.objlen += 4
            out = {}
            for _ in range(n):
                et, ep = s.rtype()
                k = s.strings[struct.unpack_from('<i', m.buf, m.take(4))[0]]
                out[k] = s.value(et, m, ep)
            return out
        raise ValueError("KV3 type %d" % t)

    def encode(s):
        h = dict(s.h)
        c1 = lz4_literal_block(bytes(s.b1)) if h['comp'] == 1 else bytes(s.b1)
        c2 = lz4_literal_block(bytes(s.b2)) if h['comp'] == 1 else bytes(s.b2)
        h['comp1'], h['comp2'] = len(c1), len(c2)
        h['comp_total'] = len(c1) + len(c2)
        return HDR.pack(*[h[k] for k in H_NAMES]) + c1 + c2 + s.tail


def set_vec(nums, new):
    """Write new numbers into the slots the old ones used. Each element keeps its lane;
    elements with their own type byte may switch between a stored value and DOUBLE_ZERO/ONE."""
    assert len(nums) == len(new)
    if all(n.tpos is None for n in nums):           # packed typed array: same type, same slots
        for n, v in zip(nums, new):
            struct.pack_into(FMT[n.t], n.buf, n.off, v)
        return
    stored = [n for n in nums if n.buf is not None]
    if not stored:
        raise ValueError("no stored slots")
    kinds = {n.t for n in stored}
    assert len(kinds) == 1 and kinds <= {DOUBLE, FLOAT}, kinds
    kind = kinds.pop(); width = WIDTH[kind]
    assert all(n.tpos is not None for n in nums)
    assert all(n.t in (DOUBLE, FLOAT, D_0, D_1) for n in nums)
    slots = sorted(n.off for n in stored)          # consecutive slots of one lane, read in element order
    assert slots == list(range(slots[0], slots[0] + width * len(slots), width)), slots
    buf = stored[0].buf
    # choose which new values need a stored slot; pad with explicit 0/1 if fewer than the slots
    need = [not (v == 0.0 or v == 1.0) for v in new]
    extra = len(slots) - sum(need)
    if extra < 0: raise ValueError("more stored values than slots")
    for i in range(len(new)):
        if extra and not need[i]: need[i] = True; extra -= 1
    k = 0
    for n, v, st in zip(nums, new, need):
        tb = n.buf  # unused
        if st:
            struct.pack_into(FMT[kind], buf, slots[k], v); k += 1; newt = kind
        else:
            newt = D_0 if v == 0.0 else D_1
        b2 = KV3_CUR.b2
        b2[n.tpos] = (b2[n.tpos] & 0xC0) | newt

# ---------- quaternion math (from Deadlock Mod Manager) ----------

OLD = (-0.5, -0.5, -0.5, 0.5); IDENT = (0.0, 0.0, 0.0, 1.0); TOL = math.pi / 6

def convert(q):
    x, y, z, w = q
    return ((x + w + z - y) * .5, (y + w + x - z) * .5, (z + w + y - x) * .5, (w - x - y - z) * .5)

def angle(a, b):
    na = math.sqrt(sum(v * v for v in a)); nb = math.sqrt(sum(v * v for v in b))
    if abs(na - 1) > 1e-3 or abs(nb - 1) > 1e-3: return None
    d = sum(x * y for x, y in zip(a, b)) / (na * nb)
    return 2 * math.acos(min(1.0, abs(d)))

def f32(v): return struct.unpack('<f', struct.pack('<f', v))[0]

# ---------- resource container ----------

def blocks(data):
    fsize, hver, ver, boff, bcount = struct.unpack_from('<IHHII', data, 0)
    tab = 8 + boff; out = []
    for i in range(bcount):
        e = tab + i * 12
        kind = data[e:e + 4].decode('ascii'); rel, size = struct.unpack_from('<II', data, e + 4)
        out.append([kind, e + 4 + rel, size, e])
    return out

def rebuild(data, replace):
    bl = blocks(data)
    head = bytearray(data[:min(b[1] for b in bl)])
    body = bytearray(); pos = len(head)
    for i, (kind, off, size, e) in enumerate(bl):
        blob = replace.get(i, data[off:off + size])
        pad = align(pos, 16) - pos; body += b'\0' * pad; pos += pad
        struct.pack_into('<II', head, e + 4, pos - (e + 4), len(blob))
        body += blob; pos += len(blob)
    out = head + body
    struct.pack_into('<I', out, 0, len(out))
    return bytes(out)

# ---------- main ----------

KV3_CUR = None

def attachments(mesh):
    for item in mesh.get('m_attachments', []):
        yield item['key'], item['value']

def root_only(v):
    names = v['m_influenceNames']
    return (v['m_nInfluences'].v == 1 and names and names[0] == 'root_motion'
            and all(n == '' for n in names[1:]) and v['m_bInfluenceRootTransform'][0].v is False)

def pivot_rot(mesh, name):
    for k, v in attachments(mesh):
        if k == name: return tuple(n.v for n in v['m_vInfluenceRotations'][0])
    return None

def skeleton_root(kv):
    sk = kv.root.get('m_modelSkeleton') or {}
    names = sk.get('m_boneName', [])
    if 'root_motion' not in names: return None
    i = names.index('root_motion')
    return (sk['m_nParent'][i].v, tuple(n.v for n in sk['m_boneRotParent'][i]))

def main():
    global KV3_CUR
    src, base, dst = sys.argv[1:4]
    data = open(src, 'rb').read(); van = open(base, 'rb').read()
    # root_motion must be a root bone with the same rotation as the game's, or the conversion is wrong
    def data_kv(d):
        for i, (kind, off, size, e) in enumerate(blocks(d)):
            if kind == 'DATA': return KV3(bytearray(d[off:off + size]))
    a, b = skeleton_root(data_kv(data)), skeleton_root(data_kv(van))
    print("root_motion mod:", a, " game:", b)
    if not a or not b or a[0] != -1 or b[0] != -1 or angle(a[1], b[1]) is None or angle(a[1], b[1]) > 0.001:
        raise SystemExit("root_motion differs from the game; not touching this model")
    replace = {}; changed = 0
    for i, (kind, off, size, e) in enumerate(blocks(data)):
        if kind != 'MDAT': continue
        kv = KV3(bytearray(data[off:off + size])); KV3_CUR = kv
        piv = [pivot_rot(kv.root, n) for n in ('standing_pivot', 'crouching_pivot')]
        piv = [p for p in piv if p]
        if not piv:
            print(f"MDAT#{i}: no pivots, skipped"); continue
        old = [p for p in piv if angle(p, OLD) is not None and angle(p, OLD) <= TOL]
        if not old:
            print(f"MDAT#{i}: pivots already in the new frame, skipped"); continue
        if len(old) != len(piv):
            raise SystemExit(f"MDAT#{i}: mixed pivot frames, not touching")
        n = 0
        for k, v in attachments(kv.root):
            if 'root_motion' not in v['m_influenceNames']: continue
            if not root_only(v): raise SystemExit(f"{k}: blended root attachment, needs the author")
            rot = v['m_vInfluenceRotations'][0]; ofs = v['m_vInfluenceOffsets'][0]
            q = tuple(x.v for x in rot)
            if abs(math.sqrt(sum(c * c for c in q)) - 1) > 1e-3: raise SystemExit(f"{k}: bad quaternion")
            x, y, z = (o.v for o in ofs)
            nq = tuple(f32(c) if rot[0].t == FLOAT else c for c in convert(q))
            nq = tuple(0.0 if abs(c) < 1e-7 else c for c in nq)
            set_vec(ofs, (z, x, y)); set_vec(rot, nq)
            if k in ('standing_pivot', 'crouching_pivot'):
                print(f"  {k}: ofs ({x:.3f},{y:.3f},{z:.3f}) -> ({z:.3f},{x:.3f},{y:.3f})  rot {q} -> {tuple(round(c, 4) for c in nq)}")
            n += 1
        enc = kv.encode()
        chk = KV3(bytearray(enc))   # re-read what we wrote
        for k, v in attachments(chk.root):
            if k == 'standing_pivot':
                r = tuple(c.v for c in v['m_vInfluenceRotations'][0])
                assert angle(r, IDENT) < 1e-3, r
        replace[i] = enc; changed += n
        print(f"MDAT#{i}: {n} root attachments converted")
    if not replace:
        raise SystemExit("nothing to fix")
    open(dst, 'wb').write(rebuild(data, replace))
    print(f"wrote {dst} ({changed} attachments)")

if __name__ == '__main__':
    main()
