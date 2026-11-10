#!/usr/bin/env python3
"""Validation harness for the VPS revamp (notes §74): every switch alone, then combined.

    python3 utilities/vps-sim/validate.py matrix          # baseline vs each switch vs combined, per year
    python3 utilities/vps-sim/validate.py onbase          # each switch added to the base, per year
    python3 utilities/vps-sim/validate.py sweep           # parameter neighbourhoods, per year
    python3 utilities/vps-sim/validate.py walk            # tune on one half of the data, report the other
    python3 utilities/vps-sim/validate.py losses          # realised loss per trade vs the nominal risk
    python3 utilities/vps-sim/validate.py montecarlo      # trade-order shuffle and weekly block bootstrap
    python3 utilities/vps-sim/validate.py roll            # a new account every two weeks, 12 months each
    python3 utilities/vps-sim/validate.py stress          # a made-up rollover spread spike, with and without #6

Every figure is a simulation on HistData M1 bars (vpssim.py), not an MT5 run.
"""
import argparse
import sys

import numpy as np
import pandas as pd

import vpssim as V

YEARS = [("2023", "2023-04-15", "2024-01-01"), ("2024", "2024-01-01", "2025-01-01"),
         ("2025", "2025-01-01", "2026-01-01"), ("2026", "2026-01-01", "2026-11-07")]
FULL = ("2023-26", "2023-04-15", "2026-11-07")

# The defect fixes the simulator can see (#1 one position, #3 peak since entry), the base the
# safety switches were judged on (the fixes plus #2 stop-aware sizing), and the recommended set.
DEFECTS = V.DEFECTS
BASE = dict(DEFECTS, cloud_size=True)
RECOMMENDED = V.RECOMMENDED
HALF = V.RISK_LIVE * 0.5
STACK = dict(RECOMMENDED, one_pos=False)          # the recommended set with #1 off: tiers may stack

ALONE = [
    ("baseline (live)", {}),
    ("#1 one position", dict(one_pos=True)),
    ("#3 peak since entry", dict(peak_entry=True)),
    ("#4 arm on peak", dict(arm_peak=True)),
    ("#1 + #4 (one position, arm on peak)", dict(one_pos=True, arm_peak=True)),
    ("#2 size on cloud distance", dict(cloud_size=True)),
    ("#5 re-align after stop", dict(realign=True)),
    ("#10 min-lot gate 5%", dict(minlot_gate=5.0)),
    ("daily loss 10%", dict(daily_loss=10.0)),
    ("weekly loss 20%", dict(weekly_loss=20.0)),
    ("max open risk 30%", dict(max_open_risk=30.0)),
    ("Friday: no entries from 20:00", dict(fri_stop=20)),
    ("Friday: flat at 22:00", dict(fri_flat=22)),
    ("quiet window 23:30-01:30", dict(q_from=23 * 60 + 30, q_to=90)),
    ("loss streak 3 -> 24 h pause", dict(streak_n=3, pause_min=1440)),
    ("drawdown 25% -> risk x0.5", dict(dd_at=25.0, dd_factor=0.5)),
    ("risk bands x0.5", dict(risk=HALF)),
]
COMBINED = [
    ("defect fixes (#1 #3)", DEFECTS),
    ("base (fixes + #2)", BASE),
    ("recommended", RECOMMENDED),
    ("recommended, bands x0.5", dict(RECOMMENDED, risk=HALF)),
    ("recommended without #1", STACK),
    ("recommended without #1, bands x0.5", dict(STACK, risk=HALF)),
]
# Each switch added alone to the base: at the live sizing one H4 trade can lose 80% of a small
# account, which drowns every smaller effect, so the switches are compared where that is fixed.
ON_BASE = [("base (fixes + #2)", BASE)] + [(f"base + {n}", dict(BASE, **kw)) for n, kw in [
    ("#4 arm on peak", dict(arm_peak=True)),
    ("#5 re-align after stop", dict(realign=True)),
    ("#10 min-lot gate 5%", dict(minlot_gate=5.0)),
    ("daily loss 5%", dict(daily_loss=5.0)),
    ("daily loss 10%", dict(daily_loss=10.0)),
    ("weekly loss 10%", dict(weekly_loss=10.0)),
    ("weekly loss 20%", dict(weekly_loss=20.0)),
    ("max open risk 20%", dict(max_open_risk=20.0)),
    ("max open risk 30%", dict(max_open_risk=30.0)),
    ("max open risk 40%", dict(max_open_risk=40.0)),
    ("Friday no entries 16:00", dict(fri_stop=16)),
    ("Friday no entries 20:00", dict(fri_stop=20)),
    ("Friday flat 16:00", dict(fri_flat=16)),
    ("Friday flat 20:00", dict(fri_flat=20)),
    ("Friday flat 22:00", dict(fri_flat=22)),
    ("quiet window 23:30-01:30", dict(q_from=23 * 60 + 30, q_to=90)),
    ("loss streak 3 -> 24 h", dict(streak_n=3, pause_min=1440)),
    ("loss streak 4 -> 24 h", dict(streak_n=4, pause_min=1440)),
    ("drawdown 15% -> x0.5", dict(dd_at=15.0, dd_factor=0.5)),
    ("drawdown 25% -> x0.5", dict(dd_at=25.0, dd_factor=0.5)),
    ("drawdown 35% -> x0.5", dict(dd_at=35.0, dd_factor=0.5)),
    ("bands x0.5", dict(risk=HALF)),
]] + [("base without #1 (tiers stack)", dict(BASE, one_pos=False)),
      ("recommended, max open risk 20%", dict(RECOMMENDED, max_open_risk=20.0)),
      ("recommended, max open risk 40%", dict(RECOMMENDED, max_open_risk=40.0)),
      ("recommended, drawdown cut at 15%", dict(RECOMMENDED, dd_at=15.0)),
      ("recommended, drawdown cut at 35%", dict(RECOMMENDED, dd_at=35.0)),
      ("recommended, Friday flat 16:00", dict(RECOMMENDED, fri_flat=16)),
      ("recommended, daily loss 3%", dict(RECOMMENDED, daily_loss=3.0)),
      ("recommended, daily loss 10%", dict(RECOMMENDED, daily_loss=10.0)),
      ("recommended, weekly loss 20%", dict(RECOMMENDED, weekly_loss=20.0))]


