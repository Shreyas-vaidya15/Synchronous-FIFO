# Synchronous FIFO (8 x 8-bit)

A synchronous FIFO in SystemVerilog with status flags and a self-checking
testbench. Pointers are one bit wider than the address (4 bits for 8 entries),
so `empty` is "pointers equal" and `full` is "lower bits equal, MSBs different".
Occupancy is `write_ptr - read_ptr`, a 4-bit value from 0 to 8.

## Ports

| Port | Dir | Description |
|---|---|---|
| `clk`, `reset_n` | in | clock, asynchronous active-low reset |
| `write_en`, `write_data[7:0]` | in | write request and data |
| `read_en` | in | read request |
| `read_data[7:0]` | out | registered, valid one cycle after a valid read |
| `full`, `empty` | out | occupancy 8 / occupancy 0 |
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
| `almost_empty` | 1 to 2 |
| `almost_full` | 5 to 7 |
| `full` | 8 |

`almost_empty` and `almost_full` are both low when the FIFO is empty or full.

`overflow` is high when a write is requested while the FIFO is full,
regardless of `read_en`. `underflow` is high when a read is requested while
the FIFO is empty, regardless of `write_en`. Both are combinational pulses:
they follow the request in the same cycle and are not latched.

## Run

    iverilog -g2012 -o sim rtl/synchronous_FIFO.sv tb/tb.sv
    vvp sim

A passing run prints `ALL CHECKS PASSED`.

## Verification

The self-checking testbench compares the DUT against a queue-based reference
model every cycle (data, flags, overflow, underflow). It stops at the first
failure and prints the time.

Directed tests: normal traffic, fill to full with extra writes, drain to empty
with extra reads, simultaneous write+read when full / empty / in the middle,
oscillation around the full and empty boundaries, reset while full.
Then three phases of random traffic (balanced, write-heavy, read-heavy).
A coverage check fails the run if any flag was never exercised.

State-based flags are checked at the falling clock edge. `overflow` and
`underflow` depend directly on the inputs, so they are checked at the rising
edge, before the DUT registers update.

### Mutation testing

To check the testbench itself, the RTL was broken on purpose, one change at a
time, starting from the clean file each time.

Depth-8 design:

| Mutation | First failure | Caught by |
|---|---|---|
| `almost_empty` threshold `< 4'd4` instead of `< 4'd3` | t=70 | Test 1, `almost_empty` at occupancy 3 |
| remove `~full` from `almost_full` | t=200 | Test 2, `almost_full` at occupancy 8 |
| 3-bit `difference` (wraps to 0 at occupancy 8) | t=200 | Test 2, `almost_empty` at occupancy 8 |
| `underflow = empty && read_en && write_en` | t=335 | Test 3, lone read on empty FIFO |
| `overflow = full && write_en && ~read_en` | t=465 | Test 4a, write+read on full FIFO |

Original 4-entry design (times from the earlier testbench):

| Mutation | First failure | Caught by |
|---|---|---|
| remove `&& ~full` from `do_write` | t=170 | Test 2, `full` flag |
| remove `&& ~empty` from `do_read` | t=260 | Test 3, `empty` flag and `read_data` hold |
| `full` compares only the lower pointer bits | t=30 | right after reset, `full` flag |
| `write_ptr + 3'd2` | t=60 | Test 1, `full` flag |
| no reset of `read_data` | t=30 | right after reset, `X` on `read_data` |

## Possible next steps

- Sticky (registered) overflow / underflow flags with a clear
- Parameterized data width, depth and thresholds
- First-word fall-through read