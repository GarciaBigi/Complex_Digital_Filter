`timescale 1ns / 1ps
// ============================================================================
// tb_spec_mult - Testbench de la multiplicacion espectral Y[k] = X[k] * H[k]
//
// Compara el RTL bit a bit contra el golden en punto fijo (frec_pf):
//   entrada        : <dataset>/fft_st4.hex   (salida de la FFT, X[k])
//   salida esperada: <dataset>/spec_mult.hex (Y[k])
//
// Cada linea de los .hex es un bin: palabra de 28 bits {im[13:0], re[13:0]}.
// Un bloque son 16 bins (16 lineas). Cada dataset tiene 64 bloques.
//
// Correr desde RTL/frec/tb o RTL/frec/sim:
//   iverilog -g2012 -o tb_spec_mult.vvp ../src/spec_mult.sv tb_spec_mult.sv
//   vvp tb_spec_mult.vvp
//   gtkwave tb_spec_mult.vcd
// ============================================================================
module tb_spec_mult;

  // Ruta a los vectores del golden (relativa a RTL/frec/tb o RTL/frec/sim)
  localparam VEC = "../../../Golden_model/frec_pf/vectors";

  localparam N    = 16;     // bins por bloque
  localparam W    = 28;     // bits por bin: {im, re} de 14 bits cada uno
  localparam NBLK = 64;     // bloques por dataset

  reg              clk;
  reg              rst_n;
  reg              in_valid;
  reg  [N*W-1:0]   x_blk;     // 16 bins de entrada, bin k en x_blk[k*W +: W]
  wire             out_valid;
  wire [N*W-1:0]   y_blk;     // 16 bins de salida

  spec_mult u_spec_mult (
      .clk(clk),
      .rst_n(rst_n),
      .in_valid(in_valid),
      .x_blk(x_blk),
      .out_valid(out_valid),
      .y_blk(y_blk)
  );

  always #5 clk = ~clk;

  // Memorias donde se cargan los .hex
  reg [W-1:0] x_mem [0:N*NBLK-1];
  reg [W-1:0] y_mem [0:N*NBLK-1];

  reg [W-1:0] esperado;       // bin esperado (para verlo en GTKWave)
  reg [W-1:0] obtenido;       // bin que saco el RTL
  integer     errores;        // errores del dataset actual
  integer     total_errores;  // errores de todos los datasets

  // --------------------------------------------------------------------------
  // Tarea: manda un bloque al RTL, espera la salida y compara los 16 bins
  // --------------------------------------------------------------------------
  task test_bloque;
    input integer b;          // numero de bloque
    integer k;
    begin
      // Cargar el bloque b (se cambia en el flanco de bajada)
      @(negedge clk);
      for (k = 0; k < N; k = k + 1)
        x_blk[k*W +: W] = x_mem[b*N + k];
      in_valid = 1'b1;

      @(negedge clk);
      in_valid = 1'b0;

      // Esperar la salida y comparar
      wait (out_valid == 1'b1);
      for (k = 0; k < N; k = k + 1) begin
        obtenido = y_blk[k*W +: W];
        esperado = y_mem[b*N + k];
        if (obtenido !== esperado) begin
          errores = errores + 1;
          if (errores <= 5)
            $display("  ERROR bloque %0d bin %0d: RTL = (%0d, %0d) | Esperado = (%0d, %0d)",
                     b, k,
                     $signed(obtenido[13:0]), $signed(obtenido[27:14]),
                     $signed(esperado[13:0]), $signed(esperado[27:14]));
        end
      end
      @(posedge clk);
    end
  endtask

  // --------------------------------------------------------------------------
  // Tarea: carga un dataset, prueba sus 64 bloques y muestra el resultado
  // --------------------------------------------------------------------------
  task test_dataset;
    input [8*16-1:0] nombre;  // nombre del dataset (texto)
    reg   [8*128-1:0] archivo;
    integer b;
    begin
      $sformat(archivo, "%0s/%0s/fft_st4.hex", VEC, nombre);
      $readmemh(archivo, x_mem);
      $sformat(archivo, "%0s/%0s/spec_mult.hex", VEC, nombre);
      $readmemh(archivo, y_mem);

      errores = 0;
      for (b = 0; b < NBLK; b = b + 1)
        test_bloque(b);

      $display("----------------------------------------");
      $display("Dataset: %0s", nombre);
      $display("  Bloques: %0d | Bins: %0d | Errores: %0d", NBLK, N*NBLK, errores);
      if (errores == 0) $display("  STATUS: [PASS]");
      else              $display("  STATUS: [FAIL]");

      total_errores = total_errores + errores;
    end
  endtask

  initial begin
    $dumpfile("tb_spec_mult.vcd");
    $dumpvars(0, tb_spec_mult);

    clk           = 0;
    rst_n         = 0;
    in_valid      = 0;
    x_blk         = 0;
    total_errores = 0;

    #15 rst_n = 1;
    #10;

    test_dataset("random_a");
    test_dataset("random_b");
    test_dataset("impulse");
    test_dataset("constant");
    test_dataset("alternating");
    test_dataset("worst_case");

    $display("----------------------------------------");
    if (total_errores == 0) $display("SIMULACION FINALIZADA: TODO PASS");
    else                    $display("SIMULACION FINALIZADA: %0d ERRORES", total_errores);
    $finish;
  end

endmodule
