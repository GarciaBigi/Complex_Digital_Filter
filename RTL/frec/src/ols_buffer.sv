`timescale 1ns / 1ps
// ============================================================================
// ols_buffer.sv - Armado de bloque del overlap-save (50 % de solapamiento)
// ----------------------------------------------------------------------------
// Recibe una muestra compleja por vez y, cada 8 muestras nuevas, entrega un
// bloque de 16 muestras para la FFT:
//
//     bloque = [ 8 muestras anteriores | 8 muestras nuevas ]
//               posiciones 0..7          posiciones 8..15
//
// Arranca con las 8 "anteriores" en cero (igual que el golden frec_pf).
//
// Arquitectura con dos bancos de 8 registros (en vez de un registro de
// desplazamiento de 16):
//   * nuevo[0..7]: cada muestra se escribe en nuevo[cnt]. Por muestra se
//     escribe UN solo registro, los demas no conmutan (menos consumo).
//   * viejo[0..7]: al completar el bloque, el banco nuevo pasa a ser el viejo.
//
// Empaquetado (igual que blk_in.hex): cada muestra es {im, re}; la muestra j
// del bloque esta en blk[j*W +: W].
// ============================================================================
module ols_buffer #(
    parameter NB   = 8,    // bits de cada parte (re, im) de x[n]: S(8,6)
    parameter HOP  = 8,    // muestras nuevas por bloque
    parameter N    = 16    // muestras por bloque (= 2*HOP)
) (
    input  logic                clk,
    input  logic                rst_n,      // reset asincronico, activo en bajo
    input  logic                s_valid,    // hay una muestra valida en s_data
    input  logic [2*NB-1:0]     s_data,     // muestra x[n] = {im, re}
    output logic                blk_valid,  // hay un bloque nuevo en blk
    output logic [N*2*NB-1:0]   blk         // 16 muestras, la 0 es la mas vieja
);

    localparam W = 2 * NB;       // bits por muestra compleja: 16

    // ------------------------------------------------------------------------
    // Registros
    // ------------------------------------------------------------------------
    logic [W-1:0] nuevo [0:HOP-1];   // muestras del bloque que se esta armando
    logic [W-1:0] viejo [0:HOP-1];   // las 8 muestras del bloque anterior
    logic [$clog2(HOP)-1:0] cnt;     // posicion donde va la proxima muestra (0..7)

    logic ultima;                    // esta muestra completa el bloque
    integer i, j;                    // indices de los for (se desenrollan)
    assign ultima = s_valid && (cnt == HOP - 1);

    // ------------------------------------------------------------------------
    // Escritura de muestras y armado del bloque
    // ------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt       <= 0;
            blk_valid <= 1'b0;
            blk       <= 0;
            for (i = 0; i < HOP; i = i + 1) begin
                nuevo[i] <= 0;
                viejo[i] <= 0;       // estado inicial: 8 muestras previas en cero
            end
        end else begin
            blk_valid <= 1'b0;       // por defecto no hay bloque nuevo

            if (s_valid) begin
                nuevo[cnt] <= s_data;          // guarda la muestra en su lugar
                cnt        <= cnt + 1'b1;      // de 7 pasa a 0 solo (3 bits, HOP potencia de 2)
            end

            if (ultima) begin
                // Bloque = 8 viejas + 7 nuevas ya guardadas + la que llega ahora.
                // (nuevo[7] todavia no tiene s_data: se escribe en este mismo flanco)
                for (j = 0; j < HOP; j = j + 1) begin
                    blk[j*W +: W] <= viejo[j];
                end
                for (j = 0; j < HOP - 1; j = j + 1) begin
                    blk[(HOP + j)*W +: W] <= nuevo[j];
                end
                blk[(N - 1)*W +: W] <= s_data;
                blk_valid <= 1'b1;

                // Las 8 nuevas pasan a ser las viejas del proximo bloque
                for (j = 0; j < HOP - 1; j = j + 1) begin
                    viejo[j] <= nuevo[j];
                end
                viejo[HOP - 1] <= s_data;
            end
        end
    end

endmodule
