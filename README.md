# Synchronous FIFO (parameterized)

A parameterized synchronous FIFO in SystemVerilog with status flags and a
self-checking testbench. Pointers are one bit wider than the address
(`$clog2(MEM_DEPTH) + 1` bits), so `empty` is "pointers equal" and `full` is
"lower bits equal, MSBs different". Occupancy is `write_ptr - read_ptr`,
from 0 to `MEM_DEPTH`.

## Repository layout

| Path | Contents |
|---|---|
| `rtl/synchronous_FIFO.sv` | the FIFO |
| `tb/tb.sv` | self-checking testbench |
| `run_checks.ps1` | runs the parameter sweep and the mutation tests (Windows PowerShell) |
| `results.md` | tables produced by the last run of `run_checks.ps1` |
| `logs/` | raw simulator output of every run (not committed) |

## Parameters

| Parameter | Default | Meaning |
|---|---|---|
| `DATA_WIDTH` | 32 | width of `write_data` / `read_data` |
| `MEM_DEPTH` | 32 | number of entries; must be a power of 2 and >= 2 |
| `ALMOST_EMPTY` | `MEM_DEPTH/4` | `almost_empty` is high for occupancy 1 to this value |
| `ALMOST_FULL` | `MEM_DEPTH - MEM_DEPTH/4` | `almost_full` is high from this occupancy to `MEM_DEPTH-1` |

Illegal settings are rejected at time 0 in simulation with an `$error`:
`MEM_DEPTH` not a power of 2 (or below 2), or thresholds that don't satisfy
`1 <= ALMOST_EMPTY < ALMOST_FULL <= MEM_DEPTH-1`. With the default threshold
formulas, `MEM_DEPTH = 2` is rejected (`ALMOST_EMPTY` would be 0). The check
is fenced with `synthesis translate_off/on`.

## Ports

| Port | Dir | Description |
|---|---|---|
| `clk`, `reset_n` | in | clock, asynchronous active-low reset |
| `write_en`, `write_data` | in | write request and data |
| `read_en` | in | read request |
| `read_data` | out | registered, valid one cycle after a valid read |
| `full`, `empty` | out | occupancy `MEM_DEPTH` / occupancy 0 |
| `almost_full`, `almost_empty` | out | see flag definitions |
| `overflow`, `underflow` | out | illegal request flags |

## Behavior

- A write when full is ignored. A read when empty is ignored (`read_data` holds).
- Simultaneous write and read are decided on the state before the clock edge:
  on a full FIFO the read goes through and the write is blocked; on an empty
  FIFO the write goes through and the read is blocked.
- Reset clears both pointers and `read_data`.

## Flag definitions

| Flag | High when occupancy is |
|---|---|
| `empty` | 0 |
| `almost_empty` | 1 to `ALMOST_EMPTY` |
| `almost_full` | `ALMOST_FULL` to `MEM_DEPTH-1` |
| `full` | `MEM_DEPTH` |

Defaults by depth:

| `MEM_DEPTH` | `almost_empty` | `almost_full` |
|---|---|---|
| 4 | 1 | 3 |
| 8 | 1 to 2 | 6 to 7 |
| 16 | 1 to 4 | 12 to 15 |
| 32 | 1 to 8 | 24 to 31 |

`almost_empty` and `almost_full` are both low when the FIFO is empty or full.

`overflow` is high when a write is requested while the FIFO is full,
regardless of `read_en`. `underflow` is high when a read is requested while
the FIFO is empty, regardless of `write_en`. Both are combinational pulses:
they follow the request in the same cycle and are not latched.

## Run

From the repository root, default configuration (32-bit data, 32 entries):

    iverilog -g2012 -o sim rtl/synchronous_FIFO.sv tb/tb.sv
    vvp sim

Other configurations (top-level testbench parameters can be overridden):

    iverilog -g2012 -Ptb.DEPTH=16 -Ptb.DATA_WIDTH=8 -o sim rtl/synchronous_FIFO.sv tb/tb.sv
    vvp sim

