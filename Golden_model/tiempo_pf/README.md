# Golden model en punto fijo: filtro RRC en el dominio del tiempo

Modelo **bit-exacto** del FIR directo de 8 taps, para verificar el RTL de tiempo.

- h es real: el filtro complejo son 2 FIR reales iguales (I y Q).
- Producto y suma a precisión completa, un solo redondeo (half-up + saturación) a la salida.
  El orden de la suma no cambia el resultado: sirve para un RTL serie o paralelo.
- Usa los taps de `../frec_float` y los datasets de `../frec_pf`: los `x_in.hex` son
  idénticos a los de frecuencia, así que los dos RTL se prueban con los mismos vectores.

## Cómo correrlo

```bash
python tiempo_pf.py
```

Verifica contra el modelo en flotante, hace el barrido de bits, exporta `vectors/` y
compara la salida contra la de `frec_pf`.

## Formatos (S(NB, NBF) = NB bits con signo, NBF fraccionales)

| Nodo | Formato |
|---|---|
| x[n] entrada | S(8,6), igual que frec_pf |
| h[n] taps | S(8,7) |
| acumulador | S(19,13), sin overflow posible |
| y[n] salida | S(10,8), igual que frec_pf |

Resultado: SNR ≈ 65 dB contra el flotante, error ≤ 0.14 LSB de salida, sin saturación en el
peor caso. La salida difiere en ≤ 1 LSB de la del filtro en frecuencia.

## Vectores

```
vectors/rom/h.hex               taps h[0..7]
vectors/rom/tiempo_params.svh   anchos de cada nodo
vectors/<dataset>/x_in.hex      entrada, palabras {im, re}
vectors/<dataset>/y_out.hex     salida esperada (causal, len(x) muestras), {im, re}
```
