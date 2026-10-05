"""claude_background_paint — 배경 첫 제작(Claude)용 핸드페인팅 텍스처 생성기. numpy + zlib 만 쓴다.

Blender 안(모델 빌드)과 일반 파이썬 양쪽에서 돌아간다. 모든 텍스처는 512px/m, 가장자리가 이어지는(타일링) 그림이다.
붓질은 '넓고 부드러운 색 변화 → 낮은 대비의 큰 붓자국 → 아주 약한 결' 순서로 칠하고, 거친 노이즈·긁힘은 쓰지 않는다.

  tile(kind, size, seed)   재질별 반복 텍스처 (purple / lilac / door / coral / dark), float32 (h, w, 3) sRGB 0..1
  floor_4m(seed)           F01 바닥 2048px(4m) — 2m 타일 네 장의 줄눈·베벨 칠·선택 마모까지 그린 월드 반복 텍스처
  save_png(path, img)      8비트 RGB PNG
"""

import math
import struct
import zlib

import numpy as np

PX_PER_M = 512


def hexc(h):
	h = h.lstrip("#")
	return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float32)


# 재질별 붓 팔레트: 바탕 · 어두운 변화 · 밝은 변화 · 보조 색(자주) — 승인 v6 기준점 #56438A/#423665/#6E4382/#CE5F54
PALETTES = {
	"purple": ("#56438A", "#4A3A7B", "#61509A", "#664585"),
	"lilac": ("#A396BE", "#968AB3", "#AEA3C8", "#A08CB8"),
	"door": ("#8873AE", "#7B67A2", "#9381B8", "#8C6FA8"),
	"coral": ("#CE5F54", "#BD5450", "#D96E5E", "#C45A5E"),
	"dark": ("#3F3462", "#372D57", "#463A6C", "#45355F"),
	# 설비실(1번 합성안) — 어두운 남색 · 파란 회색 · 보라 회색 넓은 면, 청록 탱크, 회크림 밴드, 상태등
	"navy": ("#2C3352", "#252B47", "#353D60", "#2F2D55"),
	"steel": ("#3D5880", "#344D73", "#48638E", "#41527C"),
	"slate": ("#3E3F60", "#363755", "#47496B", "#41395F"),
	"teal": ("#2E6A72", "#285F68", "#367780", "#2F636F"),
	"cream": ("#B9AF98", "#ACA28C", "#C6BDA6", "#B5A99A"),
	"lamp": ("#F1E4B2", "#EADBA4", "#F8EFC8", "#EFE2B6"),
	"deep": ("#1E2238", "#1A1D31", "#252A43", "#211F39"),
	"void": ("#0E1020", "#0B0D1A", "#121528", "#100F20"),
}


# ---------------------------------------------------------------- 반복 노이즈 / 흐림

def _freq(n):
	return np.fft.fftfreq(n)[:, None], np.fft.fftfreq(n)[None, :]


def smooth_noise(n, wavelength_px, rng):
	"""가장자리가 이어지는 부드러운 노이즈 (-1..1 근처). 흰 잡음을 FFT 가우스로 거른다."""
	w = rng.standard_normal((n, n)).astype(np.float32)
	fy, fx = _freq(n)
	sigma = 1.0 / max(wavelength_px, 1.0)
	g = np.exp(-(fx * fx + fy * fy) / (2 * sigma * sigma))
	out = np.real(np.fft.ifft2(np.fft.fft2(w) * g)).astype(np.float32)
	return out / (out.std() + 1e-6) * 0.5


def blur(img, sigma_px):
	"""가장자리가 이어지는 가우스 흐림 (채널별)."""
	if sigma_px <= 0:
		return img
	n0, n1 = img.shape[:2]
	fy = np.fft.fftfreq(n0)[:, None]
	fx = np.fft.fftfreq(n1)[None, :]
	g = np.exp(-2 * (math.pi ** 2) * (sigma_px ** 2) * (fx * fx + fy * fy))
	if img.ndim == 2:
		return np.real(np.fft.ifft2(np.fft.fft2(img) * g)).astype(np.float32)
	return np.stack([np.real(np.fft.ifft2(np.fft.fft2(img[..., c]) * g)) for c in range(img.shape[2])], -1).astype(np.float32)


