"""
Modelo golden con fxpmath (equivalente a python/run_golden.py).

    python3 run_math.py

Salidas (en python_math/out/, para no pisar las del golden de enteros):
    img/*.png          float vs fijo y barridos de SQNR
    vectors/           mismos archivos y formato que ../vectors
    resultados.md      metricas + comparacion bit a bit contra ../vectors
"""
import filecmp
import os
import time

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

import config as C
from freq_filter import FreqFilterFxp, ols_float
from fxp_utils import pack_complex_hex
from signals import datasets, normalize_taps, rrcos, upsample

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
IMG = os.path.join(OUT, "img")
VEC = os.path.join(OUT, "vectors")
GOLDEN_VEC = os.path.join(os.path.dirname(HERE), "vectors")
N_SYM = 2048
N_SYM_VEC = 256


def sqnr_db(ref, test):
    err = np.sum(np.abs(test - ref) ** 2)
    return np.inf if err == 0 else 10 * np.log10(np.sum(np.abs(ref) ** 2) / err)


# --------------------------------------------------------------- metricas ---
def evaluate(h, cfg, data):
    filt = FreqFilterFxp(h, cfg)
    rows = []
    for name, sym in data.items():
        x = upsample(sym, C.OS)
        y_td = np.convolve(x, h)[:len(x)]
        y_fd = ols_float(x, h)
        y_fx, *_, log = filt.run(x)
        err = (y_fx - y_fd) / 2.0 ** -cfg.y.nbf
        rows.append(dict(dataset=name, td_vs_fd=float(np.max(np.abs(y_td - y_fd))),
                         sqnr=sqnr_db(y_fd, y_fx),
                         max_err_lsb=float(max(np.abs(err.real).max(), np.abs(err.imag).max())),
                         ovf=sum(log.counts.values())))
    return rows


def sweep(h, x, param, values, **fixed):
    y_ref = ols_float(x, h)
    return [sqnr_db(y_ref, FreqFilterFxp(h, C.make_cfg(h, **{**fixed, param: v})).run(x)[0])
            for v in values]


def plots(h, cfg, x):
    y_fd = ols_float(x, h)
    y_fx, *_ = FreqFilterFxp(h, cfg).run(x)
    e = (y_fx - y_fd) / 2.0 ** -cfg.y.nbf
    fig, ax = plt.subplots(2, 1, figsize=(11, 6))
    n = np.arange(120)
    ax[0].plot(n, y_fd.real[n], label="float")
    ax[0].plot(n, y_fx.real[n], "--", label=f"fijo fxpmath (y {cfg.y})")
    ax[0].set(title="Salida - parte real", xlabel="n")
    ax[0].legend()
    ax[0].grid(alpha=.3)
    ax[1].hist(np.concatenate([e.real, e.imag]), bins=60)
    ax[1].set(title="Histograma del error [LSB de salida]")
    fig.tight_layout()
    fig.savefig(os.path.join(IMG, "float_vs_fijo.png"), dpi=120)
    plt.close(fig)

    nbf, nbw = list(range(2, 15)), list(range(4, 17))
    sw = dict(nbf=nbf, nbw=nbw,
              round=sweep(h, x, "nbf_d", nbf, rnd="round", nb_tw=16, nb_h=16),
              trunc=sweep(h, x, "nbf_d", nbf, rnd="trunc", nb_tw=16, nb_h=16),
              tw=sweep(h, x, "nb_tw", nbw, nbf_d=14, nb_h=16),
              h=sweep(h, x, "nb_h", nbw, nbf_d=14, nb_tw=16))
    fig, ax = plt.subplots(1, 2, figsize=(11, 3.8))
    ax[0].plot(nbf, sw["round"], "o-", label="redondeo")
    ax[0].plot(nbf, sw["trunc"], "s-", label="truncado")
    ax[0].set(title="SQNR vs NBF_D (fxpmath)", xlabel="NBF_D", ylabel="SQNR [dB]")
    ax[0].legend()
    ax[0].grid(alpha=.3)
    ax[1].plot(nbw, sw["tw"], "o-", label="twiddles (NB_TW)")
    ax[1].plot(nbw, sw["h"], "s-", label="H[k] (NB_H)")
    ax[1].set(title="SQNR vs bits de coeficientes (fxpmath)", xlabel="bits", ylabel="SQNR [dB]")
    ax[1].legend()
    ax[1].grid(alpha=.3)
    fig.tight_layout()
    fig.savefig(os.path.join(IMG, "sqnr_vs_bits.png"), dpi=120)
    plt.close(fig)
    return sw


