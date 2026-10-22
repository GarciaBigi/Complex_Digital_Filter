`timescale 1ns / 1ps
// ============================================================================
// fft16.sv - FFT / IFFT de 16 puntos, radix-2 DIT, totalmente paralela
// ----------------------------------------------------------------------------
//   x_blk (orden natural) -> bit-reverso (cableado) -> etapa 1 -> ... -> etapa 4
//
// Cada etapa: 8 mariposas en paralelo + registro de pipeline.
// Throughput: 1 bloque de 16 muestras por ciclo. Latencia: 4 ciclos.
//
// Formatos por defecto (FFT del golden frec_pf):
//   entrada S(8,6) -> etapa 1 S(11,8) -> etapa 2 S(12,8) -> etapa 3 S(13,8)
//   -> etapa 4 S(14,8)            (sin escalar: +1 bit entero por etapa)
// IFFT (INVERSE = 1): S(14,8) en todas las etapas, con /2 por etapa (= 1/16).
// ============================================================================
module fft16 #(
    parameter INVERSE = 0,    // 0 = FFT, 1 = IFFT
    parameter NB_IN   = 8,    // entrada: S(NB_IN, NBF_IN)
    parameter NBF_IN  = 6,
    parameter NB_ST1  = 11,   // salida de cada etapa: S(NB_STx, NBF)
    parameter NB_ST2  = 12,
    parameter NB_ST3  = 13,
    parameter NB_ST4  = 14,
    parameter NBF     = 8
) (
    input  logic                  clk,
    input  logic                  rst_n,      // reset asincronico, activo en bajo
    input  logic                  in_valid,
    input  logic [16*2*NB_IN-1:0] x_blk,      // muestra j en x_blk[j*2*NB_IN +: 2*NB_IN]
    output logic                  out_valid,
    output logic [16*2*NB_ST4-1:0] y_blk      // bin k en y_blk[k*2*NB_ST4 +: 2*NB_ST4]
);

    localparam N  = 16;
    localparam WI = 2 * NB_IN;

    // ------------------------------------------------------------------------
    // Reorden bit-reverso: solo cables (posicion j <- muestra bitrev(j))
    // ------------------------------------------------------------------------
    function integer bitrev4;
        input integer v;
        bitrev4 = {v[0], v[1], v[2], v[3]};
    endfunction

    logic [N*WI-1:0] x_br;

    genvar j;
    generate
        for (j = 0; j < N; j = j + 1) begin : br
            assign x_br[j*WI +: WI] = x_blk[bitrev4(j)*WI +: WI];
        end
    endgenerate

    // ------------------------------------------------------------------------
    // 4 etapas en cascada
    // ------------------------------------------------------------------------
    logic                  v1, v2, v3;
    logic [N*2*NB_ST1-1:0] y1;
    logic [N*2*NB_ST2-1:0] y2;
    logic [N*2*NB_ST3-1:0] y3;

    fft_stage #(.N(N), .STAGE(1), .NB_IN(NB_IN),  .NBF_IN(NBF_IN), .NB_OUT(NB_ST1),
                .NBF_OUT(NBF), .INVERSE(INVERSE))
        st1 (.clk(clk), .rst_n(rst_n), .in_valid(in_valid), .x_blk(x_br),
             .out_valid(v1), .y_blk(y1));

    fft_stage #(.N(N), .STAGE(2), .NB_IN(NB_ST1), .NBF_IN(NBF), .NB_OUT(NB_ST2),
                .NBF_OUT(NBF), .INVERSE(INVERSE))
        st2 (.clk(clk), .rst_n(rst_n), .in_valid(v1), .x_blk(y1),
             .out_valid(v2), .y_blk(y2));

    fft_stage #(.N(N), .STAGE(3), .NB_IN(NB_ST2), .NBF_IN(NBF), .NB_OUT(NB_ST3),
                .NBF_OUT(NBF), .INVERSE(INVERSE))
        st3 (.clk(clk), .rst_n(rst_n), .in_valid(v2), .x_blk(y2),
             .out_valid(v3), .y_blk(y3));

    fft_stage #(.N(N), .STAGE(4), .NB_IN(NB_ST3), .NBF_IN(NBF), .NB_OUT(NB_ST4),
                .NBF_OUT(NBF), .INVERSE(INVERSE))
        st4 (.clk(clk), .rst_n(rst_n), .in_valid(v3), .x_blk(y3),
             .out_valid(out_valid), .y_blk(y_blk));

endmodule
