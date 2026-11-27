#!/usr/bin/env python3
"""Notes §75: higher-timeframe key-level take-profit, re-entry, H4+D1 hold, late-candle hold and the
reversal trade, on the live VPS logic (vpssim.py, every other switch as live).

    python3 utilities/vps-sim/download.py --from-year 2015 --out XAUUSD-long   # the MN1 cloud needs 78 months
    python3 utilities/vps-sim/download.py                      # the 2023+ file the simulator calibrates on
    python3 utilities/vps-sim/keylevel_study.py all            # every table, to results/2026-11-27-keylevels/

Modes: events (what price does after touching a key line), edge (fixed 0.1 lot, per year and tier),
roll (rolling 12-month accounts at the live bands and on the §74 recommended base), placebo (every key
line moved 1% away, to see how much of the gain needs the real lines), all.
"""
import argparse
import os
import sys

import numpy as np
import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vpssim  # noqa: E402

OUT = os.path.join(vpssim.HERE, "results", "2026-11-27-keylevels")
START, END = "2023-04-15", "2026-11-13"
YEARS = [("2023", "2023-04-15", "2024-01-01"), ("2024", "2024-01-01", "2025-01-01"),
         ("2025", "2025-01-01", "2026-01-01"), ("2026", "2026-01-01", "2026-11-13")]

KL = dict(kl=True)
OFFTP = dict(kl=True, kl_floor=1e9)        # key-level arrays on, but no line is ever a target
TREND = dict(KL, kl_min_i=3, late_min=10, kl_conf_tol=0.25, re_mode=2, breach_lvltf=True)
EA = dict(TREND, rev=True, rev_first=True, rev_touch=1, rev_tol=0.0, rev_once=True, rev_newline=1.0,
          rev_risk=0.5)   # the .mq5 defaults
CONFIGS = {
    "live": {},
    "TP floor 0.5": dict(KL, kl_floor=0.5),
    "TP floor 1.0": dict(KL, kl_floor=1.0),
    "TP floor 2.0": dict(KL, kl_floor=2.0),
    "TP, H4+ lines only": dict(KL, kl_min_i=3),
    "TP, D1+ lines only": dict(KL, kl_min_i=4),
    "TP + late hold 10 min": dict(KL, late_min=10),
    "TP + H4+D1 hold 0.25": dict(KL, kl_conf_tol=0.25),
    "TP + H4+D1 hold 0.5": dict(KL, kl_conf_tol=0.5),
    "TP + lock: realign": dict(KL, re_mode=1),
    "TP + lock: tier-TF close beyond": dict(KL, re_mode=2),
    "TP + lock: level-TF close beyond": dict(KL, re_mode=2, breach_lvltf=True),
    "TP + lock: level-TF close, buffer 0.25": dict(KL, re_mode=2, breach_lvltf=True, breach_buf=0.25),
    "TP + lock: level-TF close, TP tier and below": dict(KL, re_mode=2, breach_lvltf=True, re_scope=0),
    "TP + lock: level-TF close or realign": dict(KL, re_mode=3, breach_lvltf=True),
    "D1+ lines + level-TF lock": dict(KL, kl_min_i=4, re_mode=2, breach_lvltf=True),
    "trend part only: H4+ lines, TP + late 10 + H4+D1 hold + level-TF lock": TREND,
    "trend part with M30+ lines": dict(TREND, kl_min_i=0),
    "reversal only (no TP), within 0.25 ATR": dict(OFFTP, kl_min_i=3, rev=True),
    "trend part + reversal within 0.25 ATR, any touch": dict(TREND, rev=True),
    "trend part + reversal within 0.25 ATR, first touch": dict(TREND, rev=True, rev_first=True),
    "trend part + reversal on a real M1 touch, any touch": dict(TREND, rev=True, rev_touch=1, rev_tol=0.0),
    "trend part + reversal on a real M1 touch, first touch (repeat fades allowed)": dict(EA, rev_once=False),
    "EA default: trend part + reversal on a real touch, first touch, once per line": EA,
    "EA default, reversal at 1/4 trend lots": dict(EA, rev_risk=0.25),
    "EA default, reversal at full trend lots": dict(EA, rev_risk=1.0),
    "EA default, new line at 0.5 ATR": dict(EA, rev_newline=0.5),
    "EA default, new line at 2.0 ATR": dict(EA, rev_newline=2.0),
    "EA default, reversal stop 2 ATR": dict(EA, rev_stop=2.0),
    "EA default, reversal R:R >= 1": dict(EA, rev_min_rr=1.0),
    "EA default, reversal M15 only": dict(EA, rev_max_lv=1),
    "EA default, D1+ lines": dict(EA, kl_min_i=4),
    "EA, touch = the line's own candle (InpRevTouchMode 2), first touch": dict(EA, rev_touch=2),
    "EA, touch = the line's own candle, any touch": dict(EA, rev_touch=2, rev_first=False),
    "EA, touch = the line's own candle, first touch, D1+ lines": dict(EA, rev_touch=2, kl_min_i=4),
}
ROLL = ["live", "TP floor 1.0", "TP + lock: realign", "TP + lock: level-TF close beyond",
        "trend part only: H4+ lines, TP + late 10 + H4+D1 hold + level-TF lock", "trend part with M30+ lines",
        "trend part + reversal within 0.25 ATR, first touch", "EA default: trend part + reversal on a real touch, first touch, once per line",
        "EA default, reversal at 1/4 trend lots", "EA default, reversal at full trend lots", "EA default, D1+ lines", "EA, touch = the line's own candle (InpRevTouchMode 2), first touch",
        "D1+ lines + level-TF lock"]
