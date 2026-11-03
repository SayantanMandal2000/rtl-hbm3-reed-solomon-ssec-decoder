## rs_hbm_ecc_top.xdc
## 200 MHz target clock. The design has ~1,000 I/O bits, more than any package
## provides, so implement it out-of-context (Synthesis Settings ->
## -mode out_of_context) or wrap it in a block design; no pin LOCs are given.
create_clock -period 5.000 -name clk [get_ports clk]
