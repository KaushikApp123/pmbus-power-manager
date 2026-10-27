# Architecture

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

All logic runs on one clock. SCL and SDA are treated as asynchronous inputs.

## pmbus_i2c_target

* 2-flop synchronizer and a `FILTER_LEN` glitch filter on each line. A level
  change must hold for 3 clocks before it is seen (about 60 ns at 48 MHz,
  125 ns at 24 MHz), which covers the SMBus 50 ns spike rule.
* START and STOP are SDA edges while SCL is high. SCL rising samples a bit.
* ACKs its own address and every write byte. Never stretches the clock.
* Every change it makes on SDA waits `SDA_HOLD_CYCLES` after it sees SCL fall,
  so the SMBus 300 ns data hold time is met. `hw/la_check.py` measures this on
  both the simulation VCD and real captures.
* If SCL stays low for `TIMEOUT_CYCLES` (25 ms on hardware) it drops the
  transfer, releases SDA and pulses `timeout_o`.
* Read bytes are requested from the core one byte ahead, so the core has a whole
  SCL low period to answer.

## pmbus_core

Transaction formats:

```
Write:  S  Addr+W  Cmd  [D0 [D1]]  [PEC]  P
Read:   S  Addr+W  Cmd  Sr  Addr+R  D0 [D1]  [PEC]  P
```

* **Commit on STOP only.** Write bytes go into a small buffer. Nothing touches a
  register until STOP, and only if every check passes. A transfer that is cut
  off by a timeout, a repeated START or a bad PEC never changes state.
* **Length rule.** After the command, the byte count must be exactly the
  command size (no PEC) or size + 1 (last byte is PEC). The size comes from
  the generated register file.
* **PEC check** uses the CRC property `crc(message, pec) == 0`, so the core
  just runs the CRC over every byte, including the address bytes, and tests for
  zero at STOP. One CRC-8 block (`pmbus_crc8`) is shared by all byte events.
* **Reads** snapshot the register at the Addr+R phase, so the two bytes of a
  word always belong together. The byte after the data is the PEC. The host
  decides whether to clock it out.
* **Register lookup is pipelined** by one clock. The command byte always
  arrives at least a full SCL period before it is used, so this costs nothing
  and keeps the decode off the critical path.

STATUS_CML bits:

| Bit | Name | Set when |
|-----|------|----------|
| 7 | INVALID_CMD | unknown code, write to a read-only command, read of a send-byte command |
| 6 | INVALID_DATA | wrong byte count, value not in the allowed list, write blocked by WRITE_PROTECT |
| 5 | PEC_FAIL | PEC byte present and wrong |
| 1 | OTHER | SMBus timeout during a transaction |

Bits are sticky. CLEAR_FAULTS clears all of them; writing 1s to STATUS_CML
clears the matching bits.

## pmbus_regfile (generated)

Built from `gen/regmap.yaml` by `gen/gen_regmap.py`. It decodes the command
code into valid / readable / writable / size, holds the rw registers, muxes read
data, and checks the write against the WRITE_PROTECT level and the allowed
value list. Hardware-owned commands (status, CLEAR_FAULTS) come out as write
strobes. See [register_map.md](register_map.md).

## pmbus_vout_monitor

* VOUT is captured on the sample strobe, compared against the four limits one
  clock later, then debounced: a condition must hold for `DEBOUNCE`
  consecutive samples.
* UV is only checked while the output is on and after `BLANK_SAMPLES` of
  soft-start blanking, so turning on into a ramping rail does not trip it.
* Fault response bits 7:6:
  * `00` ignore, status only
  * `01` / `10` shut down and latch off. Only OPERATION off clears the latch.
    CLEAR_FAULTS clears the status but leaves the output off.
  * `11` hiccup: off for `HICCUP_OFF` samples, retry with blanking again,
    repeat while the fault persists
* STATUS_VOUT bits are sticky and set every sample the condition is present,
  so clearing a bit while the fault is still there has no lasting effect. That
  matches PMBus behaviour.
* Power good = on, blanking done, and VOUT between the UV warn and OV fault
  limits.

## Status summary and SMBALERT#

```
STATUS_BYTE = {BUSY=0, OFF=~EN, VOUT_OV_FAULT, 0, 0, 0, CML=|STATUS_CML, NONE_OF_THE_ABOVE=|STATUS_VOUT[6:4]}
STATUS_WORD = {VOUT=|STATUS_VOUT, 0, 0, 0, POWER_GOOD#=~PG, 0, 0, 0, STATUS_BYTE}
SMBALERT#   = low while any STATUS_VOUT or STATUS_CML bit is set
```

## Parameters

| Parameter | Default | Hardware build (24 MHz) | Testbench (50 MHz) |
|-----------|---------|-------------------------|--------------------|
| FILTER_LEN | 3 | 3 | 3 |
| SDA_HOLD_CYCLES | 16 | 8 (333 ns) | 12 |
| TIMEOUT_CYCLES | 1,200,000 | 600,000 (25 ms) | 5,000 (100 us) |
| DEBOUNCE | 3 | 3 (3 ms) | 3 |
| BLANK_SAMPLES | 32 | 32 (32 ms) | 16 |
| HICCUP_OFF | 32 | 100 (100 ms) | 8 |

## Not implemented

Block read/write, Group Command, Alert Response Address, clock stretching,
current/temperature telemetry, and the retry/delay bits (5:0) of the fault
response registers. Each would be a new entry in `regmap.yaml` plus logic in
the core or monitor.
