"""python -I vpkread.py <file.vpk> [name_to_print]  -> list entries, or print one small single-file-archive entry."""
import struct, sys

sys.stdout.reconfigure(encoding="utf-8")

path = sys.argv[1]
data = open(path, "rb").read()
sig, ver, tree = struct.unpack_from("<III", data, 0)
hdr = 12 if ver == 1 else 28
pos = hdr

def cstr():
    global pos
    end = data.index(b"\0", pos)
    s = data[pos:end].decode("utf-8", "replace")
    pos = end + 1
    return s

entries = []
while True:
    ext = cstr()
    if not ext: break
    while True:
        d = cstr()
        if not d: break
        while True:
            n = cstr()
            if not n: break
            crc, pre, arc, off, ln, term = struct.unpack_from("<IHHIIH", data, pos)
            pos += 18
            preload = data[pos:pos + pre]; pos += pre
            full = (d.strip() + "/" if d.strip() else "") + n + "." + ext
            entries.append((full, arc, off, ln, preload))

base = hdr + tree
if len(sys.argv) > 2:
    for full, arc, off, ln, preload in entries:
        if full.lower() == sys.argv[2].lower():
            body = preload + (data[base + off: base + off + ln] if arc == 0x7FFF else b"")
            print(body.decode("utf-8", "replace"))
else:
    print(f"v{ver}, {len(entries)} entries")
    for e in entries:
        print(" ", e[0], e[3] + len(e[4]))
