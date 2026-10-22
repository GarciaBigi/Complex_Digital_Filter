`timescale 1ns / 1ps
// ============================================================================
// fft_stage.sv - Una etapa de la FFT/IFFT radix-2 DIT de N puntos
// ----------------------------------------------------------------------------
// N/2 mariposas en paralelo + registro de salida (1 ciclo de latencia).
//
// Etapa STAGE (1..log2 N), grupos de m = 2^STAGE posiciones:
//   mariposa i -> grupo g = i / (m/2), k = i % (m/2)
//                 a = g*m + k,  b = a + m/2,  twiddle W_N^(k*N/m)
// (los mismos indices que butterfly_indices() del golden)
//
// Twiddles: W_N^k = exp(-j 2 pi k / N) se calcula al elaborar y se cuantiza a
// S(NB_W, NBF_W) con redondeo half-up, igual que twiddle_rom() del golden
// (da los mismos valores que twiddle.hex). Cada mariposa recibe su twiddle
// como constante. En la IFFT se usa el conjugado: se niega la parte imaginaria.
// ============================================================================
module fft_stage #(
    parameter N       = 16,
    parameter STAGE   = 1,    // 1..log2(N)
    parameter NB_IN   = 8,    // entrada: S(NB_IN, NBF_IN)
    parameter NBF_IN  = 6,
    parameter NB_OUT  = 11,   // salida: S(NB_OUT, NBF_OUT)
    parameter NBF_OUT = 8,
    parameter NB_W    = 10,   // twiddle: S(10,8)
    parameter NBF_W   = 8,
    parameter INVERSE = 0     // 1 = IFFT: twiddle conjugado y /2
) (
    input  logic                  clk,
    input  logic                  rst_n,      // reset asincronico, activo en bajo
    input  logic                  in_valid,
    input  logic [N*2*NB_IN-1:0]  x_blk,      // posicion j en x_blk[j*2*NB_IN +: 2*NB_IN]
    output logic                  out_valid,
    output logic [N*2*NB_OUT-1:0] y_blk
);

    localparam WI = 2 * NB_IN;
    localparam WO = 2 * NB_OUT;
    localparam M  = 1 << STAGE;      // tamano de grupo
    localparam HM = M / 2;           // distancia entre a y b
    localparam real PI = 3.14159265358979323846;

    // ------------------------------------------------------------------------
    // N/2 mariposas en paralelo
    // ------------------------------------------------------------------------
    logic [N*WO-1:0] y_next;

    genvar i;
    generate
        for (i = 0; i < N/2; i = i + 1) begin : bf
            localparam IA = (i / HM) * M + (i % HM);
            localparam IB = IA + HM;
            localparam IW = (i % HM) * (N / M);

            // W_N^IW cuantizado: floor(x * 2^NBF_W + 0.5)
            localparam integer W_RE = $rtoi($floor($cos(-2.0 * PI * IW / N) * (1 << NBF_W) + 0.5));
            localparam integer W_IM = $rtoi($floor($sin(-2.0 * PI * IW / N) * (1 << NBF_W) + 0.5));

            butterfly #(
                .NB_IN(NB_IN), .NBF_IN(NBF_IN), .NB_W(NB_W), .NBF_W(NBF_W),
                .NB_OUT(NB_OUT), .NBF_OUT(NBF_OUT), .SCALE(INVERSE),
                .W_RE(W_RE), .W_IM(INVERSE ? -W_IM : W_IM)
            ) u_bf (
                .a    (x_blk[IA*WI +: WI]),
                .b    (x_blk[IB*WI +: WI]),
                .a_out(y_next[IA*WO +: WO]),
                .b_out(y_next[IB*WO +: WO])
            );
        end
    endgenerate

    // ------------------------------------------------------------------------
    // Registro de salida (registro de pipeline entre etapas)
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
