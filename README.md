# Complex Digital Filter

Filtro de conformación **RRC** (raíz de coseno alzado, 8 taps, roll-off 50 %) para símbolos **QPSK (±1 ± j)**, implementado de dos formas y comparado en punto flotante, punto fijo y hardware:

- **Dominio del tiempo:** FIR complejo de 8 taps en forma directa.
- **Dominio de la frecuencia:** procesamiento por bloques con **overlap-save** (50 % de superposición), con FFT de 16 puntos, multiplicación espectral por H[k] e IFFT, totalmente paralelo.

📖 La documentación completa está en la [**wiki**](https://github.com/GarciaBigi/Complex_Digital_Filter/wiki).

## Arquitectura

```
             ┌─► FIR 8 taps: línea de retardo → 8 productos × h[k] → árbol de sumas ─┐
x[n] S(8,6) ─┤                                                                       ├─► y[n] S(10,8)
             └─► ols_buffer → FFT16 → × H[k] → IFFT16 → descarte de 8 muestras ──────┘
```

`x[n]` son símbolos QPSK sobremuestreados por 2; arriba el filtro en el tiempo, abajo el filtro en la frecuencia.

Cada filtro se desarrolla en tres niveles, y cada nivel se verifica contra el anterior:

```
Golden model float (Python) ──► Golden model punto fijo (Python, fxpmath) ──► RTL (SystemVerilog)
     vs convolución lineal          SQNR y error en LSB vs float               bit a bit vs punto fijo
```

## Resultados principales

| | Filtro en el tiempo | Filtro en la frecuencia |
|---|---|---|
| Formatos | Entrada S(8,6), taps S(8,7), salida S(10,8) | Entrada S(8,6), H[k] y twiddles S(10,8), salida S(10,8) |
| Punto fijo vs float | SNR 64.7 – 68.2 dB | SQNR 39.7 – 68.0 dB, 0 overflows |
| RTL vs punto fijo | 12/12 pruebas bit a bit | 9/9 pruebas bit a bit (y cada etapa por separado) |
| Throughput | 1 muestra/ciclo | 1 muestra/ciclo (el núcleo FFT procesa 1 bloque/ciclo) |
| Latencia | 2 ciclos | 11 ciclos |

Las dos salidas en punto fijo difieren en **1 LSB como máximo** entre sí.

**PPA del filtro en frecuencia** (Yosys + SKY130 HD, corner tt, pre-layout, 100 MHz): área **0.53 mm²** (4073 FFs), Fmax **63.7 MHz** (114 MHz en el camino de datos), potencia **23.4 mW**. Detalle en [Paralelización y PPA](https://github.com/GarciaBigi/Complex_Digital_Filter/wiki/Paralelizacion-PPA).

## Estructura del repositorio

```
.
├── Golden_model/
│   ├── tiempo_float/   # FIR RRC en punto flotante
│   ├── tiempo_pf/      # FIR RRC en punto fijo + vectores para el RTL
│   ├── frec_float/     # Overlap-save en punto flotante
│   └── frec_pf/        # Overlap-save en punto fijo (fxpmath) + vectores por etapa
└── RTL/
    ├── tiempo/         # fir_serial
    │   ├── src/  tb/  sim/run.sh
    └── frec/           # ols_buffer, butterfly, fft_stage, fft16, spec_mult, ols_output, freq_filter (top)
        ├── src/  tb/
        └── sim/        # run.sh (simulación), synth.sh (Yosys), ppa.sh (área, timing y potencia en SKY130)
```

## Cómo correr

Requisitos: Python 3 (numpy, matplotlib, fxpmath), Icarus Verilog ≥ 11 (`iverilog -g2012`), GTKWave. Para síntesis: Yosys; para PPA: el entorno de OpenLane 2 (Yosys, OpenSTA y PDK SKY130).

```bash
# Golden model en punto fijo del filtro en frecuencia (regenera vectores y figuras)
cd Golden_model/frec_pf/python_math && python3 run_math.py

# Simulación RTL (cada script imprime PASS/FAIL por prueba)
cd RTL/tiempo/sim && ./run.sh
cd RTL/frec/sim   && ./run.sh

# Área, timing y potencia del filtro en frecuencia: ./ppa.sh [periodo_ns] [actividad_%]
cd RTL/frec/sim && ./ppa.sh 10 100
```

## Equipo

| Integrante | Aporte |
|---|---|
| Brian Ezequiel Aranda | Golden model tiempo (punto fijo), RTL tiempo |
| Maximo Giovanni Gullo | Golden model tiempo (float), RTL tiempo |
| Ian Valentín Parlade Peralta | Golden model frecuencia (punto fijo), RTL frecuencia (FFT/IFFT, salida, top) |
| Luka García Bigi | Golden model frecuencia (float), RTL frecuencia (armado de bloque, producto espectral), síntesis y potencia |