# ------------------------------------------------------- vectores para RTL ---
def write_hex(path, re, im, nb):
    re, im = np.asarray(re).reshape(-1), np.asarray(im).reshape(-1)
    with open(path, "w") as f:
        for r, i in zip(re, im):
            f.write(pack_complex_hex(r, i, nb) + "\n")


def export(h, cfg, data):
    filt = FreqFilterFxp(h, cfg)
    d = os.path.join(VEC, "rom")
    os.makedirs(d, exist_ok=True)
    write_hex(os.path.join(d, "twiddle.hex"), filt.tw_re.val, filt.tw_im.val, cfg.tw.nb)
    write_hex(os.path.join(d, "H.hex"), filt.H_re.val, filt.H_im.val, cfg.h.nb)
    with open(os.path.join(d, "golden_params.svh"), "w") as f:
        f.write("// Generado por python_math/run_math.py - NO EDITAR A MANO\n")
        f.write("// Formato S(NB,NBF): NB bits totales con signo, NBF fraccionales\n")
        f.write(f"localparam int N_FFT  = {C.N_FFT};\n")
        f.write(f"localparam int HOP    = {C.HOP};\n")
        f.write(f"localparam int N_TAPS = {C.N_TAPS};\n")
        for nm, fmt in [("X", cfg.x), ("TW", cfg.tw), ("H", cfg.h),
                        ("Y_SPEC", cfg.y_spec), ("Y", cfg.y)]:
            f.write(f"localparam int NB_{nm} = {fmt.nb}, NBF_{nm} = {fmt.nbf};\n")
        for i, fmt in enumerate(cfg.fft_st):
            f.write(f"localparam int NB_FFT{i + 1} = {fmt.nb}, NBF_FFT{i + 1} = {fmt.nbf};\n")
        for i, fmt in enumerate(cfg.ifft_st):
            f.write(f"localparam int NB_IFFT{i + 1} = {fmt.nb}, NBF_IFFT{i + 1} = {fmt.nbf};\n")
        f.write(f"// redondeo = {cfg.rnd}, overflow = {cfg.ovf}\n")
        f.write("// Palabras hex complejas empaquetadas como {im, re}\n")
        f.write("// H.hex / twiddle.hex: ROM_H[k] k=0..N-1 ; ROM_W[k] = W_N^k k=0..N/2-1\n")
    for name, sym in data.items():
        d = os.path.join(VEC, name)
        os.makedirs(d, exist_ok=True)
        x = upsample(sym[:N_SYM_VEC], C.OS)
        _, (xr, xi), (yr, yi), r, _ = filt.run(x, keep_blocks=True)
        write_hex(os.path.join(d, "x_in.hex"), xr, xi, cfg.x.nb)
        write_hex(os.path.join(d, "y_out.hex"), yr, yi, cfg.y.nb)
        write_hex(os.path.join(d, "blk_in.hex"), r["buf"][0].val, r["buf"][1].val, cfg.x.nb)
        for s in range(C.LOG2N):
            write_hex(os.path.join(d, f"fft_st{s + 1}.hex"), r["fft_stages"][s][0].val,
                      r["fft_stages"][s][1].val, cfg.fft_st[s].nb)
            write_hex(os.path.join(d, f"ifft_st{s + 1}.hex"), r["ifft_stages"][s][0].val,
                      r["ifft_stages"][s][1].val, cfg.ifft_st[s].nb)
        write_hex(os.path.join(d, "spec_mult.hex"), r["Y"][0].val, r["Y"][1].val, cfg.y_spec.nb)


def compare_with_golden():
    """Compara cada .hex exportado contra el mismo archivo de ../vectors."""
    if not os.path.isdir(GOLDEN_VEC):
        return None
    res = []
    for root, _, files in os.walk(VEC):
        for fn in sorted(files):
            if not fn.endswith(".hex"):
                continue
            mine = os.path.join(root, fn)
            rel = os.path.relpath(mine, VEC)
            ref = os.path.join(GOLDEN_VEC, rel)
            ok = os.path.exists(ref) and filecmp.cmp(mine, ref, shallow=False)
            res.append((rel, ok))
    return sorted(res)


