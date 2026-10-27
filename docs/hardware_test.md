# Hardware Test

The IP runs on a UPduino v3 (iCE40UP5K). An STM32 Nucleo acts as the PMBus
host and runs a scripted test. A logic analyzer records the bus and the EN,
PG and SMBALERT# pins, and `hw/la_check.py` checks the capture with the same
decoder used on the simulation VCD.

## Parts

| Item | Notes |
|------|-------|
| UPduino v3.0 / v3.1 | iCE40UP5K, programmed over its USB port |
| STM32 Nucleo-64 | F401RE shown; any STM32 with HAL I2C works |
| Logic analyzer | 8+ channels, 24 MS/s or faster (Saleae, or an fx2lafw clone with sigrok) |
| 2 x 4.7 kOhm | SCL and SDA pull-ups to 3.3 V |
| 1 x 10 kOhm | SMBALERT# pull-up to 3.3 V |
| Jumper wires, breadboard | |

Both boards are 3.3 V logic. Tie the grounds together.

## Wiring

| Signal | UPduino pin | Nucleo pin | Analyzer |
|--------|-------------|------------|----------|
| SCL | 2 | PB8 (D15) | CH0 |
| SDA | 3 | PB9 (D14) | CH1 |
| SMBALERT# | 4 | PA4 (A2) | CH2 |
| EN | 6 | PA0 (A0) | CH3 |
| PG | 9 | PA1 (A1) | CH4 |
| GND | GND | GND | GND |

Pull-ups: 4.7 k from SCL and SDA to the Nucleo 3V3 pin, 10 k from SMBALERT# to
3V3. Pin numbers follow `fpga/upduino.pcf`; check them against your board's
silkscreen and edit the pcf if they differ.

The RGB LED shows state too: green = power good, blue = enabled, red = alert.

## 1. Build and flash the FPGA

```
make -C fpga          # yosys + nextpnr + icepack -> fpga/upduino.bin
make -C fpga prog     # iceprog over the UPduino USB port
```

The FPGA build runs at 24 MHz (internal oscillator / 2). nextpnr reports
about 47 MHz max, so there is roughly 2x timing margin.

## 2. Build the STM32 firmware

1. Create a CubeMX / CubeIDE project for your Nucleo.
2. I2C1: Standard mode 100 kHz or Fast mode 400 kHz, PB8 = SCL, PB9 = SDA.
3. USART2 at 115200 8N1 (default on Nucleo-64, goes to the ST-LINK COM port).
4. PA0, PA1, PA4 as GPIO inputs, no pull.
5. Copy `fw/stm32/pmbus_host.c`, `pmbus_demo.c`, `retarget.c` into `Core/Src`
   and add `fw/stm32` and `fw/generated` to the include path.
6. Paste the lines from `fw/stm32/main_snippet.c` into `main.c`.
7. If you skip the GPIO wiring, add `PMBUS_DEMO_NO_GPIO` to the preprocessor
   defines.

`fw/generated/pmbus_regmap.h` is generated from the same YAML as the RTL, so the
firmware never drifts from the hardware.

## 3. Capture and run

1. Start a capture: CH0-CH4, 24 MS/s or faster, about 6 s, trigger on CH0
   falling.
2. Open a serial terminal on the ST-LINK COM port at 115200.
3. Press reset on the Nucleo.

Expected serial output (shortened):

```
=== PMBus Power Manager hardware test ===
[PASS] PMBUS_REVISION: 0x98 = 0x0033 (expect 0x0033)
[PASS] CAPABILITY: 0x19 = 0x00B0 (expect 0x00B0)
...
[PASS] bad PEC write ignored: 0x21 = 0x069A (expect 0x069A)
[PASS] bad PEC flagged: 0x7E = 0x0020 (expect 0x0020)
...
[PASS] 1000 back-to-back reads with PEC, 0 errors
[PASS] READ_VOUT = 3300 mV
[PASS] OV fault + warn: 0x7A = 0x00C0 (expect 0x00C0)
[PASS] OV fault: pins EN=0 PG=0 ALERT#=0
...
[PASS] hiccup: 7 restarts in 1 s (expect ~7)
...
=== N passed, 0 failed ===
```

## 4. Check the capture

Saleae Logic 2: name the channels SCL, SDA, ALERT, EN, PG, then
File > Export Data > CSV (all channels, not ISO timestamps).

```
python3 hw/la_check.py capture.csv --scl SCL --sda SDA --alert ALERT --en EN --pg PG
```

sigrok (fx2lafw clone):

```
sigrok-cli -d fx2lafw --config samplerate=24m --time 6s \
  --channels D0=SCL,D1=SDA,D2=ALERT,D3=EN,D4=PG -O csv -o capture.csv
python3 hw/la_check.py capture.csv --samplerate 24e6 --scl SCL --sda SDA --alert ALERT --en EN --pg PG
```

A 6 s capture at 24 MS/s is a big CSV. If your sigrok build has a dedup option
for the CSV output (`sigrok-cli -O csv --show`), turn it on, or capture each
test phase separately.

What to look for:

| Line | Expected |
|------|----------|
| `PEC bad (target)` | 0. Any other value is an RTL bug. |
| `PEC bad (host, injected)` | 1, from the deliberate bad-PEC write |
| `address NACKs` | 1, from the wrong-address test |
| `target SDA hold` | roughly 600 ns at 24 MHz (333 ns hold + input sync/filter delay), must be >= 300 ns |
| `SCL frequency` | your I2C setting (100 or 400 kHz) |
| `EN` fall after `WR MFR_SIM_VOUT 00 08 ..` (4.0 V) | about 2 to 3 ms: 3 consecutive 1 kHz samples, the first one up to 1 ms after the write |
| `EN` during hiccup | off about 100 ms, then on about 35 ms, repeating |

Run the checker on the simulation first to see the format:

```
make bus-check
```

## Troubleshooting

| Symptom | Check |
|---------|-------|
| Every transfer NACKs | Pull-ups present, grounds tied, SCL/SDA not swapped, FPGA programmed (LED off until OPERATION on is normal) |
| HAL returns BUSY forever | Bus stuck low: power-cycle the UPduino; the 25 ms timeout should also free it |
| PEC mismatch on reads | Slow edges: lower pull-up to 2.2 k or drop to 100 kHz |
| Hold time below 300 ns | Raise `SDA_HOLD_CYCLES` in `fpga/upduino_top.sv` |
| Hiccup count off | Response register still 0x80, or MFR_SIM_VOUT not above 0 |
