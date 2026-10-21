`timescale 1ns / 1ps
// ============================================================================
// tb_ols_buffer - Testbench del armado de bloque (overlap-save)
//
// Compara el RTL bit a bit contra el golden en punto fijo (frec_pf):
//   entrada        : <dataset>/x_in.hex   (512 muestras, una por linea)
//   salida esperada: <dataset>/blk_in.hex (64 bloques x 16 muestras)
//
// Cada muestra es una palabra de 16 bits {im[7:0], re[7:0]} en formato S(8,6).
//
// Pruebas:
//   * los 6 datasets del golden, una muestra por ciclo (continuo)
//   * dos datasets con huecos: ciclos sin muestra al azar
//   * una rampa (todas las muestras distintas), continua y con huecos
//
// Correr desde RTL/frec/tb o RTL/frec/sim:
//   iverilog -g2012 -o tb_ols_buffer.vvp ../src/ols_buffer.sv tb_ols_buffer.sv
//   vvp tb_ols_buffer.vvp
//   gtkwave tb_ols_buffer.vcd
// ============================================================================
module tb_ols_buffer;

  localparam VEC  = "../../../Golden_model/frec_pf/vectors";

  localparam N    = 16;     // muestras por bloque
  localparam HOP  = 8;      // muestras nuevas por bloque
  localparam W    = 16;     // bits por muestra: {im, re} de 8 bits cada uno
  localparam NBLK = 64;     // bloques por dataset
  localparam NMUE = 512;    // muestras de entrada por dataset

  reg              clk;
  reg              rst_n;
  reg              s_valid;
  reg  [W-1:0]     s_data;     // muestra de entrada
  wire             blk_valid;
  wire [N*W-1:0]   blk;        // bloque de 16 muestras

  ols_buffer u_ols_buffer (
      .clk(clk),
      .rst_n(rst_n),
      .s_valid(s_valid),
      .s_data(s_data),
      .blk_valid(blk_valid),
      .blk(blk)
  );

  always #5 clk = ~clk;

  // Memorias donde se cargan los .hex
  reg [W-1:0] x_mem [0:NMUE-1];
  reg [W-1:0] b_mem [0:N*NBLK-1];

  reg [W-1:0] esperado;       // muestra esperada (para verla en GTKWave)
  reg [W-1:0] obtenido;       // muestra que saco el RTL
  integer     bloques;        // bloques recibidos en el dataset actual
  integer     errores;        // errores del dataset actual
  integer     total_errores;  // errores de todo el testbench

  // --------------------------------------------------------------------------
  // Verificador: mira la salida en cada flanco de bajada (valores estables).
  // Cada vez que sale un bloque lo compara con el que corresponde en blk_in.hex.
  // Es independiente del estimulo: no le importa cuando ni como llegaron las
  // muestras, solo cuenta bloques.
  // --------------------------------------------------------------------------
  integer j;
  always @(negedge clk) begin
    if (rst_n && blk_valid) begin
      for (j = 0; j < N; j = j + 1) begin
        obtenido = blk[j*W +: W];
        esperado = b_mem[bloques*N + j];
        if (obtenido !== esperado) begin
          errores = errores + 1;
          if (errores <= 5)
            $display("  ERROR bloque %0d muestra %0d: RTL = (%0d, %0d) | Esperado = (%0d, %0d)",
                     bloques, j,
                     $signed(obtenido[7:0]), $signed(obtenido[15:8]),
                     $signed(esperado[7:0]), $signed(esperado[15:8]));
        end
      end
      bloques = bloques + 1;
    end
  end

  // --------------------------------------------------------------------------
  // Tarea: reset del DUT (el estado inicial son 8 muestras previas en cero)
  // --------------------------------------------------------------------------
  task reset_dut;
    begin
      @(negedge clk);
      rst_n   = 0;
      s_valid = 0;
      s_data  = 0;
      @(negedge clk);
      @(negedge clk);
      rst_n = 1;
    end
  endtask

  // --------------------------------------------------------------------------
  // Tarea: manda una muestra (un ciclo con s_valid = 1).
  // Con huecos = 1, a veces deja antes un ciclo sin muestra.
  // --------------------------------------------------------------------------
  task enviar_muestra;
    input [W-1:0] muestra;
    input         huecos;
    begin
      if (huecos && (($random & 3) == 0)) begin   // 25 % de las veces
        @(negedge clk);
        s_valid = 0;
      end
      @(negedge clk);
      s_valid = 1;
      s_data  = muestra;
    end
  endtask

  // --------------------------------------------------------------------------
  // Tarea: corre una prueba con lo que haya en x_mem / b_mem y muestra el resultado
  // --------------------------------------------------------------------------
  task correr_prueba;
    input [8*16-1:0] nombre;   // nombre de la prueba (texto)
    input            huecos;   // 0 = continuo, 1 = con huecos
    integer n;
    begin
      reset_dut;
      bloques = 0;
      errores = 0;

      for (n = 0; n < NMUE; n = n + 1)
        enviar_muestra(x_mem[n], huecos);

      @(negedge clk);
      s_valid = 0;
      repeat (3) @(negedge clk);       // dejar salir el ultimo bloque

      $display("----------------------------------------");
      $display("Prueba: %0s (%0s)", nombre, huecos ? "con huecos" : "continuo");
      $display("  Muestras: %0d | Bloques: %0d de %0d | Errores: %0d",
               NMUE, bloques, NBLK, errores);
      if (errores == 0 && bloques == NBLK) $display("  STATUS: [PASS]");
      else                                 $display("  STATUS: [FAIL]");

      if (bloques != NBLK) errores = errores + 1;
      total_errores = total_errores + errores;
    end
  endtask

  // --------------------------------------------------------------------------
  // Tarea: carga un dataset del golden y lo prueba
  // --------------------------------------------------------------------------
  task test_dataset;
    input [8*16-1:0] nombre;
    input            huecos;
    reg   [8*128-1:0] archivo;
    begin
      $sformat(archivo, "%0s/%0s/x_in.hex", VEC, nombre);
      $readmemh(archivo, x_mem);
      $sformat(archivo, "%0s/%0s/blk_in.hex", VEC, nombre);
      $readmemh(archivo, b_mem);
      correr_prueba(nombre, huecos);
    end
  endtask

  // --------------------------------------------------------------------------
  // Tarea: prueba con una rampa (todas las muestras distintas).
  // Los datasets QPSK tienen ceros en todas las muestras impares (upsampling
  // por 2): un error que solo afecte a esas posiciones no se veria. Con la
  // rampa cada muestra es unica, asi que cualquier muestra mal ubicada falla.
  // El bloque esperado se calcula aca mismo: muestra j del bloque b = x[8b+j-8]
  // (cero si el indice es negativo).
  // --------------------------------------------------------------------------
  task test_rampa;
    input huecos;
    integer n, b, k;
    begin
      for (n = 0; n < NMUE; n = n + 1)
        x_mem[n] = {~n[7:0], n[7:0]};          // im = ~n, re = n
      for (b = 0; b < NBLK; b = b + 1)
        for (k = 0; k < N; k = k + 1)
          b_mem[b*N + k] = (b*HOP + k - HOP >= 0) ? x_mem[b*HOP + k - HOP] : 0;
      correr_prueba("rampa", huecos);
    end
  endtask

  initial begin
    $dumpfile("tb_ols_buffer.vcd");
    $dumpvars(0, tb_ols_buffer);

    clk           = 0;
    rst_n         = 0;
    s_valid       = 0;
    s_data        = 0;
    bloques       = 0;
    errores       = 0;
    total_errores = 0;

    test_dataset("random_a",    0);
    test_dataset("random_b",    0);
    test_dataset("impulse",     0);
    test_dataset("constant",    0);
    test_dataset("alternating", 0);
    test_dataset("worst_case",  0);
    test_dataset("random_a",    1);
    test_dataset("worst_case",  1);
    test_rampa(0);
    test_rampa(1);

    $display("----------------------------------------");
    if (total_errores == 0) $display("SIMULACION FINALIZADA: TODO PASS");
    else                    $display("SIMULACION FINALIZADA: %0d ERRORES", total_errores);
    $finish;
  end

endmodule
