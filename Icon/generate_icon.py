#!/usr/bin/env python3
"""StreamWall のプレースホルダーアイコン（1024x1024 PNG）を生成する。

外部依存なし（標準ライブラリの zlib / struct のみ）。
本番では Icon/icon.png を好きな 1024x1024 の画像に差し替えてください。
"""
import struct
import zlib

SIZE = 1024


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def rounded_alpha(x, y, size, radius):
    """角丸矩形の内側なら 255、外側なら 0、境界はアンチエイリアス。"""
    cx = min(max(x, radius), size - radius)
    cy = min(max(y, radius), size - radius)
    dx = x - cx
    dy = y - cy
    dist = (dx * dx + dy * dy) ** 0.5
    if dist <= radius - 1:
        return 255
    if dist >= radius + 1:
        return 0
    return int(255 * (radius + 1 - dist) / 2)


def in_triangle(px, py, tri):
    (x1, y1), (x2, y2), (x3, y3) = tri

    def sign(ax, ay, bx, by, cx, cy):
        return (ax - cx) * (by - cy) - (bx - cx) * (ay - cy)

    d1 = sign(px, py, x1, y1, x2, y2)
    d2 = sign(px, py, x2, y2, x3, y3)
    d3 = sign(px, py, x3, y3, x1, y1)
    has_neg = (d1 < 0) or (d2 < 0) or (d3 < 0)
    has_pos = (d1 > 0) or (d2 > 0) or (d3 > 0)
    return not (has_neg and has_pos)


def build():
    top = (0x4F, 0x46, 0xE5)     # indigo
    bottom = (0x7C, 0x3A, 0xED)  # violet
    radius = int(SIZE * 0.225)   # macOS 風の角丸

    # 中央の再生三角形
    cx, cy = SIZE / 2, SIZE / 2
    r = SIZE * 0.20
    tri = [
        (cx - r * 0.6, cy - r),
        (cx - r * 0.6, cy + r),
        (cx + r, cy),
    ]

    rows = bytearray()
    for y in range(SIZE):
        rows.append(0)  # filter type 0
        t = y / (SIZE - 1)
        base = lerp(top, bottom, t)
        for x in range(SIZE):
            a = rounded_alpha(x, y, SIZE, radius)
            if a and in_triangle(x, y, tri):
                rows += bytes((255, 255, 255, a))
            else:
                rows += bytes((base[0], base[1], base[2], a))

    raw = zlib.compress(bytes(rows), 9)
    return raw


def chunk(tag, data):
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


def main():
    idat = build()
    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)  # 8-bit RGBA
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", idat)
        + chunk(b"IEND", b"")
    )
    with open("Icon/icon.png", "wb") as f:
        f.write(png)
    print("wrote Icon/icon.png (%dx%d)" % (SIZE, SIZE))


if __name__ == "__main__":
    main()
