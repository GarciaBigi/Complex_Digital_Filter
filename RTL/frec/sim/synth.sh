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

# ---------------------------------------------------------------------------
# butterfly (una mariposa con twiddle no trivial: W^-1 = 237 + j98 de la IFFT;
# chparam no acepta valores negativos)
# ---------------------------------------------------------------------------
FFT_SRC="../src/butterfly.sv ../src/fft_stage.sv ../src/fft16.sv"
BF_PARAMS="-set NB_IN 14 -set NBF_IN 8 -set NB_OUT 14 -set SCALE 1 -set W_RE 237 -set W_IM 98"

echo ""
echo ">>> [butterfly] Esquematico RTL -> yosys_out/rtl_butterfly.svg"
yosys -q -p "read_verilog -sv ../src/butterfly.sv; chparam $BF_PARAMS butterfly; prep -top butterfly; show -format svg -prefix yosys_out/rtl_butterfly"

# ---------------------------------------------------------------------------
# fft16 (FFT) y fft16 con INVERSE = 1 (IFFT)
# ---------------------------------------------------------------------------
echo ""
echo ">>> [fft16] Estadisticas (Xilinx 7-series) -> yosys_out/stat_fft16.log"
yosys -p "read_verilog -sv $FFT_SRC; synth_xilinx -family xc7 -top fft16; stat; ltp" > yosys_out/stat_fft16.log
awk '/Number of cells/{b=""; f=1} f{b=b $0 "\n"} f&&/^ *$/{f=0} END{printf "%s", b}' yosys_out/stat_fft16.log
grep "Longest topological path" yosys_out/stat_fft16.log | tail -1

echo ""
echo ">>> [ifft16] Estadisticas (Xilinx 7-series) -> yosys_out/stat_ifft16.log"
yosys -p "read_verilog -sv $FFT_SRC; chparam -set INVERSE 1 -set NB_IN 14 -set NBF_IN 8 -set NB_ST1 14 -set NB_ST2 14 -set NB_ST3 14 fft16; synth_xilinx -family xc7 -top fft16; stat; ltp" > yosys_out/stat_ifft16.log
awk '/Number of cells/{b=""; f=1} f{b=b $0 "\n"} f&&/^ *$/{f=0} END{printf "%s", b}' yosys_out/stat_ifft16.log
grep "Longest topological path" yosys_out/stat_ifft16.log | tail -1

# ---------------------------------------------------------------------------
# freq_filter (filtro completo)
# ---------------------------------------------------------------------------
echo ""
echo ">>> [freq_filter] Estadisticas (Xilinx 7-series) -> yosys_out/stat_freq_filter.log"
yosys -p "read_verilog -sv ../src/ols_buffer.sv $FFT_SRC ../src/spec_mult.sv ../src/ols_output.sv ../src/freq_filter.sv; synth_xilinx -family xc7 -top freq_filter; stat; ltp" > yosys_out/stat_freq_filter.log
awk '/Number of cells/{b=""; f=1} f{b=b $0 "\n"} f&&/^ *$/{f=0} END{printf "%s", b}' yosys_out/stat_freq_filter.log
grep "Longest topological path" yosys_out/stat_freq_filter.log | tail -1

echo ""
echo ">>> Listo. Para ver los esquematicos, abri los .svg de yosys_out/ (por ejemplo con el navegador)."
