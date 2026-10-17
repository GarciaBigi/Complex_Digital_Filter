"""
Golden model en PUNTO FIJO - Filtro RRC en el dominio del tiempo
FIR directo de 8 taps, bit-true: el RTL tiene que dar exactamente estos enteros.

h es real, asi que el filtro complejo son 2 FIR reales iguales (I y Q).
Formato S(N,F): N bits con signo (complemento a 2), F bits fraccionarios.

Usa los mismos taps, datasets, formatos de entrada/salida y .hex que el filtro en
frecuencia (frec_pf): los dos RTL se prueban con los mismos x_in.hex.
"""
import filecmp
import os
import sys

import numpy as np

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True     # no dejar __pycache__ en las carpetas de los demas
sys.path[:0] = [os.path.join(AQUI, "..", "frec_float"), os.path.join(AQUI, "..", "frec_pf", "python_math")]
from frec_float import P, TS, root_raised_cosine   # taps con max|H[k]| = 1 (iguales a frec_pf)
from signals import datasets, upsample             # datasets de frec_pf (incluye worst_case)

N_SYM = 2048       # simbolos para las metricas (igual que frec_pf)
N_SYM_VEC = 256    # simbolos para los vectores del testbench (igual que frec_pf)
FREC_VEC = os.path.join(AQUI, "..", "frec_pf", "vectors")

# ----------------------------------------------------------------------------
# Formatos de punto fijo
# ----------------------------------------------------------------------------
NX, FX = 8, 6      # entrada: igual que frec_pf (QPSK +-1 entra exacta)
NC, FC = 8, 7      # coeficientes: |h| < 0.5
NY, FY = 10, 8     # salida: igual que frec_pf; |y| <= 0.65 por componente
NACC = NX + NC + int(np.ceil(np.log2(P)))   # acumulador sin overflow (producto + log2(P))


# ----------------------------------------------------------------------------
# Cuantizacion
# ----------------------------------------------------------------------------
def saturar(v, n):
    """Satura enteros al rango de n bits con signo."""
    return np.clip(v, -(1 << (n - 1)), (1 << (n - 1)) - 1)


def cuantizar(v, n, f):
    """Real -> entero S(n,f). Redondeo half-up y saturacion."""
    return saturar(np.floor(np.asarray(v) * 2**f + 0.5).astype(np.int64), n)


def recortar(acc, facc, n, f):
    """Acumulador (fraccion facc) -> salida S(n,f).
    Igual que el RTL: suma medio LSB, desplaza (acc + 2^(s-1)) >>> s y satura.
    """
    s = facc - f
    if s > 0:
        acc = (acc + (1 << (s - 1))) >> s    # >> de numpy es aritmetico
    else:
        acc = acc << -s
    return saturar(acc, n)


# ----------------------------------------------------------------------------
# Filtro FIR en punto fijo
# ----------------------------------------------------------------------------
def filtro_fxp(x, h, nc=NC, fc=FC, ny=NY, fy=FY):
    """Filtra x (complejo) en punto fijo. Salida causal de len(x) muestras, como frec_pf.
    Producto y suma a precision completa: el orden de la suma no cambia el resultado,
    asi que vale para un RTL serie o paralelo. Un solo redondeo, a la salida.
    Devuelve (xi, xq, yi, yq, hq) en enteros.
    """
    hq = cuantizar(h, nc, fc)
    xi = cuantizar(np.real(x), NX, FX)
    xq = cuantizar(np.imag(x), NX, FX)
    n = len(x)
    yi = recortar(np.convolve(xi, hq)[:n], FX + fc, ny, fy)   # convolve de enteros: exacto
    yq = recortar(np.convolve(xq, hq)[:n], FX + fc, ny, fy)
    return xi, xq, yi, yq, hq


def a_float(yi, yq, f):
    return (yi + 1j * yq) / 2**f


def snr_db(y_ref, y):
    e = np.sum(np.abs(y_ref - y) ** 2)
    return np.inf if e == 0 else 10 * np.log10(np.sum(np.abs(y_ref) ** 2) / e)