def stats(T, eq, ruined, start_eq):
    """Net, profit factor, max equity drawdown %, worst server day %, trades, survived."""
    daily = eq.groupby(eq.index.floor("D")).last()
    prev = daily.shift().fillna(start_eq)
    worst = ((daily - prev) / prev).min() * 100 if len(daily) else 0.0
    peak = eq.cummax().clip(lower=start_eq)
    return dict(net=eq.iloc[-1] - start_eq, pf=V.pf(T.pnl) if len(T) else np.nan,
                dd=((peak - eq) / peak).max() * 100, worst_day=worst, n=len(T), ok=ruined is None)


def cell(r):
    return f"{r['net']:+,.0f} | {r['pf']:.2f} | {r['dd']:.0f}% | {r['worst_day']:.0f}% | {r['n']} | {'yes' if r['ok'] else 'RUINED'}"


def matrix(S, sets, periods, eqs):
    for eq0 in eqs:
        for name, a, b in periods:
            print(f"\n### {name}, from ${eq0:,}\n")
            print("| Run | Net $ | PF | Max DD | Worst day | Trades | Survives |\n|---|---|---|---|---|---|---|")
            for label, kw in sets:
                print(f"| {label} | {cell(stats(*S.run(a, b, eq0, **kw), eq0))} |", flush=True)


def sweep(S):
    grids = [("daily_loss", [5, 7.5, 10, 15, 20]), ("weekly_loss", [10, 15, 20, 30]),
             ("max_open_risk", [15, 20, 30, 40, 60]), ("dd_at", [15, 20, 25, 35, 50]),
             ("streak_n", [2, 3, 4, 5]), ("fri_stop", [16, 18, 20, 22]), ("fri_flat", [18, 20, 22])]
    for eq0 in (100, 10000):
        for key, vals in grids:
            print(f"\n### {key} alone, from ${eq0:,}: net $ / max DD % / survives\n")
            print("| Value | " + " | ".join(p[0] for p in YEARS + [FULL]) + " |\n|---|" + "---|" * (len(YEARS) + 1))
            for v in [None] + vals:
                kw = {} if v is None else {key: v}
                if key == "streak_n" and v:
                    kw["pause_min"] = 1440
                out = []
                for _, a, b in YEARS + [FULL]:
                    r = stats(*S.run(a, b, eq0, **kw), eq0)
                    out.append(f"{r['net']:+,.0f} / {r['dd']:.0f}{'' if r['ok'] else ' / RUINED'}")
                print(f"| {'off' if v is None else v} | " + " | ".join(out) + " |", flush=True)


