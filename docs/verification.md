# Verification

## Approach

* **Self-checking SystemVerilog testbench** (`tb/tb_pmbus.sv`) with a
  bit-banged I2C host (`tb/i2c_master_bfm.svh`). The host computes PEC with
  its own CRC function, separate from the RTL one, and the CRC is checked
  against the standard check value (CRC-8 of "123456789" = 0xF4).
* **Generated test data.** The generator writes the command list, sizes,
  access types, reset values, test values and coverage applicability into
  `tb/generated/regmap_tb.svh`. A generic loop tests every command from that
  data, so a new register in the YAML is tested with no testbench edits.
* **Directed error and fault injection** for everything the generic loop can't
  reach: bus abuse, glitches, timeouts, and output faults.
* **Functional coverage** per command and per scenario. Any hole fails the run.
* **Mutation testing** (`tb/mutate.py`) proves the checks have teeth.
* **Pin-level checker** (`hw/la_check.py`) runs the same decoder on the
  simulation VCD and on logic analyzer captures.

Simulation uses Icarus Verilog at a 50 MHz clock and a real 400 kHz bus. The
SMBus timeout, sample rate, blanking and hiccup times are scaled down so the
full run takes about 135 ms of simulated time (under a minute of wall time).

## Generic per-command tests

| Access | What is checked |
|--------|-----------------|
| rw | reset value; read; read + PEC; each test value written and read back; write + PEC then read + PEC; bad PEC write leaves the value and sets PEC_FAIL; size + 2 bytes leaves the value and sets INVALID_DATA; for words, a 1-byte write too |
| ro_const | value matches; read + PEC; write rejected with INVALID_CMD and value unchanged |
| ro_hw | read; read + PEC; write rejected with INVALID_CMD |
| w1c_hw | read; read + PEC; write 0 has no side effects; write + PEC; bad PEC; bad length |
| send | send; send + PEC; bad PEC; send with data bytes; read rejected with 0xFF and INVALID_CMD |
| unsupported (all 237 other codes) | write and read both set INVALID_CMD, read returns 0xFF, write is still ACKed |

After every negative case the test reads STATUS_CML, compares the exact bits,
checks SMBALERT# is low, and clears it.

## Directed scenarios

| Scenario | Check |
|----------|-------|
| Wrong address | NACK, no state change |
| STOP in the middle of a byte | no commit, INVALID_DATA |
| Repeated START after data bytes | write discarded, read returns 0xFF |
| Read with no command | 0xFF, no error |
| 20 ns spikes on SCL / SDA | transfer still correct with PEC |
| SCL held low past the timeout | SDA released, write discarded, CML OTHER set, next transfer works |
| Host NACKs a word read early | correct low byte, next transfer works |
| OV warning | STATUS_VOUT 0x40, output stays on, SMBALERT# low |
| CLEAR_FAULTS while still in warning | bit comes back |
| Sticky bits and write-1-to-clear | wrong bit has no effect, right bit clears, SMBALERT# releases |
| Spike shorter than debounce | no status, no shutdown |
| OV fault | shutdown, STATUS_VOUT 0xC0, STATUS_WORD 0x8861, stays off after CLEAR_FAULTS |
| Latch recovery | OPERATION off then on brings the output back |
| UV warning | on but not power good |
| UV fault | shutdown, STATUS_VOUT 0x30, STATUS_BYTE 0x41 |
| Soft-start blanking | turning on into 0 V is ignored until blanking ends, then faults |
| Response = ignore | OV reported, output stays on |
| Response = hiccup | at least 2 restarts, off time >= HICCUP_OFF, recovers when the fault clears |
| WRITE_PROTECT 0x80 / 0x40 / 0x20 | exactly the right commands blocked, INVALID_DATA set |
| Illegal values | OPERATION 0x81 and WRITE_PROTECT 0x11 rejected |

## Coverage

The run ends with a table like this (counts per bin, `-` where a bin does not
apply to that access type):

```
command                  code      RD  RD+PEC      WR  WR+PEC  BADPEC  BADLEN  WR_REJ  RD_REJ
OPERATION                0x01       1       1       3       1       1       1       -       -
CLEAR_FAULTS             0x03       -       -       1       1       1       1       -       1
...
unsupported codes: 474/474 read+write bins hit
...
Coverage: 593/593 bins (100%), 0 holes
```

## Mutation testing

`make mutate` copies the RTL, injects one bug at a time, and runs the full
testbench with `+stop_on_error`. Every mutant must fail.

| Mutant | Caught by |
|--------|-----------|
| PEC never checked on writes | bad PEC write changed the register |
| wrong PEC sent on reads | read + PEC mismatch |
| byte count not checked | bad length write changed the register |
| reads evaluated as writes | spurious CML bit in STATUS_WORD |
| read allowed after data bytes | aborted write returned data instead of 0xFF |
| hiccup has no off time | hiccup off-time check |
| write protect ignored | WP checks |
| no glitch filter | SCL glitch test |
| no SMBus timeout | timed-out write committed |
| no soft-start blanking | blanking test |
| no debounce | spike test |
| latch never clears | OPERATION off/on recovery |
| status not sticky | sticky-bit check |
| SMBALERT# ignores CML | alert check after CML errors |

## Bus checker on the simulation

`make bus-check` dumps only the five pins and runs `hw/la_check.py` on the
VCD. It decodes every transaction, checks every PEC, measures SDA hold, and
ties each EN/PG/SMBALERT# edge to the transaction before it. The first run of
this check caught that the testbench's DUT parameters gave only 285 ns of hold
time; it was raised to 12 cycles (365 ns measured).

## Lint and synthesis

* `make lint`: Verilator 5 `-Wall`, no warnings (two intentional unused-bit
  waivers for the fault response retry bits).
* `make synth`: yosys + nextpnr for the iCE40UP5K. Timing closure needed two
  changes, both kept in the RTL: the register file lookup is registered in the
  core, and the monitor captures VOUT and registers the limit compares before
  the debounce counters.
