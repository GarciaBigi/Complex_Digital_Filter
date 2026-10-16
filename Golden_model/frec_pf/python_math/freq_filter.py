"""
Filtro FIR complejo en el dominio de la frecuencia por bloques, metodo
OVERLAP-SAVE con 50 % de solapamiento, en punto fijo con fxpmath.

    N = 16 (FFT), L = N/2 = 8 muestras nuevas por bloque, M = 8 taps
    Condicion overlap-save: M - 1 = 7 <= N - L = 8   OK

Bloque b:
    buf_b   = [ x[(b-1)L .. bL-1]  |  x[bL .. (b+1)L-1] ]   (16 muestras)
                 mitad vieja            mitad nueva
    X_b     = FFT16(buf_b)
    Y_b     = X_b * H              (H = FFT16 de h con ceros)
    y_circ  = IFFT16(Y_b)
    y[bL .. (b+1)L-1] = y_circ[L .. N-1]      (se descarta la 1ra mitad,
                                                contaminada por aliasing circular)

La salida queda alineada muestra a muestra con la convolucion lineal
np.convolve(x, h)[:len(x)] (latencia algoritmica 0 en el indice de muestra;
en hardware la latencia real es 1 bloque + pipeline).

Organizacion: run() arma una matriz (bloques x 16) y process_blocks() procesa
TODOS los bloques a la vez (cada bloque es independiente), lo que hace rapido
el modelo aunque fxpmath opere con objetos.
"""
import numpy as np

import config as C
from fft_fxp import fft_fxp, twiddle_rom
from fxp_utils import OverflowLog, fxp_raw, quantize, requant


def _frames(x_len):
    return (x_len + C.HOP - 1) // C.HOP


# ------------------------------------------------------------------ float ---
def ols_float(x, h):
    """Overlap-save en punto flotante (referencia ideal)."""
    H = np.fft.fft(h, C.N_FFT)
    nb = _frames(len(x))
    xp = np.concatenate([np.zeros(C.HOP, complex), x,
                         np.zeros(nb * C.HOP - len(x), complex)])
    y = np.zeros(nb * C.HOP, complex)
    for b in range(nb):
        buf = xp[b * C.HOP: b * C.HOP + C.N_FFT]
        y_circ = np.fft.ifft(np.fft.fft(buf) * H)
        y[b * C.HOP:(b + 1) * C.HOP] = y_circ[C.HOP:]
    return y[:len(x)]


# ------------------------------------------------------------ punto fijo ---
class FreqFilterFxp:
    """Modelo golden bit-exacto del filtro en frecuencia, con fxpmath."""

    def __init__(self, h, cfg):
        self.cfg = cfg
        self.h = h
        self.tw_re, self.tw_im = twiddle_rom(C.N_FFT, cfg.tw, cfg.rnd)
        H = np.fft.fft(h, C.N_FFT)        # se cuantiza H ideal (no FFT de h cuantizado)
        self.H_re = quantize(H.real, cfg.h, cfg.rnd, cfg.ovf)
        self.H_im = quantize(H.imag, cfg.h, cfg.rnd, cfg.ovf)

    def process_blocks(self, buf_re, buf_im, log=None):
        """buf_re, buf_im: Fxp (bloques, 16) o (16,) en formato cfg.x.
        Devuelve dict con todos los nodos intermedios (Fxp)."""
        c = self.cfg
        q = dict(rnd=c.rnd, ovf=c.ovf, log=log)

        # 1) FFT16 sin escalar (crece 1 bit por etapa)
        X_re, X_im, fft_st = fft_fxp(buf_re, buf_im, c.fft_st, self.tw_re, self.tw_im,
                                     inverse=False, scale=False, tag="fft", **q)

        # 2) Producto espectral Y[k] = X[k] H[k]  (16 multiplicadores complejos)
        p_re = X_re * self.H_re - X_im * self.H_im
        p_im = X_re * self.H_im + X_im * self.H_re
        Y_re = requant(p_re, c.y_spec, node="spec_mult", **q)
        Y_im = requant(p_im, c.y_spec, node="spec_mult", **q)

        # 3) IFFT16 con /2 por etapa (= 1/16)
        yc_re, yc_im, ifft_st = fft_fxp(Y_re, Y_im, c.ifft_st, self.tw_re, self.tw_im,
                                        inverse=True, scale=True, tag="ifft", **q)

        # 4) Descarte de la primera mitad + cuantizacion de salida
        y_re = requant(yc_re[..., C.HOP:], c.y, node="y_out", **q)
        y_im = requant(yc_im[..., C.HOP:], c.y, node="y_out", **q)

        return dict(buf=(buf_re, buf_im), fft_stages=fft_st, X=(X_re, X_im),
                    Y=(Y_re, Y_im), ifft_stages=ifft_st, y_circ=(yc_re, yc_im),
                    y=(y_re, y_im))

    def run(self, x, keep_blocks=False):
        """Filtra la senal compleja float x (se cuantiza a cfg.x).
        Devuelve (y_float, x_int, y_int, nodos, overflow_log); los enteros son
        arrays numpy (.val de los Fxp) y nodos el dict de process_blocks."""
        c = self.cfg
        log = OverflowLog()
        x_re = quantize(x.real, c.x, c.rnd, c.ovf, log, "x_in")
        x_im = quantize(x.imag, c.x, c.rnd, c.ovf, log, "x_in")

        # buffer OLS: 8 ceros al principio + relleno al final
        nb = _frames(len(x))
        pad = nb * C.HOP - len(x)
        z = np.zeros(C.HOP, np.int64)
        xr = fxp_raw(np.concatenate([z, x_re.val, np.zeros(pad, np.int64)]), c.x)
        xi = fxp_raw(np.concatenate([z, x_im.val, np.zeros(pad, np.int64)]), c.x)

        # matriz de bloques: fila b = xp[8b : 8b+16]  (solapamiento 50 %)
        idx = np.arange(nb)[:, None] * C.HOP + np.arange(C.N_FFT)[None, :]
        r = self.process_blocks(xr[idx], xi[idx], log)

        y_re = r["y"][0].val.reshape(-1)[:len(x)]
        y_im = r["y"][1].val.reshape(-1)[:len(x)]
        y = (y_re + 1j * y_im) / (1 << c.y.nbf)
        return y, (x_re.val, x_im.val), (y_re, y_im), (r if keep_blocks else None), log
