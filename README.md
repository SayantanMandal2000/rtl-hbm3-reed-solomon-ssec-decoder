
# Hardware-Efficient Reed–Solomon SSEC Decoder for HBM3

A Verilog RTL implementation of a hardware-efficient **RS(19,17) Single-Symbol Error-Correcting (SSEC) decoder** for High-Bandwidth Memory (HBM3), enhanced with shared GF arithmetic logic, fault detection, and recovery through re-decoding.

## Overview

High-Bandwidth Memory requires reliable data protection while maintaining low decoder area and latency. Conventional Reed–Solomon decoders often rely on Galois Field (GF) inversion or lookup tables, which can introduce significant hardware cost.

This project implements an **inverse-free Reed–Solomon decoder** based on constant-GF multiplication and syndrome comparison. It extends the baseline architecture with hardware optimization and fault-tolerant mechanisms.

The design includes:

- A systematic RS(19,17) encoder
- Parallel syndrome calculation
- Inverse-free error-location and error-magnitude computation
- Single-symbol error correction
- Shared constant-GF logic using common-subexpression elimination (CSE)
- Post-correction syndrome consistency checking
- Fault recovery through re-decoding
- RTL testbenches and Python-based golden-model verification

## Key Features

### 1. Reed–Solomon RS(19,17) Coding

- Code: **RS(19,17)** with single-symbol error correction
- Symbol width: **16 bits**
- Field: **GF(2¹⁶)**
- Codeword width: **304 bits**
- Data width: **272 bits**
- Parity width: **32 bits**
- Corrects one erroneous 16-bit symbol per codeword

The codeword contains 17 data symbols and 2 parity symbols.

### 2. Inverse-Free Decoder

The decoder computes two syndromes from the received codeword polynomial \(r(x)\):

$$
S_1 = r(\alpha), \qquad S_2 = r(\alpha^2)
$$

where \(\alpha\) is a primitive element of the finite field \(\mathrm{GF}(2^{16})\).

For a single-symbol error at position \(i\), with error magnitude \(E\), the syndromes satisfy:

$$
S_1 = E\alpha^i
$$

$$
S_2 = E\alpha^{2i}
$$

Therefore, the error location can be identified by testing the equivalent relation:

$$
\boxed{S_2 = S_1\alpha^i}
$$

The decoder evaluates this condition for each valid symbol position. When the equality holds, position \(i\) is identified as the error location.

Once the error position is known, the error magnitude is calculated using a constant multiplication:

$$
\boxed{E = S_1\alpha^{-i}}
$$

The erroneous symbol is corrected by XORing the received symbol with the estimated error magnitude:

$$
\boxed{c_i = r_i \oplus E}
$$

Here, \(r_i\) is the received symbol and \(c_i\) is the corrected symbol.

Since \(\alpha^i\) and \(\alpha^{-i}\) are constants for each candidate position, the decoder replaces runtime GF division or inverse lookup operations with **constant-GF multiplication and comparison logic**, enabling an efficient hardware implementation.

### 3. Hardware Optimization with CSE

The constant-GF multiplier bank shares repeated XOR expressions using **common-subexpression elimination**.

| Implementation | XOR2 Count | Logic Depth |
|---|---:|---:|
| Independent constant multipliers | 2,131 | 4 |
| Shared CSE network | **188** | 6 |

This corresponds to approximately **91% fewer XOR operations before synthesis**. These are structural counts; final area and timing improvements require synthesis evaluation.

### 4. Fault Detection and Recovery

The design adds two fault-tolerance mechanisms:

- **Syndrome consistency checker:** Recomputes the syndromes of the corrected codeword and checks whether they agree with the decoder's decision.
- **Re-decoding recovery:** If a decoder fault or uncorrectable result is detected, the buffered input is decoded again after clearing the decoder state.

The output is marked verified only when the result passes the consistency check. Persistent faults are reported through the recovery-failure status.

## Architecture

```text
                 Write Path
          272-bit Input Data
                   |
           RS(19,17) Encoder
                   |
          304-bit Codeword
                   |
                 Memory
                   |
                 Read Path
                   |
          304-bit Received Word
                   |
           Syndrome Calculator
              S1 and S2
                   |
       Error Location and Magnitude
          (Inverse-Free Decoder)
                   |
            Symbol Correction
                   |
        Syndrome Consistency Check
                   |
          +--------+---------+
          |                  |
       Verified         Fault / Retry
          |                  |
      Data Output       Clear and Re-decode
                             |
                    Recovery Status
```

## RTL Modules

