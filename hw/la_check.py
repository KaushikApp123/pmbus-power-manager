#!/usr/bin/env python3
"""Decode and check a PMBus capture.

Works on a logic analyzer CSV export (Saleae Logic 2, sigrok/PulseView) or on
a VCD from the testbench, so the same checks run on simulation and hardware.

Checks:
  * every transaction decodes (START, bytes, ACK/NACK, STOP)
  * PEC on every frame that carries one (frame sizes come from regmap.yaml)
  * target SDA hold time after SCL falls (SMBus minimum 300 ns)
  * SCL frequency
  * EN / PG / SMBALERT# edges, each tied to the bus write that caused it

Examples:
  python3 hw/la_check.py build/bus.vcd
  python3 hw/la_check.py capture.csv --scl "Channel 0" --sda "Channel 1" \\
      --en "Channel 3" --pg "Channel 4" --alert "Channel 2"
  python3 hw/la_check.py sigrok.csv --samplerate 8e6 --scl SCL --sda SDA
"""
import argparse
import csv
import pathlib
import statistics
import sys

import yaml

HERE = pathlib.Path(__file__).resolve().parent


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------
def load_vcd(path, names):
    """Return list of (time_s, {name: 0/1}) at every change of a wanted signal."""
    ids, timescale = {}, 1e-9
    vals = {n: 1 for n in names.values() if n}
    out, t, dirty = [], 0, False
    with open(path) as f:
        it = iter(f)
        for line in it:
            tok = line.split()
            if not tok:
                continue
            if tok[0] == "$timescale":
                spec = " ".join(tok[1:])
                while "$end" not in spec:
                    spec += " " + next(it).strip()
                spec = spec.replace("$end", "").strip().replace(" ", "")
                num = "".join(c for c in spec if c.isdigit())
                unit = spec[len(num):]
                timescale = int(num) * {"s": 1, "ms": 1e-3, "us": 1e-6, "ns": 1e-9, "ps": 1e-12, "fs": 1e-15}[unit]
            elif tok[0] == "$var":
                ref = tok[4]
                for key, want in names.items():
                    if want and ref == want:
                        ids.setdefault(tok[3], []).append(want)
            elif tok[0].startswith("#"):
                if dirty:
                    out.append((t * timescale, dict(vals)))
                    dirty = False
                t = int(tok[0][1:])
            elif tok[0][0] in "01xzXZ" and tok[0][1:] in ids:
                v = 0 if tok[0][0] == "0" else 1      # x/z read as pulled high
                for n in ids[tok[0][1:]]:
                    vals[n] = v
                dirty = True
    if dirty:
        out.append((t * timescale, dict(vals)))
    missing = [n for n in names.values() if n and not any(n in v for v in ids.values())]
    if missing:
        sys.exit(f"signals not found in VCD: {missing}")
    return out


def load_csv(path, names, samplerate):
    rows = []
    with open(path, newline="") as f:
        lines = [l for l in f if not l.startswith(";")]
    reader = csv.reader(lines)
    header = [h.strip() for h in next(reader)]
    tcol = next((i for i, h in enumerate(header) if "time" in h.lower()), None)
    cols = {}
    for key, want in names.items():
        if not want:
            continue
        if want not in header:
            sys.exit(f"column '{want}' not in CSV header {header}")
        cols[want] = header.index(want)
    if tcol is None and not samplerate:
        sys.exit("CSV has no time column, pass --samplerate")
    prev = None
    for i, r in enumerate(reader):
        if not r:
            continue
        t = float(r[tcol]) if tcol is not None else i / samplerate
        vals = {n: int(float(r[c])) for n, c in cols.items()}
        if vals != prev:
            rows.append((t, vals))
            prev = vals
    return rows


def load_regmap(path):
    data = yaml.safe_load(pathlib.Path(path).read_text())
    return {r["code"]: (r["name"], r["size"]) for r in data["registers"]}


