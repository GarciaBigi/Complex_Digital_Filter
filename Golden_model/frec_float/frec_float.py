"""
Golden model en PUNTO FLOTANTE - Filtro RRC en el dominio de la frecuencia
NFFT=16 y 50 % de solapamiento.

"""
import os
import numpy as np
from scipy.signal import lfilter

# ----------------------------------------------------------------------------
# Parametros de diseno
# ----------------------------------------------------------------------------
P = 8              # taps del FIR (enunciado)
BETA = 0.5         # roll-off (enunciado)
TS = 2             # periodo de simbolo en muestras (= factor de upsampling) -> A CONFIRMAR
NFFT = 16          # tamano de FFT / bloque
HOP = NFFT // 2    # muestras nuevas por bloque = 50 % de solapamiento
OVERLAP = NFFT - HOP   # muestras que se guardan del bloque anterior (=8)

# Las primeras P-1 muestras de cada IFFT estan contaminadas por la convolucion
# circular. Se descartan las primeras NFFT-HOP muestras, asi que hace falta NFFT-HOP >= P-1.
assert OVERLAP >= P - 1, "NFFT demasiado chico para el largo del filtro"


# ----------------------------------------------------------------------------
# Modulador QPSK
# ----------------------------------------------------------------------------
def qammod(x, M):
    """M=4 -> QPSK con I,Q en {-1,+1}."""
    m = int(np.sqrt(M))
    re = 2 * (x % m) - m + 1
    im = 2 * (x // m) - m + 1
    return re + 1j * im


# ----------------------------------------------------------------------------
# Coeficientes RRC (reales, 8 taps)
# ----------------------------------------------------------------------------
def root_raised_cosine(n_taps=P, rolloff=BETA, ts=TS):
    """RRC muestreado.
    Con n_taps par las muestras caen en n = -3.5 ... +3.5 (retardo de 3.5 muestras), asi que no hay muestra en t = 0.
    Normalizacion: sum(h) = 1 (ganancia unitaria en DC).
    """
    n = np.arange(n_taps) - (n_taps - 1) / 2.0
    tn = n / ts
    h = np.zeros(n_taps)
    for i, t in enumerate(tn):
        if np.isclose(t, 0.0):
            h[i] = 1.0 - rolloff + 4.0 * rolloff / np.pi
        elif np.isclose(abs(t), 1.0 / (4.0 * rolloff)):
            h[i] = (rolloff / np.sqrt(2.0)) * (
                (1 + 2 / np.pi) * np.sin(np.pi / (4 * rolloff))
                + (1 - 2 / np.pi) * np.cos(np.pi / (4 * rolloff)))
        else:
            num = np.sin(np.pi * (1 - rolloff) * t) + 4 * rolloff * t * np.cos(np.pi * (1 + rolloff) * t)
            den = np.pi * t * (1 - (4 * rolloff * t) ** 2)
            h[i] = num / den
    return h / np.sum(h)


# ----------------------------------------------------------------------------
# Overlap-save: un bloque
# ----------------------------------------------------------------------------
def bloque_overlap_save(nuevas, previas, H):
    """Procesa UN bloque.
    nuevas : HOP muestras de entrada nuevas
    previas: OVERLAP muestras de entrada del bloque anterior (el 'estado')
    H      : respuesta en frecuencia de NFFT puntos

    Devuelve (salida de HOP muestras, nuevo estado).
    """
    blk = np.concatenate([previas, nuevas])   # ventana de NFFT muestras
    X = np.fft.fft(blk)                       # FFT
    Y = X * H                                 # multiplicacion espectral
    y = np.fft.ifft(Y)                        # IFFT
    return y[NFFT - HOP:], blk[HOP:]          # salida valida (se descartan las primeras 8), estado


# ----------------------------------------------------------------------------
# Overlap-save: senal completa
# ----------------------------------------------------------------------------
def filter_overlap_save(x, h):
    """Filtra x completo. Devuelve len(x)+P-1 muestras."""
    x = np.asarray(x, dtype=complex)
    H = np.fft.fft(h, NFFT)                          # H[k]: FFT de h con ceros hasta NFFT
    total = len(x) + len(h) - 1                      # largo de la convolucion lineal
    nblk = int(np.ceil(total / HOP))
    xp = np.concatenate([x, np.zeros(nblk * HOP - len(x), dtype=complex)])  # relleno con ceros

    previas = np.zeros(OVERLAP, dtype=complex)       # estado inicial: ceros
    salida = []
    for r in range(nblk):
        nuevas = xp[r * HOP:(r + 1) * HOP]
        y, previas = bloque_overlap_save(nuevas, previas, H)
        salida.append(y)
    return np.concatenate(salida)[:total]


# ----------------------------------------------------------------------------
# Datasets de prueba (simbolos QPSK)
# ----------------------------------------------------------------------------
def datasets(seed=1234):
    rng = np.random.default_rng(seed)
    return {
        "qpsk_aleatorio_256": qammod(rng.integers(0, 4, 256), 4),
        "qpsk_aleatorio_4096": qammod(rng.integers(0, 4, 4096), 4),
        "todo_+1+1j": np.ones(128) * (1 + 1j),                      # DC
        "alternado": np.tile([1 + 1j, -1 - 1j], 64),                # maxima frecuencia de simbolo
        "impulso": np.r_[1 + 0j, np.zeros(63)],                     # respuesta al impulso
        "largo_no_multiplo_de_8": qammod(rng.integers(0, 4, 203), 4),   # prueba de relleno
    }


# ----------------------------------------------------------------------------
# Verificacion contra la referencia en el tiempo
# ----------------------------------------------------------------------------
def verify(h):
    print(f"h[n] ({P} taps, beta={BETA}, Ts={TS}, sum(h)=1) = {np.round(h, 6)}")
    print(f"NFFT={NFFT}, hop={HOP}, solape={OVERLAP} (>= P-1 = {P - 1}), "
          f"muestras utiles/IFFT = {NFFT - P + 1}, guardadas = {HOP}")
    print(f"{'dataset':26s} {'err vs filtro tiempo':>21s} {'err vs convolve':>16s}")
    worst = 0.0
    for name, ak in datasets().items():
        xup = np.zeros(len(ak) * TS, dtype=complex)  # upsampling: ceros entre simbolos
        xup[::TS] = ak
        x = TS * xup                                 # compensa la amplitud
        y_ols = filter_overlap_save(x, h)            # len(x)+P-1 muestras
        y_cv = np.convolve(x, h)                     # conv. lineal completa (len(x)+P-1)
        y_t = lfilter(h, 1, x)                       # filtro FIR causal en el tiempo (len(x))
        e1 = np.max(np.abs(y_ols[:len(x)] - y_t))
        e2 = np.max(np.abs(y_ols - y_cv))
        worst = max(worst, e1, e2)
        print(f"{name:26s} {e1:21.3e} {e2:16.3e}")
    assert worst < 1e-12, "el modelo no coincide con la convolucion lineal"
    print(f"OK: error maximo global = {worst:.2e}")
    return worst


# ----------------------------------------------------------------------------
# Exportacion de vectores para testbench RTL
# ----------------------------------------------------------------------------
def export_vectors(h, outdir=None):
    if outdir is None:   # carpeta "vectors" al lado de este script (Golden_model/vectors)
        outdir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "vectors")
    os.makedirs(outdir, exist_ok=True)
    H = np.fft.fft(h, NFFT)
    rng = np.random.default_rng(2026)
    ak = qammod(rng.integers(0, 4, 256), 4)          # 256 simbolos
    xup = np.zeros(len(ak) * TS, dtype=complex)      # upsampling por TS -> 512 muestras
    xup[::TS] = ak
    x = TS * xup
    y = filter_overlap_save(x, h)
    np.savetxt(f"{outdir}/h_float.csv", h, fmt="%.17g", header="h[n]")
    np.savetxt(f"{outdir}/H_k_float.csv", np.c_[H.real, H.imag], fmt="%.17g,%.17g",
               delimiter=",", header="Re{H[k]},Im{H[k]}")
    np.savetxt(f"{outdir}/x_in.csv", np.c_[x.real, x.imag], fmt="%.17g,%.17g",
               delimiter=",", header="I,Q  (QPSK con upsampling por Ts)")
    np.savetxt(f"{outdir}/y_ref_float.csv", np.c_[y.real, y.imag], fmt="%.17g,%.17g",
               delimiter=",", header="I,Q  (len(x)+P-1 muestras, conv. lineal completa)")
    print(f"Vectores exportados en {outdir}")


