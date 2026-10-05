#!/usr/bin/env python3
"""Minute-by-minute simulator of the live VPS EA (ichimoku-h4-m1-vps-ea.mq5).

A Python port of the EA's trading logic, run on HistData M1 bid bars
(download.py) in the broker's server time, sized like XM's Micro GOLDm#
(1 lot = 1 oz, 0.1 lot minimum). It is a screening tool: many start dates,
risk plans and settings in seconds, where an MT5 real-tick run does one.
MT5 real ticks stay the reference (notes §69).

What is ported, as live (M5 tier off):
  - the bottom-up chain M1..tier TF aligned (price and chikou beyond tenkan,
    kijun and cloud), scanned H4 -> M15, the largest aligned tier opening;
  - the cloud-bias gate: future cloud of the tier TF and the TF below
    (M1 current + future for the M5 tier);
  - H4 bias, H1 stand-in on a flat H4 for M15/M30, D1 filter on the H4 tier;
  - supersede: a new bigger tier closes the smaller ones;
  - kumo-touch exit at the M1 open, break-even (1 ATR, 0.5 on H1/H4,
    + 15 points), chandelier (2 ATR spike lock, 0.5 on H1/H4, 1 ATR behind
    the forming tier bar's peak, 0.3 ATR minimum step), the 8 x ATR
    disaster stop as a broker stop;
  - the risk bands on equity with floating P/L against 2 x ATR, floored to
    the lot step, lifted to the minimum lot, capped to 80% of free margin.

Each M1 bar k: at its open the EA acts on everything closed before it
(exits, stop modifications, entries at the open price); then the bar's
range is checked against the broker-side stops. Ask = bid + --spread.

Not modelled: swaps, slippage, a varying spread, the rejection exit (off in
the live build), and the order in which a stop and a level touch happen
inside one minute.

Calibration against MT5 real ticks, $100 each year (notes §50, §69):
  2024: MT5 ruined 2024-08-02         sim ruined 2024-08-02
  2025: MT5 +$14,646, PF 2.03          sim +$14,658, PF 2.05
  2026: MT5 +$13,295, PF 1.52          sim +$1,396 (same tier edge at a fixed
        lot; the compounded path diverges in a June-August losing run)

Usage:
    python3 utilities/vps-sim/download.py                    # once: fetch the data
    python3 utilities/vps-sim/vpssim.py calibrate            # the MT5 check above
    python3 utilities/vps-sim/vpssim.py run --from 2025-01-01 --to 2026-01-01 --start-eq 100
    python3 utilities/vps-sim/vpssim.py roll --start-eq 100 --months 12
    python3 utilities/vps-sim/vpssim.py roll --start-eq 100 --risk-scale 0.5
    python3 utilities/vps-sim/vpssim.py roll --start-eq 100 --disaster 2      # §66 quarter stop
    python3 utilities/vps-sim/vpssim.py run --fixed-lot --from 2023-04-15     # edge without compounding

Porting another EA: keep load(), ichi(), build() and the run/roll harness,
and write that EA's entry and exit rules in place of sim(). Check the port
against one MT5 real-tick run before trusting it.
"""
import argparse
import os

import numpy as np
import pandas as pd
from numba import njit

HERE = os.path.dirname(os.path.abspath(__file__))
TFMIN = [1, 5, 15, 30, 60, 240]        # stack index 0..5: M1 M5 M15 M30 H1 H4 (D1 is index 6)
TIER = ["M5", "M15", "M30", "H1", "H4"]
RISK_LIVE = np.array([[1.0, 1.0, 5.0, 10.0, 20.0],     # band 1 (< $7,000):  M5 M15 M30 H1 H4
                      [0.5, 0.5, 2.5, 5.0, 10.0],      # band 2 (< $13,000)
                      [0.1, 0.1, 0.2, 1.0, 2.0]])      # band 3
REASON = {0: "kumo touch", 1: "BE/trail stop", 2: "superseded", 3: "stop-out", 4: "disaster stop"}


# ------------------------------------------------------------------ data and indicators
def load(pair="XAUUSD", server_tz="Europe/Athens"):
    """M1 bid bars indexed by naive server time (XM: EET/EEST, day opens at 00:00)."""
    df = pd.read_pickle(os.path.join(HERE, "data", f"{pair}.pkl"))
    ny = pd.DatetimeIndex(df.t).tz_localize("America/New_York", ambiguous="NaT", nonexistent="NaT")
    keep = ~ny.isna()
    df = df[keep]
    idx = ny[keep].tz_convert(server_tz).tz_localize(None)
    df = df.set_index(idx)[["o", "h", "l", "c"]]
    df = df[~df.index.duplicated()].sort_index()
    return df[df.index.dayofweek < 5]


