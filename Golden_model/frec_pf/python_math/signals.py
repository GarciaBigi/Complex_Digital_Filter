"""
Generacion de senales de prueba (en punto flotante).
Simbolos QPSK (+/-1 +/- j), sobremuestreo y filtro RRC.
"""
import numpy as np


def rrcos(beta, os, n_taps, symmetric=True):
    """
    Respuesta al impulso del filtro raiz de coseno realzado.

    beta      : roll-off (0..1)
    os        : sobremuestreo (muestras por simbolo), Ts = T/os
    n_taps    : cantidad de coeficientes
    symmetric : eje de tiempo (en periodos de simbolo T)
        True  -> t = (n - (n_taps-1)/2) / os : h[n] = h[n_taps-1-n], fase lineal
                 exacta. Con n_taps par el pico (t=0) cae ENTRE las muestras
                 n_taps/2-1 y n_taps/2 (retardo (n_taps-1)/2 muestras).
        False -> t = arange(-n_taps/2, n_taps/2) / os (convencion del curso):
                 pico en n_taps//2, pero h[0] queda sin pareja (asimetrico).
    """
    if symmetric:
        t = (np.arange(n_taps) - (n_taps - 1) / 2) / os
    else:
        t = np.arange(-n_taps // 2, n_taps - n_taps // 2) / os
    h = np.zeros(n_taps)
    for i, ti in enumerate(t):
        if np.isclose(ti, 0.0):
            h[i] = 1.0 - beta + 4.0 * beta / np.pi
        elif beta > 0 and np.isclose(abs(ti), 1.0 / (4.0 * beta)):
            h[i] = (beta / np.sqrt(2.0)) * (
                (1 + 2 / np.pi) * np.sin(np.pi / (4 * beta))
                + (1 - 2 / np.pi) * np.cos(np.pi / (4 * beta)))
        else:
            num = (np.sin(np.pi * ti * (1 - beta))
                   + 4 * beta * ti * np.cos(np.pi * ti * (1 + beta)))
            den = np.pi * ti * (1 - (4 * beta * ti) ** 2)
            h[i] = num / den
    return h


def normalize_taps(h, n_fft):
    """Escala h para que max|H[k]| = 1 sobre la FFT de n_fft puntos.
    Asi H entra en un formato S(NB, NB-2) igual que los twiddles y el filtro
    nunca amplifica ninguna componente espectral."""
    return h / np.max(np.abs(np.fft.fft(h, n_fft)))


def qpsk_symbols(n, rng):
    """n simbolos QPSK equiprobables en {+/-1 +/- j}."""
    re = 2 * rng.integers(0, 2, n) - 1
    im = 2 * rng.integers(0, 2, n) - 1
    return re + 1j * im


def upsample(sym, os):
    """Inserta os-1 ceros entre simbolos (expansor)."""
    x = np.zeros(len(sym) * os, dtype=complex)
    x[::os] = sym
    return x


def datasets(n_sym, h, os, seed=1234):
    """
    Conjuntos de datos de prueba (todos son simbolos QPSK +/-1 +/- j).

    Devuelve dict nombre -> simbolos (antes del sobremuestreo).
    """
    rng = np.random.default_rng(seed)
    d = {}
    d["random_a"] = qpsk_symbols(n_sym, rng)
    d["random_b"] = qpsk_symbols(n_sym, rng)

    # Impulso: un unico simbolo 1+j -> la salida debe ser (1+j)*h
    imp = np.zeros(n_sym, dtype=complex)
    imp[4] = 1 + 1j
    d["impulse"] = imp

    # Constante: todos 1+j -> energia concentrada en DC
    d["constant"] = np.full(n_sym, 1 + 1j)

    # Alternado: 1+j, -1-j, ... -> energia en la frecuencia de Nyquist de simbolo
    d["alternating"] = np.where(np.arange(n_sym) % 2 == 0, 1 + 1j, -1 - 1j)

    # Peor caso de amplitud a la salida: los simbolos que caen sobre taps
    # positivos valen +1 y sobre los negativos -1 -> maxima suma constructiva.
    # Con sobremuestreo, en cada muestra de salida solo "tocan" simbolos los
    # taps de una fase polifasica h[p::os]; se elige la fase de mayor sum|h|
    # y se repite periodicamente el patron de signos (invertido = convolucion).
    p = max(range(os), key=lambda q: np.sum(np.abs(h[q::os])))
    s = np.sign(h[p::os][::-1])
    s[s == 0] = 1
    wc = np.resize(s, n_sym)
    d["worst_case"] = wc + 1j * wc
    return d


def stress_signal(n, seed=4321):
    """
    n muestras complejas aleatorias en [-1, 1], SIN sobremuestreo (no es QPSK).

    Con QPSK sobremuestreada la mitad de las muestras son cero: la FFT solo
    multiplica valores exactos y nunca redondea. Esta senal hace trabajar todas
    las mariposas y todos los redondeos. |x| <= sqrt(2): respeta las mismas
    cotas de diseno que QPSK, asi que tampoco puede haber overflow.
    """
    rng = np.random.default_rng(seed)
    return rng.uniform(-1, 1, n) + 1j * rng.uniform(-1, 1, n)
