"""
Parametros del sistema y formatos de punto fijo de cada nodo del filtro en
frecuencia. Todos los anchos se derivan de unas pocas perillas (NBF_*), con los
bits enteros calculados a partir de cotas de peor caso -> sin overflow posible
para entradas QPSK (+/-1 +/- j).
"""
from dataclasses import dataclass, field
import math

import numpy as np

from fxp_utils import Fmt

# ---------------------------------------------------------------- sistema ---
BETA = 0.5          # roll-off del RRC
N_TAPS = 8          # taps del RRC
OS = 2              # sobremuestreo (muestras por simbolo) -> 8 taps = 4 simbolos
RRC_SYMMETRIC = True  # True: h[n]=h[7-n] (fase lineal, plegable). False: version
                      # anterior con pico en n=4 (ver rama git rrc-asimetrico)
N_FFT = 16          # tamano de bloque / FFT
HOP = N_FFT // 2    # muestras nuevas por bloque (solapamiento 50 %)

assert N_TAPS - 1 <= N_FFT - HOP, "overlap-save: el solapamiento no alcanza para M-1"
LOG2N = int(math.log2(N_FFT))
assert 1 << LOG2N == N_FFT


@dataclass
class FixedCfg:
    """Formatos de cada nodo + modos de cuantizacion."""
    x: Fmt                 # entrada x[n]
    tw: Fmt                # twiddles W_N^k (ROM)
    h: Fmt                 # H[k] (ROM)
    fft_st: list           # salida de cada etapa de la FFT (LOG2N formatos)
    y_spec: Fmt            # producto espectral Y[k] = X[k] H[k]
    ifft_st: list          # salida de cada etapa de la IFFT (con /2 por etapa)
    y: Fmt                 # salida y[n]
    rnd: str = "round"
    ovf: str = "sat"

    def table(self):
        rows = [("x[n] entrada", self.x), ("twiddle W", self.tw), ("H[k] ROM", self.h)]
        rows += [(f"FFT etapa {i + 1}", f) for i, f in enumerate(self.fft_st)]
        rows += [("Y[k]=X[k]H[k]", self.y_spec)]
        rows += [(f"IFFT etapa {i + 1}", f) for i, f in enumerate(self.ifft_st)]
        rows += [("y[n] salida", self.y)]
        return rows


def make_cfg(h, nbf_d=8, nb_tw=10, nb_h=10, nb_x=8, nbf_x=6, nbf_y=None,
             rnd="round", ovf="sat"):
    """
    Construye la configuracion de punto fijo.

    nbf_d : bits fraccionales del camino de datos interno (FFT, Y, IFFT)
    nb_tw : bits de los twiddles, formato S(nb_tw, nb_tw-2) (representa +1 exacto)
    nb_h  : bits de H[k],        formato S(nb_h,  nb_h-2)  (|H| <= 1 por diseno)
    nb_x/nbf_x : formato de entrada (QPSK +/-1 entra exacto con 1 bit entero)
    nbf_y : bits fraccionales de la salida (por defecto = nbf_d)

    Cotas usadas para los bits enteros (|x| <= sqrt(2) por ser QPSK):
      * FFT sin escalar: |salida etapa s| <= 2^s * sqrt(2)   -> crece 1 bit/etapa
      * |Y[k]| <= N*sqrt(2)*max|H| = N*sqrt(2)
      * IFFT con /2 por etapa (implementa el 1/N): |a +/- W b|/2 <= max(|a|,|b|)
        -> el ancho NO crece, se mantiene la cota de Y
      * |y[n]| <= sqrt(2) * sum|h|
    """
    def fmt_for(bound, nbf):
        nbi = max(0, math.floor(math.log2(bound)) + 1)   # 2^nbi > bound
        return Fmt(1 + nbi + nbf, nbf)

    sqrt2 = math.sqrt(2.0)
    fft_st = [fmt_for((2 ** s) * sqrt2, nbf_d) for s in range(1, LOG2N + 1)]
    y_spec = fmt_for(N_FFT * sqrt2, nbf_d)
    ifft_st = [y_spec] * LOG2N
    nbf_y = nbf_d if nbf_y is None else nbf_y
    y = fmt_for(sqrt2 * float(np.sum(np.abs(h))), nbf_y)
    return FixedCfg(x=Fmt(nb_x, nbf_x), tw=Fmt(nb_tw, nb_tw - 2), h=Fmt(nb_h, nb_h - 2),
                    fft_st=fft_st, y_spec=y_spec, ifft_st=ifft_st, y=y, rnd=rnd, ovf=ovf)
