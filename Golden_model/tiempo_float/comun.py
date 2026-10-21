"""Parámetros, coeficientes y datos de entrada del filtro RRC en el tiempo."""

import numpy as np

# Parámetros del filtro
N_TAPS = 8          # cantidad de coeficientes
SPS = 2             # muestras por símbolo (oversampling 2x)
ROLLOFF = 0.5
N_FFT_NORM = 16     # h se normaliza con la FFT de 16 puntos, como en el repo del grupo

# Instante de cada tap, en períodos de símbolo: -1.75, -1.25, ..., +1.75.
# Centrados en 3.5 muestras, así que h[k] = h[7-k] y el retardo es 3.5 muestras.
T_TAPS = (np.arange(N_TAPS) - (N_TAPS - 1) / 2) / SPS

# Datos QPSK al azar
SEMILLAS_QPSK = (1, 2, 3)
N_SIMBOLOS_QPSK = 2048


def coeficientes_rrc():
    """Coeficientes del RRC, normalizados para que max|H[k]| = 1 en la FFT de 16 puntos."""
    t, b = T_TAPS, ROLLOFF
    # La fórmula da 0/0 en t = 0 y en |t| = 1/(4b); con estos t no pasa nunca.
    assert not np.any(np.isclose(t, 0) | np.isclose(np.abs(t), 1 / (4 * b)))
    h = (np.sin(np.pi * t * (1 - b)) + 4 * b * t * np.cos(np.pi * t * (1 + b))) \
        / (np.pi * t * (1 - (4 * b * t) ** 2))
    return h / np.max(np.abs(np.fft.fft(h, N_FFT_NORM)))


def cota_salida(h):
    """Valor máximo de |Re y| (y de |Im y|) con QPSK a SPS muestras por símbolo.

    Por el relleno con ceros, en cada salida solo pesan los taps de una fase
    (los pares o los impares), así que la cota es la mayor suma de |h| por fase.
    """
    return max(np.abs(h[p::SPS]).sum() for p in range(SPS))


def simbolos_qpsk(n, semilla):
    """n símbolos QPSK (±1 ± j), siempre los mismos para una semilla dada."""
    rng = np.random.default_rng(semilla)
    return rng.choice([-1, 1], n) + 1j * rng.choice([-1, 1], n)


def sobremuestrear(simbolos):
    """Relleno con ceros: un símbolo cada SPS muestras (como en el TX del TP1)."""
    x = np.zeros(len(simbolos) * SPS, dtype=complex)
    x[::SPS] = simbolos
    return x


def completar(x):
    """Agrega N_TAPS-1 ceros al final, para ver la cola del filtro."""
    return np.concatenate([x, np.zeros(N_TAPS - 1, dtype=complex)])


def conjuntos_de_datos(h):
    """Entradas de prueba, en un dict nombre -> x. Cada componente vale -1, 0 o +1."""
    impulso = np.r_[1, np.zeros(N_TAPS)]

    # Peor caso: en la salida 2m pesan h0, h2, h4, h6 sobre los símbolos m, m-1,
    # m-2, m-3. Si esos símbolos valen signo(h_k)·(1+j), la salida llega a la
    # cota; el patrón negado la lleva a -cota. Por simetría, las dos fases dan igual.
    signos = np.sign(h[0::SPS])[::-1]

    datos = {
        "impulso_i": impulso,
        "impulso_q": 1j * impulso,
        "escalon": sobremuestrear(np.full(32, 1 + 1j)),
        "peor_caso": sobremuestrear((1 + 1j) * np.r_[signos, -signos]),
    }
    for s in SEMILLAS_QPSK:
        datos[f"qpsk_s{s}"] = sobremuestrear(simbolos_qpsk(N_SIMBOLOS_QPSK, s))
    return {nombre: completar(x.astype(complex)) for nombre, x in datos.items()}
