# Synchronous FIFO (4 x 8-bit)

A simple synchronous FIFO in SystemVerilog. Pointers are one bit wider than
the address, so `empty` is "pointers equal" and `full` is "lower bits equal,
MSBs different". Read data is registered (valid one cycle after `read_en`).
Writes when full and reads when empty are ignored.

## Run

    iverilog -g2012 -o sim rtl/synchronous_FIFO.sv tb/tb.sv
    vvp sim

## Verification

The self-checking testbench compares the DUT against a queue-based reference
model every cycle (flags and data), with directed tests plus random traffic.

To check the testbench itself, I broke the RTL on purpose, one change at a time:

| Mutation | First failure | Caught by |
|---|---|---|
| remove `&& ~full` from `do_write` | t=170 | Test 2, `full` flag |
| remove `&& ~empty` from `do_read` | t=260 | Test 3, `empty` flag and `read_data` hold |
| `full` compares only `[1:0]` | t=30 | right after reset, `full` flag |
| `write_ptr + 3'd2` | t=60 | Test 1, `full` flag |
| no reset of `read_data` | t=30 | right after reset, `X` on `read_data` |