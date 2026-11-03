# Hardware-Efficient RS(19,17) SSEC Decoder for HBM3 — Verilog project

**Student:** Riya Das (2025H1240213H) · **Course:** Coding Theory & Practices
**Base paper:** J. Kwon et al., "A Hardware-Efficient Reed–Solomon Decoding Architecture for Single-Symbol Error Correcting in High-Bandwidth Memory," IEEE TVLSI, vol. 34, no. 8, 2026.

The RTL reproduces the paper's inverse-free decoder and adds the three modifications from the mid-semester presentation (slides 17–18):

| | What | Where |
|---|---|---|
| Paper baseline | Syndromes S1, S2 → 17-way comparison `l_i = NOR(S2 ⊕ S1·αⁱ)` → magnitude `E = S1·α⁻ⁱ` → correction. 34 constants, no GF inverse | `rs_syndrome.v`, `rs_ssec_core.v` (NPOS=17, USE_CSE=0), `rs_ssec_decoder_base.v` |
| **Mod 1** – optimise constant GF logic | All 38 constant products of S1 (19 location + 19 magnitude) built from **one shared XOR network** found by common-subexpression elimination (Paar's greedy algorithm) | `scripts/gen_cse.py` → `gf16_cmul_bank_cse.v`; `rs_ssec_core.v` USE_CSE=1 |
| **Mod 2** – fault detection | Syndromes of the corrected codeword are recomputed and checked for **consistency** with the decoder's claim (corrected ⇒ S′=0; uncorrectable ⇒ S′≠0) | `rs_ssec_robust_decoder.v` |
| **Mod 3** – recovery by re-decoding | On a fault (or an "uncorrectable" result) the decoder state is cleared and the buffered word is decoded again; data is released only if verified; otherwise `recovery_fail` | `rs_ssec_robust_decoder.v` |

## Code definition used

* GF(2¹⁶), primitive polynomial **x¹⁶ + x¹² + x³ + x + 1** (0x1100B), α = x.
  The paper does not print the JEDEC polynomial. If your specification uses another one, change `GF16_POLY` in `rtl/gf16_functions.vh` and `POLY` in `scripts/gf16.py`, then re-run `gen_cse.py` and `gen_vectors.py`.
* RS(19,17), generator roots α and α², so S1 = r(α), S2 = r(α²). For one error E at position i: S1 = E·αⁱ, S2 = E·α²ⁱ, which gives the paper's Eq. (1)/(3)/(4).
* 304-bit codeword, symbol i at bits `[16i+15:16i]`: symbols 0–16 = data (272 bits), 17–18 = parity (32 bits).

## Files

```
rtl/
  gf16_functions.vh         GF(2^16) multiply, alpha^e, inverse (elaboration-time constants)
  rs19_17_encoder.v         systematic encoder (write path)
  rs_syndrome.v             fully parallel S1, S2 (also used by the Mod-2 checker)
  rs_ssec_core.v            paper Fig. 5/6: location vector L, magnitude, correction
                            NPOS 17 (paper) / 19 (also locates parity errors), USE_CSE 0/1
  gf16_cmul_bank_cse.v      Mod 1: generated shared XOR network (do not edit by hand)
  rs_ssec_decoder_base.v    paper baseline decoder, registered in/out (non-pipelined path)
  rs_ssec_robust_decoder.v  Mod 1 + Mod 2 + Mod 3 decoder (FSM, fault-injection ports)
  rs_hbm_ecc_top.v          TOP: encoder (write) + robust decoder (read)
tb/
  tb_rs_core.v              1094 golden vectors from Python, 3 decoder variants
  tb_rs_hbm_top.v           system test: directed + 3000-word random regression with faults
  tb_rs_demo.v              short 5-read waveform demo
  rs_vectors.mem            golden vectors (generated)
scripts/
  gf16.py                   independent Python golden model
  gen_vectors.py            builds tb/rs_vectors.mem
  gen_cse.py                Mod 1 generator (prints XOR counts)
  create_project.tcl        Vivado project with 3 simulation sets
  run_sim_iverilog.sh       open-source regression
constraints/rs_hbm_ecc_top.xdc
docs/rs_demo_waveform.png   waveform of the demo testbench
```

## Running in Vivado

```
cd rs_ssec_hbm
vivado -mode batch -source scripts/create_project.tcl
```
Open `vivado/rs_ssec_hbm/rs_ssec_hbm.xpr`, then:
* **sim_1** (`tb_rs_hbm_top`) → Run Behavioral Simulation → console ends with `*** TB_RS_HBM_TOP PASSED ***` (about 220 µs simulated, a few minutes of run time).
* **sim_core** (`tb_rs_core`) → `*** TB_RS_CORE PASSED (1094 vectors, 3 decoders) ***`.
* **sim_demo** (`tb_rs_demo`) → short 0.4 µs run for viewing waveforms; add `dut/u_dec/state`, `syn_r`, `consistent` and the `rd_*` outputs.

The top has ~1,000 I/O bits, so run synthesis **out-of-context** (Synthesis Settings → More Options `-mode out_of_context`) to get LUT/timing numbers.
To compare architectures, set the top-level parameters: `USE_CSE` 0/1, `ENABLE_CHECK` 0/1, `ENABLE_RETRY` 0/1, or synthesise `rs_ssec_decoder_base` with `NPOS=17, USE_CSE=0` (paper) and `USE_CSE=1` (Mod 1).

## Verification results (Icarus Verilog 13)

**tb_rs_core**: 1094 vectors (42 clean, 380 single-symbol errors at all 19 positions, 272 single-bit faults, 300 double, 100 triple symbol errors), all three decoders match the Python model, encoder matches on all vectors. The paper decoder and the paper + Mod 1 decoder are bit-identical, so Mod 1 does not change the decoding function.

**tb_rs_hbm_top**: 87 directed words plus a 3,000-word random regression. Random-regression counts:

| Case (random regression) | Result |
|---|---|
| Clean words (595) | no_error, verified, latency 4 clocks |
| Single data-symbol error (1,194) | all corrected and verified |
| Parity-symbol error (298) | all parity_corrected, data intact |
| Transient decoder fault, random mask in syndrome register (304) | all recovered by re-decode, latency 8 clocks |
| Permanent decoder fault (297) | all reported `recovery_fail`, never `verified` |
| Double-symbol error (312) | all reported `uncorrectable`, none verified |
| Same stimulus into a decoder **without** Mod 2/3 | 139 words delivered **wrong data silently** |

The directed part checks every data position, both parity positions, 10 transient and 4 permanent faults, and 6 double errors; all pass.

## Modification 1: XOR-network size

`scripts/gen_cse.py` output for the 38-constant bank (19 location + 19 magnitude products of S1):

| Mapping | XOR2 gates | Logic depth |
|---|---|---|
| Independent constant multipliers (paper mapping, before synthesis optimisation) | 2,131 | 4 |
| Shared CSE network (Mod 1) | **188** (−91 %) | 6 |

These are structural XOR2 counts. A synthesis tool also shares some logic on its own, so the post-synthesis difference is smaller. Confirm with Vivado or Design Compiler before quoting a final figure.

## Notes and limitations

* NPOS = 19 also locates the two parity symbols (2 extra constant comparisons). This keeps the corrected codeword valid, so the Mod-2 check is exact. NPOS = 17 is the paper's configuration.
* Fault injection corrupts the syndrome register. A fault there can never produce a valid-looking codeword: any wrong single-symbol "correction" leaves S′ ≠ 0. The consistency check also catches faults that hide a real error (syndrome forced to 0) or make a clean word look uncorrectable.
* A genuine double error can, rarely, look like a single error and be miscorrected. This is inherent to SSEC codes; the checker cannot detect it because the result is a valid codeword.
* Re-decode costs 4 extra clocks and is only taken on a fault or an uncorrectable word.
