// Generado por python_math/run_math.py - NO EDITAR A MANO
// Formato S(NB,NBF): NB bits totales con signo, NBF fraccionales
localparam int N_FFT  = 16;
localparam int HOP    = 8;
localparam int N_TAPS = 8;
localparam int NB_X = 8, NBF_X = 6;
localparam int NB_TW = 10, NBF_TW = 8;
localparam int NB_H = 10, NBF_H = 8;
localparam int NB_Y_SPEC = 14, NBF_Y_SPEC = 8;
localparam int NB_Y = 10, NBF_Y = 8;
localparam int NB_FFT1 = 11, NBF_FFT1 = 8;
localparam int NB_FFT2 = 12, NBF_FFT2 = 8;
localparam int NB_FFT3 = 13, NBF_FFT3 = 8;
localparam int NB_FFT4 = 14, NBF_FFT4 = 8;
localparam int NB_IFFT1 = 14, NBF_IFFT1 = 8;
localparam int NB_IFFT2 = 14, NBF_IFFT2 = 8;
localparam int NB_IFFT3 = 14, NBF_IFFT3 = 8;
localparam int NB_IFFT4 = 14, NBF_IFFT4 = 8;
// redondeo = round, overflow = sat
// Palabras hex complejas empaquetadas como {im, re}
// H.hex / twiddle.hex: ROM_H[k] k=0..N-1 ; ROM_W[k] = W_N^k k=0..N/2-1