A passing run prints `ALL CHECKS PASSED`. An illegal `DEPTH` prints the DUT's
`$error` and stops without that line.

To run the whole parameter sweep and all mutation tests in one go
(Windows PowerShell):

    powershell -ExecutionPolicy Bypass -File run_checks.ps1

This writes the summary tables to `results.md` and the full simulator output
to `logs/all_runs.log`.

## Verification

The self-checking testbench compares the DUT against a queue-based reference
model every cycle (data, flags, overflow, underflow). It stops at the first
failure and prints the time. Width, depth and thresholds are testbench
parameters passed to the DUT; data values come from a width-independent
generator and random phase length scales with depth.

Directed tests: normal traffic, fill to full with extra writes, drain to empty
with extra reads, simultaneous write+read when full / empty / in the middle,
oscillation around the full and empty boundaries, reset while full, and an
asynchronous reset asserted between clock edges (outputs must clear without a
clock). Then three phases of random traffic (balanced, write-heavy,
read-heavy). A coverage check fails the run if any flag was never exercised.

State-based flags are checked at the falling clock edge. `overflow` and
`underflow` depend directly on the inputs, so they are checked at the rising
edge, before the DUT registers update. A failure on one of those two flags is
therefore reported at the rising edge, and the run stops at the next falling
edge.

The expected thresholds in the testbench use the same formulas as the RTL
defaults, so threshold values are checked against the documented spec above,
not independently derived.

### Parameter sweep

Simulator: Icarus Verilog (`iverilog -g2012`).

| Config | Expected | Result |
|---|---|---|
| depth 32, width 32 (default) | pass | pass |
| depth 4, width 32 | pass | pass |
| depth 8, width 32 | pass | pass |
| depth 16, width 32 | pass | pass |
| depth 64, width 32 | pass | pass |
| depth 8, width 8 | pass | pass |
| depth 6 | rejected by `$error` | rejected by `$error` |
| depth 2 | rejected by `$error` | rejected by `$error` |

### Mutation testing

To check the testbench itself, the RTL is broken on purpose, one change at a
time, starting from the clean file each time. Each mutated copy is simulated
in the default configuration (depth 32, width 32). All 10 mutations are
caught. `run_checks.ps1` generates this table.

| Mutation | First failure | Caught by |
|---|---|---|
| remove `~full` from `do_write` | t=450 | `almost_full=1 expected 0 (occupancy 32)` |
| remove `~empty` from `do_read` | t=820 | `read_data changed to 78dde6c4 without a valid read` |
| `full` compares only the lower pointer bits | t=30 | `full=1 but model has 0 entries` |
| remove `~full` from `almost_full` | t=440 | `almost_full=1 expected 0 (occupancy 32)` |
| `almost_empty` uses `<` instead of `<=` | t=200 | `almost_empty=0 expected 1 (occupancy 8)` |
| `difference` one bit too narrow | t=440 | `almost_empty=1 expected 0 (occupancy 32)` |
| `underflow = empty && read_en && write_en` | t=820 | `underflow=0 expected 1 (occupancy 0, read_en=1)` |
| `overflow = full && write_en && ~read_en` | t=1190 | `overflow=0 expected 1 (occupancy 32, write_en=1)` |
| `write_ptr + 2'd2` | t=90 | `read_data=xxxxxxxx expected 3c6ef362` |
| no reset of `read_data` | t=30 | `read_data changed to xxxxxxxx without a valid read` |

For the two combinational flags the failure is detected at the rising edge
(t=815 and t=1185) and the run stops at the next falling edge, which is the
time shown.

## Limitations

- Simulated with Icarus Verilog only.
- Mutation tests run at the default configuration, not across the sweep.
- Threshold checks use the same formulas as the RTL (see above).
- No formal verification and no synthesis run.