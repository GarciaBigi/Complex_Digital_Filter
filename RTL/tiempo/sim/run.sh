#!/bin/bash
# Simulation of the serial time-domain FIR against the golden tiempo_pf
set -e
cd "$(dirname "$0")"

iverilog -g2012 -o sim_fir_serial.out ../tb/tb_fir_serial.sv ../src/fir_serial.sv
vvp -n sim_fir_serial.out

echo ""
echo ">>> (Optional) Waveforms: gtkwave tb_fir_serial.vcd"
