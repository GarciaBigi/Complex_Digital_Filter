# Golden model en punto fijo: filtro RRC en el dominio de la frecuencia

Modelo de referencia (*golden*) **bit-exacto** del filtro en frecuencia, pensado para
verificar el RTL bit a bit.

- Overlap-save con 50 % de solapamiento, FFT/IFFT radix-2 de 16 puntos.
- RRC de 8 taps (simétrico), β = 0.5, OS = 2, símbolos QPSK (±1 ± j).
- Punto fijo con la librería [fxpmath](https://github.com/francof2a/fxpmath): redondeo
  *half-up* + saturación en cada etapa, anchos elegidos por cotas de peor caso
  (sin overflow posible) y por barridos de SQNR.

## Estructura

```
python_math/        código del golden (fxpmath) + tests  → ver python_math/README.md
  out/              salidas de run_math.py: reporte, gráficos y vectores
vectors/            vectores para el testbench RTL
  rom/              twiddle.hex, H.hex y golden_params.svh (anchos de cada nodo)
  <dataset>/        x_in, y_out y la salida de cada etapa (fft_st1..4, spec_mult, ifft_st1..4)
                    6 datasets QPSK + stress (muestras aleatorias sin sobremuestreo: con
                    QPSK sobremuestreada la FFT nunca redondea, con stress si)
docs/
  arquitectura.md   diagrama en bloques + descripción de cada etapa + formatos
  resultados.md     métricas float vs punto fijo y barridos de bits
  img/              gráficos y diagrama en bloques (diagrama_bloques.png / .svg)
  golden_model_resumen.pptx   presentación del modelo (con notas del orador)
```

## Cómo correrlo

```bash
cd python_math
pip install -r requirements.txt
python3 test_math.py
python3 run_math.py
```

`run_math.py` regenera `python_math/out/` y compara sus vectores contra `vectors/`: debe
informar **86/86 archivos idénticos**.

## Formatos de punto fijo (S(NB, NBF) = NB bits con signo, NBF fraccionales)

| Nodo | Formato |
|---|---|
| x[n] entrada | S(8,6) |
| twiddles W, H[k] | S(10,8) |
| FFT etapas 1 → 4 | S(11,8) → S(14,8) |
| Y[k] = X[k]·H[k] | S(14,8) |
| IFFT etapas 1 – 4 (÷2 por etapa) | S(14,8) |
| y[n] salida | S(10,8) |

Resultado con QPSK aleatoria: SQNR ≈ 49 dB contra el modelo en float, error ≤ ~2 LSB de
salida, 0 overflows. Detalle y justificación en `docs/`.

## Nota: normalización del filtro

Este golden normaliza los taps para que **max|H[k]| = 1**: el filtro no amplifica ninguna
frecuencia y los anchos de punto fijo se calcularon con esa cota. `../frec_float/frec_float.py`
normaliza con **sum(h) = 1**. Los taps tienen la misma forma pero distinta escala, así que
**las salidas no se pueden comparar directamente** hasta acordar una sola normalización.
