"""패링음 '명쾌함' 측정: 시작 날카로움 · 탁함(200~800Hz 비중) · 1.77kHz 팅 선명도 · 노이즈 꼬리 길이."""
import numpy as np
import mg_fit as M

SR = 44100


def measure(x, fc=1771.0):
    x = x / np.abs(x).max() * 0.89
    on = int(np.where(np.abs(x) > 0.02 * 0.89)[0][0]); x = x[on:]
    h = int(SR * 0.001); e = np.sqrt(np.convolve(x ** 2, np.ones(h) / h, 'same'))
    rise = (np.argmax(e[:int(0.05 * SR)]) / SR) * 1000                       # 첫 정점까지 ms
    crest = 20 * np.log10(e[:int(0.005 * SR)].max() / (np.sqrt(np.mean(x[int(0.005 * SR):int(0.1 * SR)] ** 2)) + 1e-9))
    seg = x[int(0.02 * SR):int(0.3 * SR)]
    S = np.abs(np.fft.rfft(seg * np.hanning(len(seg)), 1 << 16)) ** 2; f = np.fft.rfftfreq(1 << 16, 1 / SR)
    mud = 10 * np.log10(S[(f > 200) & (f < 800)].sum() / S.sum())
    ting = 10 * np.log10(S[(f > fc * 0.98) & (f < fc * 1.02)].max() / np.median(S[(f > fc * 0.7) & (f < fc * 1.35)]))
    # 노이즈 꼬리: 4~10kHz 대역 포락선이 정점 대비 -30dB 아래로 떨어지는 시각
    X = np.fft.rfft(x); ff = np.fft.rfftfreq(len(x), 1 / SR); hi = np.fft.irfft(X * ((ff > 4000) & (ff < 10000)), len(x))
    eh = np.sqrt(np.convolve(hi ** 2, np.ones(441) / 441, 'same')); ehd = 20 * np.log10(eh / eh.max() + 1e-9)
    ntail = np.where(ehd > -30)[0][-1] / SR
    return dict(rise_ms=round(rise, 1), crest_db=round(crest, 1), mud_db=round(mud, 1), ting_db=round(ting, 1), noise_tail_s=round(ntail, 2), len_s=round(len(x) / SR, 2))


if __name__ == '__main__':
    import sys
    for p in sys.argv[1:]:
        print(p.split('/')[-1], measure(M.load(p)))
