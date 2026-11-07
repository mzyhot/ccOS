#!/usr/bin/env python3
"""Render harness captures (screens.html) to PNGs without a browser.

    render.py <screens.html> <out dir> [index ...]

Teletext cells are drawn pixel-exact; text uses ccOS's own 3x5 font
(read from gfx.lua), upper-cased, so layout and colour can be judged.
"""
import json, os, re, struct, sys, zlib

HERE = os.path.dirname(os.path.abspath(__file__))
CW, CH, SCALE = 6, 9, 2

def load_font():
    src = open(os.path.join(HERE, "..", "src", "ccos", "lib", "gfx.lua")).read()
    font = {}
    for key, rows in re.findall(r'(?:\[\"(.)\"\]|([A-Z]))\s*=\s*\{([^}]*)\}', src) and []:
        pass
    for m in re.finditer(r'(?:\["(.)"\]|\b([A-Z]))\s*=\s*\{\s*("[01]+"(?:\s*,\s*"[01]+"){4})\s*\}', src):
        ch = m.group(1) or m.group(2)
        font[ch] = re.findall(r'"([01]+)"', m.group(3))
    return font

FONT = load_font()

def load_caps(path):
    caps = []
    for m in re.finditer(r'CAPS\.push\(\{label:"((?:[^"\\]|\\.)*)",w:(\d+),h:(\d+),pal:\[([^\]]*)\],rows:\[(.*?)\]\}\)</script>', open(path, encoding="utf-8").read()):
        rows = json.loads("[" + m.group(5) + "]")
        caps.append({"label": m.group(1), "w": int(m.group(2)), "h": int(m.group(3)),
                     "pal": [int(v) for v in m.group(4).split(",")], "rows": rows})
    return caps

def png(path, w, h, pixels):
    raw = b"".join(b"\x00" + bytes(pixels[y * w * 3:(y + 1) * w * 3]) for y in range(h))
    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))

def render(cap, path):
    W, H = cap["w"] * CW * SCALE, cap["h"] * CH * SCALE
    px = bytearray(W * H * 3)
    pal = [((v >> 16) & 255, (v >> 8) & 255, v & 255) for v in cap["pal"]]

    def rect(x, y, w, h, c):
        r, g, b = c
        for yy in range(y * SCALE, (y + h) * SCALE):
            row = yy * W * 3
            for xx in range(x * SCALE, (x + w) * SCALE):
                i = row + xx * 3
                px[i], px[i + 1], px[i + 2] = r, g, b

    for cy, (codes, fg, bg) in enumerate(cap["rows"]):
        for cx, ch in enumerate(codes):
            x0, y0 = cx * CW, cy * CH
            f, b = pal[int(fg[cx], 16)], pal[int(bg[cx], 16)]
            rect(x0, y0, CW, CH, b)
            if 128 <= ch < 160:
                bits = ch - 128
                for i in range(5):
                    if bits & (1 << i):
                        rect(x0 + (i % 2) * 3, y0 + (i // 2) * 3, 3, 3, f)
            elif ch != 32:
                c = chr(ch).upper() if 32 < ch < 127 else None
                glyph = FONT.get(c) if c else None
                if glyph:
                    gw = len(glyph[0])
                    ox = x0 + (CW - gw) // 2
                    for r, line in enumerate(glyph):
                        for k, bit in enumerate(line):
                            if bit == "1":
                                rect(ox + k, y0 + 2 + r, 1, 1, f)
                elif ch in (183, 7):
                    rect(x0 + 2, y0 + 4, 2, 1, f)
                elif ch == 140:
                    rect(x0, y0 + 4, CW, 1, f)
                elif ch == 149:
                    rect(x0, y0, 3, CH, f)
                else:
                    rect(x0 + 1, y0 + 3, CW - 2, 3, f)
    png(path, W, H, px)

def main():
    html, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    caps = load_caps(html)
    which = [int(a) for a in sys.argv[3:]] or range(len(caps))
    for i in which:
        p = os.path.join(out, "cap_%02d.png" % i)
        render(caps[i], p)
        print(i, caps[i]["label"], p)

if __name__ == "__main__":
    main()
