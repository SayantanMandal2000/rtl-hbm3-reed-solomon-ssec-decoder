#==============================================================================
# create_project.tcl  -  Vivado project for the RS(19,17) SSEC decoder (HBM3)
#
# From the project root (folder containing rtl/ tb/ scripts/):
#     vivado -mode batch -source scripts/create_project.tcl
#   or in the Vivado Tcl console:
#     cd <path>/rs_ssec_hbm ; source scripts/create_project.tcl
#
# Simulation sets
#   sim_1    : tb_rs_hbm_top  (system test, fault injection, ~220 us)
#   sim_core : tb_rs_core     (1094 golden vectors, 3 decoder variants)
#   sim_demo : tb_rs_demo     (5 reads, short waveform for viewing)
#==============================================================================
set proj_name rs_ssec_hbm
set root      [file normalize [file dirname [info script]]/..]
set part      xc7z020clg400-1          ;# change to your board's device if needed

create_project $proj_name $root/vivado/$proj_name -part $part -force
set_property target_language Verilog [current_project]

# ---------------- design sources
add_files -fileset sources_1 [list \
    $root/rtl/gf16_functions.vh       \
    $root/rtl/gf16_cmul_bank_cse.v    \
    $root/rtl/rs19_17_encoder.v       \
    $root/rtl/rs_syndrome.v           \
    $root/rtl/rs_ssec_core.v          \
    $root/rtl/rs_ssec_decoder_base.v  \
    $root/rtl/rs_ssec_robust_decoder.v\
    $root/rtl/rs_hbm_ecc_top.v        ]
set_property file_type {Verilog Header} [get_files gf16_functions.vh]
set_property include_dirs [list $root/rtl] [get_filesets sources_1]
set_property top rs_hbm_ecc_top [get_filesets sources_1]

add_files -fileset constrs_1 $root/constraints/rs_hbm_ecc_top.xdc

# ---------------- simulation: system testbench
add_files -fileset sim_1 [list $root/tb/tb_rs_hbm_top.v]
set_property include_dirs [list $root/rtl] [get_filesets sim_1]
set_property top tb_rs_hbm_top [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]

# ---------------- simulation: golden-vector testbench
create_fileset -simset sim_core
add_files -fileset sim_core [list $root/tb/tb_rs_core.v $root/tb/rs_vectors.mem]
set_property include_dirs [list $root/rtl] [get_filesets sim_core]
set_property top tb_rs_core [get_filesets sim_core]
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_core]

# ---------------- simulation: short waveform demo
create_fileset -simset sim_demo
add_files -fileset sim_demo [list $root/tb/tb_rs_demo.v]
set_property include_dirs [list $root/rtl] [get_filesets sim_demo]
set_property top tb_rs_demo [get_filesets sim_demo]
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_demo]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
update_compile_order -fileset sim_core
update_compile_order -fileset sim_demo
current_fileset -simset sim_1

puts "Project created at $root/vivado/$proj_name"
puts "Run behavioural simulation (sim_1 or sim_core) and look for '*** ... PASSED ***'."