def walk(S):
    """Pick each parameter on one half of the data, on top of the base, by the worse of end/start
    from $100 and from $1,000 (both in the first risk band); then report that value on the other half.
    A value only counts if it also helps where it was not chosen."""
    halves = [("2023-04-15", "2025-01-01"), ("2025-01-01", "2026-11-07")]
    grids = [("max_open_risk", [15, 20, 30, 40, 60]), ("dd_at", [15, 20, 25, 35, 50]),
             ("fri_flat", [16, 18, 20, 22, 23]), ("daily_loss", [5, 7.5, 10, 15, 20]),
             ("weekly_loss", [10, 15, 20, 30])]

    def score(a, b, kw):
        out = []
        for e in (100, 1000):
            T, eq, ru = S.run(a, b, e, **{**BASE, **kw})
            out.append((eq.iloc[-1] / e, stats(T, eq, ru, e)["dd"]))
        return min(x[0] for x in out), max(x[1] for x in out)

    fmt = lambda r: f"{r[0]:.2f}x, DD {r[1]:.0f}%"
    print("| Parameter | Tuned on | Best value | In sample: off -> best | Out of sample: off -> best |")
    print("|---|---|---|---|---|")
    for key, vals in grids:
        extra = dict(dd_factor=0.5) if key == "dd_at" else {}
        for i in (0, 1):
            tr, te = halves[i], halves[1 - i]
            best = max(vals, key=lambda v: score(*tr, {key: v, **extra})[0])
            print(f"| {key} | {tr[0][:4]}-{tr[1][:4]} | {best} | {fmt(score(*tr, {}))} -> "
                  f"{fmt(score(*tr, {key: best, **extra}))} | {fmt(score(*te, {}))} -> "
                  f"{fmt(score(*te, {key: best, **extra}))} |", flush=True)


def losses(S):
    """Tier-1 bands at an equity where the minimum lot does not bind."""
    r1 = np.tile(V.RISK_LIVE[0], (3, 1))
    nom = dict(M15=1, M30=5, H1=10, H4=20)
    for label, kw in (("live logic", {}), ("defect fixes (#1 #3)", DEFECTS), ("recommended", RECOMMENDED),
                      ("recommended without #1", STACK)):
        T, eq, ru = S.run(FULL[1], FULL[2], 1e6, risk=r1, **kw)
        T["ret"] = T.pnl / T.eq_in * 100
        print(f"\n### {label}: result per trade as % of equity at entry, tier-1 bands, {FULL[0]}\n")
        print("| Tier | Nominal risk | Trades | Win % | Median loss | 90th pct loss | 99th pct loss | Worst | Lost more than nominal |")
        print("|---|---|---|---|---|---|---|---|---|")
        for t in ("M15", "M30", "H1", "H4"):
            g = T[T.tier == t]
            L = g.ret[g.ret < 0]
            if len(L) == 0:
                continue
            print(f"| {t} | {nom[t]}% | {len(g)} | {(g.ret > 0).mean() * 100:.0f} | {L.median():.1f}% | {L.quantile(.1):.1f}% | "
                  f"{L.quantile(.01):.1f}% | {L.min():.1f}% | {(g.ret < -nom[t]).mean() * 100:.0f}% of trades |")
        day = T.groupby(T.close.dt.floor("D")).ret.sum()
        under = sum(((T.ko <= r.ko) & (T.kc > r.ko) & (T.lvl > r.lvl)).any() for r in T.itertuples())
        print(f"\nWorst day (sum of trade results): {day.min():.0f}% on {day.idxmin():%Y-%m-%d}. "
              f"Entries opened under a running bigger tier: {under} of {len(T)}."
              + (f" Margin stop-out {ru:%Y-%m-%d}." if ru is not None else ""))


