#!/bin/bash
# ============================================================================
# ppa.sh - Performance, Power y Area del filtro en frecuencia en SKY130
#          (flujo de los Modulos 9 y 10: Yosys + SKY130 HD + OpenSTA)
#
# Uso:   ./ppa.sh [PERIODO_ns] [DUTY_%]
#          PERIODO_ns : periodo de reloj para la sintesis y la STA (default 10 = 100 MHz)
#          DUTY_%     : % de ciclos con muestra valida para medir potencia (default 100)
#        Ejemplos: ./ppa.sh            (100 MHz, una muestra por ciclo)
#                  ./ppa.sh 20 15      (50 MHz, muestra valida el 15 % de los ciclos)
#
# Pasos:
#   1. Area      : Yosys sintetiza cada bloque y el filtro completo con celdas SKY130 HD
#   2. Actividad : simulacion del netlist (gate level) con iverilog -> VCD
#                  (ademas verifica que el netlist sigue dando la salida del golden)
#   3. Timing    : OpenSTA -> slack, camino critico y frecuencia maxima
#   4. Potencia  : OpenSTA con la actividad del VCD -> interna, conmutacion y fuga
#
# Herramientas: yosys, iverilog, vvp y sta (OpenSTA) u openroad. Si no estan en el
# PATH y existe ~/openlane2, el script entra solo al entorno de OpenLane2 (nix).
# Celdas: busca sky130_fd_sc_hd__tt_025C_1v80.lib en $PDK_ROOT, ~/.ciel y ~/.volare.
# Se puede forzar con:  LIB=/ruta/al.lib ./ppa.sh
# Para repetir solo timing y potencia sin resintetizar:  SOLO_STA=1 ./ppa.sh
#
# Resultados en sim/ppa_out/ (resumen.txt, reportes y netlist).
# ============================================================================
set -e
cd "$(dirname "$0")"

PERIODO=${1:-10}
DUTY=${2:-100}
TOP=freq_filter
OUT=ppa_out
SRC=../src
FFT_SRC="$SRC/butterfly.sv $SRC/fft_stage.sv $SRC/fft16.sv"
ALL_SRC="$SRC/ols_buffer.sv $FFT_SRC $SRC/spec_mult.sv $SRC/ols_output.sv $SRC/freq_filter.sv"

# ---------------------------------------------------------------------------
# 0. Herramientas y librerias
# ---------------------------------------------------------------------------
OL2=${OPENLANE2:-$HOME/openlane2}
if ! command -v sta >/dev/null && ! command -v openroad >/dev/null; then
    if [ -z "$PPA_EN_NIX" ] && command -v nix >/dev/null && [ -d "$OL2" ]; then
        echo ">>> No encuentro OpenSTA: entro al entorno de OpenLane2 ($OL2)"
        PPA_EN_NIX=1 exec nix develop "$OL2" --command bash "$0" "$@"
    fi
    echo "ERROR: no encuentro OpenSTA ('sta') ni OpenROAD ('openroad')."
    echo "       Corre el script dentro del entorno de OpenLane2:"
    echo "       nix develop ~/openlane2 --command bash $0 $*"
    exit 1
fi
if command -v sta >/dev/null; then STA="sta -no_init -no_splash -exit"
else                               STA="openroad -no_init -no_splash -exit"; fi

for t in yosys iverilog vvp; do
    command -v $t >/dev/null || { echo "ERROR: falta $t"; exit 1; }
done

if [ -z "$LIB" ]; then
    for d in "$PDK_ROOT" "$HOME/.ciel" "$HOME/.volare" "$OL2"; do
        [ -n "$d" ] && [ -d "$d" ] || continue
        LIB=$(find -L "$d" -path '*sky130A*' -name 'sky130_fd_sc_hd__tt_025C_1v80.lib' 2>/dev/null | head -1)
        [ -n "$LIB" ] && break
    done
fi
if [ ! -f "$LIB" ]; then
    echo "ERROR: no encuentro la libreria sky130_fd_sc_hd__tt_025C_1v80.lib."
    echo "       Bajala con ciel (viene con OpenLane2):  ciel enable --pdk sky130 <version>"
    echo "       o indica la ruta:  LIB=/ruta/sky130_fd_sc_hd__tt_025C_1v80.lib ./ppa.sh"
    exit 1