FIXED = np.zeros((3, 5))


def pf(x):
    gp, gl = x[x > 0].sum(), -x[x < 0].sum()
    return gp / gl if gl else np.inf


def md(df):
    cols = list(df.columns)
    out = ["| " + " | ".join(str(c) for c in cols) + " |", "|" + "---|" * len(cols)]
    for _, r in df.iterrows():
        out.append("| " + " | ".join(str(v) for v in r.values) + " |")
    return "\n".join(out) + "\n"


def edge(s):
    rows, tiers = [], []
    for name, cf in CONFIGS.items():
        r = {"config": name}
        for y, a, b in YEARS:
            T, _, _ = s.run(a, b, 100000.0, risk=FIXED, **cf)
            r[y] = f"{pf(T.pnl / T.lots):.2f}"
        T, _, _ = s.run(START, END, 100000.0, risk=FIXED, **cf)
        po = T.pnl / T.lots
        r["2023-26 PF"] = f"{pf(po):.2f}"
        r["$/oz"] = f"{po.sum():+,.0f}"
        r["trades"] = len(T)
        rows.append(r)
        t = {"config": name}
        for tier, g in T.groupby("tier"):
            t[tier] = f"{pf(g.pnl / g.lots):.2f} ({len(g)}, {(g.pnl / g.lots).sum():+,.0f})"
        tiers.append(t)
    return pd.DataFrame(rows), pd.DataFrame(tiers).fillna("")


def roll(s, base, start_eq, label):
    rows = []
    starts = pd.date_range(START, pd.Timestamp(END) - pd.DateOffset(months=12), freq="14D")
    for name in ROLL:
        cf = CONFIGS[name]
        ends, dds, ru = [], [], 0
        for st in starts:
            T, eq, r = s.run(st, st + pd.DateOffset(months=12), start_eq, **{**base, **cf})
            ends.append(eq.iloc[-1]); dds.append(((eq.cummax() - eq) / eq.cummax()).max()); ru += r is not None
        ends, dds = np.array(ends), np.array(dds)
        rows.append({"config": name, "ruined": f"{ru / len(starts) * 100:.0f}%",
                     "below start": f"{np.mean(ends < start_eq) * 100:.0f}%",
                     "end 10/50/90%": " / ".join(f"${np.percentile(ends, q):,.0f}" for q in (10, 50, 90)),
                     "median max DD": f"{np.median(dds) * 100:.0f}%",
                     "90th pct DD": f"{np.percentile(dds, 90) * 100:.0f}%"})
    return f"### {label}: {len(starts)} accounts, 12 months each, from ${start_eq:,.0f}\n\n" + md(pd.DataFrame(rows))


