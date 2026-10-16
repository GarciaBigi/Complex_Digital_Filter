"""
Tests de la version fxpmath:   python3 test_math.py

Ademas de los chequeos de consistencia, compara BIT A BIT contra el golden de
enteros (../python), nodo por nodo, en varias configuraciones. El golden se
ejecuta en un proceso aparte porque ambas carpetas tienen modulos con el mismo
nombre (config, signals, freq_filter).
"""
import json
import os
import subprocess
import sys
import tempfile

import numpy as np
from fxpmath import Fxp

import config as C
from fft_fxp import fft_fxp, twiddle_rom
from freq_filter import FreqFilterFxp, ols_float
from fxp_utils import Fmt, fxp_raw, quantize, requant
from signals import datasets, normalize_taps, rrcos, upsample

HERE = os.path.dirname(os.path.abspath(__file__))
GOLDEN_DIR = os.path.join(os.path.dirname(HERE), "python")
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
    """Mismos casos que python/test_golden.py::test_requant."""
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


# --------------------------------------- bit a bit contra ../python ---------
_GOLDEN_SCRIPT = r"""
import json, sys
import numpy as np
import config as C
from freq_filter import FreqFilterFixed
from signals import datasets, normalize_taps, rrcos, upsample
args = json.loads(sys.argv[1])
h = normalize_taps(rrcos(C.BETA, C.OS, C.N_TAPS, C.RRC_SYMMETRIC), C.N_FFT)
f = FreqFilterFixed(h, C.make_cfg(h, **args["cfg"]))
x = upsample(datasets(args["n_sym"], h, C.OS)[args["dataset"]], C.OS)
_, (xr, xi), (yr, yi), blocks, log = f.run(x, keep_blocks=True)
out = dict(x_re=xr, x_im=xi, y_re=yr, y_im=yi, tw_re=f.tw_re, tw_im=f.tw_im,
           H_re=f.H_re, H_im=f.H_im)
for s in range(C.LOG2N):
    for t in ("fft", "ifft"):
        out[f"{t}{s}_re"] = np.stack([b[t + "_stages"][s][0] for b in blocks])
        out[f"{t}{s}_im"] = np.stack([b[t + "_stages"][s][1] for b in blocks])
out["Y_re"] = np.stack([b["Y"][0] for b in blocks])
out["Y_im"] = np.stack([b["Y"][1] for b in blocks])
np.savez(args["out"], **out)
"""


def golden_reference(cfg_kw, dataset, n_sym, out):
    args = json.dumps(dict(cfg=cfg_kw, dataset=dataset, n_sym=n_sym, out=out))
    subprocess.run([sys.executable, "-c", _GOLDEN_SCRIPT, args], cwd=GOLDEN_DIR, check=True)
    return np.load(out)


CONFIGS = [
    {},                                                   # configuracion del diseno
    {"rnd": "trunc"},                                     # truncado de hardware
    {"nbf_d": 4, "nb_tw": 6, "nb_h": 6},                  # anchos chicos: muchos redondeos
    {"nbf_d": 12, "nb_tw": 14, "nb_h": 14},               # anchos grandes
    {"nbf_d": 3, "nb_x": 4, "nbf_x": 1, "ovf": "wrap"},   # desborde en complemento a 2
]


def test_bit_exact_vs_golden():
    if not os.path.isfile(os.path.join(GOLDEN_DIR, "freq_filter.py")):
        print("    (salteado: no esta ../python, el golden de enteros contra el que se compara)")
        return
    with tempfile.TemporaryDirectory() as tmp:
        for i, kw in enumerate(CONFIGS):
            for dataset in ("random_a", "worst_case", "impulse"):
                g = golden_reference(kw, dataset, 128, os.path.join(tmp, f"g{i}.npz"))
                f = FreqFilterFxp(h, C.make_cfg(h, **kw))
                x = upsample(datasets(128, h, C.OS)[dataset], C.OS)
                _, (xr, xi), (yr, yi), r, _ = f.run(x, keep_blocks=True)
                mine = dict(x_re=xr, x_im=xi, y_re=yr, y_im=yi,
                            tw_re=f.tw_re.val, tw_im=f.tw_im.val, H_re=f.H_re.val,
                            H_im=f.H_im.val, Y_re=r["Y"][0].val, Y_im=r["Y"][1].val)
                for s in range(C.LOG2N):
                    for t in ("fft", "ifft"):
                        mine[f"{t}{s}_re"] = r[t + "_stages"][s][0].val
                        mine[f"{t}{s}_im"] = r[t + "_stages"][s][1].val
                for node, ref in g.items():
                    assert np.array_equal(np.asarray(mine[node]), ref), \
                        f"config {kw}, {dataset}: difiere el nodo {node}"


if __name__ == "__main__":
    tests = [v for k, v in dict(globals()).items() if k.startswith("test_")]
    for t in tests:
        t()
        print(f"OK  {t.__name__}")
    print(f"\n{len(tests)} tests OK")
