"""python -I vpkdrop.py <in.vpk> <out.vpk> <path_to_drop | @listfile>...
Rewrites a single-file VPK v2 tree without the given entries; file data is copied unchanged."""
import struct, sys

src, dst = sys.argv[1], sys.argv[2]
drop = set()
for a in sys.argv[3:]:
    if a.startswith("@"):  # @list.txt: one path per line (too many paths for the command line)
        drop |= {l.strip().lower() for l in open(a[1:], encoding="utf-8") if l.strip()}
    else:
        drop.add(a.lower())
data = open(src, "rb").read()
sig, ver, tree_size = struct.unpack_from("<3I", data, 0)
assert sig == 0x55AA1234 and ver in (1, 2), (hex(sig), ver)
if ver == 2:
    data_size, amd5, omd5, sigsz = struct.unpack_from("<4I", data, 12)
    print(f"header: v2 tree={tree_size} data={data_size} archive_md5={amd5} other_md5={omd5} sig={sigsz}")
    hdr_size = 28
else:
    hdr_size = 12
    data_size = len(data) - hdr_size - tree_size  # v1: file data runs to the end
    print(f"header: v1 tree={tree_size} data={data_size}")
pos = hdr_size

def cstr():
    global pos
    end = data.index(b"\0", pos)
    s = data[pos:end]
    pos = end + 1
    return s

tree = {}  # ext -> dir -> [(name, entry bytes)]
dropped = []
while (ext := cstr()):
    while (d := cstr()):
        while (n := cstr()):
            pre = struct.unpack_from("<H", data, pos + 4)[0]
            entry = data[pos:pos + 18 + pre]
            assert struct.unpack_from("<H", data, pos + 6)[0] == 0x7FFF, "multi-archive vpk not supported"
            pos += 18 + pre
            full = ((d.decode() + "/") if d.strip() else "") + n.decode() + "." + ext.decode()
            if full.lower() in drop:
                dropped.append(full)
                continue
            tree.setdefault(ext, {}).setdefault(d, []).append((n, entry))
assert pos == hdr_size + tree_size
assert len(dropped) == len(drop), f"not found: {drop - {x.lower() for x in dropped}}"

out = bytearray()
for ext, dirs in tree.items():
    out += ext + b"\0"
    for d, files in dirs.items():
        out += d + b"\0"
        for n, entry in files:
            out += n + b"\0" + entry
        out += b"\0"
    out += b"\0"
out += b"\0"

blob = data[hdr_size + tree_size: hdr_size + tree_size + data_size]
# MD5 / signature sections would no longer match the new tree, so leave them out.
if ver == 2:
    hdr = struct.pack("<7I", sig, ver, len(out), data_size, 0, 0, 0)
else:
    hdr = struct.pack("<3I", sig, ver, len(out))
open(dst, "wb").write(hdr + bytes(out) + blob)
print("dropped:", *dropped, sep="\n  ")
