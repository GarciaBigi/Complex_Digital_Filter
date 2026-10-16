"""
FFT / IFFT radix-2 DIT bit-exacta con fxpmath (equivalente a python/fft_fixed.py).

Diferencia con la version de enteros: cada Fxp ya conoce su formato, asi que no
hace falta llevar a mano los bits fraccionales ni alinear con shifts:
    t = W * b          -> fxpmath calcula el producto a ancho completo
    a + t              -> fxpmath alinea los puntos fraccionales solo
    (a + t) * HALF     -> /2 exacto de la IFFT (agrega 1 bit fraccional)
La unica perdida de precision sigue siendo requant(), una vez por salida.

Las entradas pueden ser de forma (N,) o (bloques, N): todas las operaciones se
aplican sobre el ultimo eje, asi se procesan todos los bloques de una vez.
"""
import numpy as np

from fxp_utils import HALF, Fxp, quantize, requant


def bit_reverse_perm(n):
    bits = n.bit_length() - 1
    return np.array([int(f"{i:0{bits}b}"[::-1], 2) for i in range(n)])


def twiddle_rom(n, fmt_tw, rnd="round"):
    """ROM de twiddles W_N^k = exp(-j 2 pi k / N), k = 0..N/2-1 (Fxp re, im)."""
    k = np.arange(n // 2)
    w = np.exp(-2j * np.pi * k / n)
    return quantize(w.real, fmt_tw, rnd), quantize(w.imag, fmt_tw, rnd)


def butterfly_indices(n, m):
    """Pares (a, b) y twiddle de cada mariposa de la etapa con grupos de m."""
    half = m // 2
    ia, ib, iw = [], [], []
    for g in range(0, n, m):
        for k in range(half):
            ia.append(g + k)
            ib.append(g + k + half)
            iw.append(k * (n // m))
    return np.array(ia), np.array(ib), np.array(iw)


def fft_fxp(re, im, stage_fmts, tw_re, tw_im, inverse=False, scale=False,
            rnd="round", ovf="sat", log=None, tag="fft"):
    """
    re, im     : Fxp (..., N) en ORDEN NATURAL
    stage_fmts : formato de salida de cada etapa (len = log2 N)
    inverse    : twiddles conjugados (W^-k)  -> IFFT
    scale      : /2 en cada etapa            -> 1/N total

    Devuelve (re, im, etapas) con etapas = lista de (re, im) Fxp por etapa.
    """
    n = re.shape[-1]
    perm = bit_reverse_perm(n)
    a_re, a_im = re[..., perm], im[..., perm]          # reorden bit-reverso
    tw_im_used = -tw_im if inverse else tw_im          # conjugado para la IFFT
    stages = []

    m = 2
    for s, fmt_s in enumerate(stage_fmts):
        ia, ib, iw = butterfly_indices(n, m)
        wr, wi = tw_re[iw], tw_im_used[iw]
        br, bi = a_re[..., ib], a_im[..., ib]
        ar, ai = a_re[..., ia], a_im[..., ia]

        t_re = br * wr - bi * wi                       # t = W*b, ancho completo
        t_im = br * wi + bi * wr
        s_re, s_im = ar + t_re, ai + t_im              # a + W*b
        d_re, d_im = ar - t_re, ai - t_im              # a - W*b
        if scale:                                      # /2 exacto
            s_re, s_im, d_re, d_im = (v * HALF for v in (s_re, s_im, d_re, d_im))

        kw = dict(rnd=rnd, ovf=ovf, log=log, node=f"{tag}_st{s + 1}")
        out_re = Fxp(np.zeros(re.shape), signed=True, n_word=fmt_s.nb, n_frac=fmt_s.nbf)
        out_im = Fxp(np.zeros(re.shape), signed=True, n_word=fmt_s.nb, n_frac=fmt_s.nbf)
        out_re[..., ia] = requant(s_re, fmt_s, **kw)
        out_im[..., ia] = requant(s_im, fmt_s, **kw)
        out_re[..., ib] = requant(d_re, fmt_s, **kw)
        out_im[..., ib] = requant(d_im, fmt_s, **kw)

        a_re, a_im = out_re, out_im
        stages.append((a_re, a_im))
        m *= 2

    return a_re, a_im, stages
