#!/bin/bash
# Esquematicos RTL y estadisticas de sintesis (yosys) de los modulos del filtro en frecuencia
set -e
cd "$(dirname "$0")"
mkdir -p yosys_out

echo ">>> Version de yosys:"
yosys -V

# ---------------------------------------------------------------------------
# ols_buffer (armado de bloque)
# ---------------------------------------------------------------------------
echo ""
echo ">>> [ols_buffer] Esquematico RTL -> yosys_out/rtl_ols_buffer.svg"
yosys -q -p "read_verilog -sv ../src/ols_buffer.sv; prep -top ols_buffer; show -format svg -prefix yosys_out/rtl_ols_buffer"

echo ">>> [ols_buffer] Estadisticas (Xilinx 7-series) -> yosys_out/stat_ols_buffer.log"
yosys -p "read_verilog -sv ../src/ols_buffer.sv; synth_xilinx -family xc7 -top ols_buffer; stat; ltp" > yosys_out/stat_ols_buffer.log
awk '/Number of cells/{b=""; f=1} f{b=b $0 "\n"} f&&/^ *$/{f=0} END{printf "%s", b}' yosys_out/stat_ols_buffer.log
grep "Longest topological path" yosys_out/stat_ols_buffer.log | tail -1

# ---------------------------------------------------------------------------
# spec_mult (multiplicacion espectral)
# Esquematico con un solo bin (N=1): con los 16 no se puede leer
# ---------------------------------------------------------------------------
echo ""
echo ">>> [spec_mult] Esquematico RTL de 1 bin -> yosys_out/rtl_spec_mult_1bin.svg"
yosys -q -p "read_verilog -sv ../src/spec_mult.sv; chparam -set N 1 spec_mult; prep -top spec_mult; show -format svg -prefix yosys_out/rtl_spec_mult_1bin"

echo ">>> [spec_mult] Estadisticas (Xilinx 7-series) -> yosys_out/stat_spec_mult.log"
yosys -p "read_verilog -sv ../src/spec_mult.sv; synth_xilinx -family xc7 -top spec_mult; stat; ltp" > yosys_out/stat_spec_mult.log
awk '/Number of cells/{b=""; f=1} f{b=b $0 "\n"} f&&/^ *$/{f=0} END{printf "%s", b}' yosys_out/stat_spec_mult.log
grep "Longest topological path" yosys_out/stat_spec_mult.log | tail -1

echo ""
echo ">>> Listo. Para ver los esquematicos, abri los .svg de yosys_out/ (por ejemplo con el navegador)."