# ----------------------------------------------------------------------------
# Ploteo
# ----------------------------------------------------------------------------
def plots(h):
    import matplotlib.pyplot as plt

    H = np.fft.fft(h, NFFT)
    Hf = np.fft.fft(h, 512)
    f = np.arange(512) / 512
    ak = datasets()["qpsk_aleatorio_256"]
    xup = np.zeros(len(ak) * TS, dtype=complex)      # upsampling por TS
    xup[::TS] = ak
    x = (TS * xup)[:128]
    y = filter_overlap_save(x, h)[:128]
    y_ref = lfilter(h, 1, x)               # filtro en el tiempo

    plt.figure("Coeficientes h[n]")
    plt.stem(np.arange(P), h)
    plt.title(f"RRC {P} taps, beta={BETA}, Ts={TS}")
    plt.xlabel("n")
    plt.ylabel("h[n]")
    plt.grid(alpha=.3)

    plt.figure("Respuesta en frecuencia")
    plt.plot(f, 20 * np.log10(np.abs(Hf) + 1e-12), label="|H| (512 pts)")
    plt.plot(np.arange(NFFT) / NFFT, 20 * np.log10(np.abs(H) + 1e-12), "o", label=f"H[k], N={NFFT}")
    plt.title("Respuesta en frecuencia")
    plt.xlabel("frecuencia normalizada (ciclos/muestra)")
    plt.ylabel("dB")
    plt.legend()
    plt.grid(alpha=.3)

    plt.figure("Salida I")
    plt.plot(x.real, "g.-", alpha=.5, label="entrada (QPSK upsampleada)")
    plt.plot(y_ref.real, "k-", label="filtro en el tiempo")
    plt.plot(y.real, "r.", label="overlap-save (frecuencia)")
    plt.title("Componente I (primeras 128 muestras)")
    plt.xlabel("n")
    plt.legend()
    plt.grid(alpha=.3)

    plt.figure("Error")
    plt.semilogy(np.abs(y - y_ref) + 1e-18)
    plt.title("|error| overlap-save vs filtro en el tiempo")
    plt.xlabel("n")
    plt.grid(alpha=.3)

    plt.show()    # abre las 4 ventanas a la vez


if __name__ == "__main__":
    h = root_raised_cosine()
    verify(h)
    export_vectors(h)
    try:
        plots(h)
    except ModuleNotFoundError:
        print("matplotlib no esta instalado: se omiten los graficos (pip install matplotlib)")