fi
CELLS_V=$(dirname "$LIB")/../verilog
[ -f "$CELLS_V/sky130_fd_sc_hd.v" ] || { echo "ERROR: no encuentro $CELLS_V/sky130_fd_sc_hd.v"; exit 1; }

mkdir -p $OUT
FREQ=$(awk "BEGIN{printf \"%.1f\", 1000/$PERIODO}")
echo ">>> Yosys:    $(yosys -V)"
echo ">>> OpenSTA:  ${STA%% *}"
echo ">>> Libreria: $LIB"
echo ">>> Reloj:    $PERIODO ns ($FREQ MHz) | Duty de entrada: $DUTY %"

# Script de ABC: mapeo orientado a timing + buffers en las redes de mucho fanout y
# ajuste del tamano de las celdas (como el flujo de sintesis de OpenLane). Sin los
# buffers, una senal como un valid que maneja cientos de flip-flops queda con un
# retardo irreal y domina el camino critico.
cat > $OUT/abc.script <<'EOF_ABC'
strash
&get -n
&st
&dch
&nf
&put
buffer -p
upsize {D}
dnsize {D}
stime -p
EOF_ABC

# Sintesis a celdas SKY130 HD (mismo flujo para cada bloque y para el top)
synth_sky130() {   # $1 = nombre, $2 = top, $3 = fuentes, $4 = chparam (opcional)
    yosys -q -l $OUT/synth_$1.log -p "
        read_verilog -sv $3
        $4
        synth -top $2 -flatten
        dfflibmap -liberty $LIB
        abc -D $((PERIODO * 1000)) -script $OUT/abc.script -liberty $LIB
        opt_clean -purge
        hilomap -hicell sky130_fd_sc_hd__conb_1 HI -locell sky130_fd_sc_hd__conb_1 LO
        setundef -zero
        opt_clean -purge
        tee -q -o $OUT/stat_$1.txt stat -liberty $LIB
        write_verilog -noattr -noexpr -nohex -nodec $OUT/netlist_$1.v" > /dev/null 2>&1 || { echo "ERROR en la sintesis de $1 (ver $OUT/synth_$1.log)"; exit 1; }
}
area_de()  { awk '/Chip area/{a=$NF} END{printf "%.0f", a}' $OUT/stat_$1.txt; }
celdas_de(){ awk '/Number of cells/{c=$NF} END{print c}' $OUT/stat_$1.txt; }
ffs_de()   { awk '/sky130_fd_sc_hd__(df|ed|sdf)/{s+=$NF} END{print s+0}' $OUT/stat_$1.txt; }

# ---------------------------------------------------------------------------
# 1. Area: cada bloque y el filtro completo
# ---------------------------------------------------------------------------
echo ""
if [ -n "$SOLO_STA" ] && [ -f $OUT/power.vcd ]; then
echo ">>> SOLO_STA: reuso la sintesis y el VCD de $OUT (pasos 1 y 2 salteados)"
cat $OUT/area.txt
else
echo ">>> [1/4] Sintesis con SKY130 HD (puede tardar unos minutos)"
synth_sky130 ols_buffer ols_buffer "$SRC/ols_buffer.sv"
synth_sky130 fft16      fft16      "$FFT_SRC"
synth_sky130 spec_mult  spec_mult  "$SRC/spec_mult.sv"
synth_sky130 ifft16     fft16      "$FFT_SRC" \
    "chparam -set INVERSE 1 -set NB_IN 14 -set NBF_IN 8 -set NB_ST1 14 -set NB_ST2 14 -set NB_ST3 14 fft16"
synth_sky130 ols_output ols_output "$SRC/ols_output.sv"
synth_sky130 $TOP       $TOP       "$ALL_SRC"

{
    printf "%-22s %12s %8s %8s\n" "Bloque" "Area [um2]" "Celdas" "FFs"
    for b in ols_buffer fft16 spec_mult ifft16 ols_output $TOP; do
        printf "%-22s %12s %8s %8s\n" "$b" "$(area_de $b)" "$(celdas_de $b)" "$(ffs_de $b)"
    done
} > $OUT/area.txt
cat $OUT/area.txt

