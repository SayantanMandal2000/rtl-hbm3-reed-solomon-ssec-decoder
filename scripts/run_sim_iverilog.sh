#!/usr/bin/env bash
# Open-source regression (Icarus Verilog >= 11). Run from the project root.
set -e
mkdir -p sim && cd sim
cp ../tb/rs_vectors.mem .
iverilog -g2005 -I ../rtl -s tb_rs_core    -o core.vvp ../tb/tb_rs_core.v    ../rtl/*.v
vvp -n core.vvp | tail -6
iverilog -g2005 -I ../rtl -s tb_rs_hbm_top -o top.vvp  ../tb/tb_rs_hbm_top.v ../rtl/*.v
vvp -n top.vvp  | tail -16