# ---------------------------------------------------------------------------
# I2C decode
# ---------------------------------------------------------------------------
class Txn:
    def __init__(self, t):
        self.t_start = t
        self.t_stop = None
        self.segments = []      # [[addr_byte, [(byte, ack), ...]], ...]

    def add_byte(self, b, ack):
        if not self.segments or self.segments[-1][0] is None:
            if not self.segments:
                self.segments.append([None, []])
            self.segments[-1][0] = (b, ack)
        else:
            self.segments[-1][1].append((b, ack))

    def new_segment(self):
        self.segments.append([None, []])


def decode(events, n):
    scl_n, sda_n = n["scl"], n["sda"]
    txns, holds = [], []
    cur = None
    bits, byte_dir_target = [], False   # target drives the data bits of this byte
    last_fall = None
    prev = events[0][1]
    scl_periods, last_rise = [], None

    def target_drives(idx):
        # idx 0-7 data bit, 8 ack. Target drives read data and write ACKs.
        return byte_dir_target if idx < 8 else not byte_dir_target

    for t, v in events[1:]:
        scl, sda = v[scl_n], v[sda_n]
        pscl, psda = prev[scl_n], prev[sda_n]
        if scl and pscl and sda != psda:
            if not sda:                                   # START / repeated START
                if cur is None:
                    cur = Txn(t)
                    cur.new_segment()
                else:
                    cur.new_segment()
                bits, byte_dir_target = [], False
            else:                                         # STOP
                if cur is not None:
                    cur.t_stop = t
                    txns.append(cur)
                cur, bits = None, []
        elif scl and not pscl:                            # rising edge: sample
            if last_rise is not None:
                scl_periods.append(t - last_rise)
            last_rise = t
            if cur is not None:
                bits.append(sda)
                if len(bits) == 9:
                    b = 0
                    for x in bits[:8]:
                        b = (b << 1) | x
                    ack = bits[8] == 0
                    seg = cur.segments[-1]
                    is_addr = seg[0] is None
                    cur.add_byte(b, ack)
                    bits = []
                    reading = cur.segments[-1][0][0] & 1
                    byte_dir_target = bool(reading) and ack
                    if is_addr and not ack:
                        byte_dir_target = False
        elif not scl and pscl:                            # falling edge
            last_fall = t
        elif not scl and sda != psda and last_fall is not None and cur is not None:
            idx = len(bits)
            prev_idx = idx - 1 if idx > 0 else 8
            if target_drives(idx) or target_drives(prev_idx):
                holds.append(t - last_fall)
        prev = v
    return txns, holds, scl_periods


def crc8(data):
    c = 0
    for b in data:
        c ^= b
        for _ in range(8):
            c = ((c << 1) ^ 0x07) & 0xFF if c & 0x80 else (c << 1) & 0xFF
    return c


