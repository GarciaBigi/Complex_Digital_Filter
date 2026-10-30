#!/bin/bash
# Simulacion de los modulos del filtro en frecuencia contra el golden frec_pf
set -e
cd "$(dirname "$0")"

FFT_SRC="../src/butterfly.sv ../src/fft_stage.sv ../src/fft16.sv"

echo ">>> [1/5] Armado de bloque (ols_buffer)"
iverilog -g2012 -o sim_ols_buffer.out ../tb/tb_ols_buffer.sv ../src/ols_buffer.sv
vvp sim_ols_buffer.out

echo ""
echo ">>> [2/5] FFT de 16 puntos (fft16, etapa por etapa)"
iverilog -g2012 -o sim_fft16.out ../tb/tb_fft16.sv $FFT_SRC
vvp sim_fft16.out

echo ""
echo ">>> [3/5] Multiplicacion espectral (spec_mult)"
iverilog -g2012 -o sim_spec_mult.out ../tb/tb_spec_mult.sv ../src/spec_mult.sv
vvp sim_spec_mult.out

echo ""
echo ">>> [4/5] IFFT de 16 puntos (fft16 con INVERSE = 1, etapa por etapa)"
iverilog -g2012 -Ptb_fft16.INVERSE=1 -o sim_ifft16.out ../tb/tb_fft16.sv $FFT_SRC
vvp sim_ifft16.out

echo ""
echo ">>> [5/5] Filtro completo (freq_filter): x_in -> y_out"
iverilog -g2012 -o sim_freq_filter.out ../tb/tb_freq_filter.sv ../src/freq_filter.sv \
    ../src/ols_buffer.sv $FFT_SRC ../src/spec_mult.sv ../src/ols_output.sv
vvp sim_freq_filter.out

echo ""
echo ">>> (Opcional) Revisar formas de onda:"
echo "gtkwave tb_ols_buffer.vcd"
echo "gtkwave tb_fft16.vcd"
echo "gtkwave tb_spec_mult.vcd"
echo "gtkwave tb_ifft16.vcd"
echo "gtkwave tb_freq_filter.vcd"
