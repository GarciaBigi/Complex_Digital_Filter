"""
Tests del golden en punto fijo (fxpmath):   python3 test_math.py

Chequeos de consistencia y comparacion BIT A BIT de todos los nodos (ROMs,
etapas de FFT, producto espectral, etapas de IFFT y salida) contra los
vectores de referencia de ../vectors, que son los que usa el testbench RTL.
"""
import os

import numpy as np
from fxpmath import Fxp

import config as C
from fft_fxp import fft_fxp, twiddle_rom
from freq_filter import FreqFilterFxp, ols_float
from fxp_utils import Fmt, fxp_raw, pack_complex_hex, quantize, requant
from signals import datasets, normalize_taps, rrcos, upsample

HERE = os.path.dirname(os.path.abspath(__file__))
VECTORS = os.path.join(os.path.dirname(HERE), "vectors")
h = normalize_taps(rrcos(C.BETA, C.OS, C.N_TAPS, C.RRC_SYMMETRIC), C.N_FFT)


def sqnr_db(ref, test):
    err = np.sum(np.abs(test - ref) ** 2)
    return np.inf if err == 0 else 10 * np.log10(np.sum(np.abs(ref) ** 2) / err)


# --------------------------------------------- semantica de fxpmath ---------
def test_fxpmath_rounding_semantics():
    """Documenta por que no se usan directamente los modos de fxpmath."""
    v = np.array([2.5, -2.5, 1.5, -1.5])
    trunc = Fxp(v, signed=True, n_word=8, n_frac=0, rounding="trunc").val
    around = Fxp(v, signed=True, n_word=8, n_frac=0, rounding="around").val
    floor = Fxp(v, signed=True, n_word=8, n_frac=0, rounding="floor").val
    assert list(trunc) == [2, -2, 1, -1]      # hacia cero, NO es el truncado de HW
    assert list(around) == [2, -2, 2, -2]     # empates al par, NO es half-up
    assert list(floor) == [2, -3, 1, -2]      # = truncado de hardware
    x = fxp_raw([5, -5], Fmt(8, 0))
    assert x.config.shifting == "expand"
    assert list((x >> 1).get_val()) == [2.5, -2.5]   # exacto con shifting='expand'
    half = x * Fxp(0.5)                              # exacto con cualquier config
    assert list(half.get_val()) == [2.5, -2.5] and half.n_frac == 1


def test_requant():
    """Casos hechos a mano: half-up, truncado, saturacion y wrap."""
    f = Fmt(8, 4)
    v = fxp_raw([5, 6, 7, -5, -6, -7], Fmt(16, 2))
    assert list(requant(v, Fmt(8, 0)).val) == [1, 2, 2, -1, -1, -2]
    assert list(requant(fxp_raw([5, -5], Fmt(16, 2)), Fmt(8, 0), rnd="trunc").val) == [1, -2]
    assert list(requant(fxp_raw([1000, -1000], Fmt(16, 0)), f).val) == [127, -128]
    assert list(requant(fxp_raw([128, -129], Fmt(16, 0)), Fmt(8, 0), ovf="wrap").val) == [-128, 127]
    assert list(quantize([1.0, -1.0, 0.03125], f).val) == [16, -16, 1]


# ------------------------------------------------------- consistencia -------
def test_ols_float_equals_convolution():
    x = upsample(datasets(200, h, C.OS)["random_a"], C.OS)
    assert np.allclose(ols_float(x, h), np.convolve(x, h)[:len(x)], atol=1e-12)


def test_fft_fxp_vs_numpy():
    rng = np.random.default_rng(0)
    st = [Fmt(16, 10)] * C.LOG2N
    tw = Fmt(16, 14)
    twr, twi = twiddle_rom(C.N_FFT, tw)
    x = rng.uniform(-1, 1, C.N_FFT) + 1j * rng.uniform(-1, 1, C.N_FFT)
    xr, xi = quantize(x.real, Fmt(8, 6)), quantize(x.imag, Fmt(8, 6))
    xq = xr.get_val() + 1j * xi.get_val()
    Xr, Xi, _ = fft_fxp(xr, xi, st, twr, twi)
    assert sqnr_db(np.fft.fft(xq), Xr.get_val() + 1j * Xi.get_val()) > 50
    yr, yi, _ = fft_fxp(Xr, Xi, st, twr, twi, inverse=True, scale=True)
    assert sqnr_db(xq, yr.get_val() + 1j * yi.get_val()) > 45


def test_fixed_filter_all_datasets():
    filt = FreqFilterFxp(h, C.make_cfg(h))
    for name, sym in datasets(256, h, C.OS).items():
        x = upsample(sym, C.OS)
        y_fx, *_, log = filt.run(x)
        assert not log.any(), f"overflow en {name}:\n{log.report()}"
        assert sqnr_db(ols_float(x, h), y_fx) > 35, name


# ------------------------------------- bit a bit contra ../vectors ---------
N_SYM_DATA = 2048      # los datasets se generan con 2048 simbolos (como run_math.py)
N_SYM_VEC = 256        # y se exportan los primeros 256


def _hex(re, im, nb):
    return [pack_complex_hex(r, i, nb) for r, i in zip(np.ravel(re), np.ravel(im))]


def test_matches_reference_vectors():
    """Cada nodo del modelo coincide bit a bit con los archivos de ../vectors."""
    if not os.path.isdir(VECTORS):
        print("    (salteado: no esta ../vectors)")
        return
    cfg = C.make_cfg(h)
    f = FreqFilterFxp(h, cfg)

    def check(rel, re, im, nb):
        with open(os.path.join(VECTORS, rel)) as fh:
            assert _hex(re, im, nb) == fh.read().split(), f"difiere {rel}"

    check("rom/twiddle.hex", f.tw_re.val, f.tw_im.val, cfg.tw.nb)
    check("rom/H.hex", f.H_re.val, f.H_im.val, cfg.h.nb)
    for name, sym in datasets(N_SYM_DATA, h, C.OS).items():
        x = upsample(sym[:N_SYM_VEC], C.OS)
        _, (xr, xi), (yr, yi), r, _ = f.run(x, keep_blocks=True)
        check(f"{name}/x_in.hex", xr, xi, cfg.x.nb)
        check(f"{name}/y_out.hex", yr, yi, cfg.y.nb)
        check(f"{name}/blk_in.hex", r["buf"][0].val, r["buf"][1].val, cfg.x.nb)
        check(f"{name}/spec_mult.hex", r["Y"][0].val, r["Y"][1].val, cfg.y_spec.nb)
        for s in range(C.LOG2N):
            st, ist = r["fft_stages"][s], r["ifft_stages"][s]
            check(f"{name}/fft_st{s + 1}.hex", st[0].val, st[1].val, cfg.fft_st[s].nb)
            check(f"{name}/ifft_st{s + 1}.hex", ist[0].val, ist[1].val, cfg.ifft_st[s].nb)



if __name__ == "__main__":
    tests = [v for k, v in dict(globals()).items() if k.startswith("test_")]
    for t in tests:
        t()
        print(f"OK  {t.__name__}")
    print(f"\n{len(tests)} tests OK")
