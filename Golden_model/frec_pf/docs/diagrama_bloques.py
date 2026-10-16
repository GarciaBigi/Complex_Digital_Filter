"""
Diagrama en bloques (nivel hardware) del filtro RRC en frecuencia.

    python3 docs/diagrama_bloques.py  ->  docs/img/diagrama_bloques.{png,svg}
"""
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch, Rectangle

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "img")

NAVY, TEAL, ORANGE = "#1f3a5f", "#1a9e8f", "#e07a1f"
GREY, LIGHT, PALE_T, PALE_O = "#5f6b7a", "#f3f5f8", "#e3f4f2", "#fcefe2"
WHITE = "white"

fig, ax = plt.subplots(figsize=(16, 9))
ax.set_xlim(0, 32)
ax.set_ylim(0, 18)
ax.axis("off")


def box(x0, y0, x1, y1, text="", fc=NAVY, tc=WHITE, ec=None, fs=11, bold=False,
        r=0.18, lw=1.4, va="center", ty=None, z=2):
    p = FancyBboxPatch((x0, y0), x1 - x0, y1 - y0, boxstyle=f"round,pad=0,rounding_size={r}",
                       fc=fc, ec=ec or fc, lw=lw, zorder=z)
    ax.add_patch(p)
    if text:
        ax.text((x0 + x1) / 2, ty if ty is not None else (y0 + y1) / 2, text, ha="center",
                va=va, color=tc, fontsize=fs, fontweight="bold" if bold else "normal",
                zorder=z + 1, linespacing=1.35)


def arrow(pts, color=GREY, lw=2.0, ls="-", head=True, z=1):
    for i in range(len(pts) - 1):
        last = i == len(pts) - 2
        a = FancyArrowPatch(pts[i], pts[i + 1], arrowstyle="-|>" if (last and head) else "-",
                            mutation_scale=16, color=color, lw=lw, linestyle=ls,
                            shrinkA=0, shrinkB=0, zorder=z)
        ax.add_patch(a)


def bus(x, y, label, above=True):
    ax.plot([x - 0.12, x + 0.12], [y - 0.22, y + 0.22], color=GREY, lw=1.4, zorder=3)
    ax.text(x, y + (0.32 if above else -0.32), label, ha="center",
            va="bottom" if above else "top", fontsize=9, color=GREY)


def preg(x, y0, y1):
    """Registro de pipeline (barra rayada)."""
    ax.add_patch(Rectangle((x - 0.09, y0), 0.18, y1 - y0, fc="white", ec=GREY,
                           hatch="////", lw=1.0, zorder=4))


def bitrev(x0, x1, y0, y1, label):
    box(x0, y0, x1, y1, fc=LIGHT, ec=GREY, tc=GREY)
    xs = [x0 + 0.2, x1 - 0.2]
    ys = [y0 + 0.5 + i * (y1 - y0 - 1.0) / 3 for i in range(4)]
    for a, b in [(0, 0), (1, 2), (2, 1), (3, 3)]:
        ax.plot(xs, [ys[a], ys[b]], color=GREY, lw=1.2, zorder=3)
    ax.text((x0 + x1) / 2, y0 - 0.15, label, ha="center", va="top", fontsize=9, color=GREY)


# ------------------------------------------------------------------ titulo ---
ax.text(16, 17.45, "Filtro RRC en el dominio de la frecuencia: overlap-save 50 %, N = 16",
        ha="center", va="center", fontsize=17, fontweight="bold", color=NAVY)
ax.text(16, 16.75, "h: 8 taps, β = 0.5, OS = 2   ·   señal compleja (I + jQ)   ·   "
        "cada etapa: ancho completo → redondeo half-up + saturación",
        ha="center", va="center", fontsize=11, color=GREY)

# ------------------------------------------------------ fila 1: entrada->×H ---
Y0, Y1 = 11.0, 15.0            # caja externa fila 1
YM = 12.8                      # linea de datos fila 1

# entrada
ax.text(0.25, YM + 0.45, "x[n]", fontsize=13, fontweight="bold", color=NAVY)
ax.text(0.25, YM - 0.75, "serie\nS(8,6)", fontsize=9, color=GREY)
arrow([(0.2, YM), (1.4, YM)], color=NAVY)