def ichi(df):
    """Ichimoku 9/26/52 as MT5 draws it, ATR(14) as MT5's iATR (simple mean of true range),
    and the family's CheckAlign: price beyond tenkan, kijun and the cloud under it, and the
    chikou (this close) beyond the high/low, tenkan, kijun and cloud 26 bars back."""
    h, l, c = df.h, df.l, df.c
    mid = lambda n: (h.rolling(n).max() + l.rolling(n).min()) / 2
    t, k = mid(9), mid(26)
    fa, fb = (t + k) / 2, mid(52)                       # the future cloud printed now
    sa, sb = fa.shift(26), fb.shift(26)                 # the cloud under the bar
    tr = pd.concat([h - l, (h - c.shift()).abs(), (l - c.shift()).abs()], axis=1).max(axis=1)
    x = {n: v.values for n, v in dict(o=df.o, h=h, l=l, c=c, t=t, k=k).items()}
    x["ctop"], x["cbot"] = np.fmax(sa.values, sb.values), np.fmin(sa.values, sb.values)
    x["far"] = np.sign(np.nan_to_num((fa - fb).values))
    x["now"] = np.sign(np.nan_to_num((sa - sb).values))
    x["atr"] = tr.rolling(14).mean().values
    s = lambda a: pd.Series(a).shift(26).values
    hi26 = np.fmax.reduce([s(x["h"]), s(x["t"]), s(x["k"]), s(x["ctop"])])
    lo26 = np.fmin.reduce([s(x["l"]), s(x["t"]), s(x["k"]), s(x["cbot"])])
    up = (c.values > np.fmax.reduce([x["t"], x["k"], x["ctop"]])) & (c.values > hi26)
    dn = (c.values < np.fmin.reduce([x["t"], x["k"], x["cbot"]])) & (c.values < lo26)
    x["align"] = up.astype(np.int8) - dn.astype(np.int8)
    return x


def build(df):
    """For each M1 bar k, the values of every TF's last bar closed by the open of k (MT5's
    shift 1), and the id of the TF bar containing k (for the chandelier's forming-bar peak)."""
    t = df.index.values
    n = len(df)
    A = np.zeros((7, n), np.int8)
    FAR, NOW = np.zeros((6, n), np.int8), np.zeros((6, n), np.int8)
    CT, CB, ATR = np.full((6, n), np.nan), np.full((6, n), np.nan), np.full((6, n), np.nan)
    BID = np.zeros((6, n), np.int64)
    for j, m in enumerate(TFMIN + [1440]):
        r = df if m == 1 else df.resample(f"{m}min", label="left", closed="left", origin="start_day").agg(
            {"o": "first", "h": "max", "l": "min", "c": "last"}).dropna()
        x = ichi(r)
        close_t = (r.index + pd.Timedelta(minutes=m)).values
        ix = np.searchsorted(close_t, t, side="right") - 1
        ok = ix >= 0
        g = lambda a, fill: np.where(ok, a[np.clip(ix, 0, None)], fill)
        A[j] = g(x["align"], 0)
        if j < 6:
            FAR[j], NOW[j] = g(x["far"].astype(np.int8), 0), g(x["now"].astype(np.int8), 0)
            CT[j], CB[j], ATR[j] = g(x["ctop"], np.nan), g(x["cbot"], np.nan), g(x["atr"], np.nan)
            BID[j] = np.searchsorted(r.index.values, t, side="right") - 1
    return A, FAR, NOW, CT, CB, ATR, BID


