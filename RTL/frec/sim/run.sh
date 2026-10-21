#!/bin/bash
# Simulacion de los modulos del filtro en frecuencia contra el golden frec_pf
set -e
cd "$(dirname "$0")"

echo ">>> [1/2] Armado de bloque (ols_buffer)"
iverilog -g2012 -o sim_ols_buffer.out ../tb/tb_ols_buffer.sv ../src/ols_buffer.sv
vvp sim_ols_buffer.out

echo ""
echo ">>> [2/2] Multiplicacion espectral (spec_mult)"
iverilog -g2012 -o sim_spec_mult.out ../tb/tb_spec_mult.sv ../src/spec_mult.sv
vvp sim_spec_mult.out

echo ""
echo ">>> (Opcional) Revisar formas de onda:"
echo "gtkwave tb_ols_buffer.vcd"
echo "gtkwave tb_spec_mult.vcd"