# buffer OLS
box(1.4, Y0, 5.95, Y1, fc=PALE_T, ec=TEAL)
ax.text(3.65, 14.55, "S/P + buffer OLS", ha="center", fontsize=11, fontweight="bold", color=NAVY)
box(1.7, 12.95, 4.2, 14.1, "viejo\n8 × S(8,6)", fc=WHITE, ec=NAVY, tc=NAVY, fs=9.5)
box(1.7, 11.3, 4.2, 12.45, "nuevo\n8 × S(8,6)", fc=WHITE, ec=TEAL, tc=TEAL, fs=9.5)
arrow([(3.95, 12.45), (3.95, 12.95)], color=TEAL, lw=1.5)
ax.text(4.3, 12.7, "cada 8\nmuestras", ha="left", va="center", fontsize=7.5, color=TEAL)

# bit reverso + FFT
arrow([(5.95, YM), (6.35, YM)], color=NAVY)
ax.text(6.15, 15.35, "16 × S(8,6)", ha="center", fontsize=9, color=GREY)
bitrev(6.35, 7.45, 11.6, 14.0, "bit-reverso\n(cableado)")
arrow([(7.45, YM), (8.0, YM)], color=NAVY)

box(8.0, Y0, 24.0, Y1, fc=PALE_T, ec=TEAL)
ax.text(16.0, 14.6, "FFT 16: radix-2 DIT, sin escalar (+1 bit entero por etapa)",
        ha="center", fontsize=11.5, fontweight="bold", color=NAVY)
fft = [("Etapa 1", "W⁰", "S(11,8)"), ("Etapa 2", "W⁰ W⁴", "S(12,8)"),
       ("Etapa 3", "W⁰ W² W⁴ W⁶", "S(13,8)"), ("Etapa 4", "W⁰ … W⁷", "S(14,8)")]
for i, (t, w, f) in enumerate(fft):
    x0 = 8.4 + i * 4.0
    box(x0, 11.4, x0 + 3.4, 14.15, f"{t}\n8 mariposas\n{w}\n→ {f}", fc=TEAL, fs=10.5)
    if i < 3:
        arrow([(x0 + 3.4, YM), (x0 + 4.0, YM)], color=NAVY)
        preg(x0 + 3.7, 11.55, 14.0)

# multiplicacion espectral
arrow([(24.0, YM), (24.6, YM)], color=NAVY)
ax.text(24.4, 15.35, "X[k]: 16 × S(14,8)", ha="center", fontsize=9, color=GREY)
box(24.6, 11.4, 28.2, 14.15, "× H[k]\n16 mult. compl.\nY = X·H\n→ S(14,8)", fc=ORANGE, fs=10.5)

# ----------------------------------------------- vuelta (serpentina) ---------
YR = 5.0                       # linea de datos fila 2
arrow([(28.2, YM), (29.6, YM), (29.6, YR), (26.4, YR)], color=NAVY)
ax.text(29.75, 9.0, "Y[k]\n16 × S(14,8)", ha="left", va="center", fontsize=9, color=GREY)

# ----------------------------------------------------- fila 2: IFFT -> y ---
bitrev(25.0, 26.4, 3.8, 6.2, "bit-reverso")
arrow([(25.0, YR), (24.0, YR)], color=NAVY)

box(8.0, 3.0, 24.0, 7.0, fc=PALE_T, ec=TEAL)
ax.text(16.0, 6.6, "IFFT 16: twiddle conjugado W⁻ᵏ, ÷2 por etapa (= 1/16), ancho constante",
        ha="center", fontsize=11, fontweight="bold", color=NAVY)
for i in range(4):
    x1 = 23.6 - i * 4.0
    box(x1 - 3.4, 3.4, x1, 6.15, f"Etapa {i + 1}\n8 mariposas\nW⁻ᵏ, ÷2\n→ S(14,8)", fc=TEAL, fs=10.5)
    if i < 3:
        arrow([(x1 - 3.4, YR), (x1 - 4.0, YR)], color=NAVY)
        preg(x1 - 3.7, 3.55, 6.0)