| File | Description |
|---|---|
| `rtl/rs_hbm_ecc_top.v` | Top module integrating encoder and robust decoder |
| `rtl/rs19_17_encoder.v` | Systematic RS(19,17) encoder |
| `rtl/rs_syndrome.v` | Parallel syndrome calculation |
| `rtl/rs_ssec_core.v` | Error-location, magnitude, and correction logic |
| `rtl/gf16_functions.vh` | GF(2¹⁶) arithmetic functions |
| `rtl/gf16_cmul_bank_cse.v` | Shared CSE-based constant-GF multiplier network |
| `rtl/rs_ssec_decoder_base.v` | Baseline decoder for comparison |
| `rtl/rs_ssec_robust_decoder.v` | Robust decoder with checker, retry FSM, and fault-injection support |

## Repository Structure

```text
rtl-hbm3-reed-solomon-ssec-decoder/
├── rtl/
│   ├── gf16_functions.vh
│   ├── rs19_17_encoder.v
│   ├── rs_syndrome.v
│   ├── rs_ssec_core.v
│   ├── gf16_cmul_bank_cse.v
│   ├── rs_ssec_decoder_base.v
│   ├── rs_ssec_robust_decoder.v
│   └── rs_hbm_ecc_top.v
├── tb/
│   ├── tb_rs_core.v
│   ├── tb_rs_hbm_top.v
│   ├── tb_rs_demo.v
│   └── rs_vectors.mem
├── scripts/
│   ├── gf16.py
│   ├── gen_vectors.py
│   ├── gen_cse.py
│   ├── create_project.tcl
│   └── run_sim_iverilog.sh
├── constraints/
│   └── rs_hbm_ecc_top.xdc
├── docs/
│   ├── cse_stats.json
│   └── rs_demo_waveform.png
└── README.md
```

## Simulation and Verification

The RTL was verified using an independent Python golden model and Verilog testbenches.

### Golden-Vector Verification

The core testbench checks the encoder and three decoder configurations against **1,094 test vectors**, including:

- Clean codewords
- Single-symbol errors across all 19 symbol positions
- Single-bit errors
- Double-symbol errors
- Triple-symbol errors

All tested vectors passed with **zero mismatches**.

### Random Regression with Fault Injection

A 3,000-word random regression evaluated error correction, fault detection, and recovery.

| Test Case | Words | Result |
|---|---:|---|
| Clean codewords | 595 | All verified |
| Single data-symbol errors | 1,194 | All corrected |
| Parity-symbol errors | 298 | All corrected |
| Transient decoder faults | 304 | All recovered through re-decoding |
| Permanent decoder faults | 297 | All reported as recovery failures |
| Double-symbol errors | 312 | All reported as uncorrectable |

Under the same stimulus, the decoder without the checker and recovery modifications silently delivered **139 incorrect words**.

## Running the Simulation

### Option 1: Vivado

From the project root:

```bash
vivado -mode batch -source scripts/create_project.tcl
```

Open the generated Vivado project and run the available simulation sets:

- `sim_1` — top-level regression
- `sim_core` — golden-vector core verification
- `sim_demo` — short waveform demonstration

### Option 2: Icarus Verilog

Run the open-source simulation script:

```bash
bash scripts/run_sim_iverilog.sh
```

The script compiles and runs the testbenches and generates simulation output files.

## Design Parameters

| Parameter | Description |
|---|---|
| `USE_CSE` | Selects the shared CSE-based GF multiplier implementation |
| `ENABLE_CHECK` | Enables the post-correction syndrome checker |
| `ENABLE_RETRY` | Enables recovery through re-decoding |
| `NPOS` | Number of candidate error positions: 17 or 19 |

The 17-position configuration follows the baseline decoder's data-symbol search. The 19-position configuration also locates errors in the parity symbols.

## Tools and Technologies

- **Verilog-2001** — RTL implementation
- **Vivado / XSim** — FPGA design and simulation
- **Icarus Verilog** — Open-source RTL simulation
- **Python** — Golden model, vector generation, and CSE logic generation
- **Reed–Solomon Coding**
- **GF(2¹⁶) Arithmetic**
- **RTL Verification and Fault Injection**

## Limitations and Future Work

- Area, timing, and power have not yet been measured through synthesis.
- The XOR counts represent the pre-synthesis logic structure; synthesis tools may perform additional optimization.
- A double-symbol error can sometimes appear as a single-symbol error and be miscorrected, which is an inherent limitation of an SSEC code.
- Future work includes synthesis-based PPA evaluation, broader fault injection, and exploration of pipelining and further GF logic optimization.

## Reference

J. Kwon, J. Kim, J. Yoon, H. Jeong, and I.-C. Park, “A Hardware-Efficient Reed–Solomon Decoding Architecture for Single-Symbol Error Correcting in High-Bandwidth Memory,” *IEEE Transactions on Very Large Scale Integration (VLSI) Systems*, vol. 34, no. 8, 2026.

## Author

**Sayantan Mandal**
RTL Design Engineer
ARM, Bengaluru

**Riya Das**  
Communication Engineering Student  
BITS Pilani, Hyderabad Campus

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
