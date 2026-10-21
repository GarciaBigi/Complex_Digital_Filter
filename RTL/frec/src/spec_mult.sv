// ============================================================================
// spec_mult.sv - Multiplicacion espectral Y[k] = X[k] * H[k]
// ----------------------------------------------------------------------------
// Filtro en frecuencia (overlap-save, FFT de 16 puntos).
// Totalmente paralelo: procesa los 16 bins de un bloque en un ciclo
// (16 multiplicadores complejos).
//
// Aritmetica (igual al golden frec_pf, bit-exact):
//   * El producto complejo se calcula a ancho completo:
//       p_re = x_re*h_re - x_im*h_im
//       p_im = x_re*h_im + x_im*h_re
//   * Un solo redondeo half-up a la salida: (p + 2^(SH-1)) >>> SH
//   * Saturacion al formato de salida.
//
// Empaquetado de los buses (igual que los .hex del golden):
//   cada bin ocupa una palabra {im, re}; el bin k esta en [k*W +: W].
// ============================================================================
`timescale 1ns / 1ps

module spec_mult #(
    parameter N      = 16,   // bins por bloque
    parameter NB_X   = 14,   // X[k]: S(14,8)
    parameter NBF_X  = 8,
    parameter NB_H   = 10,   // H[k]: S(10,8)
    parameter NBF_H  = 8,
    parameter NB_Y   = 14,   // Y[k]: S(14,8)
    parameter NBF_Y  = 8,
    // ROM de H[k], palabras {im, re}. Ruta relativa a RTL/frec/sim (desde donde se
    // corren iverilog y yosys); el testbench la sobreescribe.
    parameter     H_FILE = "../../../Golden_model/frec_pf/vectors/rom/H.hex"
) (
    input  logic                  clk,
    input  logic                  rst_n,      // reset asincronico, activo en bajo
    input  logic                  in_valid,   // hay un bloque valido en x_blk
    input  logic [N*2*NB_X-1:0]   x_blk,      // 16 bins X[k]
    output logic                  out_valid,  // hay un bloque valido en y_blk
    output logic [N*2*NB_Y-1:0]   y_blk       // 16 bins Y[k]
);

    // ------------------------------------------------------------------------
    // Anchos internos
    // ------------------------------------------------------------------------
    localparam NB_P = NB_X + NB_H;                // un producto real: 24 bits
    localparam NB_S = NB_P + 1;                   // suma de dos productos: 25 bits
    localparam SH   = NBF_X + NBF_H - NBF_Y;      // bits fraccionales a descartar: 8

    localparam signed [NB_S:0] Y_MAX =  (1 <<< (NB_Y - 1)) - 1;   //  8191
    localparam signed [NB_S:0] Y_MIN = -(1 <<< (NB_Y - 1));       // -8192

    // ------------------------------------------------------------------------
    // ROM de H[k] (16 constantes)
    // ------------------------------------------------------------------------
    logic [2*NB_H-1:0] rom_h [0:N-1];
    initial $readmemh(H_FILE, rom_h);

    // ------------------------------------------------------------------------
    // Redondeo half-up + saturacion: ancho completo -> S(NB_Y, NBF_Y)
    // ------------------------------------------------------------------------
    function signed [NB_Y-1:0] round_sat;
        input signed [NB_S-1:0] v;
        reg   signed [NB_S:0]   t;
    begin
        t = v;                          // un bit mas para que la suma no desborde
        t = t + (1 <<< (SH - 1));       // + medio LSB de salida
        t = t >>> SH;                   // desplazamiento aritmetico (= floor)
        if (t > Y_MAX)      round_sat = Y_MAX[NB_Y-1:0];
        else if (t < Y_MIN) round_sat = Y_MIN[NB_Y-1:0];
        else                round_sat = t[NB_Y-1:0];
    end
    endfunction

    // ------------------------------------------------------------------------
    // 16 multiplicadores complejos en paralelo
    // ------------------------------------------------------------------------
    logic [N*2*NB_Y-1:0] y_next;

    genvar k;
    generate
        for (k = 0; k < N; k = k + 1) begin : bin
            // Desempaquetado con signo (se ven por bin en GTKWave: dut.bin[k].*)
            wire signed [NB_X-1:0] x_re, x_im;
            wire signed [NB_H-1:0] h_re, h_im;
            wire signed [NB_S-1:0] p_re, p_im;
            wire signed [NB_Y-1:0] y_re, y_im;

            assign x_re = x_blk[k*2*NB_X        +: NB_X];
            assign x_im = x_blk[k*2*NB_X + NB_X +: NB_X];
            assign h_re = rom_h[k][NB_H-1:0];
            assign h_im = rom_h[k][2*NB_H-1:NB_H];

            // Producto complejo a ancho completo (operandos con signo,
            // se extienden a NB_S bits antes de multiplicar)
            assign p_re = x_re * h_re - x_im * h_im;
            assign p_im = x_re * h_im + x_im * h_re;

            assign y_re = round_sat(p_re);
            assign y_im = round_sat(p_im);

            assign y_next[k*2*NB_Y +: 2*NB_Y] = {y_im, y_re};
        end
    endgenerate

    // ------------------------------------------------------------------------
    // Registro de salida (1 ciclo de latencia).
    // El "if (in_valid)" es la habilitacion que la sintesis convierte en
    // clock gating (bajo consumo).
    // ------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            y_blk     <= 0;
        end else begin
            out_valid <= in_valid;
            if (in_valid) y_blk <= y_next;
        end
    end

endmodule