# ----------------------------------------------------------------------------
# Verificacion contra el modelo en punto flotante
# ----------------------------------------------------------------------------
def verify(h):
    *_, hq = filtro_fxp(np.zeros(1), h)
    print(f"Formatos: x S({NX},{FX}), h S({NC},{FC}), acumulador S({NACC},{FX + FC}), y S({NY},{FY})")
    print(f"hq = {hq}  ->  h cuantizado = {np.round(hq / 2**FC, 6)}")

    # Cota del error: coeficientes (medio LSB por tap activo, |x| <= 1) + redondeo de salida
    activos = P // TS                        # taps con entrada distinta de cero en cada salida
    cota = activos * 2.0 ** -(FC + 1) + 2.0 ** -(FY + 1)

    print(f"{'dataset':12s} {'SNR [dB]':>9s} {'err max [LSB y]':>16s} {'max|y|':>8s}")
    for name, sym in datasets(N_SYM, h, TS).items():
        x = upsample(sym, TS)
        y_f = np.convolve(x, h)[:len(x)]                 # referencia en flotante
        _, _, yi, yq, _ = filtro_fxp(x, h)
        y = a_float(yi, yq, FY)
        err = np.max(np.abs(np.r_[y.real - y_f.real, y.imag - y_f.imag]))
        print(f"{name:12s} {snr_db(y_f, y):9.1f} {err * 2**FY:16.2f} "
              f"{np.max(np.abs(np.r_[y.real, y.imag])):8.4f}")
        assert err <= cota, f"{name}: error {err:.3e} mayor a la cota {cota:.3e}"

        if name == "impulse":   # un simbolo 1+j en el indice 4: la salida es hq desde n = 4*TS
            n0 = 4 * TS
            assert np.array_equal(yi[n0:n0 + P], recortar(hq << FX, FX + FC, NY, FY)), "impulso"
        if name == "worst_case":
            assert np.max(np.abs(yi)) < (1 << (NY - 1)) - 1, "la salida satura en el peor caso"
    print(f"OK: error <= cota ({cota * 2**FY:.2f} LSB), impulso bit-exacto, peor caso sin saturar")


# ----------------------------------------------------------------------------
# Barrido de bits (comparacion flotante vs fijo)
# ----------------------------------------------------------------------------
def barrido(h):
    x = upsample(datasets(N_SYM, h, TS)["random_a"], TS)
    y_f = np.convolve(x, h)[:len(x)]

    # Coeficientes: salida a precision completa, para aislar el efecto de cuantizar h
    nc_list = np.arange(4, 17)
    snr_c = []
    for nc in nc_list:
        fc = nc - 1
        _, _, yi, yq, _ = filtro_fxp(x, h, nc, fc, ny=64, fy=FX + fc)
        snr_c.append(snr_db(y_f, a_float(yi, yq, FX + fc)))

    # Salida: coeficientes en el formato elegido, se barren los bits fraccionales (NY = FY+2)
    fy_list = np.arange(2, 15)
    snr_y = []
    for fy in fy_list:
        _, _, yi, yq, _ = filtro_fxp(x, h, ny=fy + 2, fy=fy)
        snr_y.append(snr_db(y_f, a_float(yi, yq, fy)))

    print(f"{'NC':>4s} {'SNR [dB]':>9s}   {'FY':>4s} {'SNR [dB]':>9s}")
    for nc, a, fy, b in zip(nc_list, snr_c, fy_list, snr_y):
        print(f"{nc:4d} {a:9.1f}   {fy:4d} {b:9.1f}")
    return nc_list, snr_c, fy_list, snr_y


# ----------------------------------------------------------------------------
# Exportacion de vectores para testbench RTL (mismo formato que frec_pf)
# ----------------------------------------------------------------------------
def palabra_hex(v, nb):
    """Entero con signo -> hex de nb bits (complemento a 2)."""
    return f"{int(v) & ((1 << nb) - 1):0{(nb + 3) // 4}x}"


def escribir_hex(path, re, im, nb):
    """Una palabra {im, re} de 2*nb bits por linea, igual que frec_pf."""
    with open(path, "w") as f:
        for r, i in zip(re, im):
            f.write(f"{(int(i) & ((1 << nb) - 1)) << nb | (int(r) & ((1 << nb) - 1)):0{(2 * nb + 3) // 4}x}\n")


def export_vectors(h, outdir=os.path.join(AQUI, "vectors")):
    rom = os.path.join(outdir, "rom")
    os.makedirs(rom, exist_ok=True)
    *_, hq = filtro_fxp(np.zeros(1), h)
    with open(os.path.join(rom, "h.hex"), "w") as f:
        f.write("".join(palabra_hex(v, NC) + "\n" for v in hq))
    with open(os.path.join(rom, "tiempo_params.svh"), "w") as f:
        f.write("// Generado por tiempo_pf.py - NO EDITAR A MANO\n")
        f.write("// Formato S(NB,NBF): NB bits totales con signo, NBF fraccionales\n")
        f.write(f"localparam int N_TAPS = {P};\n")
        f.write(f"localparam int NB_X = {NX}, NBF_X = {FX};\n")
        f.write(f"localparam int NB_H = {NC}, NBF_H = {FC};\n")
        f.write(f"localparam int NB_ACC = {NACC}, NBF_ACC = {FX + FC};\n")
        f.write(f"localparam int NB_Y = {NY}, NBF_Y = {FY};\n")
        f.write("// redondeo = half-up solo a la salida, overflow = sat\n")
        f.write("// h.hex: h[n] n=0..N_TAPS-1 ; x_in/y_out: palabras {im, re}\n")

    for name, sym in datasets(N_SYM, h, TS).items():
        d = os.path.join(outdir, name)
        os.makedirs(d, exist_ok=True)
        xi, xq, yi, yq, _ = filtro_fxp(upsample(sym[:N_SYM_VEC], TS), h)
        escribir_hex(os.path.join(d, "x_in.hex"), xi, xq, NX)
        escribir_hex(os.path.join(d, "y_out.hex"), yi, yq, NY)
    print(f"Vectores exportados en {outdir}")


