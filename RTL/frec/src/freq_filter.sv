`timescale 1ns / 1ps
// ============================================================================
// freq_filter.sv - Filtro RRC en el dominio de la frecuencia (top)
// ----------------------------------------------------------------------------
// Overlap-save con 50 % de solapamiento y FFT de 16 puntos:
//
//   x[n] -> ols_buffer -> FFT16 -> X[k]*H[k] -> IFFT16 -> ols_output -> y[n]
//   S(8,6)  16 x S(8,6)  S(14,8)    S(14,8)    S(14,8)    8 x S(10,8)   S(10,8)
//
// Entrada y salida serie: una muestra compleja {im, re} por ciclo como maximo.
// El nucleo FFT -> X*H -> IFFT es totalmente paralelo (un bloque por ciclo).
//
// Latencia: desde la muestra que completa un bloque hasta la primera muestra
// de salida de ese bloque, 11 ciclos (buffer 1 + FFT 4 + mult 1 + IFFT 4 +
// salida 1). y[n] coincide bit a bit con y_out.hex del golden frec_pf.
// ============================================================================
module freq_filter #(
    // ROM de H[k] (ruta relativa a RTL/frec/sim, desde donde se corren iverilog y yosys)
    parameter     H_FILE = "../../../Golden_model/frec_pf/vectors/rom/H.hex"
) (
    input  logic        clk,
    input  logic        rst_n,      // reset asincronico, activo en bajo
    input  logic        s_valid,    // hay una muestra valida en s_data
    input  logic [15:0] s_data,     // x[n] = {im, re}, S(8,6)
    output logic        m_valid,    // hay una muestra valida en m_data
    output logic [19:0] m_data      // y[n] = {im, re}, S(10,8)
);

    localparam N = 16;

    logic              blk_valid, x_valid, y_valid, yc_valid;
    logic [N*2*8-1:0]  blk;         // bloque de entrada: 16 x S(8,6)
    logic [N*2*14-1:0] x_blk;       // X[k]:              16 x S(14,8)
    logic [N*2*14-1:0] y_blk;       // Y[k] = X[k]*H[k]:  16 x S(14,8)
    logic [N*2*14-1:0] yc_blk;      // y_c = IFFT(Y):     16 x S(14,8)

    ols_buffer #(.NB(8), .HOP(8), .N(N)) u_buffer (
        .clk(clk), .rst_n(rst_n),
        .s_valid(s_valid), .s_data(s_data),
        .blk_valid(blk_valid), .blk(blk)
    );

    fft16 #(
        .INVERSE(0), .NB_IN(8), .NBF_IN(6),
        .NB_ST1(11), .NB_ST2(12), .NB_ST3(13), .NB_ST4(14), .NBF(8)
    ) u_fft (
        .clk(clk), .rst_n(rst_n),
        .in_valid(blk_valid), .x_blk(blk),
        .out_valid(x_valid), .y_blk(x_blk)
    );

    spec_mult #(.N(N), .H_FILE(H_FILE)) u_mult (
        .clk(clk), .rst_n(rst_n),
        .in_valid(x_valid), .x_blk(x_blk),
        .out_valid(y_valid), .y_blk(y_blk)
    );

    fft16 #(
        .INVERSE(1), .NB_IN(14), .NBF_IN(8),
        .NB_ST1(14), .NB_ST2(14), .NB_ST3(14), .NB_ST4(14), .NBF(8)
    ) u_ifft (
        .clk(clk), .rst_n(rst_n),
        .in_valid(y_valid), .x_blk(y_blk),
        .out_valid(yc_valid), .y_blk(yc_blk)
    );

    ols_output #(.N(N), .HOP(8), .NB_IN(14), .NB_OUT(10)) u_output (
        .clk(clk), .rst_n(rst_n),
        .blk_valid(yc_valid), .blk(yc_blk),
        .m_valid(m_valid), .m_data(m_data)
    );

endmodule
