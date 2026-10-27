# PMBus Power Manager IP

A PMBus target (an SMBus/I2C device) written in SystemVerilog. It supervises
one output voltage rail: a host can configure it, turn the rail on and off,
read the voltage, and read fault status over a two-wire bus. When the rail
goes over or under voltage, the IP raises status bits, pulls SMBALERT# low, and
shuts the rail down (latched or hiccup) depending on how it is configured.

The register map lives in one YAML file. A Python script turns that file into
the RTL register file, the testbench data and coverage bins, a C header for the
host firmware, and the register map document. The design is checked by a
self-checking testbench with functional coverage and mutation testing, built
for a Lattice iCE40UP5K FPGA (UPduino board), and tested on hardware with an
STM32 Nucleo as the PMBus host and a logic analyzer on the pins.

This README is meant to answer any question about the project. Use the table of
contents to jump around.

---

## Contents

1. [Results at a glance](#1-results-at-a-glance)
2. [Quick start](#2-quick-start)
3. [Repository layout, file by file](#3-repository-layout-file-by-file)
4. [Background: I2C, SMBus and PMBus in 5 minutes](#4-background-i2c-smbus-and-pmbus-in-5-minutes)
5. [System architecture](#5-system-architecture)
6. [A write and a read, step by step](#6-a-write-and-a-read-step-by-step)
7. [Module reference](#7-module-reference)
8. [Register map](#8-register-map)
9. [Error handling: every bad input and what happens](#9-error-handling-every-bad-input-and-what-happens)
10. [Fault supervision: timelines and numbers](#10-fault-supervision-timelines-and-numbers)
11. [Write protect](#11-write-protect)
12. [The code generator](#12-the-code-generator)
13. [Verification](#13-verification)
14. [FPGA build](#14-fpga-build)
15. [STM32 firmware](#15-stm32-firmware)
16. [Hardware test procedure](#16-hardware-test-procedure)
17. [The bus checker (la_check.py)](#17-the-bus-checker-la_checkpy)
18. [Continuous integration](#18-continuous-integration)
19. [Design decisions and trade-offs](#19-design-decisions-and-trade-offs)
20. [Where this differs from the PMBus spec](#20-where-this-differs-from-the-pmbus-spec)
21. [Limitations and future work](#21-limitations-and-future-work)
22. [Troubleshooting](#22-troubleshooting)
23. [FAQ](#23-faq)
24. [Glossary](#24-glossary)

---

## 1. Results at a glance

| Item | Result |
|------|--------|
| Testbench | 1,339 PMBus transactions, 1,974 checks, 0 errors |
| Functional coverage | 593 / 593 bins (100%), 0 holes |
| Coverage scope | every supported command x every applicable access type, all 256 command codes, 24 bus and fault scenarios |
| Mutation testing | 14 bugs injected into the RTL one at a time, 14 caught |
| Lint | Verilator 5 `-Wall`, no warnings |
| Simulated time / wall time | about 134.5 ms simulated, about 50 s wall time on Icarus Verilog |
| IP size (yosys, iCE40) | about 618 LUT4, 358 flip-flops, 98 carry cells |
| Full FPGA design (IP + demo plant + top) | 1,025 of 5,280 logic cells (19%), 5 I/O pins plus the RGB LED driver |
| Timing | nextpnr reports about 47 MHz max; the board runs at 24 MHz (about 2x margin) |
| Bus timing checked | target SDA hold time measured by the checker on the sim VCD: 365 ns minimum (SMBus needs 300 ns) |
| Firmware | compiles cleanly against a HAL stub; PEC and LINEAR16 helpers pass a host-side unit test |

What has and has not been proven:

* Proven by running here: generator, lint, full simulation, coverage, mutation
  testing, bus checker on the simulation VCD, FPGA synthesis, place and route,
  bitstream generation, firmware compile and helper unit test.
* Not yet proven: the firmware running on a real STM32, the bitstream running on
  a real UPduino, and a real logic analyzer capture. The procedure for that is in
  [section 16](#16-hardware-test-procedure). Check the UPduino pin numbers
  against your board before wiring.

---

## 2. Quick start

### Tools

Tested with Ubuntu 24.04 packages:

| Tool | Version used | Used for |
|------|--------------|----------|
| Python | 3.13 | generator, mutation script, bus checker |
| PyYAML, Jinja2 | 6.0, 3.1 | generator (see `requirements.txt`) |
| Icarus Verilog | 12.0 | simulation |
| Verilator | 5.020 | lint |
| Yosys | 0.33 | synthesis |
| nextpnr-ice40, icestorm | Ubuntu packages | place and route, bitstream, programming |
| gcc | any | firmware host checks |

```
sudo apt install iverilog verilator yosys nextpnr-ice40 fpga-icestorm
pip install -r requirements.txt
```

### Make targets

| Command | What it does | Pass condition |
|---------|--------------|----------------|
| `make gen` | regenerate all generated files from `gen/regmap.yaml` | prints the 5 files written |
| `make gen-check` | regenerate in memory and compare with the files on disk | exits 0 if nothing is stale |
| `make lint` | Verilator `-Wall` on the IP | no output, exit 0 |
| `make sim` | compile and run the testbench, log in `build/sim.log` | `TEST PASSED` |
| `make wave` | same with a full VCD (`build/tb_pmbus.vcd`, large) | |
| `make bus-check` | sim with a pins-only VCD (`build/bus.vcd`), then `hw/la_check.py` on it | `RESULT: PASS` |
| `make fw-test` | firmware helper unit test plus compile check against a HAL stub | `PASS` |
| `make mutate` | inject 14 bugs, run the testbench on each | `14/14 mutants killed` |
| `make synth` | build `fpga/upduino.bin` | `PASS at 24.00 MHz` |
| `make -C fpga prog` | flash the UPduino with iceprog | |
| `make all` | gen, lint, sim, fw-test, synth | |
| `make clean` | remove `build/` and FPGA outputs | |

### What a passing simulation prints (end of the log)

```
Command coverage (count per bin, '-' = not applicable)
command                  code      RD  RD+PEC      WR  WR+PEC  BADPEC  BADLEN  WR_REJ  RD_REJ
OPERATION                0x01       1       1       3       1       1       1       -       -
CLEAR_FAULTS             0x03       -       -       1       1       1       1       -       1
WRITE_PROTECT            0x10       1       1       4       1       1       1       -       -
CAPABILITY               0x19       1       1       -       -       -       -       1       -
...
unsupported codes: 474/474 read+write bins hit

Scenario coverage
  wrong address NACKed                        hit
  ...
Coverage: 593/593 bins (100%), 0 holes

1339 transactions, 1974 checks, 0 errors, sim time 134500090000
TEST PASSED
```

---

## 3. Repository layout, file by file

```
pmbus-power-manager/
├── README.md                       this file
├── Makefile                        top-level targets (section 2)
├── requirements.txt                PyYAML, Jinja2
├── .gitignore
├── .github/workflows/ci.yml        CI pipeline (section 18)
├── gen/
│   ├── regmap.yaml                 THE source of truth for the register map
│   ├── gen_regmap.py               validates the YAML and renders the templates
│   └── templates/
│       ├── pmbus_regmap_pkg.sv.j2  -> rtl/generated/pmbus_regmap_pkg.sv
│       ├── pmbus_regfile.sv.j2     -> rtl/generated/pmbus_regfile.sv
│       ├── regmap_tb.svh.j2        -> tb/generated/regmap_tb.svh
│       ├── pmbus_regmap.h.j2       -> fw/generated/pmbus_regmap.h
│       └── register_map.md.j2      -> docs/register_map.md
├── rtl/
│   ├── pmbus_power_manager.sv      IP top: wires the blocks, builds STATUS_BYTE/WORD, SMBALERT#
│   ├── pmbus_i2c_target.sv         bit-level I2C target: filter, START/STOP, ACK, shift, timeout, SDA hold
│   ├── pmbus_glitch_filter.sv      2-flop synchronizer + glitch filter for SCL and SDA
│   ├── pmbus_core.sv               transaction layer: byte count, PEC, commit on STOP, reads, STATUS_CML
│   ├── pmbus_crc8.sv               combinational CRC-8 (one byte per call)
│   ├── pmbus_vout_monitor.sv       OV/UV compare, debounce, blanking, latch/hiccup, STATUS_VOUT, PG
│   └── generated/
│       ├── pmbus_regmap_pkg.sv     command codes, reset values, response encodings (package)
│       └── pmbus_regfile.sv        command decode, storage, read mux, WP and value checks
├── tb/
│   ├── tb_pmbus.sv                 self-checking testbench, coverage, report
│   ├── i2c_master_bfm.svh          bit-banged I2C host and PMBus transaction tasks
│   ├── mutate.py                   mutation testing script
│   └── generated/regmap_tb.svh     register data functions for the testbench
├── fpga/
│   ├── upduino_top.sv              board top: oscillator, reset, open-drain pads, plant model, LED
│   ├── upduino.pcf                 pin constraints
│   ├── Makefile                    yosys, nextpnr, icepack, iceprog
│   └── upduino.bin                 prebuilt bitstream
├── fw/
│   ├── stm32/
│   │   ├── pmbus_host.h / .c       PMBus host driver on STM32 HAL I2C (PEC, words, fault injection)
│   │   ├── pmbus_demo.c            scripted hardware test, prints PASS/FAIL over UART
│   │   ├── retarget.c              printf to USART2
│   │   └── main_snippet.c          what to paste into the CubeMX main.c
│   ├── generated/pmbus_regmap.h    command codes, reset values, register table, LINEAR16 helpers
│   ├── stubs/main.h                tiny HAL stand-in so the firmware compiles on a PC
│   └── test_host.c                 PC unit test of CRC-8 and LINEAR16 helpers
├── hw/
│   └── la_check.py                 decodes and checks a logic analyzer CSV or a simulation VCD
└── docs/
    ├── architecture.md             design notes
    ├── register_map.md             generated register reference
    ├── verification.md             verification plan and results
    └── hardware_test.md            wiring and bring-up guide
```

Files under any `generated/` folder and `docs/register_map.md` are written by
the generator. Do not edit them by hand. Edit `gen/regmap.yaml` or a template
and run `make gen`. CI fails if they are stale (`make gen-check`).

---

## 4. Background: I2C, SMBus and PMBus in 5 minutes

### I2C

Two open-drain wires: SCL (clock) and SDA (data). Devices only pull a line low
or let go; resistors pull the line high. That is why the RTL has `*_oe_o`
outputs ("pull low when 1") instead of normal outputs.

* **START**: SDA falls while SCL is high. Begins a transaction.
* **STOP**: SDA rises while SCL is high. Ends it.
* **Repeated START (Sr)**: a START without a STOP before it. Used to turn a
  write into a read without releasing the bus.
* **Data bits** change while SCL is low and are sampled when SCL rises.
* Every byte is 8 bits, MSB first, followed by a 9th **ACK** bit driven by the
  receiver: low = ACK, high = NACK.
* The first byte is the 7-bit address plus a R/W bit (0 = write, 1 = read).

### SMBus

A stricter profile of I2C used for system management. The parts that matter
here:

* **PEC (Packet Error Code)**: an optional CRC-8 byte at the end of a
  transaction. Polynomial x^8 + x^2 + x + 1 (0x07), initial value 0, no bit
  reversal, no final XOR. It covers every byte on the bus in that transaction,
  including the address bytes. Check value: CRC-8 of the ASCII string
  "123456789" is 0xF4.
* **Timeout**: if SCL is held low for 25 ms or more, every device must give up
  the transaction and release the bus. This keeps one stuck device from hanging
  the bus forever.
* **Data hold time**: after SCL falls, a device must keep SDA steady for at
  least 300 ns before changing it.
* **SMBALERT#**: an extra open-drain line a device pulls low to tell the host
  "read my status".

### PMBus

A command set on top of SMBus for power supplies. The first data byte of every
transaction is a **command code** (like a register address). Commands have a
fixed data size (0, 1 or 2 bytes). Formats used here:

```
Send byte:  S  Addr+W  Cmd  [PEC]  P
Write byte: S  Addr+W  Cmd  D0  [PEC]  P
Write word: S  Addr+W  Cmd  D0(low)  D1(high)  [PEC]  P
Read byte:  S  Addr+W  Cmd  Sr  Addr+R  D0  [PEC]  P
Read word:  S  Addr+W  Cmd  Sr  Addr+R  D0(low)  D1(high)  [PEC]  P
```

Words are sent low byte first.

**LINEAR16 voltage format**: a voltage is a 16-bit unsigned mantissa times
2^exponent. The exponent is reported by VOUT_MODE. This design fixes the
exponent at -9, so:

```
volts = value / 512        1 LSB = 1.953 mV        max = 65535 / 512 = 127.998 V
value = round(volts * 512)
```

Examples: 3.30 V -> 1690 (0x069A). 0x0699 = 1689 -> 3.2988 V.
4.00 V -> 2048 (0x0800). 2.50 V -> 1280 (0x0500).

**Status model**: faults and warnings set sticky bits in STATUS_* registers.
STATUS_BYTE and STATUS_WORD summarize them. CLEAR_FAULTS clears everything.
Bits that are still true get set again right away.

---

## 5. System architecture

```
            +--------------------+   byte events   +--------------+   lookup / commit   +-------------------+
 SCL ------>| pmbus_i2c_target   |---------------->| pmbus_core   |<------------------->| pmbus_regfile     |
 SDA <----->|  sync + glitch flt |<----------------|  PEC, length |                     |  (generated from  |
            |  bit FSM, SDA hold |   tx byte       |  commit@STOP |                     |   regmap.yaml)    |
            |  SMBus timeout     |                 |  STATUS_CML  |                     |  WP + value check |
            +--------------------+                 +--------------+                     +-------------------+
                                                                                          | limits, OPERATION
 VOUT samples ------------------------------------------------------------------>+------v-------------+
                                                                                 | pmbus_vout_monitor |--> EN
                                                                                 |  debounce, blank,  |--> PG
                                                                                 |  latch / hiccup    |
                                                                                 +--------------------+
                                                              STATUS_VOUT | STATUS_CML --> SMBALERT#
```

### Layers

| Layer | Module | Knows about |
|-------|--------|-------------|
| Physical / bit | `pmbus_i2c_target` + `pmbus_glitch_filter` | wires, edges, bits, bytes, ACK, timeout |
| Transaction | `pmbus_core` + `pmbus_crc8` | commands, byte counts, PEC, commit rules, CML errors |
| Register | `pmbus_regfile` (generated) | which commands exist, sizes, access types, storage, WP, legal values |
| Application | `pmbus_vout_monitor` | voltage limits, faults, enable, power good |
| Glue | `pmbus_power_manager` | status summary registers, SMBALERT# |

Each layer only talks to its neighbors. The I2C target has no idea what a
PMBus command is; the core has no idea what a voltage is; the monitor has no
idea a bus exists.

### Clock and reset

* One clock (`clk`) for everything. SCL and SDA are treated as asynchronous
  inputs and synchronized. There are no clock domain crossings inside the IP.
* `rst_n` is an active-low asynchronous reset. Every flop has a reset value.
* The IP works at any clock speed that leaves enough cycles per SCL period.
  Rule of thumb: at least 20x the SCL rate after accounting for the filter and
  hold delays. 24 MHz with a 400 kHz bus gives 60 clocks per SCL period.

### Top-level ports (`pmbus_power_manager`)

| Port | Dir | Width | Meaning |
|------|-----|-------|---------|
| `clk` | in | 1 | system clock |
| `rst_n` | in | 1 | async reset, active low |
| `addr_i` | in | 7 | 7-bit bus address (tie to a constant or pin straps) |
| `scl_i` | in | 1 | SCL pad input |
| `sda_i` | in | 1 | SDA pad input |
| `sda_oe_o` | out | 1 | 1 = pull SDA low |
| `smbalert_oe_o` | out | 1 | 1 = pull SMBALERT# low |
| `vout_sample_i` | in | 1 | one-clock strobe: a new VOUT sample is on `vout_i` |
| `vout_i` | in | 16 | output voltage in LINEAR16 (exponent -9) |
| `en_o` | out | 1 | enable for the power stage |
| `pg_o` | out | 1 | power good |
| `vout_command_o` | out | 16 | VOUT_COMMAND register, for a regulator reference or DAC |
| `mfr_sim_vout_o` | out | 16 | MFR_SIM_VOUT register, used only by the FPGA demo plant |

### Parameters

| Parameter | Default | Meaning | Hardware build (24 MHz) | Testbench (50 MHz) |
|-----------|---------|---------|-------------------------|--------------------|
| `FILTER_LEN` | 3 | clocks a new SCL/SDA level must hold to be accepted | 3 (125 ns) | 3 (60 ns) |
| `SDA_HOLD_CYCLES` | 16 | clocks between seeing SCL fall and changing SDA | 8 (333 ns) | 12 (240 ns) |
| `TIMEOUT_CYCLES` | 1,200,000 | SCL-low time that aborts a transfer | 600,000 (25 ms) | 5,000 (100 us) |
| `DEBOUNCE` | 3 | consecutive samples a limit violation must last | 3 (3 ms) | 3 (150 us) |
| `BLANK_SAMPLES` | 32 | samples after turn-on before UV is checked | 32 (32 ms) | 16 (800 us) |
| `HICCUP_OFF` | 32 | samples the output stays off before a hiccup retry | 100 (100 ms) | 8 (400 us) |

Defaults assume a 48 MHz clock. The testbench values are scaled so the run
finishes in under a minute.

---

## 6. A write and a read, step by step

### Write word: set VOUT_COMMAND to 0x069A with PEC

Bus: `S 0x80 0x21 0x9A 0x06 PEC P` (0x80 is address 0x40 shifted left with W = 0).

1. **START**. The I2C target sees SDA fall while SCL is high, pulses
   `start_o`, enters `S_ADDR`.
2. **Address byte**. 8 bits are shifted in on SCL rising edges. On the falling
   edge after bit 8, `shreg[7:1] == own_addr`, so the target pulses
   `addr_hit_o` with `rw_o = 0` and asks to drive ACK. The core resets its
   byte counter and starts the CRC with the address byte: `crc = crc8(0, 0x80)`.
3. **ACK**. After `SDA_HOLD_CYCLES` the target pulls SDA low. On the next SCL
   fall it releases SDA (again after the hold delay).
4. **Command byte 0x21**. The target pulses `rx_valid_o` with `rx_data_o = 0x21`
   and ACKs. The core stores `cmd_o = 0x21`, updates the CRC,
   `wr_cnt = 1`. The register file now decodes 0x21: valid, writable, size 2.
   The core registers that lookup on the next clock.
5. **Data bytes 0x9A, 0x06**. Stored in `buf0`, `buf1`, CRC updated,
   `wr_cnt = 3`. `wdata_o = 0x069A`.
6. **PEC byte**. Not stored, but it goes through the CRC. If the host's PEC is
   right, the CRC is now exactly 0x00. `wr_cnt = 4`.
7. **STOP**. The core evaluates: `n_data = wr_cnt - 1 = 3 = size + 1`, so the
   last byte was PEC. Checks in priority order:
   command known and writable, byte count legal, `crc == 0`, write protect
   allows it, value legal. All pass, so `wr_en_o` pulses for one clock.
8. **Commit**. The register file sees `wr_en_i` with `cmd_i = 0x21` and loads
   `vout_command_q <= 16'h069A`.

If any check fails, nothing is written and one STATUS_CML bit is set instead.

### Read word: READ_VOUT with PEC

Bus: `S 0x80 0x8B Sr 0x81 D0 D1 PEC P`, host ACKs D0 and D1, NACKs PEC.

1. START, address+W, command 0x8B exactly as above. `wr_cnt = 1`.
2. **Repeated START**. The core sees a START while in a transaction with
   exactly one byte written, so it sets `sr_cmd_ok`. Any other byte count
   means the read will be refused.
3. **Address+R (0x81)**. On `addr_hit_o` with `rw_o = 1` the core:
   continues the CRC (it already covers 0x80 and 0x8B) with 0x81, decides
   `rd_ok` (command known and readable), takes a **snapshot** of the 16-bit
   read data, stores the size (2), and resets the read index.
4. **First byte**. One clock after the address hit, the target asks for a byte
   (`tx_req_o`). The core answers with the low byte of the snapshot and adds it
   to the CRC. The target loads it on the falling edge that ends the ACK bit
   and shifts it out MSB first.
5. **Next bytes**. Each time the target finishes 8 bits it releases SDA for the
   host ACK and immediately asks for the next byte. The core supplies the high
   byte, then the PEC (the CRC so far), then 0xFF for anything after.
6. Host NACKs the PEC byte, the target goes idle, host sends STOP.

Because the read value is snapshotted at the Addr+R phase, a word can never
tear (low byte from one sample, high byte from the next).

### Timing of one transaction at 400 kHz

One byte is 9 SCL clocks = 22.5 us. A word read with PEC is START + 6 bytes +
STOP, about 140 us. The testbench averages about 100 us per transaction.

---

## 7. Module reference

### 7.1 `pmbus_glitch_filter`

Two-flop synchronizer, then a counter. The output only changes after the
synchronized input has held a new level for `LEN` clocks in a row. Any shorter
pulse is ignored. Reset value is 1 (bus idle high).

| Port | Dir | Meaning |
|------|-----|---------|
| `d_i` | in | raw asynchronous pin |
| `q_o` | out | clean level |

Latency: 2 clocks of synchronizer plus `LEN` clocks of filter. At 24 MHz with
`LEN = 3` that is 5 clocks, about 210 ns, and the filter rejects spikes up to
about 125 ns. SMBus requires rejecting 50 ns spikes.

### 7.2 `pmbus_i2c_target`

Turns pins into byte events. One instance of the glitch filter on each line,
then edge detection on the clean signals:

```
scl_rise  = scl & ~scl_d
scl_fall  = ~scl & scl_d
start_det = scl & scl_d & ~sda & sda_d     (SDA falls while SCL stays high)
stop_det  = scl & scl_d &  sda & ~sda_d    (SDA rises while SCL stays high)
```

#### State machine

| State | Waits for | Then |
|-------|-----------|------|
| `S_IDLE` | START | `S_ADDR` |
| `S_ADDR` | 8 bits on SCL rising; after the 8th, the next SCL falling | if address matches: pulse `addr_hit_o`, drive ACK, go `S_ADDR_ACK`. Otherwise go `S_IDLE` and ignore the rest of the transaction |
| `S_ADDR_ACK` | SCL falling (end of ACK clock) | write: release SDA, go `S_RX`. Read: load first byte, drive bit 7, go `S_TX` |
| `S_RX` | 8 bits; after the 8th, SCL falling | pulse `rx_valid_o` with the byte, drive ACK, go `S_RX_ACK` |
| `S_RX_ACK` | SCL falling | release SDA, go `S_RX` |
| `S_TX` | SCL falling, 7 more times to shift bits 6..0, then once more | release SDA for the host ACK, pulse `tx_req_o` to fetch the next byte, go `S_TX_ACK` |
| `S_TX_ACK` | SCL rising (sample host ACK), then SCL falling | ACK: load next byte, go `S_TX`. NACK: go `S_IDLE` |

Overrides from any state, in priority order: timeout -> `S_IDLE`;
START -> `S_ADDR`; STOP -> `S_IDLE`.

#### Outputs to the core

| Signal | Meaning |
|--------|---------|
| `start_o` | pulse on START or repeated START |
| `stop_o` | pulse on STOP |
| `addr_hit_o`, `rw_o` | pulse when our address was received; `rw_o` holds the direction |
| `rx_valid_o`, `rx_data_o` | pulse with each received write byte |
| `tx_req_o` | pulse: put the next read byte on `tx_data_i` |
| `timeout_o` | pulse when SCL has been low for `TIMEOUT_CYCLES` |

The first read byte is requested one clock after `addr_hit_o`, not in the same
clock, so the core handles the two events separately. Later bytes are
requested as soon as the previous byte's 8th bit is out, which gives the core
the whole ACK bit time to answer.

#### SDA hold delay

The FSM never drives SDA directly. It sets a request bit (`drive_req`). A small
counter copies the request to `sda_oe_o` only after `SDA_HOLD_CYCLES` clocks.
Since every request changes right after an SCL falling edge is seen, every
SDA change happens at least that long after SCL fell. The real hold time on
the wire is longer, because the falling edge is first delayed by the
synchronizer and filter: about 6 clocks extra. In simulation at 50 MHz,
12 hold cycles measured 365 ns. On the board at 24 MHz, 8 hold cycles should
give roughly 580 ns.

#### Timeout

A counter runs while the filtered SCL is low and resets when SCL is high. When
it reaches `TIMEOUT_CYCLES - 1` it fires one pulse, then saturates so it does
not fire again until SCL goes high. The FSM goes to `S_IDLE` and releases SDA.

#### Clock stretching

Never used. The target answers every read byte request within one clock, so it
never needs to hold SCL low. SCL is input only.

### 7.3 `pmbus_crc8`

Combinational, one byte per call: XOR the byte into the CRC, then 8 rounds of
shift-left with conditional XOR 0x07. The core uses one instance. A mux picks
the starting CRC and the input byte for whichever event is happening (address
byte, received byte or transmitted byte).

### 7.4 `pmbus_core`

The transaction layer. State it keeps:

| Register | Meaning |
|----------|---------|
| `in_txn` | our address was hit since the last START |
| `rd_phase` | current transfer is a read |
| `sr_cmd_ok` | a repeated START came right after exactly one written byte (the command) |
| `wr_cnt` | bytes written after Addr+W, including the command; saturates at 7 |
| `cmd_o` | command byte (feeds the register file decode) |
| `buf0`, `buf1` | data bytes; `wdata_o = {buf1, buf0}`. `buf1` is cleared when `buf0` is written, so 1-byte writes have a clean high byte |
| `crc` | running CRC over the transaction |
| `rd_ok`, `rd_shadow`, `rd_size`, `rd_idx` | read permission, snapshot, size, and which byte is next |
| `status_cml_o` | STATUS_CML register |

**Registered lookup.** The register file's answers (`cmd_valid`, `readable`,
`writable`, `size`, `wp_ok`, `value_ok`, `rdata`) are registered one clock
inside the core. Safe because the command and data bytes always arrive at
least one SCL period before they are used. This was added to meet timing on
the FPGA.

**Write evaluation at STOP.** Only if the transaction was ours, was a write,
and had at least one byte:

```
n_data = wr_cnt - 1
if command unknown or not writable           -> INVALID_CMD
else if n_data != size and n_data != size+1  -> INVALID_DATA
else if n_data == size+1 and crc != 0        -> PEC_FAIL
else if write protect blocks it or value
        is not in the allowed list           -> INVALID_DATA
else                                         -> commit (wr_en_o pulse)
```

Only one bit is set per bad transaction, the first that applies in that order.

**Read rules.**

* Read after `Sr` with exactly one command byte and a known readable command:
  data bytes from the snapshot, then PEC, then 0xFF.
* Read after `Sr` of an unknown or non-readable command: every byte is 0xFF
  and INVALID_CMD is set.
* Read with no command (START then Addr+R): every byte is 0xFF, no flag.
* Read after data bytes (`S Addr+W Cmd D0 Sr Addr+R`): the write is thrown
  away (no STOP, so no commit), every read byte is 0xFF, no flag.

**STATUS_CML.** Sticky. Each clock: `cml = (cml & ~clear) | set`. Set beats
clear in the same clock. Clear comes from CLEAR_FAULTS (all bits) or a write to
STATUS_CML (bits that are 1 in the written byte).

| Bit | Name | Cause |
|-----|------|-------|
| 7 | INVALID_CMD | unknown code, write to read-only, read of a send-byte command |
| 6 | INVALID_DATA | wrong byte count, illegal value, write-protected |
| 5 | PEC_FAIL | PEC present and wrong |
| 1 | OTHER | SMBus timeout during one of our transactions |

### 7.5 `pmbus_regfile` (generated)

Generated from `gen/regmap.yaml`. Contents:

* **Decode** (`always_comb case (cmd_i)`): for each command sets valid,
  readable, writable, size, write-protect permission, value legality, and
  read data. Unknown codes fall to `default`: invalid, read data 0xFFFF.
* **Write-protect permission**: `wp_ok = (WRITE_PROTECT == 0x00)` by default.
  Commands with a `wp_allow` list add `|| (WRITE_PROTECT == level)` terms.
* **Value check**: commands with an `allowed` list get
  `value_ok = (wdata == v0) || (wdata == v1) || ...`.
* **Storage**: one flop register per `rw` command with its reset value, loaded
  when `wr_en_i` and `cmd_i` match.
* **Hardware inputs**: `ro_hw` and `w1c_hw` commands read from `<name>_i` ports.
* **Strobes**: `w1c_hw` and `send` commands produce `<name>_wr` pulses; the
  owner reads the data from `wdata`.

### 7.6 `pmbus_vout_monitor`

The supervisor. Pipeline, in clock order after `sample_i`:

```
clock 0: sample_i            vout_s <= vout_i (capture)
clock 1: sample_d1           raw[] <= compares on vout_s
clock 2: sample_d2           debounce counters update from raw[]
clock 3:                     act[] (debounced) visible: status bits set, enable decision
clock 4:                     en_o, status_vout_o updated (registered)
```

Compares:

| raw bit | Condition |
|---------|-----------|
| OV fault | `vout > VOUT_OV_FAULT_LIMIT` |
| OV warn | `vout > VOUT_OV_WARN_LIMIT` |
| UV warn | checking and `vout < VOUT_UV_WARN_LIMIT` |
| UV fault | checking and `vout < VOUT_UV_FAULT_LIMIT` |

`checking = en_o && blank_cnt == BLANK_SAMPLES`. The blanking counter resets
whenever the output is off and counts samples while it is on. UV debounce
counters also reset whenever `checking` is false.

Debounce: each condition has a counter that counts consecutive samples where it
is true and resets on the first sample where it is false. A condition is
"active" when its counter reaches `DEBOUNCE`.

OV is checked even when the output is off. If something else drives the rail
high, you still find out.

Fault response, bits 7:6 of the response register:

| Bits 7:6 | Behavior | Restart |
|----------|----------|---------|
| 00 | ignore: status bits and SMBALERT# only | not needed |
| 01 or 10 | shut down and latch off (`latched_o = 1`) | OPERATION off, then on |
| 11 | hiccup: off, wait `HICCUP_OFF` samples, turn on again with fresh blanking | automatic, repeats while the fault lasts |

Enable logic, registered:

```
en_o <= OPERATION[7] && !latched && !ov_latch && !uv_latch
        && !ov_hiccup && !uv_hiccup && hiccup_timer == 0
```

The `!ov_latch` and `!uv_latch` terms make the output drop in the same clock
the latch is set, not one clock later.

STATUS_VOUT is sticky like STATUS_CML: bits are set every clock their
condition is active, cleared by CLEAR_FAULTS or by writing 1s to STATUS_VOUT.
Set wins over clear, so a bit cannot be cleared while the fault is still there.

Power good (registered):
`pg_o = checking && vout >= VOUT_UV_WARN_LIMIT && vout <= VOUT_OV_FAULT_LIMIT`.

READ_VOUT returns `vout_s`, the last captured sample.

### 7.7 `pmbus_power_manager` (top)

Instantiates the four blocks and adds:

```
STATUS_BYTE = { BUSY=0,
                OFF = ~en_o,
                VOUT_OV_FAULT = STATUS_VOUT[7],
                IOUT_OC=0, VIN_UV=0, TEMP=0,
                CML = |STATUS_CML,
                NONE_OF_THE_ABOVE = |STATUS_VOUT[6:4] }

STATUS_WORD = { VOUT = |STATUS_VOUT, IOUT=0, INPUT=0, MFR=0,
                POWER_GOOD# = ~pg_o, FANS=0, OTHER=0, UNKNOWN=0,
                STATUS_BYTE }

SMBALERT# pulled low (registered) while |STATUS_VOUT or |STATUS_CML
```

Values you will see often:

| Situation | STATUS_BYTE | STATUS_WORD | STATUS_VOUT |
|-----------|-------------|-------------|-------------|
| Reset (output off) | 0x40 | 0x0840 | 0x00 |
| On, healthy | 0x00 | 0x0000 | 0x00 |
| On, OV warning | 0x01 | 0x8001 | 0x40 |
| OV fault, latched off | 0x61 | 0x8861 | 0xC0 |
| UV fault, latched off | 0x41 | 0x8841 | 0x30 |

---

## 8. Register map

Default address 0x40 (7-bit). Write byte 0x80, read byte 0x81.

| Code | Name | Access | Bytes | Reset | Notes |
|------|------|--------|-------|-------|-------|
| 0x01 | OPERATION | rw | 1 | 0x00 | 0x80 on, 0x00 off, 0x40 soft off (treated as off). Only these 3 values accepted. Off clears a latched fault. |
| 0x03 | CLEAR_FAULTS | send | 0 | | clears STATUS_VOUT and STATUS_CML; does not restart a latched output |
| 0x10 | WRITE_PROTECT | rw | 1 | 0x00 | 0x00, 0x20, 0x40, 0x80 only (section 11) |
| 0x19 | CAPABILITY | ro_const | 1 | 0xB0 | PEC supported, 400 kHz, SMBALERT# supported |
| 0x20 | VOUT_MODE | ro_const | 1 | 0x17 | LINEAR16 mode, exponent -9 (5-bit two's complement 10111) |
| 0x21 | VOUT_COMMAND | rw | 2 | 0x0699 | 3.299 V. Drives `vout_command_o` |
| 0x40 | VOUT_OV_FAULT_LIMIT | rw | 2 | 0x0742 | 3.629 V (110%) |
| 0x41 | VOUT_OV_FAULT_RESPONSE | rw | 1 | 0x80 | bits 7:6 (section 7.6) |
| 0x42 | VOUT_OV_WARN_LIMIT | rw | 2 | 0x06EE | 3.465 V (105%) |
| 0x43 | VOUT_UV_WARN_LIMIT | rw | 2 | 0x0645 | 3.135 V (95%) |
| 0x44 | VOUT_UV_FAULT_LIMIT | rw | 2 | 0x05F0 | 2.969 V (90%) |
| 0x45 | VOUT_UV_FAULT_RESPONSE | rw | 1 | 0x80 | same encoding as 0x41 |
| 0x78 | STATUS_BYTE | ro_hw | 1 | | summary (section 7.7) |
| 0x79 | STATUS_WORD | ro_hw | 2 | | summary (section 7.7) |
| 0x7A | STATUS_VOUT | w1c_hw | 1 | | 7 OV fault, 6 OV warn, 5 UV warn, 4 UV fault |
| 0x7E | STATUS_CML | w1c_hw | 1 | | 7 invalid cmd, 6 invalid data, 5 PEC fail, 1 other (timeout) |
| 0x8B | READ_VOUT | ro_hw | 2 | | last VOUT sample |
| 0x98 | PMBUS_REVISION | ro_const | 1 | 0x33 | PMBus 1.3 |
| 0xD0 | MFR_SIM_VOUT | rw | 2 | 0x0000 | manufacturer specific. FPGA demo: non-zero forces the plant voltage (fault injection) |

Access types:

| Type | Read | Write |
|------|------|-------|
| rw | stored value | stored, subject to WP and allowed values |
| ro_const | fixed value | rejected, INVALID_CMD |
| ro_hw | live hardware value | rejected, INVALID_CMD |
| w1c_hw | live hardware value | each 1 bit clears that status bit |
| send | rejected (0xFF, INVALID_CMD) | send byte, no data |

The generated reference with every field is [docs/register_map.md](docs/register_map.md).

---

## 9. Error handling: every bad input and what happens

"ACK" means the target acknowledges the bytes anyway. The host learns about
the problem from STATUS_CML and SMBALERT#.

| Input | Bus response | State change | STATUS_CML |
|-------|--------------|--------------|------------|
| Wrong address | address NACKed, rest ignored | none | none |
| Unknown command, write | ACK | none | 0x80 |
| Unknown command, read | ACK, data 0xFF | none | 0x80 |
| Write to read-only command | ACK | none | 0x80 |
| Read of CLEAR_FAULTS (send byte) | ACK, data 0xFF | none | 0x80 |
| Too many bytes (more than size + 1) | ACK | none | 0x40 |
| Too few bytes (word write with 1 byte) | ACK | none | 0x40 |
| STOP in the middle of a byte | partial byte ignored, then judged on full bytes | none | usually 0x40 (too few bytes) |
| Wrong PEC | ACK | none | 0x20 |
| Illegal value (e.g. OPERATION 0x81) | ACK | none | 0x40 |
| Write blocked by WRITE_PROTECT | ACK | none | 0x40 |
| Repeated START after data bytes | ACK, read data 0xFF | write discarded | none |
| Read with no command | ACK, data 0xFF | none | none |
| SCL held low past the timeout | target releases SDA, goes idle | pending write discarded | 0x02 |
| Glitch shorter than the filter on SCL or SDA | ignored | none | none |
| Host NACKs a read early | target stops sending | none | none |
| Extra read bytes past the PEC | 0xFF | none | none |
| Bad PEC on a command that is also invalid | | none | 0x80 (invalid command wins) |

Two consequences worth knowing:

* An error never partly writes a register. All checks happen at STOP.
* Under any non-zero WRITE_PROTECT, CLEAR_FAULTS and writes to STATUS_VOUT /
  STATUS_CML are also blocked. Set WRITE_PROTECT to 0x00 first, then clear.

---

## 10. Fault supervision: timelines and numbers

### Hardware build (24 MHz, 1 kHz samples)

| Event | Time |
|-------|------|
| Turn-on (OPERATION 0x80) to EN high | a few clocks |
| Plant ramp 0 V to 3.3 V | about 14 ms (0.25 V per 1 ms step) |
| UV blanking after EN | 32 ms |
| Fault onset to shutdown | about 2 to 3 ms (3 consecutive samples, the first up to 1 ms away) plus 4 clocks of pipeline |
| Hiccup period | about 135 ms: 100 ms off, then 32 ms blanking + 3 ms debounce on |
| Hiccup restarts per second | about 7 |
| SMBus timeout | 25 ms |
| SMBALERT# after an error | 1 to 2 clocks after the status bit sets |

### Testbench (50 MHz, 50 us samples)

| Event | Time |
|-------|------|
| Debounce | 3 samples = 150 us |
| UV blanking | 16 samples = 800 us |
| Hiccup off | 8 samples = 400 us |
| Timeout | 5,000 clocks = 100 us |

### Latch-off sequence (what the host should do)

1. Fault happens. EN drops, STATUS_VOUT shows the fault, SMBALERT# goes low.
2. Host reads STATUS_WORD, then STATUS_VOUT to see what happened.
3. Host fixes the cause.
4. Host sends CLEAR_FAULTS. Status clears, SMBALERT# releases. The output is
   still off on purpose.
5. Host writes OPERATION 0x00, then 0x80. The output turns on again with
   fresh blanking.

If step 4 happens while the fault is still present, the bits come right back.

---

## 11. Write protect

| WRITE_PROTECT | Writable commands |
|---------------|-------------------|
| 0x00 | all writable commands |
| 0x20 | WRITE_PROTECT, OPERATION, VOUT_COMMAND |
| 0x40 | WRITE_PROTECT, OPERATION |
| 0x80 | WRITE_PROTECT only |
| anything else | rejected as an illegal value |

Reads are never blocked. A blocked write sets INVALID_DATA. The per-command
rule comes from the `wp_allow` list in the YAML, so changing the policy is a
YAML edit.

---

## 12. The code generator

### Why

The same facts about each register (code, size, access, reset, legal values)
are needed in four places: RTL, testbench, firmware and documentation. Copying
them by hand guarantees they drift apart. With one YAML file and a generator,
they cannot.

### YAML schema (`gen/regmap.yaml`)

Top level:

```yaml
ip:
  name: pmbus_power_manager
  default_address: 0x40
  vout_exponent: -9
registers:
  - ...
```

Per register:

| Key | Required | Meaning |
|-----|----------|---------|
| `name` | yes | UPPER_SNAKE_CASE, unique |
| `code` | yes | 0x00 to 0xFF, unique |
| `access` | yes | `rw`, `ro_const`, `ro_hw`, `w1c_hw`, `send` |
| `size` | yes | 0, 1 or 2 data bytes. 0 only for `send` |
| `reset` | rw and ro_const | reset or constant value; must fit in `size` bytes |
| `wp_allow` | no (rw only) | list of WRITE_PROTECT levels (0x20, 0x40, 0x80) where writes still work |
| `allowed` | no | list of legal write values; reset must be in it |
| `test_values` | no | values the testbench writes; must be in `allowed` if both exist. Default: `allowed`, else 0x55/0xAA or 0x5555/0xAAAA |
| `desc` | no | text for the docs |
| `fields` | no | list of `{bits, name, desc}` for the docs |

### Validation

The generator stops with a clear message if any of these is wrong: missing
keys, bad names, duplicate names or codes, code out of range, unknown access
type, size not 0/1/2, size 0 on a non-send command, reset missing or too big,
`wp_allow` on a non-rw command or with a bad level, `allowed` or `test_values`
that do not fit, reset not in `allowed`, test value not in `allowed`,
WRITE_PROTECT or STATUS_CML missing (the RTL needs both). Examples:

```
regmap error: register VOUT_UV_FAULT_RESPONSE: code 0x44 already used by VOUT_UV_FAULT_LIMIT
regmap error: register VOUT_OV_FAULT_LIMIT: reset value does not fit in 2 byte(s)
```

### Outputs

| Template | Output | Used by |
|----------|--------|---------|
| `pmbus_regmap_pkg.sv.j2` | `rtl/generated/pmbus_regmap_pkg.sv` | testbench (`CMD_*`, `RST_*` constants) |
| `pmbus_regfile.sv.j2` | `rtl/generated/pmbus_regfile.sv` | the IP |
| `regmap_tb.svh.j2` | `tb/generated/regmap_tb.svh` | testbench: `reg_code_at`, `reg_known`, `reg_name`, `reg_access`, `reg_size`, `reg_reset`, `reg_test_value`, `cov_applicable` |
| `pmbus_regmap.h.j2` | `fw/generated/pmbus_regmap.h` | STM32 firmware: `PMBUS_*` codes, `PMBUS_RST_*`, `pmbus_regs[]` table, LINEAR16 helpers |
| `register_map.md.j2` | `docs/register_map.md` | people |

### Usage

```
python3 gen/gen_regmap.py                 # write everything
python3 gen/gen_regmap.py --check         # exit 1 if any file on disk is stale
python3 gen/gen_regmap.py --yaml other.yaml --out /some/dir
```

### Worked example: adding a register

Say you want VOUT_MAX (0x24), a word that stores the highest allowed setpoint.

1. Add to `gen/regmap.yaml`:
   ```yaml
   - name: VOUT_MAX
     code: 0x24
     access: rw
     size: 2
     reset: 0x0800
     desc: "Highest VOUT_COMMAND the host may set."
   ```
2. `make gen`. The register file gets a `vout_max_q` port, decode entry, and
   storage. The testbench data, C header and docs update.
3. Connect `.vout_max_q()` in `pmbus_power_manager.sv` (and use it, for
   example to clamp `vout_command_o`).
4. `make sim`. The generic loop already tests VOUT_MAX for reset value, reads,
   writes, PEC, bad PEC and bad length. The coverage table grows by 6 bins and
   must still reach 100%.

The only hand edit is step 3, wiring the new value to logic that uses it.

---

## 13. Verification

### Testbench structure

```
tb_pmbus
├── clock (50 MHz), reset
├── bus: tri1 scl, sda (pull-ups), host drivers, glitch injectors, DUT open-drain driver
├── VOUT "ADC": a vout variable and a sample strobe every 2,500 clocks
├── DUT: pmbus_power_manager with scaled parameters
├── i2c_master_bfm.svh: bit tasks, byte tasks, pm_write, pm_read
├── generated/regmap_tb.svh: register data
├── checks, coverage arrays, scenario list
└── test sequence + coverage report
```

### The host model (BFM)

* Bit timing for 400 kHz: half period 1,250 ns. SDA changes 625 ns after SCL
  falls, read bits are sampled in the middle of SCL high.
* `i2c_start` does a plain START or a repeated START depending on bus state.
* `pm_write(cmd, data, nbytes, pec_mode, acked)`: `pec_mode` is none, good, or
  bad (good PEC XOR 0x5A). Bytes past the first two are filler (0xA5 ^ index)
  so wrong-length writes are easy.
* `pm_read(cmd, nbytes, use_pec, data, pec_ok, acked)`: does the Sr read, ACKs
  every byte but the last, optionally reads and checks the PEC.
* The host computes PEC with its own `tb_crc8`, written separately from the
  RTL CRC, and the testbench checks it against the standard value 0xF4 for
  "123456789" first. So a CRC bug in the RTL cannot hide behind the same bug in
  the testbench.

### Test sequence

1. **CRC check value** of the testbench CRC.
2. **Reset state**: EN and PG low, SMBALERT# high, STATUS_BYTE 0x40,
   STATUS_WORD 0x0840, STATUS_VOUT and STATUS_CML 0, READ_VOUT = nominal.
3. **Generated per-command tests**, one loop over `NUM_REGS` (table below).
4. **All 237 unsupported codes**: write and read each; both must be ACKed,
   the read must be 0xFF, STATUS_CML must be exactly 0x80.
5. **Bus error injection** (directed).
6. **Write protect** (directed).
7. **Output faults** (directed).
8. **Coverage report**; any hole is an error.

Generic tests by access type:

| Access | Steps |
|--------|-------|
| rw | read = reset; read + PEC = reset and PEC ok; write and read back every test value; write + PEC then read + PEC; restore reset; bad-PEC write must not change it and must set 0x20; size + 2 bytes must not change it and must set 0x40; for words, a 1-byte write must not change it and must set 0x40 |
| ro_const | read = constant; read + PEC; write rejected with 0x80 and value unchanged |
| ro_hw | read; read + PEC ok; write rejected with 0x80 |
| w1c_hw | read; read + PEC; write 0 (no error); write 0 + PEC; bad PEC (0x20); bad length (0x40) |
| send | send; send + PEC; bad PEC (0x20); send with 2 data bytes (0x40); read returns 0xFF and sets 0x80 |

After every step that could set an error, `expect_cml` reads STATUS_CML,
compares the exact value, checks SMBALERT# is low if an error was expected,
then clears it.

Directed scenarios (24, each a coverage bin):

| # | Scenario | Pass condition |
|---|----------|----------------|
| 0 | wrong address | NACK, no CML |
| 1 | STOP mid byte | no commit, 0x40 |
| 2 | repeated START after data | 0xFF read, no commit, no CML |
| 3 | read with no command | 0xFF, no CML |
| 4 | SCL glitch (20 ns, mid high) | write + PEC and read back still correct |
| 5 | SDA glitch (20 ns, mid high) | same |
| 6 | SCL held low past timeout | SDA released, no commit, 0x02 |
| 7 | host NACKs word read early | right low byte, next read fine |
| 8 | OV warning | EN stays on, SMBALERT# low, STATUS_VOUT 0x40, STATUS_BYTE 0x01 |
| 9 | OV fault latch | EN off, STATUS_VOUT 0xC0, STATUS_WORD 0x8861, stays off after CLEAR_FAULTS |
| 10 | UV warning | on, not power good, STATUS_VOUT 0x20 |
| 11 | UV fault latch | off, STATUS_VOUT 0x30, STATUS_BYTE 0x41 |
| 12 | UV blanking | no fault before blanking ends, fault after |
| 13 | debounce | a 2-sample spike above OV fault does nothing |
| 14 | response ignore | OV fault reported, EN stays on |
| 15 | response hiccup | at least 2 restarts, every off period at least `HICCUP_OFF - 1` samples, recovers when the fault goes away |
| 16 | STATUS_VOUT write-1-to-clear | wrong bit has no effect, right bit clears |
| 17 | CLEAR_FAULTS with fault still present | bit returns |
| 18-20 | WP 0x80 / 0x40 / 0x20 | exactly the right writes blocked |
| 21 | illegal values | OPERATION 0x81, WRITE_PROTECT 0x11 rejected |
| 22 | SMBALERT# cycle | asserts on warning, releases after clear |
| 23 | latch recovery | OPERATION off/on brings EN and PG back |

Some checks look inside the DUT (`dut.status_vout`) where timing matters more
than a bus read can show, for example "nothing happened during blanking".

### Coverage model

* 10 kinds of bins per command: RD, RD+PEC, WR, WR+PEC, BADPEC, BADLEN,
  WR_REJECT, RD_REJECT, UNSUP_RD, UNSUP_WR.
* Which kinds apply to which command comes from the generated
  `cov_applicable` function, so coverage grows on its own when the YAML grows.
* 19 supported commands give 95 bins, 237 unsupported codes x 2 give 474 bins,
  plus 24 scenario bins: 593 total.
* Icarus Verilog has no covergroups, so coverage is counted in plain arrays
  (`int cov[0:255][0:9]`, `int scen[0:23]`). Any zero in an applicable bin is
  printed as `HOLE` and fails the run.

### Mutation testing (`tb/mutate.py`)

Coverage says what the tests exercised. Mutation testing says whether the
checks would notice a bug. The script copies the sources to a temp folder,
replaces one exact line with a broken version, runs the full testbench with
`+stop_on_error`, and expects `TEST FAILED`. It refuses to run a mutant whose
pattern is not found exactly once.

| Mutant | First check that caught it |
|--------|----------------------------|
| PEC never checked on writes | bad PEC must not write: OPERATION changed |
| wrong PEC sent on reads | OPERATION read + PEC: pec_ok = 0 |
| byte count not checked | bad length must not write |
| reads evaluated as writes | reset STATUS_WORD = 0x0842 (spurious CML) |
| read allowed after data bytes | read after aborted write returned data |
| hiccup has no off time | hiccup off time 0 samples |
| write protect ignored | WP 0x80 did not flag CLEAR_FAULTS |
| no glitch filter | write + PEC not ACKed under SCL glitches |
| no SMBus timeout | timed-out write committed |
| no soft-start blanking | UV checked during blanking |
| no debounce | short OV spike shut the output down |
| latch never clears | no recovery after OPERATION off/on |
| status not sticky | warning bit gone after the condition cleared |
| SMBALERT# ignores CML | SMBALERT# not asserted after a bad PEC |

Result: 14 of 14 killed. One early mutant (dropping `in_txn` from the STOP
check) survived; analysis showed other state already guarantees the same thing,
so it was an equivalent mutant, not a test gap. It was replaced with ones that
change behavior.

### Bus checker on simulation (`make bus-check`)

The testbench can dump just the five pins (`+vcd_bus`). The same checker used
on logic analyzer captures then decodes all 1,364 bus transactions (including
raw ones the high-level count leaves out), checks every PEC, measures hold
time and lists EN/PG/SMBALERT# edges. Its first run found that the testbench's
DUT setting of 8 hold cycles gave only 285 ns; it was raised to 12 (365 ns).

Sample output:

```
transactions        1364
address NACKs       1
PEC frames ok       41
PEC bad (host, injected)  13
PEC bad (target)    0
SCL frequency       400.0 kHz (median)
target SDA hold     min 365 ns over 11786 edges (ok, spec >= 300 ns)
EN     edges         23
PG     edges         15
ALERT  edges         580
RESULT: PASS
```

### Lint

`verilator --lint-only -Wall`, clean. The only waiver is for bits 5:0 of the
fault response inputs, which are intentionally unused.

---

## 14. FPGA build

### Board top (`fpga/upduino_top.sv`)

* **Clock**: internal `SB_HFOSC` 48 MHz divided by 2 = 24 MHz. No external
  crystal or jumper needed.
* **Reset**: an 8-bit power-on counter; reset releases after 128 clocks.
* **Pads**: `SB_IO` cells in tri-state mode for SCL (input only), SDA and
  SMBALERT# (open drain: output data 0, output enable = pull low). Weak
  internal pull-ups are on, but external 4.7 k pull-ups are still required.
* **Plant model** (stands in for a real regulator):
  * a 1 kHz tick is the ADC sample strobe
  * target voltage = VOUT_COMMAND when EN is high, 0 when low
  * VOUT moves toward the target by 0.25 V (128 LSB) per tick, so turn-on and
    turn-off are visible ramps
  * if MFR_SIM_VOUT is non-zero, VOUT is forced to that value right away; this
    is how the STM32 injects OV and UV faults
  * the plant math is pipelined (registered sums and compares) so it stays off
    the critical path; VOUT only changes on the tick, so the delay is invisible
* **RGB LED** via `SB_RGBA_DRV`: green = PG, blue = EN, red = SMBALERT#.

### Pins (`fpga/upduino.pcf`)

| Signal | Pin |
|--------|-----|
| scl | 2 |
| sda | 3 |
| smbalert_n | 4 |
| en_out | 6 |
| pg_out | 9 |
| led_g / led_b / led_r | 39 / 40 / 41 |

Check these against your board revision before wiring.

### Build flow

```
yosys   read_verilog -sv ...; synth_ice40 -top upduino_top -json upduino.json
nextpnr-ice40 --up5k --package sg48 --pcf upduino.pcf --freq 24 --asc upduino.asc
icepack upduino.asc upduino.bin
iceprog upduino.bin
```

### Timing closure history

The first place and route at 48 MHz reached only about 28 MHz. Fixes, in order:

1. Pipelined the plant model (was the worst path). Reached about 34 MHz.
2. Registered the register file lookup inside the core and registered PG.
   Reached about 40 MHz.
3. Captured VOUT and registered the limit compares in the monitor.
   Reached about 48.4 MHz: a pass at 48 MHz, but with almost no margin.
4. Moved the board clock to 24 MHz. Max is now about 47 MHz, about 2x margin.

The remaining critical path is a 16-bit compare inside the monitor. Splitting it
into two 8-bit stages would be the next step if 48 MHz were needed.

### Resources

Full design: 1,025 / 5,280 logic cells (19%), 0 block RAMs, 5 SB_IO. The IP on
its own: about 618 LUT4, 358 flip-flops, 98 carry cells (yosys numbers before
packing).

---

## 15. STM32 firmware

### Driver (`fw/stm32/pmbus_host.c/.h`)

```c
typedef struct {
    I2C_HandleTypeDef *hi2c;
    uint8_t  addr7;        /* 7-bit address */
    bool     use_pec;      /* add / check PEC on every transaction */
    uint32_t timeout_ms;
} pmbus_dev_t;

pmbus_status_t pmbus_send_byte (pmbus_dev_t *d, uint8_t cmd);
pmbus_status_t pmbus_write_byte(pmbus_dev_t *d, uint8_t cmd, uint8_t v);
pmbus_status_t pmbus_write_word(pmbus_dev_t *d, uint8_t cmd, uint16_t v);
pmbus_status_t pmbus_read_byte (pmbus_dev_t *d, uint8_t cmd, uint8_t *v);
pmbus_status_t pmbus_read_word (pmbus_dev_t *d, uint8_t cmd, uint16_t *v);
pmbus_status_t pmbus_write_raw (pmbus_dev_t *d, uint8_t cmd, const uint8_t *data, size_t len);
pmbus_status_t pmbus_write_word_bad_pec(pmbus_dev_t *d, uint8_t cmd, uint16_t v);
```

* Writes use `HAL_I2C_Master_Transmit` with the command, data and PEC in one
  buffer. PEC is computed over the address byte, command and data.
* Reads use `HAL_I2C_Mem_Read` with an 8-bit "memory address" equal to the
  command. That HAL call produces exactly `S Addr+W Cmd Sr Addr+R data... P`,
  which is the PMBus read format. PEC is checked over Addr+W, Cmd, Addr+R and
  the data.
* Return codes: `PMBUS_OK`, `PMBUS_NACK` (HAL acknowledge failure),
  `PMBUS_PEC_MISMATCH`, `PMBUS_BUS_ERROR`.
* `pmbus_write_raw` and `pmbus_write_word_bad_pec` exist only for fault
  injection.
* Only HAL I2C calls are used, so the driver works on any STM32 family.

### Generated header (`fw/generated/pmbus_regmap.h`)

`PMBUS_<NAME>` codes, `PMBUS_RST_<NAME>` values, `PMBUS_DEFAULT_ADDR`,
`pmbus_regs[]` (name, code, size, access, reset), and:

```c
uint16_t pmbus_mv_to_linear16(uint32_t mv);   /* 3300 -> 1690 */
uint32_t pmbus_linear16_to_mv(uint16_t v);    /* 1689 -> 3299 */
```

### Hardware test sequence (`fw/stm32/pmbus_demo.c`)

Everything uses PEC unless the step is testing PEC. Each step prints
`[PASS]` or `[FAIL]`.

| Step | Action | Expected |
|------|--------|----------|
| Identity | read PMBUS_REVISION, CAPABILITY, VOUT_MODE | 0x33, 0xB0, 0x17 |
| Dump | read every readable register | printed |
| Write | VOUT_COMMAND = 3300 mV with PEC | reads back 0x069A |
| Bad PEC | write 5000 mV with a corrupted PEC | value unchanged, STATUS_CML 0x20 |
| Bad length | VOUT_COMMAND with 4 data bytes | unchanged, 0x40 |
| Unsupported | write 0xE5 | 0x80 |
| Read-only | write READ_VOUT | 0x80 |
| Illegal value | OPERATION 0x81 | 0x40 |
| Wrong address | read at 0x41 | NACK |
| Stress | 1,000 back-to-back PEC reads | 0 errors |
| Power up | OPERATION off, CLEAR_FAULTS, on, wait 100 ms | STATUS_WORD 0x0000, READ_VOUT 3.25 to 3.35 V, pins EN=1 PG=1 ALERT#=1 |
| OV fault | MFR_SIM_VOUT = 4.0 V, wait 20 ms | STATUS_VOUT 0xC0, STATUS_BYTE 0x61, pins EN=0 PG=0 ALERT#=0 |
| Latch | MFR_SIM_VOUT = 0, wait 50 ms, CLEAR_FAULTS | STATUS_BYTE 0x40, still off, ALERT# released |
| Recover | power cycle | STATUS_WORD 0x0000, pins back on |
| UV fault | MFR_SIM_VOUT = 2.5 V, wait 20 ms | STATUS_VOUT 0x30, pins EN=0 PG=0 ALERT#=0 |
| Hiccup | UV response 0xC0, MFR_SIM_VOUT = 2.5 V, count EN rises for 1 s | 5 to 9 (about 7) |
| Hiccup recover | MFR_SIM_VOUT = 0, wait 200 ms, CLEAR_FAULTS | STATUS_WORD 0x0000 |
| Write protect | WP 0x80, write VOUT_COMMAND | unchanged; after WP 0x00, STATUS_CML 0x40 |

Why the 50 ms wait in the latch step: when MFR_SIM_VOUT goes back to 0 the
plant ramps down from 4.0 V at 0.25 V/ms. Sending CLEAR_FAULTS while it is
still above the OV limits would just set the bits again.

GPIO pin checks use PA0 (EN), PA1 (PG), PA4 (SMBALERT#). Define
`PMBUS_DEMO_NO_GPIO` to skip them if those wires are not connected.

### PC-side checks (`make fw-test`)

`fw/test_host.c` checks: CRC-8 check value 0xF4, 3300 mV -> 1690,
0x0699 -> 3299 mV, 4000 mV -> 0x0800, and that a message plus its PEC has a
CRC of 0. Then the driver and demo are compiled against `fw/stubs/main.h`
(a minimal HAL stand-in) with `-Wall -Wextra`.

---

## 16. Hardware test procedure

Full guide: [docs/hardware_test.md](docs/hardware_test.md). Summary:

### Parts

UPduino v3.x, STM32 Nucleo-64 (F401RE assumed), logic analyzer (8+ channels,
24 MS/s or faster), two 4.7 k resistors, one 10 k resistor, jumper wires.

### Wiring

| Signal | UPduino | Nucleo | Analyzer |
|--------|---------|--------|----------|
| SCL | 2 | PB8 (D15) | CH0 |
| SDA | 3 | PB9 (D14) | CH1 |
| SMBALERT# | 4 | PA4 (A2) | CH2 |
| EN | 6 | PA0 (A0) | CH3 |
| PG | 9 | PA1 (A1) | CH4 |
| GND | GND | GND | GND |

Pull-ups to the Nucleo 3V3: 4.7 k on SCL and SDA, 10 k on SMBALERT#. Both
boards are 3.3 V. Grounds must be tied.

### Steps

1. `make -C fpga prog`
2. CubeMX project: I2C1 on PB8/PB9 at 100 or 400 kHz, USART2 115200,
   PA0/PA1/PA4 inputs. Add `fw/stm32/*.c`, add `fw/stm32` and `fw/generated`
   to includes, paste `main_snippet.c` into `main.c`.
3. Start the analyzer (CH0-CH4, about 6 s, trigger on CH0 falling).
4. Open the ST-LINK COM port at 115200, press reset.
5. Export the capture as CSV and run `la_check.py` (next section).

### What success looks like on the analyzer

* PEC bad (target): 0
* PEC bad (host, injected): 1 (the deliberate bad-PEC write)
* address NACKs: 1 (the wrong-address test)
* target SDA hold: roughly 580 ns, must be at least 300 ns
* EN falls about 2 to 3 ms after the MFR_SIM_VOUT = 4.0 V write
* During the hiccup test, EN is off about 100 ms and on about 35 ms, repeating

---

## 17. The bus checker (`la_check.py`)

### Inputs

* **VCD** (file ends in `.vcd`): default signal names `scl`, `sda`, `en`,
  `pg`, `alert_n`. Values `x` and `z` count as high (pulled up).
* **CSV**: a header row, optional `;` comment lines (sigrok). Uses the first
  column whose name contains "time" as seconds. If there is no time column,
  pass `--samplerate`. Only rows where something changed are kept.

### Options

| Option | Meaning |
|--------|---------|
| `--scl`, `--sda` | column / signal names (CSV defaults `SCL`, `SDA`) |
| `--en`, `--pg`, `--alert` | optional pin columns |
| `--samplerate` | Hz, for CSVs without a time column |
| `--regmap` | YAML for command names and sizes (default `gen/regmap.yaml`) |
| `--min-hold-ns` | hold time limit (default 300) |
| `-v` | print every decoded transaction |

### How it decodes

* START / STOP: SDA edge while SCL is high on both samples.
* Bit: SDA value at each SCL rising edge. 9 bits make a byte plus ACK.
* A transaction runs from START to STOP and is split into segments at every
  repeated START. Each segment has an address byte and data bytes.
* Which side drives each bit: data bits of read bytes and ACK bits of write
  bytes come from the target. Hold time is measured for SDA changes next to
  target-driven bits: time from the last SCL fall to the SDA change.

### How it judges PEC

It looks up the command size in the YAML. A write with size + 1 data bytes
carries a PEC; a read of size + 1 bytes of a command with size > 0 carries a
PEC. A wrong PEC from the host is counted as "injected" (tests do this on
purpose). A wrong PEC from the target is an error.

### Output pin edges

Every EN, PG and ALERT edge is printed with its time and the last completed
transaction before it, and how long after it. This is how fault-to-shutdown
latency is measured on real hardware.

### Exit code

1 if the target sent a bad PEC or the minimum hold time is under the limit,
otherwise 0.

---

## 18. Continuous integration

`.github/workflows/ci.yml` on every push and pull request, Ubuntu 24.04:

1. install tools and Python packages
2. `make gen-check` (generated files committed and current)
3. `make lint`
4. `make sim`
5. `make bus-check`
6. `make fw-test`
7. `make synth`
8. `make mutate`
9. upload `build/sim.log`, `build/mutate.log`, `fpga/upduino.bin`, `fpga/nextpnr.log`

Any failing step fails the build. `make sim` fails unless the log contains
`TEST PASSED`.

---

## 19. Design decisions and trade-offs

**Commit on STOP, not byte by byte.** The core buffers the data and writes the
register only after the whole transaction passes every check. Cost: 2 bytes of
buffer and one more clock. Benefit: a cut-off, wrong-length or bad-PEC
transaction can never leave a half-written word or a value that was never
checked. For a power supply, writing a wrong limit is worse than writing
nothing.

**ACK everything, report through STATUS_CML.** The target never NACKs a data
byte. PMBus lets devices either NACK or flag errors in STATUS_CML; flagging
gives the host a specific reason (bad PEC vs bad command vs bad data) and keeps
the bus state machine simple. The address is the only thing NACKed.

**PEC is optional per transaction.** The length rule tells the two apart: if
there is one byte more than the command needs, the last byte is PEC. This lets
hosts with and without PEC talk to the same device.

**CRC check by zero remainder.** Running the CRC over the message and its PEC
gives 0. So the core does not need to know which byte was the PEC until STOP;
it just tests `crc == 0`.

**Read snapshot.** Prevents torn words when the hardware value changes between
the two bytes of a read.

**No clock stretching.** The core always has a byte ready in one clock, so
stretching would add complexity for nothing, and some hosts handle stretching
badly.

**Separate glitch filter and hold delay.** The filter protects the target
from noise; the hold delay protects the host from the target. Both are
parameters because they depend on the clock.

**Fixed LINEAR16 exponent.** One exponent (-9) for every voltage keeps the
compares as plain unsigned compares. 1.95 mV resolution and 128 V range is
plenty for a 3.3 V rail.

**Debounce and blanking in samples, not clocks.** Fault timing scales with the
ADC rate, which is what actually matters for a power rail. The same RTL works
with a fast or slow ADC.

**OV checked even when off, UV only when on and after blanking.** An off rail
being low is normal. An off rail being high is a real problem worth reporting.

**Hiccup has an off timer.** Without it, the output would try to restart
right after shutting off, which in a real short circuit means repeated
high-current starts. The mutation test proves the testbench checks this.

**Strict write protect.** CLEAR_FAULTS and status clears are blocked under
any write protect level because the spec says "all writes except...". Many
real parts relax this. Relaxing it here needs a small generator change: today
`wp_allow` is only accepted on `rw` commands, so the validator and the
regfile template would need to allow it on `send` and `w1c_hw` too.

**24 MHz on the board.** Running at 48 MHz closes timing with almost no
margin. 24 MHz is still 60 clocks per SCL period at 400 kHz, and gives about
2x margin.

**Generated, not hand-written, register file.** It is the part that changes
most when a design evolves, and the part most likely to drift from the docs
and firmware.

**Plain arrays instead of covergroups.** Icarus Verilog is free and fast but
has no covergroups. Counting in arrays works on any simulator and makes the
report easy to read.

---

## 20. Where this differs from the PMBus spec

This is a teaching and portfolio implementation of a subset. Known differences:

* Only the commands in section 8 exist. No block reads/writes, no Group
  Command, no Alert Response Address (ARA), no QUERY, no COEFFICIENTS.
* Fault response bits 5:0 (retry count and delay time) are ignored. 01 and 10
  both mean latch off.
* OPERATION 0x40 (soft off) behaves like immediate off. Margin bits are not
  supported.
* No ON_OFF_CONFIG or CONTROL pin; OPERATION alone turns the output on.
* VOUT_COMMAND is stored and exported but not clamped by a VOUT_MAX.
* STATUS_BYTE bits for IOUT, VIN and TEMP are always 0.
* CLEAR_FAULTS and status clears are blocked under write protect (strict
  reading).
* Write to a read-only command is reported as INVALID_CMD; wrong length,
  illegal value and write-protected writes as INVALID_DATA.
* SMBALERT# is a level that follows the status bits; there is no ARA handshake
  to release it.
* PEC is accepted but not required. There is no "PEC required" mode.

---

## 21. Limitations and future work

* Real ADC input instead of the plant model (for example an SPI ADC feeding
  `vout_i` and `vout_sample_i`).
* IOUT and temperature telemetry with their own limits and STATUS registers.
* Block read for MFR_ID / MFR_MODEL strings.
* Alert Response Address support.
* Fault retry counts and delays from bits 5:0.
* A PEC-required mode bit.
* Split the 16-bit monitor compares to close timing at 48 MHz.
* Formal properties (for example "no write without STOP", "EN never high while
  latched") with SymbiYosys.
* A UVM version of the testbench for commercial simulators.
* Proven runs on real hardware with the capture committed to the repo.

---

## 22. Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `TEST FAILED` after editing the YAML | generated files stale, or new register not wired | `make gen`, wire the new port in `pmbus_power_manager.sv` |
| `make gen-check` fails in CI | generated files not committed | run `make gen` and commit |
| Coverage `HOLE` for a new register | access type bins not exercised | check the generic loop handles that access type |
| `sorry: constant selects in always_* processes` from iverilog | harmless Icarus message | ignored by the Makefile |
| Every transfer NACKs on hardware | no pull-ups, grounds not tied, SCL/SDA swapped, FPGA not programmed | check wiring, reflash |
| HAL stuck BUSY | bus held low | power-cycle; the 25 ms timeout should also free it |
| PEC mismatch on hardware reads | slow edges from weak pull-ups | 2.2 k pull-ups or 100 kHz |
| Hold time below 300 ns in the checker | `SDA_HOLD_CYCLES` too small for the clock | raise it |
| Hiccup count wrong in the demo | response not 0xC0, or MFR_SIM_VOUT not set | check the register writes |
| Timing fails after changes | new long combinational path | read `fpga/nextpnr.log` "Critical path", add a register stage |
| Mutant reports "BAD MUTANT" | the RTL line it patches changed | update the pattern in `tb/mutate.py` |

---

## 23. FAQ

**What does this project actually do, in one sentence?**
It is a chip block that lets a host computer read and control a power rail over
a two-wire bus, and shuts the rail off safely if the voltage goes out of range.

**Why PMBus?**
It is the standard way servers, telecom gear and many embedded boards talk to
power supplies and voltage regulators. It combines serial interface design,
safety logic and status reporting in one block.

**What is the IP vs. the demo?**
The IP is everything in `rtl/`. The FPGA top, plant model, LED and pins in
`fpga/` are only there to run it on a board without real power hardware.

**How do you know the testbench is good and not just passing?**
Three ways. Coverage proves every command and scenario was exercised. Mutation
testing proves the checks catch 14 realistic bugs. The PEC math is checked
against the standard CRC-8 check value with a separate implementation.

**What is the hardest bug you hit?**
Two good ones. (1) The first read byte request and the address-hit event came
out of the I2C target in the same clock, and the core only handled one,
so read data was never loaded. Fixed by requesting the first byte one clock
later. (2) The bus checker, run on the simulation, found the hold time was
285 ns, below the SMBus 300 ns minimum, because the filter and synchronizer
delay was not counted. Fixed by raising the hold cycles.

**What was the testbench race in the debounce test?**
The test changed VOUT right when the sample strobe went high, but the DUT
reads the strobe on the next clock edge, so it saw one extra high sample and
tripped. Waiting two clocks after the strobe before changing VOUT fixed it.
The design was right; the test was off by one sample.

**How does the IP know whether the last byte is a PEC?**
From the command size in the register file. size + 1 bytes means the last is
PEC. Exactly size bytes means no PEC. Anything else is a length error.

**Why is the PEC check "crc == 0"?**
A property of this CRC: CRC(message followed by CRC(message)) = 0. So the core
runs one CRC over everything it receives and checks for zero at STOP.

**What happens if the host sends a STOP halfway through a word write?**
Nothing is written. The core only commits at STOP after all checks pass, and a
partial word fails the length check, setting INVALID_DATA.

**What happens if the bus gets stuck?**
If SCL stays low for 25 ms, the target releases SDA, goes idle, drops the
pending write, and sets STATUS_CML bit 1.

**How fast does it shut down on an over-voltage?**
On the board: about 2 to 3 ms, set by 3 consecutive samples at 1 kHz. With a
faster ADC it is faster; the RTL adds only 4 clocks.

**Why does the output not come back after CLEAR_FAULTS?**
That is the latch-off behavior. CLEAR_FAULTS clears the record of the fault,
not the shutdown. You must turn OPERATION off and on to restart on purpose.

**How do I make it restart by itself?**
Set the response register to 0xC0 (hiccup). It will retry every
`HICCUP_OFF` samples while the fault lasts and stay on once it is gone.

**How do I change the address?**
`addr_i` is a port. Tie it to a different constant in the top, or to pins.
The firmware uses `PMBUS_DEFAULT_ADDR` from the YAML (`default_address`).

**How do I add a command?**
Add it to `gen/regmap.yaml`, run `make gen`, wire the new port if it is `rw`
or hardware-owned, run `make sim`. See section 12.

**Can it run at 100 kHz?**
Yes. Nothing assumes 400 kHz. Slower is easier.

**Can it run at 1 MHz (Fast-mode Plus)?**
Probably at 48 MHz with smaller hold and filter settings, but it was not
tested, and CAPABILITY advertises 400 kHz.

**Why Icarus Verilog and not a commercial simulator?**
Free, scriptable, runs in CI. The testbench uses only SystemVerilog features
Icarus supports, so it would also run on commercial tools.

**What does `MFR_SIM_VOUT` do in a real chip?**
Nothing; it is a manufacturer-specific command used only by the FPGA demo to
inject faults. In a real product you would remove it from the YAML.

**How much FPGA does it use?**
The IP is about 618 LUT4 and 358 flip-flops. The whole board design is 19% of
an iCE40UP5K.

**Why is the board clock 24 MHz instead of 48?**
48 MHz only closed with about 0.4 MHz of margin. 24 MHz gives about 2x margin
and is still plenty for a 400 kHz bus.

**What is the critical path?**
A 16-bit unsigned compare between the captured VOUT and a limit register in
the monitor.

**Does the firmware depend on a specific STM32?**
No. It only uses HAL I2C, GPIO and UART calls. Pins in the demo are for a
Nucleo-64 and are easy to change.

**Why read with `HAL_I2C_Mem_Read`?**
It produces exactly the PMBus read sequence (write command, repeated START,
read). Using Transmit then Receive would put a STOP in between, which the IP
treats as a separate transaction.

**What does la_check prove that the testbench does not?**
It checks the actual pins, so it covers the board, wiring, pull-ups and the
real host. And because it also runs on the simulation VCD, sim and hardware
are judged by the same rules.

**What would you do next?**
Real ADC input, IOUT and temperature telemetry, formal properties, and a
committed hardware capture.

---

## 24. Glossary

| Term | Meaning |
|------|---------|
| ACK / NACK | 9th bit of a byte: low = received, high = not received or stop sending |
| BFM | bus functional model: testbench code that drives a bus like a real device |
| Blanking | time after turn-on when UV is not checked, so a ramping rail does not trip |
| CML | communications, memory and logic: the PMBus status category for bus errors |
| Debounce | requiring a condition to last several samples before acting |
| EN | enable output to the power stage |
| Hiccup | shut down, wait, retry, repeat while the fault lasts |
| Latch-off | shut down and stay off until deliberately restarted |
| LINEAR16 | PMBus voltage format: 16-bit mantissa x 2^exponent |
| Mutation testing | adding bugs on purpose to check the tests catch them |
| Open drain | output that can only pull low; a resistor pulls high |
| OV / UV | over-voltage / under-voltage |
| PEC | packet error code: SMBus CRC-8 byte |
| PG | power good |
| Plant model | simple stand-in for the real power hardware |
| Sr | repeated START |
| SMBALERT# | open-drain line a device pulls low to request attention |
| Sticky bit | stays set until cleared, even after the cause is gone |
| W1C | write 1 to clear |
| WP | write protect |