# ---------------------------------------------------------------------------
# 2. Actividad: simulacion del netlist con las celdas SKY130 -> VCD
# ---------------------------------------------------------------------------
echo ""
echo ">>> [2/4] Simulacion del netlist (gate level) para la actividad -> $OUT/power.vcd"
# Los modelos de celdas de SKY130 tienen texto despues de `endif, que iverilog no acepta
sed -E 's/^`endif .*/`endif/' "$CELLS_V/sky130_fd_sc_hd.v" > $OUT/sky130_cells.v
iverilog -g2012 -DFUNCTIONAL -DUNIT_DELAY=#1 \
    -Ptb_power_freq_filter.PERIODO=$PERIODO -Ptb_power_freq_filter.DUTY=$DUTY \
    -o $OUT/gls.out "$CELLS_V/primitives.v" $OUT/sky130_cells.v $OUT/netlist_$TOP.v \
    ../tb/tb_power_freq_filter.sv 2> $OUT/gls_compile.log
vvp -n $OUT/gls.out | tee $OUT/gls.log | grep "POWER-TB"
mv power.vcd $OUT/power.vcd
grep -q "salida OK" $OUT/gls.log || { echo "ERROR: el netlist no coincide con el golden"; exit 1; }
fi

# ---------------------------------------------------------------------------
# 3 y 4. Timing y potencia con OpenSTA
# ---------------------------------------------------------------------------
echo ""
echo ">>> [3/4] Timing (OpenSTA) y [4/4] potencia con la actividad del VCD"

# Script de STA para un netlist ($1 = nombre del bloque, $2 = modulo top)
sta_tcl() {
    cat <<EOF
read_liberty $LIB
read_verilog $OUT/netlist_$1.v
link_design $2

# Constraints (Modulo 9): reloj, incertidumbre y retardos de entrada/salida
create_clock -name clk -period $PERIODO [get_ports clk]
set_clock_uncertainty 0.1 [get_clocks clk]
set_input_delay  0 -clock clk [delete_from_list [all_inputs] [get_ports clk]]
set_output_delay 0 -clock clk [all_outputs]

report_checks -path_delay max -fields {fanout} -digits 3 > $OUT/timing_setup_$1.rpt
report_checks -path_delay min -digits 3 > $OUT/timing_hold_$1.rpt
report_worst_slack -max -digits 3
report_worst_slack -min -digits 3
EOF
}

# Timing de cada bloque (sus entradas son puertos: mide el camino de datos interno)
for b in ols_buffer fft16 spec_mult ifft16 ols_output; do
    top=$b; [ $b = ifft16 ] && top=fft16
    sta_tcl $b $top > $OUT/sta_$b.tcl
    $STA $OUT/sta_$b.tcl > $OUT/sta_$b.log 2>&1 || { echo "ERROR en OpenSTA ($b, ver $OUT/sta_$b.log)"; exit 1; }
done

# Filtro completo: timing + potencia con la actividad real
{
    sta_tcl $TOP $TOP
    cat <<EOF
report_tns -digits 3
if {[catch {read_vcd -scope tb_power_freq_filter/u_freq_filter $OUT/power.vcd} err]} {
    puts "AVISO: read_vcd fallo (\$err): potencia con actividad por defecto"
}
report_power > $OUT/power.rpt

# Camino de datos: se excluyen los caminos que arrancan en registros con fanout > 64
# (los valid que habilitan bloques enteros), para ver el retardo de la aritmetica
set n 0
foreach q [get_pins -hierarchical */Q] {
    set fo [llength [get_pins -of_objects [get_nets -of_objects \$q] -filter "direction == input"]]
    if {\$fo > 64} {
        regsub {/Q\$} [get_full_name \$q] {/CLK} ck
        set_false_path -from [get_pins \$ck]
        incr n
    }
}
puts "REGISTROS_ALTO_FANOUT \$n"
report_worst_slack -max -digits 3
report_checks -path_delay max -fields {fanout} -digits 3 > $OUT/timing_setup_datapath.rpt
EOF
} > $OUT/sta_$TOP.tcl
$STA $OUT/sta_$TOP.tcl > $OUT/sta_$TOP.log 2>&1 || { echo "ERROR en OpenSTA (ver $OUT/sta_$TOP.log)"; exit 1; }
grep -E "AVISO|Annotated" $OUT/sta_$TOP.log || true

