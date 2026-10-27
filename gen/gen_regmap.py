#!/usr/bin/env python3
"""Generate RTL, testbench data, C header and docs from regmap.yaml.

Usage:
    python3 gen/gen_regmap.py [--yaml gen/regmap.yaml] [--out .] [--check]

--check regenerates into memory and exits 1 if any checked-in file is stale.
"""
import argparse
import pathlib
import sys

import yaml
from jinja2 import Environment, FileSystemLoader, StrictUndefined

ACCESS_TYPES = {"rw", "ro_const", "ro_hw", "w1c_hw", "send"}
WP_LEVELS = {0x20, 0x40, 0x80}

# Access codes shared by the testbench (must match ACC_* in the template)
ACCESS_CODE = {"rw": 0, "ro_const": 1, "ro_hw": 2, "w1c_hw": 3, "send": 4}

OUTPUTS = {
    "pmbus_regmap_pkg.sv.j2": "rtl/generated/pmbus_regmap_pkg.sv",
    "pmbus_regfile.sv.j2": "rtl/generated/pmbus_regfile.sv",
    "regmap_tb.svh.j2": "tb/generated/regmap_tb.svh",
    "pmbus_regmap.h.j2": "fw/generated/pmbus_regmap.h",
    "register_map.md.j2": "docs/register_map.md",
}


class RegmapError(Exception):
    pass


def validate(data):
    regs = data.get("registers")
    if not regs:
        raise RegmapError("no registers defined")
    seen_codes, seen_names = {}, set()
    for r in regs:
        name = r.get("name")
        where = f"register {name or '?'}"
        for key in ("name", "code", "access", "size"):
            if key not in r:
                raise RegmapError(f"{where}: missing '{key}'")
        if not name.isidentifier() or name.upper() != name:
            raise RegmapError(f"{where}: name must be UPPER_SNAKE_CASE")
        if name in seen_names:
            raise RegmapError(f"{where}: duplicate name")
        seen_names.add(name)
        code = r["code"]
        if not 0 <= code <= 0xFF:
            raise RegmapError(f"{where}: code 0x{code:X} out of range")
        if code in seen_codes:
            raise RegmapError(f"{where}: code 0x{code:02X} already used by {seen_codes[code]}")
        seen_codes[code] = name
        acc = r["access"]
        if acc not in ACCESS_TYPES:
            raise RegmapError(f"{where}: unknown access '{acc}'")
        size = r["size"]
        if size not in (0, 1, 2):
            raise RegmapError(f"{where}: size must be 0, 1 or 2")
        if (acc == "send") != (size == 0):
            raise RegmapError(f"{where}: only 'send' commands may have size 0")
        maxval = (1 << (8 * size)) - 1
        if acc in ("rw", "ro_const"):
            if "reset" not in r:
                raise RegmapError(f"{where}: '{acc}' needs a reset value")
            if not 0 <= r["reset"] <= maxval:
                raise RegmapError(f"{where}: reset value does not fit in {size} byte(s)")
        elif "reset" in r:
            raise RegmapError(f"{where}: reset only applies to rw/ro_const")
        wp = r.get("wp_allow", [])
        if acc != "rw" and wp:
            raise RegmapError(f"{where}: wp_allow only applies to rw")
        for lvl in wp:
            if lvl not in WP_LEVELS:
                raise RegmapError(f"{where}: bad wp level 0x{lvl:02X}")
        for key in ("allowed", "test_values"):
            for v in r.get(key, []):
                if not 0 <= v <= maxval:
                    raise RegmapError(f"{where}: {key} value 0x{v:X} does not fit")
        allowed = r.get("allowed")
        if allowed and acc == "rw" and r["reset"] not in allowed:
            raise RegmapError(f"{where}: reset value is not in 'allowed'")
        if allowed:
            for v in r.get("test_values", []):
                if v not in allowed:
                    raise RegmapError(f"{where}: test value 0x{v:X} is not in 'allowed'")
    if "WRITE_PROTECT" not in seen_names:
        raise RegmapError("WRITE_PROTECT register is required")
    if "STATUS_CML" not in seen_names:
        raise RegmapError("STATUS_CML register is required")


def enrich(data):
    for r in data["registers"]:
        acc, size = r["access"], r["size"]
        r["lname"] = r["name"].lower()
        r["width"] = 8 * size
        r["readable"] = acc != "send"
        r["writable"] = acc in ("rw", "w1c_hw", "send")
        r["acc_code"] = ACCESS_CODE[acc]
        r.setdefault("wp_allow", [])
        r.setdefault("allowed", [])
        r.setdefault("fields", [])
        r.setdefault("desc", "")
        if "test_values" not in r:
            if r["allowed"]:
                r["test_values"] = list(r["allowed"])
            elif size == 1:
                r["test_values"] = [0x55, 0xAA]
            elif size == 2:
                r["test_values"] = [0x5555, 0xAAAA]
            else:
                r["test_values"] = []
        r["reset"] = r.get("reset", 0)
    data["registers"].sort(key=lambda x: x["code"])
    data["ip"]["vout_lsb_mv"] = 1000.0 * 2.0 ** data["ip"]["vout_exponent"]
    return data


def hexn(value, digits):
    return f"{value:0{digits}X}"


def sv_lit(value, width):
    return f"{width}'h{value:0{(width + 3) // 4}X}"


def make_env(template_dir):
    env = Environment(
        loader=FileSystemLoader(str(template_dir)),
        undefined=StrictUndefined,
        trim_blocks=True,
        lstrip_blocks=True,
        keep_trailing_newline=True,
    )
    env.filters["hex2"] = lambda v: hexn(v, 2)
    env.filters["hex4"] = lambda v: hexn(v, 4)
    env.filters["sv"] = sv_lit
    return env


def render_all(yaml_path, out_root):
    data = yaml.safe_load(pathlib.Path(yaml_path).read_text())
    validate(data)
    enrich(data)
    env = make_env(pathlib.Path(__file__).parent / "templates")
    results = {}
    for tpl, rel in OUTPUTS.items():
        text = env.get_template(tpl).render(ip=data["ip"], regs=data["registers"],
                                            source=pathlib.Path(yaml_path).name)
        results[pathlib.Path(out_root) / rel] = text
    return results


def main():
    here = pathlib.Path(__file__).resolve().parent
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--yaml", default=str(here / "regmap.yaml"))
    ap.add_argument("--out", default=str(here.parent))
    ap.add_argument("--check", action="store_true", help="fail if generated files are stale")
    args = ap.parse_args()

    try:
        results = render_all(args.yaml, args.out)
    except RegmapError as e:
        print(f"regmap error: {e}", file=sys.stderr)
        return 2

    stale = []
    for path, text in results.items():
        if args.check:
            if not path.exists() or path.read_text() != text:
                stale.append(path)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
            print(f"wrote {path.relative_to(args.out)}")
    if stale:
        for p in stale:
            print(f"stale: {p}", file=sys.stderr)
        print("run `make gen` and commit the result", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
