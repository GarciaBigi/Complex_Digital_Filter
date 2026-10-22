`timescale 1ns / 1ps
// ============================================================================
// ols_output.sv - Descarte del overlap-save + salida serie (P/S)
// ----------------------------------------------------------------------------
// Recibe el bloque y_c de la IFFT (16 muestras) y saca las 8 validas, una por
// ciclo:
//
//     y_c = [ 0..7: aliasing circular, se descartan | 8..15: salida y[n] ]
//
// Formato: S(14,8) -> S(10,8). Los bits fraccionales son los mismos, asi que no
// hay redondeo: solo se recortan bits enteros (saturacion; con las cotas del
// golden nunca se activa).
//
// Al llegar un bloque, la muestra 8 sale en el ciclo siguiente y las otras 7
// quedan en un registro de desplazamiento. Con una muestra de entrada por
// ciclo como maximo, los bloques llegan cada 8 ciclos o mas: el registro ya se
// vacio cuando llega el siguiente.
// ============================================================================
module ols_output #(
    parameter N       = 16,   // muestras por bloque
    parameter HOP     = 8,    // muestras validas por bloque
    parameter NB_IN   = 14,   // y_c: S(14,8)
    parameter NB_OUT  = 10    // y[n]: S(10,8) (mismos bits fraccionales)
) (
    input  logic                 clk,
    input  logic                 rst_n,      // reset asincronico, activo en bajo
    input  logic                 blk_valid,  // hay un bloque y_c en blk
    input  logic [N*2*NB_IN-1:0] blk,        // muestra j en blk[j*2*NB_IN +: 2*NB_IN]
    output logic                 m_valid,    // hay una muestra valida en m_data
    output logic [2*NB_OUT-1:0]  m_data      // y[n] = {im, re}
);

    localparam WI = 2 * NB_IN;
    localparam WO = 2 * NB_OUT;

    localparam signed [NB_IN-1:0] Y_MAX =  (1 <<< (NB_OUT - 1)) - 1;
    localparam signed [NB_IN-1:0] Y_MIN = -(1 <<< (NB_OUT - 1));

    // Saturacion S(NB_IN, F) -> S(NB_OUT, F)
    function signed [NB_OUT-1:0] sat;
        input signed [NB_IN-1:0] v;
    begin
        if (v > Y_MAX)      sat = Y_MAX[NB_OUT-1:0];
        else if (v < Y_MIN) sat = Y_MIN[NB_OUT-1:0];
        else                sat = v[NB_OUT-1:0];
    end
    endfunction

    // ------------------------------------------------------------------------
    // Descarte: solo se usan las posiciones HOP..N-1, ya en S(NB_OUT, F)
    // ------------------------------------------------------------------------
    logic [WO-1:0] valida [0:HOP-1];

    genvar j;
    generate
        for (j = 0; j < HOP; j = j + 1) begin : desc
            wire signed [NB_IN-1:0] re = blk[(HOP + j)*WI          +: NB_IN];
            wire signed [NB_IN-1:0] im = blk[(HOP + j)*WI + NB_IN  +: NB_IN];
            assign valida[j] = {sat(im), sat(re)};
        end
    endgenerate

    // ------------------------------------------------------------------------
    // Salida serie
    // ------------------------------------------------------------------------
    logic [WO-1:0] pend [0:HOP-2];          // muestras que faltan sacar
    logic [$clog2(HOP)-1:0] quedan;         // cuantas hay en pend (0..7)
    integer i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_valid <= 1'b0;
            m_data  <= 0;
            quedan  <= 0;
            for (i = 0; i < HOP - 1; i = i + 1) pend[i] <= 0;
        end else begin
            m_valid <= 1'b0;                 // por defecto no hay muestra
            if (blk_valid) begin
                m_data  <= valida[0];
                m_valid <= 1'b1;
                for (i = 0; i < HOP - 1; i = i + 1) pend[i] <= valida[i + 1];
                quedan  <= HOP - 1;
            end else if (quedan != 0) begin
                m_data  <= pend[0];
                m_valid <= 1'b1;
                for (i = 0; i < HOP - 2; i = i + 1) pend[i] <= pend[i + 1];
                quedan  <= quedan - 1'b1;
            end
        end
    end

endmodule
