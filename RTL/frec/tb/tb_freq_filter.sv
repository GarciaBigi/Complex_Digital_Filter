`timescale 1ns / 1ps
// ============================================================================
// tb_freq_filter - Testbench del filtro en frecuencia completo (top)
//
// Compara el RTL bit a bit contra el golden en punto fijo (frec_pf):
//   entrada        : <dataset>/x_in.hex  (512 muestras S(8,6), {im, re})
//   salida esperada: <dataset>/y_out.hex (512 muestras S(10,8), {im, re})
//
// Pruebas:
//   * los 6 datasets del golden, una muestra por ciclo (continuo)
//   * stress: 512 muestras aleatorias sin sobremuestreo (no QPSK). Con QPSK
//     sobremuestreada la FFT nunca redondea; con esta senal redondean todas
//     las mariposas.
//   * dos datasets con huecos: ciclos sin muestra al azar
//
// Correr desde RTL/frec/tb o RTL/frec/sim:
//   iverilog -g2012 -o tb_freq_filter.vvp ../src/*.sv tb_freq_filter.sv
//   vvp tb_freq_filter.vvp
// ============================================================================
module tb_freq_filter;

  localparam VEC  = "../../../Golden_model/frec_pf/vectors";

  localparam WI   = 16;     // bits por muestra de entrada: {im, re} de 8 bits
  localparam WO   = 20;     // bits por muestra de salida: {im, re} de 10 bits
  localparam NMUE = 512;    // muestras por dataset

  reg           clk;
  reg           rst_n;
  reg           s_valid;
  reg  [WI-1:0] s_data;
  wire          m_valid;
  wire [WO-1:0] m_data;

  freq_filter u_freq_filter (
      .clk(clk),
      .rst_n(rst_n),
      .s_valid(s_valid),
      .s_data(s_data),
      .m_valid(m_valid),
      .m_data(m_data)
  );

  always #5 clk = ~clk;

  // Memorias donde se cargan los .hex
  reg [WI-1:0] x_mem [0:NMUE-1];
  reg [WO-1:0] y_mem [0:NMUE-1];

  reg [WO-1:0] esperado;      // muestra esperada (para verla en GTKWave)
  integer      salidas;       // muestras recibidas en la prueba actual
  integer      errores;       // errores de la prueba actual
  integer      total_errores; // errores de todo el testbench

  // --------------------------------------------------------------------------
  // Verificador: cada muestra que sale se compara con la que sigue en y_out.hex
  // --------------------------------------------------------------------------
  always @(negedge clk) begin
    if (rst_n && m_valid) begin
      esperado = y_mem[salidas];
      if (m_data !== esperado) begin
        errores = errores + 1;
        if (errores <= 5)
          $display("  ERROR muestra %0d: RTL = (%0d, %0d) | Esperado = (%0d, %0d)",
                   salidas,
                   $signed(m_data[9:0]), $signed(m_data[19:10]),
                   $signed(esperado[9:0]), $signed(esperado[19:10]));
      end
      salidas = salidas + 1;
    end
  end

  // --------------------------------------------------------------------------
  // Tarea: reset del DUT
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
  // Tarea: manda una muestra; con huecos = 1, a veces deja antes un ciclo vacio
  // --------------------------------------------------------------------------
  task enviar_muestra;
    input [WI-1:0] muestra;
    input          huecos;
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
  // Tarea: carga un dataset, lo manda entero y muestra el resultado
  // --------------------------------------------------------------------------
  task test_dataset;
    input [8*16-1:0] nombre;
    input            huecos;   // 0 = continuo, 1 = con huecos
    reg   [8*128-1:0] archivo;
    integer n;
    begin
      $sformat(archivo, "%0s/%0s/x_in.hex", VEC, nombre);
      $readmemh(archivo, x_mem);
      $sformat(archivo, "%0s/%0s/y_out.hex", VEC, nombre);
      $readmemh(archivo, y_mem);

      reset_dut;
      salidas = 0;
      errores = 0;

      for (n = 0; n < NMUE; n = n + 1)
        enviar_muestra(x_mem[n], huecos);
      @(negedge clk);
      s_valid = 0;
      repeat (30) @(negedge clk);      // dejar salir el ultimo bloque

      $display("----------------------------------------");
      if (huecos) $display("Prueba: %0s (con huecos)", nombre);
      else        $display("Prueba: %0s (continuo)", nombre);
      $display("  Muestras: %0d de %0d | Errores: %0d", salidas, NMUE, errores);
      if (errores == 0 && salidas == NMUE) $display("  STATUS: [PASS]");
      else                                 $display("  STATUS: [FAIL]");

      if (salidas != NMUE) errores = errores + 1;
      total_errores = total_errores + errores;
    end
  endtask

  initial begin
    $dumpfile("tb_freq_filter.vcd");
    $dumpvars(0, tb_freq_filter);

    clk           = 0;
    rst_n         = 0;
    s_valid       = 0;
    s_data        = 0;
    salidas       = 0;
    errores       = 0;
    total_errores = 0;

    test_dataset("random_a",    0);
    test_dataset("random_b",    0);
    test_dataset("impulse",     0);
    test_dataset("constant",    0);
    test_dataset("alternating", 0);
    test_dataset("worst_case",  0);
    test_dataset("stress",      0);   // no QPSK: hace redondear a todas las mariposas
    test_dataset("random_a",    1);
    test_dataset("worst_case",  1);

    $display("----------------------------------------");
    if (total_errores == 0) $display("SIMULACION FINALIZADA: TODO PASS");
    else                    $display("SIMULACION FINALIZADA: %0d ERRORES", total_errores);
    $finish;
  end

endmodule
