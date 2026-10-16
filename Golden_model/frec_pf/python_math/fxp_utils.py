"""
Utilidades de punto fijo bit-exactas sobre la libreria fxpmath.

Convencion de formato: S(NB, NBF) == dtype fxpmath 'fxp-s<NB>/<NBF>'.

Cada valor es un objeto Fxp que guarda su formato; los enteros (lo que
veria el RTL) estan en .val y el valor real en .get_val().

Diferencias de fxpmath a tener en cuenta (verificadas en test_math.py):
  * rounding='trunc'  redondea HACIA CERO (-2.5 -> -2). El truncado de
                      hardware (descartar LSBs en complemento a 2) es 'floor'.
  * rounding='around' redondea los empates AL PAR (2.5 -> 2, 3.5 -> 4).
                      El RTL usa half-up (2.5 -> 3), que fxpmath no trae:
                      se emula sumando 1/2 LSB y usando 'floor'.
  * x >> 1            es exacto solo con config.shifting='expand' (el default:
                      agrega 1 bit fraccional); con 'keep' perderia el LSB.
                      Para no depender de la configuracion, el /2 se hace
                      multiplicando por Fxp(0.5), que siempre es exacto.
  * a + b, a * b      a ancho completo: alinea los puntos y agranda la palabra
                      (s12/8 * s10/8 -> s22/16, s12/8 + s22/16 -> s23/16).
"""
from dataclasses import dataclass

import numpy as np
from fxpmath import Fxp


@dataclass(frozen=True)
class Fmt:
    nb: int    # bits totales
    nbf: int   # bits fraccionales

    @property
    def nbi(self):
        return self.nb - self.nbf - 1

    @property
    def dtype(self):
        return f"fxp-s{self.nb}/{self.nbf}"

    @property
    def max_int(self):
        return (1 << (self.nb - 1)) - 1

    @property
    def min_int(self):
        return -(1 << (self.nb - 1))

    def __str__(self):
        return f"S({self.nb},{self.nbf})"


# constante exacta 0.5 (para el /2 de la IFFT)
HALF = Fxp(0.5, signed=True, n_word=2, n_frac=1)


class OverflowLog:
    """Cuenta, por nodo, cuantas muestras desbordaron."""

    def __init__(self):
        self.counts = {}
        self.totals = {}

    def add(self, node, n_ovf, n_total):
        self.counts[node] = self.counts.get(node, 0) + int(n_ovf)
        self.totals[node] = self.totals.get(node, 0) + int(n_total)

    def any(self):
        return any(v > 0 for v in self.counts.values())

    def report(self):
        return "\n".join(f"    {n:<14s} {self.counts[n]:6d} / {self.totals[n]:<8d}"
                         for n in self.counts)


def fxp_raw(raw, fmt):
    """Enteros (complemento a 2) -> Fxp con formato fmt."""
    v = Fxp(None, signed=True, n_word=fmt.nb, n_frac=fmt.nbf)
    v.set_val(np.asarray(raw, dtype=np.int64), raw=True)
    return v


def requant(v, fmt, rnd="round", ovf="sat", log=None, node=None):
    """
    Re-cuantiza un Fxp (normalmente a ancho completo) al formato fmt.

    rnd: 'round' = half-up  (v + 1/2 LSB, despues floor)  -> igual al RTL
         'trunc' = descartar LSBs (floor)                 -> truncado de hardware
    ovf: 'sat' = saturacion, 'wrap' = desborde en complemento a 2
    """
    if rnd not in ("round", "trunc"):
        raise ValueError(f"modo de redondeo desconocido: {rnd}")
    if ovf not in ("sat", "wrap"):
        raise ValueError(f"modo de overflow desconocido: {ovf}")

    # 1) redondeo (LSBs): +1/2 LSB de salida si es half-up, despues floor.
    #    Se conserva la parte entera completa: aca todavia no puede desbordar.
    if rnd == "round" and v.n_frac > fmt.nbf:
        v = v + Fxp(2.0 ** -(fmt.nbf + 1), signed=True, n_word=fmt.nbf + 3,
                    n_frac=fmt.nbf + 1)
    nbi_full = v.n_word - v.n_frac          # bits enteros + signo de v
    r = v.copy()
    r.config.rounding = "floor"
    r.resize(True, nbi_full + fmt.nbf, fmt.nbf)

    # 2) overflow (MSBs)
    if log is not None and node is not None:
        bad = (r.val > fmt.max_int) | (r.val < fmt.min_int)
        log.add(node, np.count_nonzero(bad), r.val.size)
    r.config.overflow = "saturate" if ovf == "sat" else "wrap"
    r.resize(True, fmt.nb, fmt.nbf)
    return r


def quantize(x, fmt, rnd="round", ovf="sat", log=None, node=None):
    """Valores float -> Fxp en formato fmt (mismo criterio que requant)."""
    x = np.asarray(x, dtype=np.float64)
    extra = 24                                   # bits de guarda antes de redondear
    peak = float(np.max(np.abs(x))) if x.size else 0.0
    nbi = int(np.floor(np.log2(peak))) + 2 if peak > 0 else 1
    wide = Fxp(x, signed=True, n_word=1 + max(nbi, fmt.nbi + 1) + fmt.nbf + extra,
               n_frac=fmt.nbf + extra, rounding="floor", overflow="saturate")
    return requant(wide, fmt, rnd, ovf, log, node)


def pack_complex_hex(re, im, nb):
    """Empaqueta {im, re} (enteros) en una palabra hex de 2*nb bits."""
    mask = (1 << nb) - 1
    word = ((int(im) & mask) << nb) | (int(re) & mask)
    return f"{word:0{(2 * nb + 3) // 4}x}"
