# Build the UPduino bitstream with the open-source flow (yosys + nextpnr + icestorm).
#   make          synth, place & route, pack -> upduino.bin
#   make prog     flash with iceprog (UPduino's FTDI)

TOP  := upduino_top
RTL  := ../rtl/generated/pmbus_regmap_pkg.sv \
        ../rtl/pmbus_crc8.sv \
        ../rtl/pmbus_glitch_filter.sv \
        ../rtl/pmbus_i2c_target.sv \
        ../rtl/pmbus_core.sv \
        ../rtl/generated/pmbus_regfile.sv \
        ../rtl/pmbus_vout_monitor.sv \
        ../rtl/pmbus_power_manager.sv \
        upduino_top.sv

.PHONY: all prog clean

all: upduino.bin

upduino.json: $(RTL)
	yosys -q -l yosys.log -p "read_verilog -sv $(RTL); synth_ice40 -top $(TOP) -json $@"

upduino.asc: upduino.json upduino.pcf
	nextpnr-ice40 --up5k --package sg48 --json $< --pcf upduino.pcf --asc $@ \
	    --freq 24 --report timing.json -l nextpnr.log

upduino.bin: upduino.asc
	icepack $< $@
	@grep -A12 "Device utilisation" nextpnr.log | head -14
	@grep "Max frequency" nextpnr.log | tail -1

prog: upduino.bin
	iceprog $<

clean:
	rm -f upduino.json upduino.asc upduino.bin *.log timing.json
