// Generado por tiempo_pf.py - NO EDITAR A MANO
// Formato S(NB,NBF): NB bits totales con signo, NBF fraccionales
localparam int N_TAPS = 8;
localparam int NB_X = 8, NBF_X = 6;
localparam int NB_H = 8, NBF_H = 7;
localparam int NB_ACC = 19, NBF_ACC = 13;
localparam int NB_Y = 10, NBF_Y = 8;
// redondeo = half-up solo a la salida, overflow = sat
// h.hex: h[n] n=0..N_TAPS-1 ; x_in/y_out: palabras {im, re}
