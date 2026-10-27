#!/usr/bin/env python3
"""Mutation check: inject known bugs into the RTL and confirm the testbench
catches every one. A testbench that passes on broken RTL is not testing much.

Usage: python3 tb/mutate.py [-j N]
"""
import argparse
import concurrent.futures as cf
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent

RTL = [
    "rtl/generated/pmbus_regmap_pkg.sv",
    "rtl/pmbus_crc8.sv",
    "rtl/pmbus_glitch_filter.sv",
    "rtl/pmbus_i2c_target.sv",
    "rtl/pmbus_core.sv",
    "rtl/generated/pmbus_regfile.sv",
    "rtl/pmbus_vout_monitor.sv",
    "rtl/pmbus_power_manager.sv",
]

# (name, file, original text, mutated text)
MUTANTS = [
    ("PEC never checked on writes", "rtl/pmbus_core.sv",
     "else if (len_pec && crc != 8'h00)", "else if (1'b0)"),
    ("wrong PEC sent on reads", "rtl/pmbus_core.sv",
     "else if (rd_idx == rd_size)     tx_byte = crc;", "else if (rd_idx == rd_size)     tx_byte = crc ^ 8'h01;"),
    ("byte count not checked", "rtl/pmbus_core.sv",
     "else if (!len_exact && !len_pec)           err_data = 1'b1;", "else if (1'b0)                             err_data = 1'b1;"),
    ("reads evaluated as writes", "rtl/pmbus_core.sv",
     "wire write_done = stop_i && in_txn && !rd_phase && (wr_cnt != 3'd0);",
     "wire write_done = stop_i && in_txn && (wr_cnt != 3'd0);"),
    ("read allowed after data bytes", "rtl/pmbus_core.sv",
     "sr_cmd_ok <= in_txn && !rd_phase && (wr_cnt == 3'd1);",
     "sr_cmd_ok <= in_txn && !rd_phase;"),
    ("hiccup has no off time", "rtl/pmbus_vout_monitor.sv",
     "!ov_hiccup && !uv_hiccup && (hic_cnt == '0);", "!ov_hiccup && !uv_hiccup;"),
    ("write protect ignored", "rtl/generated/pmbus_regfile.sv",
     "cmd_wp_ok_o    = (wp_level == 8'h00);", "cmd_wp_ok_o    = 1'b1;"),
    ("no glitch filter", "rtl/pmbus_glitch_filter.sv",
     "end else if (cnt == CW'(LEN - 1)) begin", "end else if (1'b1) begin"),
    ("no SMBus timeout", "rtl/pmbus_i2c_target.sv",
     "wire  to_hit = ~scl && (to_cnt == TW'(TIMEOUT_CYCLES - 1));", "wire  to_hit = 1'b0;"),
    ("no soft-start blanking", "rtl/pmbus_vout_monitor.sv",
     "assign checking = en_o && (blank_cnt == BW'(BLANK_SAMPLES));", "assign checking = en_o;"),
    ("no debounce", "rtl/pmbus_vout_monitor.sv",
     "assign act[g] = (cnt == DW'(DEBOUNCE));", "assign act[g] = (cnt != '0);"),
    ("latch never clears", "rtl/pmbus_vout_monitor.sv",
     "if (!op_on_i)                   latched_o <= 1'b0;", "if (1'b0)                       latched_o <= 1'b0;"),
    ("status not sticky", "rtl/pmbus_vout_monitor.sv",
     "status_vout_o <= (status_vout_o & ~st_clr) | st_set;", "status_vout_o <= st_set;"),
    ("SMBALERT# ignores CML", "rtl/pmbus_power_manager.sv",
     "smbalert_oe_o <= (|status_vout) || (|status_cml);", "smbalert_oe_o <= (|status_vout);"),
]


def run_mutant(m):
    name, rel, orig, new = m
    with tempfile.TemporaryDirectory() as td:
        td = pathlib.Path(td)
        for sub in ("rtl/generated", "tb/generated"):
            (td / sub).mkdir(parents=True)
        for f in RTL + ["tb/tb_pmbus.sv", "tb/i2c_master_bfm.svh", "tb/generated/regmap_tb.svh"]:
            shutil.copy(ROOT / f, td / f)
        src = (td / rel).read_text()
        if src.count(orig) != 1:
            return name, "BAD MUTANT (pattern not found once)"
        (td / rel).write_text(src.replace(orig, new))
        comp = subprocess.run(["iverilog", "-g2012", "-I", "tb", "-o", "sim.vvp", *RTL, "tb/tb_pmbus.sv"],
                              cwd=td, capture_output=True, text=True)
        if comp.returncode != 0:
            return name, "COMPILE ERROR"
        sim = subprocess.run(["vvp", "-n", "sim.vvp", "+stop_on_error"], cwd=td,
                             capture_output=True, text=True, timeout=900)
        if "TEST PASSED" in sim.stdout:
            return name, "SURVIVED"
        first = next((l for l in sim.stdout.splitlines() if "ERROR" in l), "")
        return name, "killed: " + first.split("ERROR:", 1)[-1].strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-j", type=int, default=2)
    args = ap.parse_args()
    survived = 0
    with cf.ThreadPoolExecutor(args.j) as ex:
        for name, result in ex.map(run_mutant, MUTANTS):
            print(f"{name:32s} {result}")
            if not result.startswith("killed"):
                survived += 1
    print(f"\n{len(MUTANTS) - survived}/{len(MUTANTS)} mutants killed")
    return 1 if survived else 0


if __name__ == "__main__":
    sys.exit(main())
