`timescale 1ns / 1ps
// ============================================================================
// tb_power_freq_filter - Estimulo para medir potencia del filtro en frecuencia
//
// Manda el dataset random_a al filtro (RTL o netlist sintetizado) y graba en
// un VCD solo la actividad del DUT, para que OpenSTA calcule la potencia con
// la conmutacion real de cada senal.
//
// Parametros (se cambian con -P al compilar):
//   PERIODO : periodo del reloj en ns (debe coincidir con el de la STA)
//   DUTY    : porcentaje de ciclos con muestra valida (100 = una por ciclo)
//
// Tambien compara la salida con y_out.hex: si el netlist no coincide con el
// golden, la potencia medida no sirve.
// ============================================================================
module tb_power_freq_filter;

  parameter PERIODO = 10;    // ns
  parameter DUTY    = 100;   // % de ciclos con s_valid = 1

  localparam VEC  = "../../../Golden_model/frec_pf/vectors";
  localparam NMUE = 512;

  reg         clk;
  reg         rst_n;
  reg         s_valid;
  reg  [15:0] s_data;
  wire        m_valid;
  wire [19:0] m_data;

  freq_filter u_freq_filter (
      .clk(clk),
      .rst_n(rst_n),
      .s_valid(s_valid),
      .s_data(s_data),
      .m_valid(m_valid),
      .m_data(m_data)
  );

  always #(PERIODO / 2.0) clk = ~clk;

  reg [15:0] x_mem [0:NMUE-1];
  reg [19:0] y_mem [0:NMUE-1];
  integer    n, salidas, errores;
  reg [8*128-1:0] archivo;

  // Verificacion de la salida
  always @(negedge clk) begin
    if (rst_n && m_valid) begin
      if (m_data !== y_mem[salidas]) errores = errores + 1;
      salidas = salidas + 1;
    end
  end

  initial begin
    $sformat(archivo, "%0s/random_a/x_in.hex", VEC);
    $readmemh(archivo, x_mem);
    $sformat(archivo, "%0s/random_a/y_out.hex", VEC);
    $readmemh(archivo, y_mem);

    clk = 0; rst_n = 0; s_valid = 0; s_data = 0;
    salidas = 0; errores = 0;

    repeat (3) @(negedge clk);
    rst_n = 1;
    @(negedge clk);

    $dumpfile("power.vcd");
    $dumpvars(0, u_freq_filter);      // solo el DUT

    for (n = 0; n < NMUE; n = n + 1) begin
      while (($random % 100 + 100) % 100 >= DUTY) begin   // ciclo sin muestra
        @(negedge clk);
        s_valid = 0;
      end
      @(negedge clk);
      s_valid = 1;
      s_data  = x_mem[n];
    end
    @(negedge clk);
    s_valid = 0;
    repeat (30) @(negedge clk);

    $dumpoff;
    if (errores == 0 && salidas == NMUE)
      $display("POWER-TB: salida OK (%0d muestras, 0 errores)", salidas);
    else
      $display("POWER-TB: ERROR (%0d de %0d muestras, %0d errores)", salidas, NMUE, errores);
    $finish;
  end

endmodule