# ------------------------------------------------------------------ the EA
@njit(cache=True)
def sim(o, h, l, c, A, FAR, NOW, CT, CB, ATR, BID, k0, k1, start_eq, spread, risk, lev,
        disaster_mult, m5tier, contract, lotmin, lotstep):
    NL = 5
    st = np.zeros(NL, np.int64); lots = np.zeros(NL); ent = np.zeros(NL); sl = np.zeros(NL)
    pkH = np.zeros(NL); pkL = np.zeros(NL); be = np.zeros(NL, np.bool_); topen = np.zeros(NL, np.int64)
    bal = start_eq
    trades = []            # (level, dir, k_open, k_close, lots, pnl, reason, equity at entry)
    eqc = np.zeros(k1 - k0)
    runH = np.zeros((6,)); runL = np.zeros((6,)); lastbid = -np.ones(6, np.int64)
    ruined = -1
    pt = 0.01
    for k in range(k0, k1):
        bid = o[k]; ask = o[k] + spread
        for j in range(6):                              # forming-bar extremes up to k-1
            if BID[j, k] != lastbid[j]:
                lastbid[j] = BID[j, k]; runH[j] = bid; runL[j] = bid
            else:
                runH[j] = max(runH[j], h[k - 1], bid); runL[j] = min(runL[j], l[k - 1], bid)
        # ---- exits and protection at the open of k
        for lv in range(NL):
            if st[lv] == 0:
                continue
            tf = lv + 1
            d = st[lv]
            if (d == 1 and bid <= CT[tf, k]) or (d == -1 and ask >= CB[tf, k]):
                px = bid if d == 1 else ask
                pnl = (px - ent[lv]) * d * lots[lv] * contract
                bal += pnl
                trades.append((lv, d, topen[lv], k, lots[lv], pnl, 0, 0.0))
                st[lv] = 0
                continue
            a = ATR[tf, k]
            if not (a > 0):
                continue
            if d == 1:
                pkH[lv] = max(pkH[lv], runH[tf])
            else:
                pkL[lv] = min(pkL[lv], runL[tf])
            beA = 0.5 if lv >= 3 else 1.0
            if not be[lv]:
                if (d == 1 and bid >= ent[lv] + beA * a) or (d == -1 and ask <= ent[lv] - beA * a):
                    nsl = ent[lv] + d * 15 * pt
                    if (d == 1 and nsl > sl[lv] + pt and nsl < bid) or (d == -1 and nsl < sl[lv] - pt and nsl > ask):
                        sl[lv] = nsl; be[lv] = True
            armA = 0.5 if lv >= 3 else 2.0
            if (d == 1 and bid >= ent[lv] + armA * a) or (d == -1 and ask <= ent[lv] - armA * a):
                nsl = pkH[lv] - a if d == 1 else pkL[lv] + a
                if d == 1 and nsl > sl[lv] + pt and nsl < bid and nsl - sl[lv] >= 0.3 * a:
                    sl[lv] = nsl
                if d == -1 and nsl < sl[lv] - pt and nsl > ask and sl[lv] - nsl >= 0.3 * a:
                    sl[lv] = nsl
        # ---- equity and the broker's stop-out (margin level 20%)
        fl = 0.0; used = 0.0
        for lv in range(NL):
            if st[lv] != 0:
                px = bid if st[lv] == 1 else ask
                fl += (px - ent[lv]) * st[lv] * lots[lv] * contract
                used += lots[lv] * contract * bid / lev
        eq = bal + fl
        if ruined < 0 and (eq <= 0 or (used > 0 and eq / used < 0.2)):
            ruined = k
            for lv in range(NL):
                if st[lv] != 0:
                    px = bid if st[lv] == 1 else ask
                    pnl = (px - ent[lv]) * st[lv] * lots[lv] * contract
                    bal += pnl
                    trades.append((lv, st[lv], topen[lv], k, lots[lv], pnl, 3, 0.0))
                    st[lv] = 0
            eqc[k - k0:] = bal
            break
        # ---- entries: largest aligned tier, H4 down
        top = -1; tdir = 0
        for lv in range(NL - 1, -1, -1):
            if st[lv] != 0:
                continue
            if lv == 0 and not m5tier:
                continue
            tf = lv + 1
            d = np.int64(A[0, k])
            if d == 0:
                continue
            okc = True
            for j in range(1, tf + 1):
                if A[j, k] != d:
                    okc = False; break
            if not okc:
                continue
            if FAR[tf, k] != d:
                continue
            if lv == 0:
                if not (NOW[0, k] == d and FAR[0, k] == d):
                    continue
            elif FAR[tf - 1, k] != d:
                continue
            h4 = A[5, k]
            if h4 != d:
                if lv > 2 or h4 != 0:
                    continue
                if not (A[4, k] == d and FAR[4, k] == d):
                    continue
            if lv == 4 and A[6, k] != d:
                continue
            top = lv; tdir = d
            break
        if top >= 0:
            for lv in range(top):
                if st[lv] != 0:
                    px = bid if st[lv] == 1 else ask
                    pnl = (px - ent[lv]) * st[lv] * lots[lv] * contract
                    bal += pnl
                    trades.append((lv, st[lv], topen[lv], k, lots[lv], pnl, 2, 0.0))
                    st[lv] = 0
            fl = 0.0; used = 0.0
            for lv in range(NL):
                if st[lv] != 0:
                    px = bid if st[lv] == 1 else ask
                    fl += (px - ent[lv]) * st[lv] * lots[lv] * contract
                    used += lots[lv] * contract * bid / lev
            eq = bal + fl
            a = ATR[top + 1, k]
            if a > 0 and eq > 0:
                rt = 2 if eq >= 13000 else (1 if eq >= 7000 else 0)
                lt = eq * risk[rt, top] / 100.0 / (a * 2.0 * contract)
                lt = np.floor(lt / lotstep + 1e-9) * lotstep
                lt = max(lotmin, lt)
                price = ask if tdir == 1 else bid
                m1lot = contract * price / lev
                maxl = np.floor(((eq - used) * 0.8 / m1lot) / lotstep + 1e-9) * lotstep
                maxl = max(lotmin, maxl)
                if lt > maxl:
                    lt = maxl
                st[top] = tdir; lots[top] = lt; ent[top] = price; topen[top] = k
                sl[top] = price - tdir * disaster_mult * a
                pkH[top] = price; pkL[top] = price; be[top] = False
                trades.append((top, tdir, k, -1, lt, 0.0, 9, eq))
        # ---- broker stops inside bar k
        for lv in range(NL):
            if st[lv] == 0:
                continue
            d = st[lv]
            if d == 1:
                if o[k] <= sl[lv] and not (topen[lv] == k):
                    px = o[k]
                elif l[k] <= sl[lv]:
                    px = sl[lv]
                else:
                    continue
            else:
                if o[k] + spread >= sl[lv] and not (topen[lv] == k):
                    px = o[k] + spread
                elif h[k] + spread >= sl[lv]:
                    px = sl[lv]
                else:
                    continue
            pnl = (px - ent[lv]) * d * lots[lv] * contract
            bal += pnl
            trades.append((lv, d, topen[lv], k, lots[lv], pnl, 1 if be[lv] else 4, 0.0))
            st[lv] = 0
        fl = 0.0
        for lv in range(NL):
            if st[lv] != 0:
                px = c[k] if st[lv] == 1 else c[k] + spread
                fl += (px - ent[lv]) * st[lv] * lots[lv] * contract
        eqc[k - k0] = bal + fl
    return trades, eqc, ruined, bal


