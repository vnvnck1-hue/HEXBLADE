"""HEXBLADE 아이콘을 코드로 그린다 → tools/launcher/hexblade.ico (16~256) + assets/icon/hexblade.png (게임 창 아이콘).
남보라 육각 판 · 민트 테두리 · 대각선 붉은 광선검 · 칼끝 섬광. 다시 만들기: python tools/launcher/make_icon.py
"""
import math, os
from PIL import Image, ImageDraw, ImageFilter

S = 1024
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def hexagon(cx, cy, r, rot=90):
    return [(cx + r * math.cos(math.radians(rot + 60 * i)), cy + r * math.sin(math.radians(rot + 60 * i))) for i in range(6)]


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def draw():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    c = S / 2
    # 그림자
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(sh).polygon(hexagon(c + 14, c + 26, 470), fill=(10, 8, 30, 170))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(18)))
    # 바깥 민트 테두리 → 남색 띠 → 안쪽 판(위 밝고 아래 어두운 남보라)
    d = ImageDraw.Draw(img)
    d.polygon(hexagon(c, c, 470), fill=(94, 255, 187, 255))
    d.polygon(hexagon(c, c, 440), fill=(26, 22, 58, 255))
    inner = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    grad = Image.new("RGBA", (S, S))
    gd = ImageDraw.Draw(grad)
    for y in range(S):
        gd.line([(0, y), (S, y)], fill=lerp((92, 78, 170, 255), (36, 28, 82, 255), y / S))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).polygon(hexagon(c, c, 412), fill=255)
    inner.paste(grad, (0, 0), mask)
    img.alpha_composite(inner)
    # 안쪽 얇은 육각선 (회로 느낌)
    d = ImageDraw.Draw(img)
    d.line(hexagon(c, c, 330) + [hexagon(c, c, 330)[0]], fill=(120, 110, 210, 255), width=10, joint="curve")

    # 광선검: 왼쪽 아래 손잡이 → 오른쪽 위 칼끝
    a = math.radians(-45)
    ux, uy = math.cos(a), math.sin(a)          # 칼날 방향 (오른쪽 위)
    nx, ny = -uy, ux
    hilt_c = (c - 250, c + 250)
    base = (hilt_c[0] + ux * 95, hilt_c[1] + uy * 95)
    tip = (c + 300, c - 300)

    def quad(p0, p1, w0, w1):
        return [(p0[0] + nx * w0, p0[1] + ny * w0), (p1[0] + nx * w1, p1[1] + ny * w1),
                (p1[0] - nx * w1, p1[1] - ny * w1), (p0[0] - nx * w0, p0[1] - ny * w0)]

    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.polygon(quad(base, tip, 95, 60), fill=(255, 60, 90, 210))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(34)))
    d = ImageDraw.Draw(img)
    d.polygon(quad(base, tip, 62, 30), fill=(255, 74, 96, 255))       # 붉은 칼날
    d.polygon(quad(base, tip, 30, 12), fill=(255, 226, 214, 255))       # 흰 심지
    # 손잡이
    h0 = (hilt_c[0] - ux * 90, hilt_c[1] - uy * 90)
    d.polygon(quad(h0, base, 44, 44), fill=(232, 224, 205, 255))
    d.polygon(quad(h0, base, 44, 44), outline=(20, 16, 44, 255), width=10)
    for t in (0.3, 0.55, 0.8):
        p = (h0[0] + (base[0] - h0[0]) * t, h0[1] + (base[1] - h0[1]) * t)
        d.line([(p[0] + nx * 44, p[1] + ny * 44), (p[0] - nx * 44, p[1] - ny * 44)], fill=(20, 16, 44, 255), width=10)
    # 가드 (민트)
    d.polygon(quad((base[0] - ux * 14, base[1] - uy * 14), (base[0] + ux * 14, base[1] + uy * 14), 96, 96), fill=(94, 255, 187, 255), outline=(20, 16, 44, 255), width=10)
    # 칼끝 섬광 (네 갈래 별)
    sx, sy = tip[0] - ux * 30, tip[1] - uy * 30
    star = [(sx, sy - 120), (sx + 22, sy - 22), (sx + 120, sy), (sx + 22, sy + 22), (sx, sy + 120), (sx - 22, sy + 22), (sx - 120, sy), (sx - 22, sy - 22)]
    d.polygon(star, fill=(255, 250, 235, 255))
    return img


def main():
    big = draw()
    os.makedirs(os.path.join(ROOT, "assets", "icon"), exist_ok=True)
    big.resize((256, 256), Image.LANCZOS).save(os.path.join(ROOT, "assets", "icon", "hexblade.png"))
    big.resize((512, 512), Image.LANCZOS).save(os.path.join(ROOT, "tools", "launcher", "hexblade_preview.png"))
    sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    big.resize((256, 256), Image.LANCZOS).save(os.path.join(ROOT, "tools", "launcher", "hexblade.ico"), sizes=sizes)
    print("icon written")


if __name__ == "__main__":
    main()
