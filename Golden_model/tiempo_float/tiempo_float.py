import numpy as np
import matplotlib.pyplot as plt

from comun import (
    N_TAPS, SPS, ROLLOFF, T_TAPS, N_FFT_NORM,
    coeficientes_rrc, conjuntos_de_datos, cota_salida
)


# 1. Coeficientes y señales de entrada
h = coeficientes_rrc()
x = conjuntos_de_datos(h)

print("Coeficientes:", h)
print("max|H[k]| con FFT de 16:", np.max(np.abs(np.fft.fft(h, N_FFT_NORM))))
print("Retardo [muestras]:", (N_TAPS - 1) / 2)


# 2. Filtrar cada señal, muestra por muestra
y = {}

for nombre in x:
    entrada = x[nombre]
    salida = np.zeros(len(entrada), dtype=complex)
    linea = np.zeros(N_TAPS, dtype=complex)

    for n in range(len(entrada)):
        linea[1:] = linea[:-1]       # desplazar las muestras anteriores
        linea[0] = entrada[n]        # ingresar la muestra nueva
        productos = h * linea        # multiplicar por los coeficientes
        salida[n] = np.sum(productos)

    y[nombre] = salida


# 3. Comparar con la convolución de NumPy
tol = 1e-12

print("\nComparación con np.convolve:")

for nombre in x:
    referencia = np.convolve(x[nombre], h)[:len(x[nombre])]
    error = np.max(np.abs(y[nombre] - referencia))
    print(nombre, "error máximo:", error, "OK:", error < tol)


# 4. Verificar la respuesta al impulso
error_i = np.max(np.abs(y["impulso_i"][:N_TAPS] - h))
error_q = np.max(np.abs(y["impulso_q"][:N_TAPS] - 1j * h))

print("\nImpulso I correcto:", error_i < tol)
print("Impulso Q correcto:", error_q < tol)


# 5. Verificar la cota de salida por componente
cota = cota_salida(h)
pico = y["peor_caso"].real

print("\nCota de salida:", cota)
print("Peor caso alcanza +cota:", abs(pico.max() - cota) < tol)
print("Peor caso alcanza -cota:", abs(pico.min() + cota) < tol)

for nombre in y:
    maximo = max(
        np.max(np.abs(y[nombre].real)),
        np.max(np.abs(y[nombre].imag))
    )
    print(nombre, "máximo por componente:", maximo,
          "dentro de cota:", maximo <= cota + tol)


# 6. Respuesta en frecuencia
N_FFT = 4096

H = np.fft.fftshift(np.fft.fft(h, N_FFT))
f = np.fft.fftshift(np.fft.fftfreq(N_FFT)) * SPS

# Normalizar respecto de la ganancia en continua
magnitud = np.abs(H) / np.abs(H[N_FFT // 2])
H_db = 20 * np.log10(np.maximum(magnitud, 1e-12))

rechazo = np.abs(f) >= (1 + ROLLOFF) / 2

print("\nRespuesta en Rs/2 [dB]:", np.interp(0.5, f, H_db))
print("Máximo en banda de rechazo [dB]:", np.max(H_db[rechazo]))


# 7. Mostrar los coeficientes
plt.figure()
plt.stem(T_TAPS, h)
plt.xlabel("t [períodos de símbolo]")
plt.ylabel("h[k]")
plt.title("Coeficientes RRC")
plt.grid()
plt.tight_layout()


# 8. Mostrar la respuesta en frecuencia
plt.figure()
plt.plot(f, H_db)
plt.xlabel("f / Rs")
plt.ylabel("|H| [dB]")
plt.title("Respuesta en frecuencia")
plt.ylim(-60, 5)
plt.grid()
plt.tight_layout()


# 9. Mostrar entrada y salida QPSK: primeras 48 muestras
n = np.arange(48)

plt.figure()
plt.stem(n, x["qpsk_s1"].real[:48],
         linefmt="C1-", markerfmt="C1o", basefmt=" ",
         label="Entrada I")
plt.plot(n, y["qpsk_s1"].real[:48], "C0.-", label="Salida I")
plt.xlabel("n [muestras]")
plt.title("QPSK: entrada y salida")
plt.legend()
plt.grid()
plt.tight_layout()

plt.show()