# ------------------------------------------------------------------ harness
class Sim:
    def __init__(self, pair="XAUUSD", spread=0.30, risk=RISK_LIVE, lev=1000.0, disaster=8.0, m5=False,
                 contract=1.0, lotmin=0.1, lotstep=0.01):
        self.df = load(pair)
        self.P = build(self.df)
        self.o, self.h, self.l, self.c = (self.df[x].values for x in "ohlc")
        self.cfg = dict(spread=spread, risk=np.asarray(risk, float), lev=lev, disaster=disaster, m5=m5,
                        contract=contract, lotmin=lotmin, lotstep=lotstep)

    def run(self, start, end, start_eq=100.0, **over):
        cf = {**self.cfg, **over}
        t = self.df.index
        k0 = max(1, int(np.searchsorted(t, pd.Timestamp(start))))
        k1 = int(np.searchsorted(t, pd.Timestamp(end)))
        tr, eqc, ruined, bal = sim(self.o, self.h, self.l, self.c, *self.P, k0, k1, float(start_eq), cf["spread"],
                                   cf["risk"], cf["lev"], cf["disaster"], cf["m5"], cf["contract"], cf["lotmin"],
                                   cf["lotstep"])
        ent_eq = {(r[0], r[2]): r[7] for r in tr if r[6] == 9}
        T = pd.DataFrame([r[:7] for r in tr if r[6] != 9], columns=["lvl", "d", "ko", "kc", "lots", "pnl", "why"])
        T["tier"] = T.lvl.map(lambda v: TIER[v]); T["reason"] = T.why.map(REASON)
        T["open"] = t[T.ko.values]; T["close"] = t[T.kc.values]
        T["eq_in"] = [ent_eq.get((a, b), np.nan) for a, b in zip(T.lvl, T.ko)]
        m = (ruined - k0 + 1) if ruined >= 0 else len(eqc)
        eq = pd.Series(eqc[:m], index=t[k0:k0 + m])
        return T, eq, (t[ruined] if ruined >= 0 else None)


def pf(x):
    gp, gl = x[x > 0].sum(), -x[x < 0].sum()
    return gp / gl if gl else np.inf


