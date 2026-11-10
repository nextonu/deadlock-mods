"""python -I vpkui.py <a.vpk> [b.vpk ...] -> "<arg index>\t<entry>" for every panorama layout/style/script file.
Used by the mod app to find mods whose UI files are split between mods (lower pak number wins per file)."""
import struct, sys, re

sys.stdout.reconfigure(encoding="utf-8")
UI = re.compile(r"^panorama/(layout|styles|scripts)/", re.I)

def tree(path):
    with open(path, "rb") as f:
        sig, ver, size = struct.unpack("<III", f.read(12))
        if sig != 0x55AA1234:
            return
        hdr = 12 if ver == 1 else 28
        f.seek(hdr)
        data = f.read(size)
    pos = 0
    def cstr():
        nonlocal pos
        end = data.index(b"\0", pos)
        s = data[pos:end].decode("utf-8", "replace")
        pos = end + 1
        return s
    while True:
        ext = cstr()
        if not ext: break
        while True:
            d = cstr()
            if not d: break
            while True:
                n = cstr()
                if not n: break
                pre = struct.unpack_from("<IHHIIH", data, pos)[1]
                pos += 18 + pre
                yield (d.strip() + "/" if d.strip() else "") + n + "." + ext

for i, p in enumerate(sys.argv[1:]):
    try:
        for e in tree(p):
            if UI.match(e):
                print(f"{i}\t{e}")
    except Exception as ex:
        print(f"{i}\t!error {ex}")