# descarte + P/S + salida
arrow([(8.0, YR), (7.4, YR)], color=NAVY)
ax.text(7.7, 2.75, "y_c: 16 × S(14,8)", ha="center", va="top", fontsize=9, color=GREY)
box(4.6, 3.4, 7.4, 6.15, fc=WHITE, ec=NAVY)
ax.text(6.0, 5.8, "Descarte", ha="center", fontsize=11, fontweight="bold", color=NAVY)
ax.text(6.0, 5.05, "y_c[0..7] ✗", ha="center", fontsize=10, color=GREY)
ax.text(6.0, 4.4, "y_c[8..15] ✓\n→ S(10,8)", ha="center", va="center", fontsize=10, color=TEAL)
arrow([(4.6, YR), (3.9, YR)], color=NAVY)
box(1.6, 3.9, 3.9, 5.9, "P/S\n8 → 1", fc=PALE_T, ec=TEAL, tc=NAVY, fs=11, bold=True)
arrow([(1.6, YR), (0.2, YR)], color=NAVY)
ax.text(0.25, YR + 0.45, "y[n]", fontsize=13, fontweight="bold", color=NAVY)
ax.text(0.25, YR - 0.75, "serie\nS(10,8)", fontsize=9, color=GREY)

# ----------------------------------------------------------------- ROMs ---
box(13.6, 8.25, 18.4, 9.75, "ROM twiddles\nW₁₆ᵏ, k = 0..7 · S(10,8)", fc=PALE_O, ec=ORANGE,
    tc=NAVY, fs=10)
arrow([(16.0, 9.75), (16.0, 11.0)], color=ORANGE, ls="--", lw=1.8)
arrow([(16.0, 8.25), (16.0, 7.0)], color=ORANGE, ls="--", lw=1.8)
ax.text(16.15, 10.4, "Wᵏ", fontsize=10, color=ORANGE)
ax.text(16.15, 7.55, "W⁻ᵏ (conj.)", fontsize=10, color=ORANGE)

box(24.3, 8.25, 28.5, 9.75, "ROM H[k]\nk = 0..15 · S(10,8)", fc=PALE_O, ec=ORANGE, tc=NAVY, fs=10)
arrow([(26.4, 9.75), (26.4, 11.4)], color=ORANGE, ls="--", lw=1.8)

# mariposa (recordatorio)
box(1.4, 7.6, 11.4, 10.4, fc=WHITE, ec=GREY, lw=1.0)
ax.text(1.65, 9.95, "Mariposa (FFT e IFFT)", fontsize=10.5, fontweight="bold", color=NAVY, va="center")
ax.text(1.65, 9.3, "t = W·b   (ancho completo, sin redondeo)", fontsize=10, color=GREY, va="center")
ax.text(1.65, 8.7, "a′ = rq(a + t)      b′ = rq(a − t)", fontsize=10, color=GREY, va="center")
ax.text(1.65, 8.1, "rq = redondeo half-up + saturación", fontsize=10, color=GREY, va="center")

# --------------------------------------------------------------- leyenda ---
ly = 1.6
items = [(1.4, TEAL, "aritmética (mariposas)"), (7.6, ORANGE, "multiplicación espectral"),
         (14.2, PALE_O, "ROM / constantes"), (19.4, PALE_T, "almacenamiento / reorden")]
for x, c, t in items:
    ax.add_patch(Rectangle((x, ly - 0.22), 0.5, 0.44, fc=c,
                           ec={PALE_T: TEAL, PALE_O: ORANGE}.get(c, c)))
    ax.text(x + 0.7, ly, t, va="center", fontsize=10, color=GREY)
ax.add_patch(Rectangle((26.0, ly - 0.3), 0.18, 0.6, fc="white", ec=GREY, hatch="////"))
ax.text(26.4, ly, "registro de pipeline", va="center", fontsize=10, color=GREY)
ax.text(1.4, 0.85, "Por bloque entran 8 muestras nuevas y salen 8 filtradas.  Núcleo FFT → ×H → IFFT "
        "totalmente paralelo: 1 bloque por ciclo, latencia = 9 etapas de pipeline.",
        fontsize=9.5, color=GREY, va="center")
ax.text(1.4, 0.3, "Bus \"16 × S(14,8)\" = 16 muestras complejas (re + im), cada componente de 14 bits "
        "con 8 fraccionales.", fontsize=9.5, color=GREY, va="center")

os.makedirs(OUT, exist_ok=True)
fig.savefig(os.path.join(OUT, "diagrama_bloques.png"), dpi=170, bbox_inches="tight",
            facecolor="white")
fig.savefig(os.path.join(OUT, "diagrama_bloques.svg"), bbox_inches="tight", facecolor="white")
print("Diagrama guardado en:")
for ext in ("png", "svg"):
    print("  " + os.path.join(OUT, "diagrama_bloques." + ext))
