# PMBus Power Manager IP
#   make gen     regenerate RTL, TB data, C header and docs from gen/regmap.yaml
#   make lint    Verilator lint of the IP
#   make sim     run the self-checking testbench (Icarus Verilog)
#   make wave    same, and dump tb_pmbus.vcd
#   make bus-check  sim with a pins-only VCD, then run hw/la_check.py on it
#   make fw-test host-side checks of the firmware (PEC, LINEAR16, compiles vs HAL stub)
#   make mutate  inject bugs into the RTL and confirm the testbench catches them
#   make synth   synthesize, place and route for the UPduino (iCE40UP5K)
#   make all     gen + lint + sim + synth

RTL := rtl/generated/pmbus_regmap_pkg.sv \
       rtl/pmbus_crc8.sv \
       rtl/pmbus_glitch_filter.sv \
       rtl/pmbus_i2c_target.sv \
       rtl/pmbus_core.sv \
       rtl/generated/pmbus_regfile.sv \
       rtl/pmbus_vout_monitor.sv \
       rtl/pmbus_power_manager.sv

TB  := tb/tb_pmbus.sv
BUILD := build

.PHONY: all gen gen-check lint sim wave bus-check fw-test mutate synth clean

all: gen lint sim fw-test synth

gen:
	python3 gen/gen_regmap.py

gen-check:
	python3 gen/gen_regmap.py --check

lint:
	verilator --lint-only -Wall --top-module pmbus_power_manager $(RTL)

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/tb_pmbus.vvp: $(RTL) $(TB) tb/i2c_master_bfm.svh tb/generated/regmap_tb.svh | $(BUILD)
	iverilog -g2012 -Wall -Wno-timescale -Wno-sensitivity-entire-array -I tb -o $@ $(RTL) $(TB) 2>&1 | grep -v "sorry: constant selects" || true
	@test -f $@

sim: $(BUILD)/tb_pmbus.vvp
	cd $(BUILD) && vvp -n tb_pmbus.vvp | tee sim.log
	@grep -q "TEST PASSED" $(BUILD)/sim.log

wave: $(BUILD)/tb_pmbus.vvp
	cd $(BUILD) && vvp -n tb_pmbus.vvp +wave | tee sim.log

# Dump only the pins and run the same checker used on logic analyzer captures
bus-check: $(BUILD)/tb_pmbus.vvp
	cd $(BUILD) && vvp -n tb_pmbus.vvp +vcd_bus > sim.log
	@grep -q "TEST PASSED" $(BUILD)/sim.log
	python3 hw/la_check.py $(BUILD)/bus.vcd

fw-test: | $(BUILD)
	gcc -Wall -Wextra -std=c11 fw/test_host.c -o $(BUILD)/fw_test && $(BUILD)/fw_test
	gcc -fsyntax-only -Wall -Wextra -std=c11 -Ifw/stubs -Ifw/stm32 fw/stm32/pmbus_host.c fw/stm32/pmbus_demo.c

mutate:
	mkdir -p $(BUILD)
	python3 tb/mutate.py -j 2 | tee $(BUILD)/mutate.log

synth:
	$(MAKE) -C fpga

clean:
	rm -rf $(BUILD)
	$(MAKE) -C fpga clean