# ---------------------------------------------------------------- reporte ---
def write_report(cfg, rows, sw, cmp, t_run):
    p = os.path.join(OUT, "resultados.md")
    with open(p, "w") as f:
        f.write("# Resultados del modelo con fxpmath (generado por `run_math.py`)\n\n")
        f.write("## Formatos\n\n| Nodo | Formato | dtype fxpmath |\n|---|---|---|\n")
        for node, fmt in cfg.table():
            f.write(f"| {node} | {fmt} | `{fmt.dtype}` |\n")
        f.write(f"\n## Float vs punto fijo ({N_SYM} simbolos por dataset)\n\n")
        f.write("| Dataset | max\\|FIR - OLS float\\| | SQNR [dB] | Error max [LSB] | Overflows |\n"
                "|---|---|---|---|---|\n")
        for r in rows:
            f.write(f"| {r['dataset']} | {r['td_vs_fd']:.1e} | {r['sqnr']:.1f} | "
                    f"{r['max_err_lsb']:.2f} | {r['ovf']} |\n")
        f.write(f"\nTiempo de `run()` con {N_SYM} simbolos: {t_run * 1e3:.0f} ms\n")
        f.write("\n## Comparacion bit a bit contra el golden de enteros (`../vectors`)\n\n")
        if cmp is None:
            f.write("No se encontro `../vectors`: correr antes `make golden`.\n")
        else:
            n_ok = sum(ok for _, ok in cmp)
            f.write(f"**{n_ok} / {len(cmp)} archivos identicos.**\n\n| Archivo | Identico |\n|---|---|\n")
            for rel, ok in cmp:
                f.write(f"| {rel} | {'si' if ok else '**NO**'} |\n")
        f.write("\n## Barridos de SQNR\n\n| NBF_D | redondeo | truncado |\n|---|---|---|\n")
        for n, a, b in zip(sw["nbf"], sw["round"], sw["trunc"]):
            f.write(f"| {n} | {a:.1f} | {b:.1f} |\n")
        f.write("\n![float vs fijo](img/float_vs_fijo.png)\n\n![sqnr](img/sqnr_vs_bits.png)\n")
    return p


def main():
    os.makedirs(IMG, exist_ok=True)
    h = normalize_taps(rrcos(C.BETA, C.OS, C.N_TAPS, C.RRC_SYMMETRIC), C.N_FFT)
    cfg = C.make_cfg(h)
    data = datasets(N_SYM, h, C.OS)

    print("Formatos (dtype fxpmath):")
    for node, fmt in cfg.table():
        print(f"  {node:<16s} {str(fmt):<8s} {fmt.dtype}")

    rows = evaluate(h, cfg, data)
    print(f"\n{'dataset':<12s} {'FIR-OLS':>9s} {'SQNR dB':>8s} {'errLSB':>7s} {'ovf':>4s}")
    for r in rows:
        print(f"{r['dataset']:<12s} {r['td_vs_fd']:9.1e} {r['sqnr']:8.1f} "
              f"{r['max_err_lsb']:7.2f} {r['ovf']:4d}")

    x_a = upsample(data["random_a"], C.OS)
    t0 = time.perf_counter()
    FreqFilterFxp(h, cfg).run(x_a)
    t_run = time.perf_counter() - t0
    sw = plots(h, cfg, x_a)

    export(h, cfg, data)
    cmp = compare_with_golden()
    if cmp is None:
        print("\nNo hay ../vectors para comparar (correr antes `make golden`).")
    else:
        n_ok = sum(ok for _, ok in cmp)
        print(f"\nBit a bit contra ../vectors: {n_ok}/{len(cmp)} archivos identicos")
        for rel, ok in cmp:
            if not ok:
                print(f"  DIFIERE: {rel}")

    rep = write_report(cfg, rows, sw, cmp, t_run)
    print(f"\nGraficos en {IMG}\nVectores en {VEC}\nReporte en {rep}")


if __name__ == "__main__":
    main()