def _sstep(a, b, x):
	t = np.clip((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3 - 2 * t)


# ---------------------------------------------------------------- 붓질

def strokes(img, rng, count, length, width, opacity, jitter, flow=None, palette=None):
	"""길쭉하고 끝이 가늘어지는 붓자국을 겹쳐 칠한다 (가장자리 넘어가면 반대편으로 이어짐).
	색은 그 자리 바탕색에서 명도/색을 조금 흔든 값 — 대비가 낮아 '칠한 면'으로 읽히고 얼룩으로 튀지 않는다.
	flow(y, x) -> 각도: 붓 방향장(없으면 무작위 + 약한 결)."""
	n0, n1 = img.shape[:2]
	for _ in range(count):
		cy, cx = rng.uniform(0, n0), rng.uniform(0, n1)
		L = rng.uniform(*length)
		W = rng.uniform(*width)
		ang = flow(cy, cx) + rng.normal(0, 0.22) if flow else rng.uniform(0, math.pi)
		ca, sa = math.cos(ang), math.sin(ang)
		r = int(L * 0.5 + W + 2)
		ys = np.arange(int(cy) - r, int(cy) + r + 1)
		xs = np.arange(int(cx) - r, int(cx) + r + 1)
		yy, xx = np.meshgrid(ys - cy, xs - cx, indexing="ij")
		along = xx * ca + yy * sa
		across = -xx * sa + yy * ca
		t = np.clip(along / (L * 0.5), -1, 1)
		# 붓 끝이 가늘어지는 폭 (시작은 둥글고 끝은 빠진다)
		half = W * 0.5 * (1.0 - 0.35 * np.abs(t) ** 3.0) * (1.0 - 0.15 * (t > 0) * t)
		d_end = np.abs(along) - L * 0.5
		dist = np.where(d_end > 0, np.sqrt(np.maximum(d_end, 0) ** 2 + across ** 2), np.abs(across))
		a = _sstep(half, half * 0.45, dist)
		if not np.any(a > 0.01):
			continue
		# 붓털 결: 아주 약하게 (붓자국이 과하지 않게)
		bristle = 0.95 + 0.05 * np.sin(across * (6.0 / max(W, 1.0)) * math.pi + rng.uniform(0, 6.28))
		a = a * bristle * opacity
		iy = ys % n0
		ix = xs % n1
		patch = img[np.ix_(iy, ix)]
		base = img[int(cy) % n0, int(cx) % n1]
		if palette is not None and rng.random() < 0.35:
			base = base * 0.6 + palette[rng.integers(0, len(palette))] * 0.4
		col = np.clip(base * (1.0 + rng.normal(0, jitter)) + rng.normal(0, jitter * 0.25, 3), 0, 1)
		patch = patch * (1 - a[..., None]) + col[None, None, :] * a[..., None]
		img[np.ix_(iy, ix)] = patch
	return img


def _flow_field(n, rng, wavelength):
	"""붓 방향장: 넓은 영역마다 붓이 비슷한 방향으로 흐른다 (화가가 면을 따라 칠한 느낌)."""
	f = smooth_noise(n, wavelength, rng)

	def fn(y, x):
		return math.pi * 0.25 + float(f[int(y) % n, int(x) % n]) * 1.6
	return fn


def tile(kind, size=1024, seed=1):
	"""재질 반복 텍스처. size px = size/512 m."""
	rng = np.random.default_rng(seed)
	base, dark, light, alt = (hexc(c) for c in PALETTES[kind])
	n = size
	# 1) 넓고 부드러운 색 변화 (약 1.2m · 0.4m 파장)
	t1 = _sstep(-0.9, 0.9, smooth_noise(n, 0.55 * PX_PER_M, rng))
	t2 = _sstep(-0.9, 0.9, smooth_noise(n, 0.22 * PX_PER_M, rng))
	t3 = _sstep(0.2, 1.4, smooth_noise(n, 0.7 * PX_PER_M, rng))
	img = base[None, None, :] * np.ones((n, n, 1), np.float32)
	img = img * (1 - t1[..., None] * 0.55) + dark * (t1[..., None] * 0.55)
	img = img * (1 - t2[..., None] * 0.35) + light * (t2[..., None] * 0.35)
	img = img * (1 - t3[..., None] * 0.35) + alt * (t3[..., None] * 0.35)
	# 2) 큰 붓자국 → 중간 붓자국 (낮은 대비)
	flow = _flow_field(n, rng, 0.6 * PX_PER_M)
	pal = [dark, light, alt]
	area = (n / 512.0) ** 2
	strokes(img, rng, int(110 * area), (130, 280), (70, 140), 0.36, 0.04, flow, pal)
	strokes(img, rng, int(260 * area), (50, 120), (28, 60), 0.34, 0.035, flow, pal)
	# 3) 작은 붓 끝 (결만 살짝)
	strokes(img, rng, int(120 * area), (20, 44), (10, 18), 0.18, 0.03, flow, None)
	img = blur(img, 0.9)
	return np.clip(img, 0, 1)


# ---------------------------------------------------------------- 바닥 4m

def floor_4m(seed=7):
	"""F01 바닥용 2048px = 4m 반복 텍스처. 2m 타일(1024px) 네 장이 서로 조금씩 다르다.
	타일 경계: 3px 어두운 줄눈 + 위·왼쪽 안쪽의 밝은 베벨 칠 + 아래·오른쪽의 짙은 칠, 타일 가운데는 조용하게.
	마모는 타일마다 한두 모서리에만, 코랄 테두리로 전체를 두르지 않는다."""
	rng = np.random.default_rng(seed)
	n = 2048
	T = 1024
	img = tile("purple", n, seed + 100)
	# 바닥은 전투 공간이라 더 조용하게: 붓질 대비를 40% 줄이고, 현재 전투 조명(푸른 환경광)에 덜 파랗게 보이도록
	# 아주 조금 어둡고 붉은 쪽으로 옮긴다 (기준점 #56438A 근처 유지)
	img = img * 0.6 + blur(img, 10.0) * 0.4
	img = img * 0.9 + hexc("#58407F") * 0.1
	img *= 0.94
	yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
	ly, lx = yy % T, xx % T
	d_top, d_left = ly, lx
	d_bot, d_right = (T - 1) - ly, (T - 1) - lx
	d_edge = np.minimum(np.minimum(d_top, d_bot), np.minimum(d_left, d_right))

	# 타일마다 아주 약한 명도 차 (한 장씩 따로 깐 판으로 읽히게)
	tid = (yy // T) * 2 + (xx // T)
	tone = np.array([1.0, 0.975, 0.985, 1.015], np.float32)[tid.astype(int)]
	img *= tone[..., None]

	# 칠한 부피감: 가장자리로 갈수록 조금 어둡고 가운데가 약간 밝다 (아주 넓고 약하게)
	pillow = _sstep(0, 150, d_edge)
	img *= (0.93 + 0.07 * pillow)[..., None]

	# 베벨 칠: 위·왼쪽 안쪽은 밝게, 아래·오른쪽 안쪽은 짙게 (폭 4~9px = 8~18mm)
	hi = hexc("#7D6AB4")
	lo = hexc("#3B2F64")
	edge_n = smooth_noise(n, 40, rng)          # 칠 선의 굵기가 조금씩 흔들리게
	wob = 1.5 * edge_n
	band_hi = np.maximum(_sstep(9 + wob, 3, d_top), _sstep(9 + wob, 3, d_left)) * (d_top > 1.5) * (d_left > 1.5)
	band_lo = np.maximum(_sstep(8 + wob, 2.5, d_bot), _sstep(8 + wob, 2.5, d_right))
	img = img * (1 - band_hi[..., None] * 0.5) + hi * (band_hi[..., None] * 0.5)
	img = img * (1 - band_lo[..., None] * 0.55) + lo * (band_lo[..., None] * 0.55)

	# 줄눈: 경계 3px 어두운 선
	groove = _sstep(2.2, 0.8, np.minimum(np.minimum(d_top, d_bot + 1), np.minimum(d_left, d_right + 1)))
	gcol = hexc("#2A2247")
	img = img * (1 - groove[..., None] * 0.85) + gcol * (groove[..., None] * 0.85)

	# 선택 마모: 타일마다 한두 모서리 근처에만 밝은 보라 + 코랄 조각
	wear_mask = np.zeros((n, n), np.float32)
	blob = smooth_noise(n, 34, rng)
	for ty in range(2):
		for tx in range(2):
			corners = [(0, 0), (0, 1), (1, 0), (1, 1)]
			rng.shuffle(corners)
			for (cy, cx) in corners[: rng.integers(1, 3)]:
				py = ty * T + (cy * (T - 1))
				px = tx * T + (cx * (T - 1))
				# 모서리에서 경계를 따라 퍼진 마모 (길이 60~160px, 경계 쪽으로 붙음)
				reach = rng.uniform(60, 160)
				dy = np.abs(yy - py)
				dx = np.abs(xx - px)
				m = _sstep(reach, reach * 0.3, np.maximum(dx, dy)) * _sstep(26, 6, np.minimum(dx, dy))
				wear_mask = np.maximum(wear_mask, m)
	wear = wear_mask * _sstep(0.05, 0.45, blob) * (d_edge > 2.5)
	coral = hexc("#B65A58")
	lav = hexc("#7A69AE")
	img = img * (1 - wear[..., None] * 0.55) + lav * (wear[..., None] * 0.55)
	core = wear * _sstep(0.35, 0.7, blob)
	img = img * (1 - core[..., None] * 0.5) + coral * (core[..., None] * 0.5)

	# 가운데의 넓고 약한 밝은 문질림 (몇 장에만)
	for _ in range(2):
		cy, cx = rng.uniform(0, n), rng.uniform(0, n)
		dy = np.minimum(np.abs(yy - cy), n - np.abs(yy - cy))
		dx = np.minimum(np.abs(xx - cx), n - np.abs(xx - cx))
		r = rng.uniform(140, 240)
		m = np.exp(-(dx * dx + dy * dy) / (2 * r * r)) * 0.06
		img = img * (1 - m[..., None]) + hexc("#6A58A0") * m[..., None]
	return np.clip(img, 0, 1)


# ---------------------------------------------------------------- PNG

def save_png(path, img):
	a = (np.clip(img, 0, 1) * 255.0 + 0.5).astype(np.uint8)
	h, w = a.shape[:2]
	raw = b"".join(b"\x00" + a[y].tobytes() for y in range(h))

	def chunk(t, d):
		c = struct.pack(">I", len(d)) + t + d
		return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
	png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
	png += chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b"")
	with open(path, "wb") as f:
		f.write(png)


if __name__ == "__main__":
	import os
	import sys
	import time
	out = sys.argv[1] if len(sys.argv) > 1 else "."
	os.makedirs(out, exist_ok=True)
	t0 = time.time()
	for k in PALETTES:
		save_png(os.path.join(out, "tile_%s.png" % k), tile(k, 1024, 11))
		print(k, "%.1fs" % (time.time() - t0))
	save_png(os.path.join(out, "floor_4m.png"), floor_4m())
	print("floor %.1fs" % (time.time() - t0))