def describe(txn, regmap):
    """Return (text, pec_state, pec_by_target) for one transaction."""
    segs = txn.segments
    if not segs or segs[0][0] is None:
        return "empty", None, False
    a0, ack0 = segs[0][0]
    if not ack0:
        return f"addr 0x{a0 >> 1:02X} NACK", None, False
    if a0 & 1:
        data = [b for b, _ in segs[0][1]]
        return f"read (no cmd) {data}", None, False
    wbytes = [b for b, _ in segs[0][1]]
    if not wbytes:
        return "quick command", None, False
    cmd = wbytes[0]
    name, size = regmap.get(cmd, (f"0x{cmd:02X}", None))
    if len(segs) > 1 and segs[1][0] is not None and segs[1][0][0] & 1:
        a1 = segs[1][0][0]
        rbytes = [b for b, _ in segs[1][1]]
        val = rbytes[:size] if size else rbytes
        text = f"RD {name} -> " + " ".join(f"{b:02X}" for b in val)
        if size and len(wbytes) == 1 and len(rbytes) == size + 1:
            ok = crc8([a0, cmd, a1] + rbytes[:size]) == rbytes[size]
            return text + (" PEC ok" if ok else " PEC BAD"), ok, True
        return text, None, True
    data = wbytes[1:]
    text = f"WR {name} " + " ".join(f"{b:02X}" for b in data)
    if size is not None and len(data) == size + 1:
        ok = crc8([a0] + wbytes[:-1]) == wbytes[-1]
        return text + (" PEC ok" if ok else " PEC BAD (host)"), ok, False
    return text, None, False


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("capture")
    ap.add_argument("--scl", default=None)
    ap.add_argument("--sda", default=None)
    ap.add_argument("--en", default=None)
    ap.add_argument("--pg", default=None)
    ap.add_argument("--alert", default=None)
    ap.add_argument("--samplerate", type=float, default=None, help="for CSVs without a time column")
    ap.add_argument("--regmap", default=str(HERE.parent / "gen" / "regmap.yaml"))
    ap.add_argument("--min-hold-ns", type=float, default=300.0)
    ap.add_argument("-v", "--verbose", action="store_true", help="print every transaction")
    args = ap.parse_args()

    is_vcd = args.capture.lower().endswith(".vcd")
    defaults = {"scl": "scl", "sda": "sda", "en": "en", "pg": "pg", "alert": "alert_n"} if is_vcd else \
               {"scl": "SCL", "sda": "SDA", "en": None, "pg": None, "alert": None}
    names = {k: (getattr(args, k) or defaults[k]) for k in defaults}
    events = load_vcd(args.capture, names) if is_vcd else load_csv(args.capture, names, args.samplerate)
    regmap = load_regmap(args.regmap)

    txns, holds, periods = decode(events, names)
    errors = 0

    pec_ok = pec_bad_target = pec_bad_host = nacks = 0
    descs = []
    for tx in txns:
        text, pec, by_target = describe(tx, regmap)
        descs.append((tx, text))
        if "NACK" in text:
            nacks += 1
        if pec is True:
            pec_ok += 1
        elif pec is False:
            if by_target:
                pec_bad_target += 1
                print(f"ERROR {tx.t_start * 1e3:10.4f} ms  target sent bad PEC: {text}")
            else:
                pec_bad_host += 1
        if args.verbose:
            print(f"{tx.t_start * 1e3:10.4f} ms  {text}")

    print(f"transactions        {len(txns)}")
    print(f"address NACKs       {nacks}")
    print(f"PEC frames ok       {pec_ok}")
    print(f"PEC bad (host, injected)  {pec_bad_host}")
    print(f"PEC bad (target)    {pec_bad_target}")
    errors += pec_bad_target

    if periods:
        f = 1.0 / statistics.median(periods)
        print(f"SCL frequency       {f / 1e3:.1f} kHz (median)")
    if holds:
        hmin = min(holds) * 1e9
        verdict = "ok" if hmin >= args.min_hold_ns else "VIOLATION"
        print(f"target SDA hold     min {hmin:.0f} ns over {len(holds)} edges ({verdict}, spec >= {args.min_hold_ns:.0f} ns)")
        if hmin < args.min_hold_ns:
            errors += 1

    # Output pin edges tied to the last completed bus write before them
    for key in ("en", "pg", "alert"):
        sig = names[key]
        if not sig:
            continue
        prev = events[0][1][sig]
        edges = []
        for t, v in events[1:]:
            if v[sig] != prev:
                edges.append((t, v[sig]))
                prev = v[sig]
        print(f"{key.upper():6s} edges         {len(edges)}")
        for t, val in edges[:40]:
            cause = None
            for tx, text in descs:
                if tx.t_stop is not None and tx.t_stop <= t:
                    cause = (tx, text)
            ctext = f"{(t - cause[0].t_stop) * 1e3:8.3f} ms after: {cause[1]}" if cause else ""
            print(f"   {t * 1e3:10.4f} ms  {'rise' if val else 'fall'}  {ctext}")
        if len(edges) > 40:
            print(f"   ... {len(edges) - 40} more")

    print("RESULT:", "PASS" if errors == 0 else f"FAIL ({errors})")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