# report_worst_slack escribe "worst slack max X" (OpenSTA nuevo) o "worst slack X" (viejo):
# se toma por orden de aparicion: 1ro = setup (max), 2do = hold (min)
slack_de() { awk -v k=$([ $2 = max ] && echo 1 || echo 2) '/^worst slack/{n++; if (n == k) {print $NF; exit}}' $OUT/sta_$1.log; }
fmax_de()  { awk "BEGIN{printf \"%.1f\", 1000/($PERIODO - $(slack_de $1 max))}"; }
# Fanout de la primera senal del camino critico (si es muy alto, el camino lo domina el fanout)
fanout_de(){ awk '/Path Group: clk/{f=1} f && /^ +[0-9]+ +[0-9.-]+ +[0-9.-]+ [v^]/{print $1; exit}' $OUT/timing_setup_$1.rpt; }

{
    printf "%-14s %10s %10s %10s %14s\n" "Bloque" "Slack [ns]" "Hold [ns]" "Fmax [MHz]" "Fanout inicio"
    for b in ols_buffer fft16 spec_mult ifft16 ols_output $TOP; do
        printf "%-14s %10s %10s %10s %14s\n" "$b" "$(slack_de $b max)" "$(slack_de $b min)" "$(fmax_de $b)" "$(fanout_de $b)"
    done
} > $OUT/timing.txt
cat $OUT/timing.txt

FMAX=$(fmax_de $TOP)
# El ultimo "worst slack max" del log es el del camino de datos (despues de los false paths)
SLACK_DP=$(awk '/^worst slack/{s=$NF} END{print s}' $OUT/sta_$TOP.log)
NREG=$(awk '/^REGISTROS_ALTO_FANOUT/{print $2}' $OUT/sta_$TOP.log)
FMAX_DP=$(awk "BEGIN{printf \"%.1f\", 1000/($PERIODO - $SLACK_DP)}")
echo "Camino de datos (sin los $NREG registros valid de fanout > 64): slack $SLACK_DP ns -> Fmax $FMAX_DP MHz"
# Fila "Total" de report_power: interna, conmutacion, fuga, total [W]
read P_INT P_SW P_LEAK P_TOT <<< $(awk '/^Total/{print $2, $3, $4, $5}' $OUT/power.rpt)

# ---------------------------------------------------------------------------
# Resumen
# ---------------------------------------------------------------------------
mw() { awk "BEGIN{printf \"%.3f\", $1*1000}"; }
{
    echo "PPA del filtro en frecuencia ($TOP) - SKY130 HD, corner tt_025C_1v80"
    echo "Reloj de la sintesis/STA: $PERIODO ns ($FREQ MHz) | duty de entrada: $DUTY %"
    echo "Yosys: $(yosys -V | awk '{print $2}') | STA: ${STA%% *} (pre-layout: sin cables ni arbol de reloj)"
    echo ""
    echo "AREA"
    cat $OUT/area.txt
    echo ""
    echo "PERFORMANCE (STA pre-layout, corner tt)"
    cat $OUT/timing.txt
    echo "  Fmax del filtro completo:  $FMAX MHz (camino critico tal cual sale de la sintesis)"
    echo "  Fmax del camino de datos:  $FMAX_DP MHz (sin los $NREG registros valid de fanout > 64)"
    echo "  Throughput: una muestra compleja por ciclo -> $FMAX Mmuestras/s a la Fmax del filtro"
    echo "  Latencia: 11 ciclos (bloque completo -> primera muestra de salida)"
    echo "  Los valid habilitan bloques enteros de registros (fanout de cientos) y la sintesis no"
    echo "  les pone buffers: en place & route se resuelve con buffers (repair_design de OpenROAD)"
    echo "  o en el RTL replicando esos registros (cloning, Modulo 9). La Fmax del camino de datos"
    echo "  es la que queda cuando ese fanout esta resuelto."
    echo ""
    echo "POTENCIA a $FREQ MHz, duty $DUTY %"
    echo "  Interna:      $(mw $P_INT) mW"
    echo "  Conmutacion:  $(mw $P_SW) mW"
    echo "  Fuga:         $(awk "BEGIN{printf \"%.3f\", $P_LEAK*1e6}") uW"
    echo "  Total:        $(mw $P_TOT) mW"
    echo ""
    echo "Reportes: $OUT/timing_setup_*.rpt (caminos criticos), $OUT/power.rpt, $OUT/stat_*.txt"
} | tee $OUT/resumen.txt