def comparar_con_frec(outdir=os.path.join(AQUI, "vectors")):
    """Mismo x_in.hex que frec_pf, y diferencia entre las salidas de tiempo y frecuencia."""
    if not os.path.isdir(FREC_VEC):
        print("No estan los vectores de frec_pf: se omite la comparacion")
        return
    print(f"{'dataset':12s} {'x_in igual':>10s} {'|y_tiempo - y_frec| max [LSB]':>30s}")
    for name in sorted(os.listdir(outdir)):
        if name == "rom" or not os.path.isdir(os.path.join(FREC_VEC, name)):
            continue
        a, b = os.path.join(outdir, name), os.path.join(FREC_VEC, name)
        igual = filecmp.cmp(os.path.join(a, "x_in.hex"), os.path.join(b, "x_in.hex"), shallow=False)
        yt, yf = (np.loadtxt(os.path.join(p, "y_out.hex"), dtype=str) for p in (a, b))
        yt, yf = ([int(w, 16) for w in v] for v in (yt, yf))
        mask = (1 << NY) - 1
        sx = lambda v: v - (1 << NY) if v >> (NY - 1) else v     # extension de signo
        dif = max(max(abs(sx(p & mask) - sx(q & mask)), abs(sx(p >> NY) - sx(q >> NY)))
                  for p, q in zip(yt, yf))
        print(f"{name:12s} {str(igual):>10s} {dif:30d}")


# ----------------------------------------------------------------------------
# Ploteo
# ----------------------------------------------------------------------------
def plots(h, sweep):
    import matplotlib.pyplot as plt

    nc_list, snr_c, fy_list, snr_y = sweep
    x = upsample(datasets(N_SYM, h, TS)["random_a"], TS)[:128]
    y_f = np.convolve(x, h)[:len(x)]
    _, _, yi, yq, _ = filtro_fxp(x, h)
    y = a_float(yi, yq, FY)

    fig, ax = plt.subplots(2, 2, figsize=(12, 8), num="Golden tiempo punto fijo")
    ax[0, 0].plot(nc_list, snr_c, "o-")
    ax[0, 0].axvline(NC, color="r", ls="--", label=f"NC={NC}")
    ax[0, 0].set_title("SNR vs bits de coeficientes (salida a precision completa)")
    ax[0, 0].set_xlabel("NC")

    ax[0, 1].plot(fy_list, snr_y, "o-")
    ax[0, 1].axvline(FY, color="r", ls="--", label=f"FY={FY}")
    ax[0, 1].set_title(f"SNR vs bits fraccionales de salida (NC={NC})")
    ax[0, 1].set_xlabel("FY")

    ax[1, 0].plot(y_f.real, "k-", label="flotante")
    ax[1, 0].plot(y.real, "r.", label=f"fijo S({NY},{FY})")
    ax[1, 0].set_title("Componente I (primeras 128 muestras)")
    ax[1, 0].set_xlabel("n")

    ax[1, 1].plot((y.real - y_f.real) * 2**FY, ".-")
    ax[1, 1].set_title("Error I (fijo - flotante) en LSB de salida")
    ax[1, 1].set_xlabel("n")

    for a in ax.flat:
        a.grid(alpha=.3)
    for a in (ax[0, 0], ax[0, 1]):
        a.set_ylabel("SNR [dB]")
    for a in ax.flat[:3]:
        a.legend(loc="lower right")
    fig.tight_layout()
    fig.savefig(os.path.join(AQUI, "tiempo_pf.png"), dpi=110)
    plt.show()


if __name__ == "__main__":
    h = root_raised_cosine()
    verify(h)
    sweep = barrido(h)
    export_vectors(h)
    comparar_con_frec()
    try:
        plots(h, sweep)
    except ModuleNotFoundError:
        print("matplotlib no esta instalado: se omiten los graficos (pip install matplotlib)")
