`timescale 1ns / 1ps
// ============================================================================
// tb_fir_serial - Testbench of the serial time-domain RRC FIR
//
// Compares the RTL bit by bit against the fixed-point golden model (tiempo_pf):
//   input          : <dataset>/x_in.hex   (512 samples, {im, re} of 8 bits)
//   expected output: <dataset>/y_out.hex  (512 samples, {im, re} of 10 bits)
//
// Each dataset is run twice:
//   1. continuous : s_valid = 1 every clock
//   2. with gaps  : s_valid goes to 0 at random, to check that valid stays
//                   aligned with the data
//
// Run from RTL/tiempo/sim with ./run.sh
// ============================================================================
module tb_fir_serial;

  // Path to the golden vectors (relative to RTL/tiempo/sim)
  localparam string VEC = "../../../Golden_model/tiempo_pf/vectors/";

  localparam integer NB_X = 8;     // bits of each part of x (re, im)
  localparam integer NB_Y = 10;    // bits of each part of y (re, im)
  localparam integer N    = 512;   // samples per dataset
  localparam integer N_DS = 6;     // number of datasets

  logic                 clk = 1'b0;
  logic                 rst_n;
  logic                 s_valid;
  logic [2*NB_X-1:0]    s_data;
  logic                 m_valid;
  logic [2*NB_Y-1:0]    m_data;

  fir_serial dut (
      .clk(clk),
      .rst_n(rst_n),
      .s_valid(s_valid),
      .s_data(s_data),
      .m_valid(m_valid),
      .m_data(m_data)
  );

  always #5 clk = ~clk;            // 100 MHz

  // Memories where the .hex files are loaded
  logic [2*NB_X-1:0] x_mem [0:N-1];
  logic [2*NB_Y-1:0] y_mem [0:N-1];

  string  datasets [N_DS];
  integer n_out;                   // outputs received in the current run
  integer errors;                  // errors in the current run
  integer total_errors = 0;        // errors in all the runs
  logic [2*NB_Y-1:0] expected;     // expected output (to see it in GTKWave)

  // --------------------------------------------------------------------------
  // Monitor: every valid output is compared, in order, with y_out.hex
  // --------------------------------------------------------------------------
  always @(posedge clk) begin
    if (rst_n && m_valid) begin
      expected = y_mem[n_out];
      if (m_data !== expected) begin
        if (errors < 5)
          $display("    sample %0d: got %h, expected %h", n_out, m_data, expected);
        errors = errors + 1;
      end
      n_out = n_out + 1;
    end
  end

  // --------------------------------------------------------------------------
  // Task: reset the filter, send the 512 samples of a dataset and wait
  // --------------------------------------------------------------------------
  task automatic run_dataset(input string name, input bit gaps);
    $readmemh({VEC, name, "/x_in.hex"}, x_mem);
    $readmemh({VEC, name, "/y_out.hex"}, y_mem);

    // Reset (the inputs change on the falling edge)
    @(negedge clk);
    rst_n   = 1'b0;
    s_valid = 1'b0;
    s_data  = '0;
    n_out   = 0;
    errors  = 0;
    @(negedge clk);
    rst_n = 1'b1;

    // Send the samples
    for (int n = 0; n < N; n++) begin
      if (gaps) begin
        while ($urandom_range(0, 2) == 0) begin   // 1 in 3: insert an idle clock
          s_valid = 1'b0;
          @(negedge clk);
        end
      end
      s_data  = x_mem[n];
      s_valid = 1'b1;
      @(negedge clk);
    end
    s_valid = 1'b0;
    repeat (4) @(negedge clk);     // wait for the last outputs (latency = 2)

    if (n_out != N) errors = errors + 1;
    $display("%-12s %-10s outputs: %0d/%0d  errors: %0d  %s",
             name, gaps ? "with gaps" : "continuous", n_out, N, errors,
             errors == 0 ? "OK" : "FAIL");
    total_errors = total_errors + errors;
  endtask

  initial begin
    $dumpfile("tb_fir_serial.vcd");
    $dumpvars(0, tb_fir_serial);

    // First the impulse (checks the coefficients), then the rest
    datasets[0] = "impulse";
    datasets[1] = "constant";
    datasets[2] = "alternating";
    datasets[3] = "worst_case";
    datasets[4] = "random_a";
    datasets[5] = "random_b";

    for (int g = 0; g < 2; g++)
      for (int d = 0; d < N_DS; d++)
        run_dataset(datasets[d], g);

    if (total_errors == 0) $display("\nPASS: the RTL matches tiempo_pf bit by bit");
    else                   $display("\nFAIL: %0d errors", total_errors);
    $finish;
  end

endmodule