def events(s):
    """Every key-level TP of the 'TP floor 1.0' run at a fixed lot: which TF's line it was, and what price did
    next, in ATR(tier) units: the further run in the trade's direction and the retrace against it, over the
    next 4 and 16 tier bars, and how often the level TF's next closed bar ended beyond the line."""
    KLv, KLC, KLA, KLB = s.klarrays(True)[:4]
    T, _, _ = s.run(START, END, 100000.0, risk=FIXED, kl=True, kl_floor=1.0)
    T = T[T.reason == "key-level TP"]
    h, l, c = s.h, s.l, s.c
    atr = s.P[5]
    tfmin = {1: 5, 2: 15, 3: 30, 4: 60, 5: 240}
    rows = []
    for _, r in T.iterrows():
        k, d, lv = int(r.kc), int(r.d), int(r.lvl)
        tf = lv + 1
        a = atr[tf, k]
        px = s.o[k] if k < len(s.o) else np.nan
        # the line the trade closed on: the key line of a TF above the tier nearest the exit
        best, bi = np.inf, -1
        for i in range(max(tf - 1, 0), 7):
            for q in range(4):
                v = KLv[i, q, k]
                if v > 0:
                    dist = min(abs(v - h[k]), abs(v - l[k]), abs(v - px))
                    if dist < best:
                        best, bi, lvl = dist, i, v
        rec = {"tier": vpssim.TIER[lv], "line TF": vpssim.KLNAME[bi] if bi >= 0 else "?"}
        for nb in (4, 16):
            m = tfmin[tf] * nb
            seg = slice(k, min(k + m, len(h)))
            if d == 1:
                rec[f"run {nb}"] = (h[seg].max() - lvl) / a; rec[f"retrace {nb}"] = (lvl - l[seg].min()) / a
            else:
                rec[f"run {nb}"] = (lvl - l[seg].min()) / a; rec[f"retrace {nb}"] = (h[seg].max() - lvl) / a
            rec[f"net {nb}"] = (c[min(k + m, len(c) - 1)] - lvl) * d / a
        # did the line TF's bar close beyond the line? (the bar holding k)
        if bi >= 0:
            b = KLB[bi, k]
            nxt = np.searchsorted(KLB[bi], b + 1)
            rec["level-TF close beyond"] = bool(nxt < len(c) and (KLC[bi, nxt] - lvl) * d > 0)
        rows.append(rec)
    E = pd.DataFrame(rows)
    g = E.groupby("line TF")
    out = pd.DataFrame({
        "touches": g.size(),
        "median run 4 bars (ATR)": g["run 4"].median().round(2),
        "median retrace 4 bars": g["retrace 4"].median().round(2),
        "retrace > run, 4 bars": (g.apply(lambda x: (x["retrace 4"] > x["run 4"]).mean()) * 100).round(0),
        "median net 16 bars": g["net 16"].median().round(2),
        "net 16 < 0": (g.apply(lambda x: (x["net 16"] < 0).mean()) * 100).round(0),
        "line-TF bar closed beyond": (g["level-TF close beyond"].mean() * 100).round(0),
    }).reset_index()
    tot = {"line TF": "all", "touches": len(E),
           "median run 4 bars (ATR)": round(E["run 4"].median(), 2), "median retrace 4 bars": round(E["retrace 4"].median(), 2),
           "retrace > run, 4 bars": round((E["retrace 4"] > E["run 4"]).mean() * 100),
           "median net 16 bars": round(E["net 16"].median(), 2), "net 16 < 0": round((E["net 16"] < 0).mean() * 100),
           "line-TF bar closed beyond": round(E["level-TF close beyond"].mean() * 100)}
    return pd.concat([out, pd.DataFrame([tot])], ignore_index=True)


def placebo(s):
    real = s.klarrays(True)
    keep = dict(CONFIGS)
    names = ["live", "TP floor 1.0", "TP + lock: level-TF close beyond", "D1+ lines + level-TF lock",
             "trend part only: H4+ lines, TP + late 10 + H4+D1 hold + level-TF lock",
             "EA default: trend part + reversal on a real touch, first touch, once per line"]
    t = ""
    for tag, mult in (("real lines", 1.0), ("every line x 1.01", 1.01), ("every line x 0.99", 0.99)):
        s._kl = (real[0] * mult,) + real[1:]
        CONFIGS.clear(); CONFIGS.update({n: keep[n] for n in names})
        e, _ = edge(s)
        t += f"### {tag}\n\n" + md(e) + "\n"
    s._kl = real
    CONFIGS.clear(); CONFIGS.update(keep)
    return t


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", choices=["events", "edge", "roll", "placebo", "all"])
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    s = vpssim.Sim()
    if a.mode in ("events", "all"):
        t = md(events(s)); print(t); open(os.path.join(OUT, "events.md"), "w").write(t)
    if a.mode in ("edge", "all"):
        e, tiers = edge(s)
        t = "### Profit factor at a fixed 0.1 lot (per oz)\n\n" + md(e) + "\n### Per tier: PF (trades, $/oz)\n\n" + md(tiers)
        print(t); open(os.path.join(OUT, "edge.md"), "w").write(t)
    if a.mode in ("placebo", "all"):
        t = placebo(s); print(t); open(os.path.join(OUT, "placebo.md"), "w").write(t)
    if a.mode in ("roll", "all"):
        rec = {**vpssim.RECOMMENDED}
        rec_half = vpssim.RISK_LIVE * 0.5
        t = roll(s, {}, 100.0, "Live bands") + "\n" + roll(s, {}, 1000.0, "Live bands")
        t += "\n" + roll(s, dict(rec, risk=rec_half), 100.0, "§74 recommended, bands x 0.5")
        t += "\n" + roll(s, dict(rec, risk=rec_half), 1000.0, "§74 recommended, bands x 0.5")
        print(t); open(os.path.join(OUT, "roll.md"), "w").write(t)


if __name__ == "__main__":
    main()
