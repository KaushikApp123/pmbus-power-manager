<!-- AUTO-GENERATED from regmap.yaml by gen/gen_regmap.py. Do not edit. -->
# Register Map

Default 7-bit address: `0x40`.
Voltages use LINEAR16 with exponent -9 (1 LSB = 1.953 mV).
Words are sent low byte first. PEC (CRC-8, poly 0x07) is optional on every transaction.

## Summary

| Code | Name | Access | Bytes | Reset | WP allowed at |
|------|------|--------|-------|-------|---------------|
| `0x01` | [OPERATION](#operation) | rw | 1 | `0x00` | 0x00, 0x40, 0x20 |
| `0x03` | [CLEAR_FAULTS](#clear_faults) | send | 0 | - | - |
| `0x10` | [WRITE_PROTECT](#write_protect) | rw | 1 | `0x00` | 0x00, 0x80, 0x40, 0x20 |
| `0x19` | [CAPABILITY](#capability) | ro_const | 1 | `0xB0` | - |
| `0x20` | [VOUT_MODE](#vout_mode) | ro_const | 1 | `0x17` | - |
| `0x21` | [VOUT_COMMAND](#vout_command) | rw | 2 | `0x0699` | 0x00, 0x20 |
| `0x40` | [VOUT_OV_FAULT_LIMIT](#vout_ov_fault_limit) | rw | 2 | `0x0742` | 0x00 |
| `0x41` | [VOUT_OV_FAULT_RESPONSE](#vout_ov_fault_response) | rw | 1 | `0x80` | 0x00 |
| `0x42` | [VOUT_OV_WARN_LIMIT](#vout_ov_warn_limit) | rw | 2 | `0x06EE` | 0x00 |
| `0x43` | [VOUT_UV_WARN_LIMIT](#vout_uv_warn_limit) | rw | 2 | `0x0645` | 0x00 |
| `0x44` | [VOUT_UV_FAULT_LIMIT](#vout_uv_fault_limit) | rw | 2 | `0x05F0` | 0x00 |
| `0x45` | [VOUT_UV_FAULT_RESPONSE](#vout_uv_fault_response) | rw | 1 | `0x80` | 0x00 |
| `0x78` | [STATUS_BYTE](#status_byte) | ro_hw | 1 | - | - |
| `0x79` | [STATUS_WORD](#status_word) | ro_hw | 2 | - | - |
| `0x7A` | [STATUS_VOUT](#status_vout) | w1c_hw | 1 | - | - |
| `0x7E` | [STATUS_CML](#status_cml) | w1c_hw | 1 | - | - |
| `0x8B` | [READ_VOUT](#read_vout) | ro_hw | 2 | - | - |
| `0x98` | [PMBUS_REVISION](#pmbus_revision) | ro_const | 1 | `0x33` | - |
| `0xD0` | [MFR_SIM_VOUT](#mfr_sim_vout) | rw | 2 | `0x0000` | 0x00 |

Access types: `rw` stored, `ro_const` constant, `ro_hw` live hardware value,
`w1c_hw` hardware status (write 1 to clear), `send` send-byte command with no data.

## Details

### OPERATION

Code `0x01`, rw, 1 data byte.
Reset `0x00`.

Output on/off. 0x80 = on, 0x00 = immediate off, 0x40 = soft off (treated as off). Turning off clears a latched fault.

Legal values: `0x00`, `0x40`, `0x80`. Anything else sets STATUS_CML.INVALID_DATA.

| Bits | Field | Description |
|------|-------|-------------|
| 7 | True | 1 = output enabled |

### CLEAR_FAULTS

Code `0x03`, send, 0 data bytes.

Clears all STATUS bits and releases SMBALERT#. Bits set again if the fault is still present. Does not restart a latched-off output.

### WRITE_PROTECT

Code `0x10`, rw, 1 data byte.
Reset `0x00`.

0x80 = only WRITE_PROTECT writable. 0x40 = also OPERATION. 0x20 = also VOUT_COMMAND. 0x00 = all writable.

Legal values: `0x00`, `0x20`, `0x40`, `0x80`. Anything else sets STATUS_CML.INVALID_DATA.

### CAPABILITY

Code `0x19`, ro_const, 1 data byte.
Reset `0xB0`.

PEC supported, 400 kHz max bus speed, SMBALERT# supported.

| Bits | Field | Description |
|------|-------|-------------|
| 7 | PEC | 1 = PEC supported |
| 6:5 | SPEED | 01 = 400 kHz |
| 4 | ALERT | 1 = SMBALERT# supported |

### VOUT_MODE

Code `0x20`, ro_const, 1 data byte.
Reset `0x17`.

LINEAR16 mode, exponent -9.

### VOUT_COMMAND

Code `0x21`, rw, 2 data bytes.
Reset `0x0699` (3.299 V).

Output voltage setpoint (LINEAR16). Reset = 3.30 V. Exposed on vout_command_o for a regulator or DAC.

### VOUT_OV_FAULT_LIMIT

Code `0x40`, rw, 2 data bytes.
Reset `0x0742` (3.629 V).

Over-voltage fault threshold. Reset = 3.63 V (110%).

### VOUT_OV_FAULT_RESPONSE

Code `0x41`, rw, 1 data byte.
Reset `0x80`.

Bits 7:6: 00 = ignore, 01/10 = shut down and latch off, 11 = disable while fault is present (hiccup).

### VOUT_OV_WARN_LIMIT

Code `0x42`, rw, 2 data bytes.
Reset `0x06EE` (3.465 V).

Over-voltage warning threshold. Reset = 3.47 V (105%).

### VOUT_UV_WARN_LIMIT

Code `0x43`, rw, 2 data bytes.
Reset `0x0645` (3.135 V).

Under-voltage warning threshold. Reset = 3.13 V (95%).

### VOUT_UV_FAULT_LIMIT

Code `0x44`, rw, 2 data bytes.
Reset `0x05F0` (2.969 V).

Under-voltage fault threshold. Reset = 2.97 V (90%). Checked only while on and after soft-start blanking.

### VOUT_UV_FAULT_RESPONSE

Code `0x45`, rw, 1 data byte.
Reset `0x80`.

Same encoding as VOUT_OV_FAULT_RESPONSE.

### STATUS_BYTE

Code `0x78`, ro_hw, 1 data byte.

Summary status.

| Bits | Field | Description |
|------|-------|-------------|
| 6 | OFF | Output is off |
| 5 | VOUT_OV_FAULT | Over-voltage fault |
| 1 | CML | Communication fault, see STATUS_CML |
| 0 | NONE_OF_THE_ABOVE | Other VOUT warning or UV fault, see STATUS_VOUT |

### STATUS_WORD

Code `0x79`, ro_hw, 2 data bytes.

Low byte = STATUS_BYTE.

| Bits | Field | Description |
|------|-------|-------------|
| 15 | VOUT | Any bit set in STATUS_VOUT |
| 11 | POWER_GOOD_N | 1 = power is not good |
| 7:0 | STATUS_BYTE | Copy of STATUS_BYTE |

### STATUS_VOUT

Code `0x7A`, w1c_hw, 1 data byte.

Output voltage status. Write 1 to clear a bit.

| Bits | Field | Description |
|------|-------|-------------|
| 7 | OV_FAULT | Over-voltage fault |
| 6 | OV_WARN | Over-voltage warning |
| 5 | UV_WARN | Under-voltage warning |
| 4 | UV_FAULT | Under-voltage fault |

### STATUS_CML

Code `0x7E`, w1c_hw, 1 data byte.

Communication status. Write 1 to clear a bit.

| Bits | Field | Description |
|------|-------|-------------|
| 7 | INVALID_CMD | Unsupported command, write to a read-only command, or read of a send-byte command |
| 6 | INVALID_DATA | Wrong byte count, illegal value, or write blocked by WRITE_PROTECT |
| 5 | PEC_FAIL | PEC byte did not match |
| 1 | OTHER | SMBus timeout (SCL held low too long) |

### READ_VOUT

Code `0x8B`, ro_hw, 2 data bytes.

Last sampled output voltage (LINEAR16).

### PMBUS_REVISION

Code `0x98`, ro_const, 1 data byte.
Reset `0x33`.

PMBus Part I and Part II revision 1.3.

### MFR_SIM_VOUT

Code `0xD0`, rw, 2 data bytes.
Reset `0x0000`.

Manufacturer specific. FPGA demo only: 0 = plant model follows VOUT_COMMAND, other = force plant voltage to this value (fault injection from the bus).
