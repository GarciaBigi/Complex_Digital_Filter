# Simulacion del filtro en frecuencia con Icarus Verilog (SystemVerilog)
#   make spec_mult        compila y corre el testbench (6 datasets)
#   make wave_spec_mult   abre las ondas en GTKWave
#   make clean            borra lo generado
.RECIPEPREFIX = >
SRC := ../src
TB  := ../tb
.PHONY: spec_mult wave_spec_mult clean
tb_spec_mult.vvp: $(SRC)/spec_mult.sv $(TB)/tb_spec_mult.sv
> iverilog -g2012 -o $@ $^
spec_mult: tb_spec_mult.vvp
> vvp tb_spec_mult.vvp | tee spec_mult.log
> @grep -q "TODO PASS" spec_mult.log
wave_spec_mult: spec_mult
> gtkwave tb_spec_mult.vcd &
clean:
> rm -f *.vvp *.vcd *.log
