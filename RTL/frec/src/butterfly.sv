`timescale 1ns / 1ps
// ============================================================================
// butterfly.sv - Mariposa radix-2 DIT (combinacional)
// ----------------------------------------------------------------------------
//     a' = (a + W*b) [/2 si SCALE]
//     b' = (a - W*b) [/2 si SCALE]
//
// Aritmetica (igual al golden frec_pf, bit-exact):
//   * t = W*b a ancho completo (fraccionales NBF_IN + NBF_W).
//   * a se alinea con t corriendolo NBF_W bits; a +/- t tambien es exacto.
//   * El /2 de la IFFT no cuesta logica: es correr el punto un bit mas
//     (se descarta un bit mas en el redondeo).
//   * Un solo redondeo half-up y saturacion por salida.
//
// El twiddle es un parametro (constante): la sintesis no pone multiplicador
// para W = 1 o W = -j (+j en la IFFT) y usa multiplicadores por constante
// en el resto.
//
// Operandos complejos empaquetados {im, re}, igual que los .hex del golden.
// ============================================================================
module butterfly #(
    parameter NB_IN   = 8,    // a, b: S(NB_IN, NBF_IN)
    parameter NBF_IN  = 6,
    parameter NB_W    = 10,   // twiddle: S(10,8)
    parameter NBF_W   = 8,
    parameter NB_OUT  = 11,   // a', b': S(NB_OUT, NBF_OUT)
    parameter NBF_OUT = 8,
    parameter SCALE   = 0,    // 1 = divide por 2 (IFFT)
    parameter W_RE    = 256,  // twiddle W = W_RE + j W_IM (enteros en S(NB_W, NBF_W))
    parameter W_IM    = 0
) (
    input  logic [2*NB_IN-1:0]  a,
    input  logic [2*NB_IN-1:0]  b,
    output logic [2*NB_OUT-1:0] a_out,
    output logic [2*NB_OUT-1:0] b_out
);

    // ------------------------------------------------------------------------
    // Anchos internos
    // ------------------------------------------------------------------------
    localparam NB_T = NB_IN + NB_W + 2;               // a +/- W*b sin desborde
    localparam SH   = NBF_IN + NBF_W + SCALE - NBF_OUT; // bits fraccionales a descartar

    localparam signed [NB_T:0] Y_MAX =  (1 <<< (NB_OUT - 1)) - 1;
    localparam signed [NB_T:0] Y_MIN = -(1 <<< (NB_OUT - 1));

    // ------------------------------------------------------------------------
    // Redondeo half-up + saturacion: ancho completo -> S(NB_OUT, NBF_OUT)
    // ------------------------------------------------------------------------
    function signed [NB_OUT-1:0] round_sat;
        input signed [NB_T-1:0] v;
        reg   signed [NB_T:0]   t;
    begin
        t = v;                          // un bit mas para que la suma no desborde
        t = t + (1 <<< (SH - 1));       // + medio LSB de salida
        t = t >>> SH;                   // desplazamiento aritmetico (= floor)
        if (t > Y_MAX)      round_sat = Y_MAX[NB_OUT-1:0];
        else if (t < Y_MIN) round_sat = Y_MIN[NB_OUT-1:0];
        else                round_sat = t[NB_OUT-1:0];
    end
    endfunction

    // ------------------------------------------------------------------------
    // Desempaquetado con signo
    // ------------------------------------------------------------------------
    wire signed [NB_IN-1:0] a_re = a[NB_IN-1:0];
    wire signed [NB_IN-1:0] a_im = a[2*NB_IN-1:NB_IN];
    wire signed [NB_IN-1:0] b_re = b[NB_IN-1:0];
    wire signed [NB_IN-1:0] b_im = b[2*NB_IN-1:NB_IN];
    localparam signed [NB_W-1:0] w_re = W_RE;
    localparam signed [NB_W-1:0] w_im = W_IM;

    // ------------------------------------------------------------------------
    // t = W*b y a alineado (ambos con NBF_IN + NBF_W fraccionales)
    // ------------------------------------------------------------------------
    wire signed [NB_T-1:0] t_re = b_re * w_re - b_im * w_im;
    wire signed [NB_T-1:0] t_im = b_re * w_im + b_im * w_re;
    wire signed [NB_T-1:0] al_re = a_re <<< NBF_W;
    wire signed [NB_T-1:0] al_im = a_im <<< NBF_W;

    assign a_out = {round_sat(al_im + t_im), round_sat(al_re + t_re)};
    assign b_out = {round_sat(al_im - t_im), round_sat(al_re - t_re)};

endmodule