def summary(T, eq, ruined, start_eq, label):
    dd = ((eq.cummax() - eq) / eq.cummax()).max() * 100
    print(f"{label}: net ${eq.iloc[-1] - start_eq:+,.0f} (end ${eq.iloc[-1]:,.0f}), PF {pf(T.pnl):.2f}, "
          f"{len(T)} trades, win {(T.pnl > 0).mean() * 100:.0f}%, max equity DD {dd:.1f}%"
          + (f", RUINED {ruined:%Y-%m-%d}" if ruined is not None else ""))
    for tier, g in T.groupby("tier"):
        print(f"    {tier:4s} n={len(g):4d} net ${g.pnl.sum():+10,.0f}  PF {pf(g.pnl):5.2f}  "
              + " ".join(f"{r}:{(g.reason == r).sum()}" for r in REASON.values() if (g.reason == r).any()))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", choices=["calibrate", "run", "roll"])
    ap.add_argument("--pair", default="XAUUSD")
    ap.add_argument("--from", dest="start", default="2023-04-15", help="run/roll: first start (server time)")
    ap.add_argument("--to", dest="end", default=None, help="run: end; roll: last day of data used")
    ap.add_argument("--start-eq", type=float, default=100.0)
    ap.add_argument("--months", type=int, default=12, help="roll: months each start runs")
    ap.add_argument("--step-days", type=int, default=7, help="roll: days between starts")
    ap.add_argument("--risk-scale", type=float, default=1.0, help="multiply every live risk band")
    ap.add_argument("--fixed-lot", action="store_true", help="every trade at the minimum lot (edge, no compounding)")
    ap.add_argument("--disaster", type=float, default=8.0, help="disaster stop, x ATR (live 8)")
    ap.add_argument("--m5", action="store_true", help="re-enable the M5 tier (off since 2026-09-23)")
    ap.add_argument("--spread", type=float, default=0.30, help="constant spread in price")
    ap.add_argument("--leverage", type=float, default=1000.0)
    ap.add_argument("--contract", type=float, default=1.0, help="oz per lot (XM Micro GOLDm# = 1)")
    ap.add_argument("--lot-min", type=float, default=0.1)
    a = ap.parse_args()

    risk = np.zeros_like(RISK_LIVE) if a.fixed_lot else RISK_LIVE * a.risk_scale
    s = Sim(a.pair, a.spread, risk, a.leverage, a.disaster, a.m5, a.contract, a.lot_min)
    last = s.df.index[-1]
    end = pd.Timestamp(a.end) if a.end else last

    if a.mode == "calibrate":
        ref = {2024: "MT5: ruined 2024-08-02", 2025: "MT5: +$14,646, PF 2.03", 2026: "MT5: +$13,295, PF 1.52 (to 09-19)"}
        for y, e in ((2024, "2025-01-01"), (2025, "2026-01-01"), (2026, "2026-09-20")):
            T, eq, ru = s.run(f"{y}-01-01", e, 100.0)
            summary(T, eq, ru, 100.0, f"{y} from $100   [{ref[y]}]")
    elif a.mode == "run":
        T, eq, ru = s.run(a.start, end, a.start_eq)
        if a.fixed_lot:
            per_oz = T.pnl / T.lots
            print(f"{a.start} .. {end:%Y-%m-%d} at the minimum lot: PF {pf(per_oz):.2f}, {len(T)} trades")
            for tier, g in T.groupby("tier"):
                print(f"    {tier:4s} n={len(g):4d} PF {pf(g.pnl / g.lots):5.2f}  ${(g.pnl / g.lots).sum():+,.0f} per oz")
        else:
            summary(T, eq, ru, a.start_eq, f"{a.start} .. {end:%Y-%m-%d} from ${a.start_eq:,.0f}")
            ye = eq.groupby(eq.index.year).last()
            print("    year-ends: " + " ".join(f"{y}:${v:,.0f}" for y, v in ye.items()))
    else:
        starts = pd.date_range(a.start, end - pd.DateOffset(months=a.months), freq=f"{a.step_days}D")
        ends, dds, ruins = [], [], 0
        for st in starts:
            T, eq, ru = s.run(st, st + pd.DateOffset(months=a.months), a.start_eq)
            ends.append(eq.iloc[-1]); dds.append(((eq.cummax() - eq) / eq.cummax()).max()); ruins += ru is not None
        ends, dds = np.array(ends), np.array(dds)
        print(f"{len(starts)} starts every {a.step_days} days, {starts[0]:%Y-%m-%d} .. {starts[-1]:%Y-%m-%d}, "
              f"{a.months} months each, from ${a.start_eq:,.0f} (starts overlap; not independent)")
        print(f"  ruined {ruins / len(starts) * 100:.0f}% | below start {np.mean(ends < a.start_eq) * 100:.0f}% | "
              f"end 10/25/50/75/90%: " + " / ".join(f"${np.percentile(ends, q):,.0f}" for q in (10, 25, 50, 75, 90))
              + f" | median max DD {np.median(dds) * 100:.0f}%")


if __name__ == "__main__":
    main()