def montecarlo(S, n=5000, seed=7):
    """Per-trade returns (P/L over equity at entry) at tier-1 bands, re-ordered at random and
    compounded. The shuffle breaks the clustering of losses, so a weekly block bootstrap (whole
    weeks of trades kept together, drawn with replacement) is shown beside it."""
    rng = np.random.default_rng(seed)
    r1 = np.tile(V.RISK_LIVE[0], (3, 1))
    print("| Plan | Method | Median max DD | 95th pct max DD | P(max DD >= 50%) | P(max DD >= 90%) | Median end / start |")
    print("|---|---|---|---|---|---|---|")
    for label, kw, scale in (("live", {}, 1.0), ("live, bands x0.5", {}, 0.5), ("defect fixes (#1 #3)", DEFECTS, 1.0),
                             ("recommended", RECOMMENDED, 1.0), ("recommended, bands x0.5", RECOMMENDED, 0.5),
                             ("recommended without #1", STACK, 1.0),
                             ("recommended without #1, bands x0.5", STACK, 0.5)):
        T, eq, ru = S.run(FULL[1], FULL[2], 1e6, risk=r1 * scale, **kw)
        ret = np.clip((T.pnl / T.eq_in).values, -0.999, None)
        wk = T.close.dt.to_period("W").astype(str).values
        blocks = [ret[wk == w] for w in pd.unique(wk)]
        for method in ("trade shuffle", "weekly blocks"):
            dds, ends = [], []
            for _ in range(n):
                if method == "trade shuffle":
                    x = rng.permutation(ret)
                else:
                    x = np.concatenate([blocks[i] for i in rng.integers(0, len(blocks), len(blocks))])
                e = np.cumprod(1 + x)
                pk = np.maximum.accumulate(np.maximum(e, 1.0))
                dds.append(((pk - e) / pk).max()); ends.append(e[-1])
            dds, ends = np.array(dds), np.array(ends)
            print(f"| {label} | {method} | {np.median(dds) * 100:.0f}% | {np.percentile(dds, 95) * 100:.0f}% | "
                  f"{(dds >= .5).mean() * 100:.0f}% | {(dds >= .9).mean() * 100:.0f}% | {np.median(ends):,.1f}x |", flush=True)


def stress(S):
    """#6 and the rollover: a made-up spread of $1.50 from 23:55 to 01:15 server time, on the
    recommended set from $1,000. It is a stress model, not XM's spread history."""
    print("| Spread | " + " | ".join(p[0] for p in YEARS + [FULL]) + " |\n|---|" + "---|" * (len(YEARS) + 1))
    for label, kw in (("constant $0.30", {}), ("spike, no exit guard", dict(roll_spread=1.5)),
                      ("spike, kumo exit waits above $0.60", dict(roll_spread=1.5, exit_max_spread=0.6))):
        out = []
        for _, a, b in YEARS + [FULL]:
            r = stats(*S.run(a, b, 1000, **{**RECOMMENDED, **kw}), 1000)
            out.append(f"{r['net']:+,.0f} / {r['dd']:.0f}%")
        print(f"| {label} | " + " | ".join(out) + " |", flush=True)


def _roll_one(job):
    label, kw, eq0, starts = job
    S = _roll_one.S
    ends, dds, worst, ruins = [], [], [], 0
    for st in starts:
        T, eq, ru = S.run(st, st + pd.DateOffset(months=12), eq0, **kw)
        r = stats(T, eq, ru, eq0)
        ends.append(eq.iloc[-1]); dds.append(r["dd"]); worst.append(r["worst_day"]); ruins += ru is not None
    ends = np.array(ends)
    return (f"| {label} | ${eq0:,} | {ruins / len(starts) * 100:.0f}% | {np.mean(ends < eq0) * 100:.0f}% | "
            f"{np.mean(ends < eq0 * 0.5) * 100:.0f}% | "
            + " / ".join(f"${np.percentile(ends, q):,.0f}" for q in (10, 50, 90))
            + f" | {np.median(dds):.0f}% | {np.percentile(dds, 90):.0f}% | {np.median(worst):.0f}% |")


def _roll_init():
    _roll_one.S = V.Sim()


def roll(S, sets=None, eqs=(100, 1000, 10000)):
    """A new account every two weeks, each run for 12 months: the distribution, not one path."""
    from multiprocessing import Pool
    starts = pd.date_range("2023-04-15", pd.Timestamp("2025-11-01"), freq="14D")
    sets = sets or ALONE + COMBINED + ON_BASE[1:]
    print(f"{len(starts)} accounts, one every two weeks from {starts[0]:%Y-%m-%d} to {starts[-1]:%Y-%m-%d}, "
          "12 months each (the runs overlap, so they are not independent).\n")
    print("| Plan | Start | Ruined | Below start | Below half | End 10% / 50% / 90% | Median max DD | 90th pct max DD "
          "| Median worst day |\n|---|---|---|---|---|---|---|---|---|")
    jobs = [(label, kw, eq0, starts) for eq0 in eqs for label, kw in sets]
    with Pool(4, initializer=_roll_init) as pool:
        for line in pool.imap(_roll_one, jobs):
            print(line, flush=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", choices=["matrix", "onbase", "sweep", "walk", "losses", "montecarlo", "roll", "stress"])
    a = ap.parse_args()
    S = V.Sim()
    if a.mode == "matrix":
        matrix(S, ALONE + COMBINED, YEARS + [FULL], (100, 10000))
    elif a.mode == "onbase":
        matrix(S, ON_BASE[:-8], YEARS + [FULL], (100, 1000))
    else:
        globals()[a.mode](S)


if __name__ == "__main__":
    sys.exit(main())
