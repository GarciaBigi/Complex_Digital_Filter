`timescale 1ns / 1ps
// ============================================================================
// tb_fft16 - Testbench de la FFT / IFFT de 16 puntos
//
// Compara el RTL bit a bit contra el golden en punto fijo (frec_pf), etapa por
// etapa:
//   FFT  (INVERSE = 0): entrada blk_in.hex    -> fft_st1.hex .. fft_st4.hex
//   IFFT (INVERSE = 1): entrada spec_mult.hex -> ifft_st1.hex .. ifft_st4.hex
//
// Los 64 bloques de cada dataset se mandan seguidos (uno por ciclo) para probar
// que el pipeline procesa un bloque por ciclo.
//
// El dataset "stress" (muestras aleatorias sin sobremuestreo, no QPSK) es el
// que prueba el redondeo de la FFT: con QPSK sobremuestreada la mitad de las
// muestras son cero y ninguna etapa de la FFT descarta bits distintos de cero.
//
// Correr desde RTL/frec/tb o RTL/frec/sim:
//   iverilog -g2012 -o tb_fft16.vvp ../src/butterfly.sv ../src/fft_stage.sv \
//            ../src/fft16.sv tb_fft16.sv                    (FFT)
//   iverilog -g2012 -Ptb_fft16.INVERSE=1 -o ...             (IFFT)
//   vvp tb_fft16.vvp
// ============================================================================
module tb_fft16;

  parameter INVERSE = 0;

  localparam VEC = "../../../Golden_model/frec_pf/vectors";

  localparam N    = 16;     // puntos por bloque
  localparam NBLK = 64;     // bloques por dataset
  localparam WM   = 28;     // ancho de las memorias (el mayor: {im, re} de 14 bits)

  // Formatos (golden frec_pf)
  localparam NB_IN  = INVERSE ? 14 : 8;
  localparam NBF_IN = INVERSE ? 8  : 6;
  localparam NB1    = INVERSE ? 14 : 11;
  localparam NB2    = INVERSE ? 14 : 12;
  localparam NB3    = INVERSE ? 14 : 13;
  localparam NB4    = 14;

  reg                  clk;
  reg                  rst_n;
  reg                  in_valid;
  reg  [N*2*NB_IN-1:0] x_blk;
  wire                 out_valid;
  wire [N*2*NB4-1:0]   y_blk;

  fft16 #(
      .INVERSE(INVERSE), .NB_IN(NB_IN), .NBF_IN(NBF_IN),
      .NB_ST1(NB1), .NB_ST2(NB2), .NB_ST3(NB3), .NB_ST4(NB4), .NBF(8)
  ) u_fft16 (
      .clk(clk),
      .rst_n(rst_n),
      .in_valid(in_valid),
      .x_blk(x_blk),
      .out_valid(out_valid),
      .y_blk(y_blk)
  );

  always #5 clk = ~clk;

  // Memorias donde se cargan los .hex
  reg [WM-1:0] x_mem  [0:N*NBLK-1];
  reg [WM-1:0] e1_mem [0:N*NBLK-1];
  reg [WM-1:0] e2_mem [0:N*NBLK-1];
  reg [WM-1:0] e3_mem [0:N*NBLK-1];
  reg [WM-1:0] e4_mem [0:N*NBLK-1];

  integer bloques [1:4];     // bloques recibidos en cada etapa
  integer errores;           // errores del dataset actual
  integer total_errores;     // errores de todos los datasets

  // --------------------------------------------------------------------------
  // Tarea: compara un elemento de la salida de una etapa con el golden.
  // Es "automatic" porque la llaman 4 always en el mismo flanco: con una tarea
  // estatica los argumentos de una llamada pisan los de otra.
  // --------------------------------------------------------------------------
  task automatic comparar;
    input integer  etapa, k;
    input [WM-1:0] obtenido, esperado;
    begin
      if (obtenido !== esperado) begin
        errores = errores + 1;
        if (errores <= 5)
          $display("  ERROR etapa %0d bloque %0d pos %0d: RTL = %h | Esperado = %h",
                   etapa, bloques[etapa], k, obtenido, esperado);
      end
    end
  endtask

  // --------------------------------------------------------------------------
  // Verificadores: miran la salida de cada etapa en el flanco de bajada
  // --------------------------------------------------------------------------
  integer k1, k2, k3, k4;

  always @(negedge clk) if (rst_n && u_fft16.st1.out_valid) begin
    for (k1 = 0; k1 < N; k1 = k1 + 1)
      comparar(1, k1, u_fft16.st1.y_blk[k1*2*NB1 +: 2*NB1], e1_mem[bloques[1]*N + k1]);
    bloques[1] = bloques[1] + 1;
  end

  always @(negedge clk) if (rst_n && u_fft16.st2.out_valid) begin
    for (k2 = 0; k2 < N; k2 = k2 + 1)
      comparar(2, k2, u_fft16.st2.y_blk[k2*2*NB2 +: 2*NB2], e2_mem[bloques[2]*N + k2]);
    bloques[2] = bloques[2] + 1;
  end

  always @(negedge clk) if (rst_n && u_fft16.st3.out_valid) begin
    for (k3 = 0; k3 < N; k3 = k3 + 1)
      comparar(3, k3, u_fft16.st3.y_blk[k3*2*NB3 +: 2*NB3], e3_mem[bloques[3]*N + k3]);
    bloques[3] = bloques[3] + 1;
  end

  always @(negedge clk) if (rst_n && out_valid) begin
    for (k4 = 0; k4 < N; k4 = k4 + 1)
      comparar(4, k4, y_blk[k4*2*NB4 +: 2*NB4], e4_mem[bloques[4]*N + k4]);
    bloques[4] = bloques[4] + 1;
  end

  // --------------------------------------------------------------------------
  // Tarea: carga un dataset, manda sus 64 bloques seguidos y muestra el resultado
  // --------------------------------------------------------------------------
  task test_dataset;
    input [8*16-1:0] nombre;  // nombre del dataset (texto)
    reg   [8*128-1:0] archivo;
    reg   [8*8-1:0]   pre;    // "fft" o "ifft"
    integer b, k, s;
    begin
      // (sin ?: entre cadenas: la mas corta se completaria con bytes nulos)
      if (INVERSE) begin
        pre = "ifft";
        $sformat(archivo, "%0s/%0s/spec_mult.hex", VEC, nombre);
      end else begin
        pre = "fft";
        $sformat(archivo, "%0s/%0s/blk_in.hex", VEC, nombre);
      end
      $readmemh(archivo, x_mem);
      $sformat(archivo, "%0s/%0s/%0s_st1.hex", VEC, nombre, pre); $readmemh(archivo, e1_mem);
      $sformat(archivo, "%0s/%0s/%0s_st2.hex", VEC, nombre, pre); $readmemh(archivo, e2_mem);
      $sformat(archivo, "%0s/%0s/%0s_st3.hex", VEC, nombre, pre); $readmemh(archivo, e3_mem);
      $sformat(archivo, "%0s/%0s/%0s_st4.hex", VEC, nombre, pre); $readmemh(archivo, e4_mem);

      errores = 0;
      for (s = 1; s <= 4; s = s + 1) bloques[s] = 0;

      for (b = 0; b < NBLK; b = b + 1) begin
        @(negedge clk);
        for (k = 0; k < N; k = k + 1)
          x_blk[k*2*NB_IN +: 2*NB_IN] = x_mem[b*N + k][2*NB_IN-1:0];
        in_valid = 1'b1;
      end
      @(negedge clk);
      in_valid = 1'b0;

      wait (bloques[4] == NBLK);
      @(posedge clk);

      $display("----------------------------------------");
      $display("Dataset: %0s", nombre);
      $display("  Bloques: %0d | Etapas verificadas: 4 | Errores: %0d", NBLK, errores);
      if (errores == 0) $display("  STATUS: [PASS]");
      else              $display("  STATUS: [FAIL]");

      total_errores = total_errores + errores;
    end
  endtask

  initial begin
    if (INVERSE) $dumpfile("tb_ifft16.vcd");
    else         $dumpfile("tb_fft16.vcd");
    $dumpvars(0, tb_fft16);

    clk           = 0;
    rst_n         = 0;
    in_valid      = 0;
    x_blk         = 0;
    total_errores = 0;

    #15 rst_n = 1;
    #10;

    if (INVERSE) $display("Modo: IFFT");
    else         $display("Modo: FFT");
    test_dataset("random_a");
    test_dataset("random_b");
    test_dataset("impulse");
    test_dataset("constant");
    test_dataset("alternating");
    test_dataset("worst_case");
    test_dataset("stress");      // no QPSK: hace redondear a todas las mariposas

    $display("----------------------------------------");
    if (total_errores == 0) $display("SIMULACION FINALIZADA: TODO PASS");
    else                    $display("SIMULACION FINALIZADA: %0d ERRORES", total_errores);
    $finish;
  end

endmodule
