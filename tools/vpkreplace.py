"""python -I vpkreplace.py <in.vpk> <out.vpk> <entry/path.ext> <new_file> [<entry> <file>]...
Replaces files inside a single-file VPK (v1/v2). The new data is appended after the existing
file data and the entries are re-pointed; the tree keeps its size. Old bytes stay as dead data.
MD5/signature sections are dropped (they would no longer match), like vpkdrop.py."""
import struct, sys, zlib

src, dst = sys.argv[1], sys.argv[2]
pairs = sys.argv[3:]
repl = {pairs[i].lower(): open(pairs[i + 1], 'rb').read() for i in range(0, len(pairs), 2)}

data = bytearray(open(src, 'rb').read())
sig, ver, tree_size = struct.unpack_from('<3I', data, 0)
assert sig == 0x55AA1234 and ver in (1, 2), (hex(sig), ver)
if ver == 2:
    data_size = struct.unpack_from('<I', data, 12)[0]; hdr = 28
else:
    hdr = 12; data_size = len(data) - hdr - tree_size
pos = hdr

def cstr():
    global pos
    e = data.index(0, pos); s = bytes(data[pos:e]); pos = e + 1; return s

blob = bytearray(data[hdr + tree_size: hdr + tree_size + data_size])
done = []
while (ext := cstr()):
    while (d := cstr()):
        while (n := cstr()):
            crc, pre, arc, off, ln, term = struct.unpack_from('<IHHIIH', data, pos)
            assert arc == 0x7FFF, "multi-archive vpk not supported"
            full = ((d.decode() + '/') if d.strip() else '') + n.decode() + '.' + ext.decode()
            if full.lower() in repl:
                assert pre == 0, "preload data not supported"
                new = repl[full.lower()]
                struct.pack_into('<IHHIIH', data, pos, zlib.crc32(new) & 0xFFFFFFFF, 0, 0x7FFF, len(blob), len(new), 0xFFFF)
                blob += new; done.append(full)
            pos += 18 + pre
assert pos == hdr + tree_size
missing = set(repl) - {x.lower() for x in done}
assert not missing, f"not found: {missing}"

tree = bytes(data[hdr:hdr + tree_size])
if ver == 2:
    head = struct.pack('<7I', sig, ver, tree_size, len(blob), 0, 0, 0)
else:
    head = struct.pack('<3I', sig, ver, tree_size)
open(dst, 'wb').write(head + tree + bytes(blob))
print("replaced:", *done, sep="\n  ")
