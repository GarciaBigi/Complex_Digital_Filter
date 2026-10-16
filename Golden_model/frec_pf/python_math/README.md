# Golden en punto fijo con fxpmath (`python_math/`)

Modelo bit-exacto del filtro RRC en frecuencia (overlap-save 50 %, FFT de 16 puntos),
escrito con la librería [fxpmath](https://github.com/francof2a/fxpmath). Cada valor es un
objeto `Fxp` que conoce su formato S(NB, NBF); los enteros que vería el RTL están en `.val`.

| Archivo | Qué hace |
|---|---|
| `config.py` | parámetros del sistema y formato de cada nodo (`make_cfg`, a partir de cotas de peor caso) |
| `fxp_utils.py` | `Fmt` (dtype `fxp-sNB/NBF`), `requant` (redondeo half-up + saturación) y `quantize` |
| `signals.py` | RRC, símbolos QPSK, sobremuestreo y datasets de prueba (en float) |
| `fft_fxp.py` | FFT/IFFT radix-2 DIT bit-exacta: 4 etapas × 8 mariposas, un redondeo por salida |
| `freq_filter.py` | `ols_float` (referencia ideal) y `FreqFilterFxp` (el golden), que procesa todos los bloques a la vez |
| `test_math.py` | 6 tests: semántica de fxpmath, cuantización, FFT, filtro y comparación bit a bit contra `../vectors` |
| `run_math.py` | métricas float vs fijo, barridos de SQNR, gráficos, vectores y reporte en `out/` |

## Cuidado con los modos de fxpmath

Estas diferencias con el hardware están verificadas en `test_fxpmath_rounding_semantics`:

| fxpmath | Qué hace | Qué necesita el RTL |
|---|---|---|
| `rounding="trunc"` | redondea **hacia cero** (−2.5 → −2) | truncado de hardware = **`"floor"`** (−2.5 → −3) |
| `rounding="around"` | empates **al par** (2.5 → 2) | **half-up** (2.5 → 3): no existe; se emula sumando ½ LSB y usando `"floor"` |
| `x >> 1` | exacto solo con `config.shifting="expand"` (default) | el ÷2 de la IFFT se hace con `× Fxp(0.5)`, exacto siempre |

Si se usaran `"trunc"` o `"around"` directamente, el modelo **no** coincidiría con el RTL.

## Cómo correrlo

Desde esta carpeta, con Python ≥ 3.10:

```bash
pip install -r requirements.txt
python3 test_math.py      # tests (incluye la comparación bit a bit contra ../vectors)
python3 run_math.py       # métricas, gráficos, vectores y reporte en out/
```

`run_math.py` también compara los vectores que genera contra `../vectors`: tiene que dar
**74/74 archivos idénticos**. En `out/vectors/rom/golden_params.svh` deja los anchos de cada
nodo para el RTL.

## Velocidad

Filtrar 2048 símbolos (512 bloques) tarda ~0.9 s, porque todos los bloques se procesan como
una sola matriz (bloques × 16). `run_math.py` completo, con los barridos de SQNR, ~1 min.
