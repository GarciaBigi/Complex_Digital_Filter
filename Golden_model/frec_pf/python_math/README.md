# Golden con fxpmath (`python_math/`)

Es la misma implementación que [`../python`](../python), escrita con la librería
[fxpmath](https://github.com/francof2a/fxpmath) en lugar de enteros y shifts a mano.
**Da los mismos resultados bit a bit**: los 74 archivos `.hex` que exporta son idénticos a
los de `../vectors`, y `test_math.py` compara todos los nodos internos en 5 configuraciones
distintas.

| `python/` (enteros) | `python_math/` (fxpmath) | Qué cambia |
|---|---|---|
| `fixed_point.py` | `fxp_utils.py` | `Fmt` → dtype `fxp-sNB/NBF`; `requant` y `quantize` sobre objetos `Fxp` |
| `config.py` | `config.py` | idéntico (solo cambia de dónde importa `Fmt`) |
| `signals.py` | `signals.py` | idéntico (no usa punto fijo) |
| `fft_fixed.py` | `fft_fxp.py` | sin alinear a mano: fxpmath alinea los puntos en `a + W·b` |
| `freq_filter.py` | `freq_filter.py` | procesa todos los bloques a la vez (matriz bloques × 16) |
| `test_golden.py` | `test_math.py` | + comparación bit a bit contra `../python` |
| `run_golden.py` | `run_math.py` | salidas en `out/` + comparación contra `../vectors` |

## Cuidado con los modos de fxpmath

Estas diferencias con el hardware están verificadas en `test_fxpmath_rounding_semantics`:

| fxpmath | Qué hace | Qué necesita el RTL |
|---|---|---|
| `rounding="trunc"` | redondea **hacia cero** (−2.5 → −2) | truncado de hardware = **`"floor"`** (−2.5 → −3) |
| `rounding="around"` | empates **al par** (2.5 → 2) | **half-up** (2.5 → 3): no existe; se emula sumando ½ LSB y usando `"floor"` |
| `x >> 1` | exacto solo con `config.shifting="expand"` (default) | el ÷2 de la IFFT se hace con `× Fxp(0.5)`, exacto siempre |

Si se usaran `"trunc"` o `"around"` directamente, el modelo **no** coincidiría con el RTL.

## Cómo correrlo

Desde esta carpeta (`python_math/`), con Python ≥ 3.10:

```bash
pip install -r requirements.txt
python3 test_math.py      # tests de consistencia
python3 run_math.py       # métricas, gráficos, vectores y comparación contra ../vectors
```

En este repo no está `../python` (el golden de enteros), así que el test bit a bit contra él
se saltea y lo avisa en pantalla. La equivalencia ya se verificó en el repo original: todos
los nodos, en 5 configuraciones, son idénticos. `run_math.py` igual compara su salida contra
`../vectors` (que generó el golden de enteros): tiene que dar **74/74 archivos idénticos**.

## Comparación entre las dos versiones

| | Enteros (`python/`) | fxpmath (`python_math/`) |
|---|---|---|
| Resultado | referencia | idéntico bit a bit |
| Legibilidad | bits fraccionales y shifts explícitos | cada valor conoce su formato |
| Riesgo | errores al alinear a mano | usar un modo de redondeo de la librería que no es el del RTL |
| `run()` con 2048 símbolos | 0.54 s | 0.91 s (vectorizado sobre los bloques) |
| `run_*.py` completo | 34 s | 56 s |
| Dependencias | numpy | numpy + fxpmath (pip) |
