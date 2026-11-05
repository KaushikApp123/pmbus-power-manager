# pmbus-power-manager

[![ci](https://github.com/KaushikApp123/pmbus-power-manager/actions/workflows/ci.yml/badge.svg)](https://github.com/KaushikApp123/pmbus-power-manager/actions/workflows/ci.yml)

A PMBus target written in SystemVerilog that supervises one output voltage rail.
A host talks to it over SMBus/I2C to set the output voltage, set over and under
voltage limits, turn the rail on and off, and read back status. If the rail
goes out of range it sets status bits, pulls SMBALERT# low, and shuts the
output down (either latched off or hiccup mode).

I built this to learn how digital power controllers handle the bus side and
the fault side, and to get better at verification. The register map is one
YAML file, and a Python script generates the register file RTL, the testbench
data, a C header for the host firmware, and the register docs from it.

## Status

- RTL, lint, simulation and coverage: done, all passing
- iCE40 synthesis and place and route: done, bitstream builds and meets timing
- STM32 host firmware: written and compiles, not run on a board yet
- Hardware bring-up on the UPduino with a logic analyzer: in progress

## What's in it

```
gen/     regmap.yaml + gen_regmap.py + Jinja2 templates
rtl/     the IP (rtl/generated/ is generator output)
tb/      testbench, I2C host model, mutation test script
fpga/    UPduino top level, pin file, build
fw/      STM32 HAL host driver and test sequence
hw/      la_check.py, a bus decoder/checker for logic analyzer captures
docs/    architecture notes, register map, verification, hardware setup
```

The IP is split into four blocks:

- `pmbus_i2c_target` handles the wires: glitch filtering, START/STOP, ACK,
  shifting bytes in and out, the 25 ms SMBus timeout, and SDA hold time.
- `pmbus_core` handles transactions: byte counts, PEC (CRC-8), and errors.
  Writes are buffered and only committed on STOP after every check passes, so
  a bad or cut-off transaction never changes a register.
- `pmbus_regfile` is generated from the YAML. It decodes commands, stores
  registers, and checks write protect and legal values.
- `pmbus_vout_monitor` compares each voltage sample against the four limits,
  debounces them, ignores UV during soft-start, and decides whether the output
  stays on.

More detail is in [docs/architecture.md](docs/architecture.md).

## Commands

| Code | Command | Notes |
|------|---------|-------|
| 0x01 | OPERATION | 0x80 on, 0x00 off |
| 0x03 | CLEAR_FAULTS | clears status, does not restart a latched output |
| 0x10 | WRITE_PROTECT | 0x00 / 0x20 / 0x40 / 0x80 |
| 0x19 | CAPABILITY | PEC, 400 kHz, SMBALERT# |
| 0x20 | VOUT_MODE | LINEAR16, exponent -9 |
| 0x21 | VOUT_COMMAND | default 3.3 V |
| 0x40-0x45 | OV/UV fault and warn limits, fault responses | |
| 0x78 / 0x79 | STATUS_BYTE / STATUS_WORD | |
| 0x7A / 0x7E | STATUS_VOUT / STATUS_CML | write 1 to clear |
| 0x8B | READ_VOUT | |
| 0x98 | PMBUS_REVISION | 1.3 |
| 0xD0 | MFR_SIM_VOUT | demo only, forces the plant voltage for fault testing |

Full map: [docs/register_map.md](docs/register_map.md) (generated, don't edit by hand).

## Verification

The testbench is self-checking and runs on Icarus Verilog. It has its own
bit-banged I2C host and its own CRC implementation, separate from the RTL, so a
CRC bug can't hide in both places.

It runs a generic set of tests on every command using the generated register
data (reset value, read, read with PEC, write, write with PEC, bad PEC, wrong
length, writes to read-only commands), then hits all 237 unsupported command
codes, then a set of directed tests for bus errors and output faults.

Latest run:

- 1,339 transactions, 1,974 checks, 0 errors
- 593/593 coverage bins hit
- 14 bugs injected into the RTL one at a time with `tb/mutate.py`, all 14 caught

The bus checker (`hw/la_check.py`) also runs on the simulation waveform. It
decodes every transaction, checks every PEC, and measures SDA hold time. The
first time I ran it, it showed my hold time was 285 ns, under the 300 ns SMBus
minimum, because I hadn't counted the input filter delay. Fixed, now 365 ns.

More in [docs/verification.md](docs/verification.md).

## FPGA

Target is a UPduino v3 (iCE40UP5K) using the open source flow (yosys,
nextpnr, icestorm). There's no real power stage on the board, so
`fpga/upduino_top.sv` has a simple plant model: the "voltage" ramps toward
VOUT_COMMAND when enabled, and writing MFR_SIM_VOUT forces it to a value so the
host can trigger OV and UV faults.

- 1,025 of 5,280 logic cells (19%)
- First place and route only reached about 28 MHz. After pipelining the
  plant model, the register lookup, and the monitor compares, it gets about
  47 MHz. I run it at 24 MHz for margin.

## Running it

Ubuntu packages:

```
sudo apt install iverilog verilator yosys nextpnr-ice40 fpga-icestorm
pip install -r requirements.txt
```

```
make gen        # regenerate from gen/regmap.yaml
make lint       # verilator -Wall
make sim        # full testbench, ends with TEST PASSED
make bus-check  # sim + la_check.py on the waveform
make mutate     # mutation tests (slow, ~10 min)
make synth      # build fpga/upduino.bin
```

CI runs all of these on every push.

To add a command, add it to `gen/regmap.yaml`, run `make gen`, wire up the new
port in `rtl/pmbus_power_manager.sv` if it needs logic, and run `make sim`. The
generic tests and coverage bins pick it up automatically.

## Hardware setup

UPduino as the PMBus target, an STM32 Nucleo as the host, and a logic analyzer
on SCL, SDA, SMBALERT#, EN and PG. Wiring, firmware setup and what to expect
on the analyzer are in [docs/hardware_test.md](docs/hardware_test.md).

## Things I left out or would change

- Only a subset of PMBus: no block reads, Group Command, or Alert Response
  Address. The retry/delay bits in the fault response registers are ignored.
- CLEAR_FAULTS is blocked under any write protect level. That's the strict
  reading of the spec. A lot of real parts allow it.
- No current or temperature telemetry.
- The critical path is a 16-bit compare in the monitor. Splitting it would get
  48 MHz with real margin.
- I'd like to add formal checks (SymbiYosys) for things like "no register
  changes without a STOP".
