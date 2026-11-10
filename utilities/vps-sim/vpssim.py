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
    python3 utilities/vps-sim/vpssim.py roll --start-eq 100 --fixes           # §73: the EA's default-on fixes
    python3 utilities/vps-sim/vpssim.py roll --start-eq 100 --one-pos         # §73: one review fix alone
    python3 utilities/vps-sim/vpssim.py roll --start-eq 100 --recommended --risk-scale 0.5   # §74
    python3 utilities/vps-sim/validate.py matrix                              # §74: the whole validation

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
# Notes §74. DEFECTS: the defect fixes the simulator can see (#1 one position, #3 peak since entry).
# RECOMMENDED: those plus #2 stop-aware sizing, the open-risk cap, the drawdown risk cut, Friday flat
# and the daily/weekly loss limits (the EA inputs are listed in PROMOTION.md).
DEFECTS = dict(one_pos=True, peak_entry=True)
RECOMMENDED = dict(DEFECTS, cloud_size=True, max_open_risk=30.0, dd_at=25.0, dd_factor=0.5, fri_flat=22,
                   daily_loss=5.0, weekly_loss=10.0)
REASON = {0: "kumo touch", 1: "BE/trail stop", 2: "superseded", 3: "stop-out", 4: "disaster stop",
          5: "weekend flat"}


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
def sim(o, h, l, c, A, FAR, NOW, CT, CB, ATR, BID, DAY, TOD, DOW, TMIN, SPR, k0, k1, start_eq, risk, lev,
        disaster_mult, m5tier, contract, lotmin, lotstep,
        one_pos, cloud_size, peak_entry, arm_peak, realign, minlot_gate, daily_loss,
        weekly_loss, max_open_risk, fri_stop, fri_flat, q_from, q_to, streak_n, pause_min,
        dd_at, dd_factor, exit_max_spread, max_spread):
    # Review-fix switches (notes §73), all False / 0 = the live build:
    #   one_pos     #1  a running tier blocks itself and every smaller tier
    #   cloud_size  #2  size on max(2 ATR, distance to the tier cloud), capped at the disaster stop
    #   peak_entry  #3  chandelier peak from M1 bars since entry, not the forming tier bar
    #   arm_peak    #4  the chandelier arms on the peak reached, not the bid at the minute open
    #   realign     #5  after a broker-side stop the tier must lose alignment before re-entering
    #   minlot_gate #10 skip (walk down) a tier whose minimum lot would risk more than this % (0 = off)
    #   daily_loss  #12 no entries for the rest of the day once equity is this % below its start (0 = off)
    # Revamp safety switches (notes §74), all 0 / -1 = the live build:
    #   weekly_loss      no entries for the rest of the week (Monday start) after this % loss
    #   max_open_risk    cap the lots so the loss at every hard stop on the symbol, the new trade's
    #                    disaster stop included, stays within this % of equity; skip a tier that cannot fit
    #   fri_stop         no new entries on Friday from this server hour
    #   fri_flat         close everything on Friday at this server hour, and no entries after it
    #   q_from, q_to     quiet window in minutes of the server day (may wrap midnight): no entries inside
    #   streak_n, pause_min   every loss that makes the run of losing trades >= streak_n pauses entries
    #   dd_at, dd_factor      risk x dd_factor while equity is dd_at % or more below its high-water mark
    #   exit_max_spread  the kumo-touch exit waits while the spread is above this (§73 #6)
    #   max_spread       the live entry gate InpMaxSpreadPoints (0.60); inert at the default 0.30 spread
    NL = 5
    st = np.zeros(NL, np.int64); lots = np.zeros(NL); ent = np.zeros(NL); sl = np.zeros(NL)
    pkH = np.zeros(NL); pkL = np.zeros(NL); be = np.zeros(NL, np.bool_); topen = np.zeros(NL, np.int64)
    bal = start_eq
    trades = []            # (level, dir, k_open, k_close, lots, pnl, reason, equity at entry)
    eqc = np.zeros(k1 - k0)
    runH = np.zeros((6,)); runL = np.zeros((6,)); lastbid = -np.ones(6, np.int64)
    ruined = -1
    pt = 0.01
    needR = np.zeros(NL, np.int64); dsl = np.zeros(NL)
    day = -1; day_eq = start_eq
    week = -1; week_eq = start_eq; hwm = start_eq; streak = 0; pause_until = -1
    for k in range(k0, k1):
        spread = SPR[k]
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
            if fri_flat >= 0 and DOW[k] == 4 and TOD[k] >= fri_flat * 60:
                px = bid if d == 1 else ask
                pnl = (px - ent[lv]) * d * lots[lv] * contract
                bal += pnl
                trades.append((lv, d, topen[lv], k, lots[lv], pnl, 5, 0.0))
                st[lv] = 0
                if pnl < 0:
                    streak += 1
                    if streak_n > 0 and streak >= streak_n:
                        pause_until = TMIN[k] + pause_min
                else:
                    streak = 0
                continue
            touch = (d == 1 and bid <= CT[tf, k]) or (d == -1 and ask >= CB[tf, k])
            if touch and not (exit_max_spread > 0 and spread > exit_max_spread):
                px = bid if d == 1 else ask
                pnl = (px - ent[lv]) * d * lots[lv] * contract
                bal += pnl
                trades.append((lv, d, topen[lv], k, lots[lv], pnl, 0, 0.0))
                st[lv] = 0
                if pnl < 0:
                    streak += 1
                    if streak_n > 0 and streak >= streak_n:
                        pause_until = TMIN[k] + pause_min
                else:
                    streak = 0
                continue
            a = ATR[tf, k]
            if not (a > 0):
                continue
            if peak_entry:
                if k - 1 >= topen[lv]:                  # bar k-1 lies wholly after the entry
                    pkH[lv] = max(pkH[lv], h[k - 1]); pkL[lv] = min(pkL[lv], l[k - 1])
                pkH[lv] = max(pkH[lv], bid); pkL[lv] = min(pkL[lv], bid)
            elif d == 1:
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
            if arm_peak:
                armed = (d == 1 and pkH[lv] >= ent[lv] + armA * a) or (d == -1 and pkL[lv] <= ent[lv] - armA * a)
            else:
                armed = (d == 1 and bid >= ent[lv] + armA * a) or (d == -1 and ask <= ent[lv] - armA * a)
            if armed:
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
        top = -1; tdir = 0; tlots = 0.0
        if DAY[k] != day:
            day = DAY[k]; day_eq = eq
        wk = (DAY[k] + 3) // 7                         # weeks starting on Monday
        if wk != week:
            week = wk; week_eq = eq
        if eq > hwm:
            hwm = eq
        blocked = daily_loss > 0 and eq <= day_eq * (1.0 - daily_loss / 100.0)
        if weekly_loss > 0 and eq <= week_eq * (1.0 - weekly_loss / 100.0):
            blocked = True
        if DOW[k] == 4 and ((fri_stop >= 0 and TOD[k] >= fri_stop * 60) or (fri_flat >= 0 and TOD[k] >= fri_flat * 60)):
            blocked = True
        if q_from != q_to:
            if q_from < q_to:
                if TOD[k] >= q_from and TOD[k] < q_to:
                    blocked = True
            elif TOD[k] >= q_from or TOD[k] < q_to:
                blocked = True
        if streak_n > 0 and TMIN[k] < pause_until:
            blocked = True
        if max_spread > 0 and spread > max_spread:
            blocked = True
        rscale = dd_factor if (dd_at > 0 and eq <= hwm * (1.0 - dd_at / 100.0)) else 1.0
        for lv in range(NL - 1, -1, -1):
            if blocked:
                break
            if st[lv] != 0:
                if one_pos:
                    break
                continue
            if lv == 0 and not m5tier:
                continue
            tf = lv + 1
            d = np.int64(A[0, k])
            okc = d != 0
            if okc:
                for j in range(1, tf + 1):
                    if A[j, k] != d:
                        okc = False; break
            if needR[lv] != 0:
                if okc and d == needR[lv]:
                    continue
                needR[lv] = 0
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
            a = ATR[tf, k]
            if not (a > 0 and eq > 0):
                top = lv; tdir = d; tlots = -1.0      # as before: picked, supersedes, opens nothing
                break
            dist = a * 2.0
            if cloud_size:
                cdist = (ask - CT[tf, k]) if d == 1 else (CB[tf, k] - bid)
                if cdist > dist:
                    dist = cdist
                dist = max(a * 2.0, min(dist, a * disaster_mult))
            rt = 2 if eq >= 13000 else (1 if eq >= 7000 else 0)
            lt = eq * risk[rt, lv] * rscale / 100.0 / (dist * contract)
            lt = np.floor(lt / lotstep + 1e-9) * lotstep
            if minlot_gate > 0 and risk[rt, lv] > 0 and lt < lotmin and lotmin * dist * contract / eq * 100.0 > minlot_gate:
                continue
            lt = max(lotmin, lt)
            if max_open_risk > 0:
                held = 0.0                              # loss at the stops of the tiers that stay open
                for j in range(lv + 1, NL):
                    if st[j] != 0:
                        pxj = bid if st[j] == 1 else ask
                        held += max(0.0, (pxj - sl[j]) * st[j]) * lots[j] * contract
                room = eq * max_open_risk / 100.0 - held
                maxl = np.floor(room / (a * disaster_mult * contract) / lotstep + 1e-9) * lotstep
                if maxl < lotmin:
                    continue
                if lt > maxl:
                    lt = maxl
            top = lv; tdir = d; tlots = lt
            break
        if top >= 0:
            for lv in range(top):
                if st[lv] != 0:
                    px = bid if st[lv] == 1 else ask
                    pnl = (px - ent[lv]) * st[lv] * lots[lv] * contract
                    bal += pnl
                    trades.append((lv, st[lv], topen[lv], k, lots[lv], pnl, 2, 0.0))
                    st[lv] = 0
                    if pnl < 0:
                        streak += 1
                        if streak_n > 0 and streak >= streak_n:
                            pause_until = TMIN[k] + pause_min
                    else:
                        streak = 0
            fl = 0.0; used = 0.0
            for lv in range(NL):
                if st[lv] != 0:
                    px = bid if st[lv] == 1 else ask
                    fl += (px - ent[lv]) * st[lv] * lots[lv] * contract
                    used += lots[lv] * contract * bid / lev
            eq = bal + fl
            a = ATR[top + 1, k]
            if a > 0 and eq > 0 and tlots > 0:
                lt = tlots
                price = ask if tdir == 1 else bid
                m1lot = contract * price / lev
                maxl = np.floor(((eq - used) * 0.8 / m1lot) / lotstep + 1e-9) * lotstep
                maxl = max(lotmin, maxl)
                if lt > maxl:
                    lt = maxl
                st[top] = tdir; lots[top] = lt; ent[top] = price; topen[top] = k
                sl[top] = price - tdir * disaster_mult * a; dsl[top] = sl[top]
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
            trades.append((lv, d, topen[lv], k, lots[lv], pnl, 1 if (be[lv] or sl[lv] != dsl[lv]) else 4, 0.0))
            st[lv] = 0
            if pnl < 0:
                streak += 1
                if streak_n > 0 and streak >= streak_n:
                    pause_until = TMIN[k] + pause_min
            else:
                streak = 0
            if realign:
                needR[lv] = d
        fl = 0.0
        for lv in range(NL):
            if st[lv] != 0:
                px = c[k] if st[lv] == 1 else c[k] + spread
                fl += (px - ent[lv]) * st[lv] * lots[lv] * contract
        eqc[k - k0] = bal + fl
    return trades, eqc, ruined, bal


# ------------------------------------------------------------------ harness
class Sim:
    # Every switch and its "off" value. hhmm() turns 2330 into minutes of the day.
    OFF = dict(one_pos=False, cloud_size=False, peak_entry=False, arm_peak=False, realign=False, minlot_gate=0.0,
               daily_loss=0.0, weekly_loss=0.0, max_open_risk=0.0, fri_stop=-1, fri_flat=-1, q_from=0, q_to=0,
               streak_n=0, pause_min=0, dd_at=0.0, dd_factor=1.0, exit_max_spread=0.0, max_spread=0.60,
               roll_spread=0.0)

    def __init__(self, pair="XAUUSD", spread=0.30, risk=RISK_LIVE, lev=1000.0, disaster=8.0, m5=False,
                 contract=1.0, lotmin=0.1, lotstep=0.01, **switches):
        self.df = load(pair)
        self.P = build(self.df)
        ix = self.df.index
        self.day = (ix.values.astype("datetime64[D]").astype(np.int64))
        self.tod = (ix.hour * 60 + ix.minute).values.astype(np.int64)
        self.dow = ix.dayofweek.values.astype(np.int64)
        self.tmin = ix.values.astype("datetime64[m]").astype(np.int64)
        self.o, self.h, self.l, self.c = (self.df[x].values for x in "ohlc")
        bad = set(switches) - set(self.OFF)
        if bad:
            raise TypeError(f"unknown switch: {sorted(bad)}")
        self.cfg = dict(spread=spread, risk=np.asarray(risk, float), lev=lev, disaster=disaster, m5=m5,
                        contract=contract, lotmin=lotmin, lotstep=lotstep, **{**self.OFF, **switches})

    def spread_series(self, spread, roll_spread):
        """Constant spread, or (--roll-spread) a stress model: that spread from 23:55 to 01:15 server
        time, the daily break and the minutes either side of it. Made up, not XM's history."""
        spr = np.full(len(self.o), float(spread))
        if roll_spread > 0:
            spr[(self.tod >= 23 * 60 + 55) | (self.tod < 75)] = roll_spread
        return spr

    def run(self, start, end, start_eq=100.0, **over):
        cf = {**self.cfg, **over}
        t = self.df.index
        k0 = max(1, int(np.searchsorted(t, pd.Timestamp(start))))
        k1 = int(np.searchsorted(t, pd.Timestamp(end)))
        tr, eqc, ruined, bal = sim(self.o, self.h, self.l, self.c, *self.P, self.day, self.tod, self.dow, self.tmin,
                                   self.spread_series(cf["spread"], cf["roll_spread"]), k0, k1, float(start_eq),
                                   np.asarray(cf["risk"], float), cf["lev"], cf["disaster"], cf["m5"], cf["contract"],
                                   cf["lotmin"], cf["lotstep"], cf["one_pos"], cf["cloud_size"], cf["peak_entry"],
                                   cf["arm_peak"], cf["realign"], float(cf["minlot_gate"]), float(cf["daily_loss"]),
                                   float(cf["weekly_loss"]), float(cf["max_open_risk"]), int(cf["fri_stop"]),
                                   int(cf["fri_flat"]), int(cf["q_from"]), int(cf["q_to"]), int(cf["streak_n"]),
                                   int(cf["pause_min"]), float(cf["dd_at"]), float(cf["dd_factor"]),
                                   float(cf["exit_max_spread"]), float(cf["max_spread"]))
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
    g = ap.add_argument_group("review fixes (notes §73; all off = the live build)")
    g.add_argument("--one-pos", action="store_true", help="#1 a running tier blocks itself and every smaller tier")
    g.add_argument("--cloud-size", action="store_true", help="#2 size on max(2 ATR, distance to the tier cloud)")
    g.add_argument("--peak-entry", action="store_true", help="#3 chandelier peak from bars since entry only")
    g.add_argument("--arm-peak", action="store_true", help="#4 chandelier arms on the peak reached")
    g.add_argument("--realign", action="store_true", help="#5 re-align before re-entering after a broker-side stop")
    g.add_argument("--minlot-gate", type=float, default=0.0, help="#10 skip a tier whose min lot risks more than this %%")
    g.add_argument("--daily-loss", type=float, default=0.0, help="#12 no entries for the day after this %% loss")
    g.add_argument("--fixes", action="store_true", help="the EA's default-on fixes together: #1 #3 #4")
    g = ap.add_argument_group("revamp safety switches (notes §74; all off = the live build)")
    g.add_argument("--weekly-loss", type=float, default=0.0, help="no entries for the week after this %% loss")
    g.add_argument("--max-open-risk", type=float, default=0.0,
                   help="cap lots so the loss at every hard stop on the symbol stays within this %% of equity")
    g.add_argument("--fri-stop", type=int, default=-1, help="no new entries on Friday from this server hour")
    g.add_argument("--fri-flat", type=int, default=-1, help="close everything on Friday at this server hour")
    g.add_argument("--quiet", default="", help="no entries inside this server-time window, e.g. 2330-0130")
    g.add_argument("--loss-streak", type=int, default=0, help="pause entries once this many trades in a row lost")
    g.add_argument("--pause-hours", type=float, default=24.0, help="length of the loss-streak pause")
    g.add_argument("--dd-at", type=float, default=0.0, help="cut risk while equity is this %% below its high")
    g.add_argument("--dd-factor", type=float, default=0.5, help="risk multiplier while in that drawdown")
    g.add_argument("--exit-max-spread", type=float, default=0.0, help="§73 #6: kumo exit waits above this spread")
    g.add_argument("--roll-spread", type=float, default=0.0,
                   help="stress model: this spread from 23:55 to 01:15 server time")
    g.add_argument("--recommended", action="store_true", help="the §74 recommended set (see RECOMMENDED)")
    a = ap.parse_args()
    if a.fixes:
        a.one_pos = a.peak_entry = a.arm_peak = True
    hhmm = lambda v: int(v) // 100 * 60 + int(v) % 100
    qf, qt = (hhmm(x) for x in a.quiet.split("-")) if a.quiet else (0, 0)
    fx = dict(one_pos=a.one_pos, cloud_size=a.cloud_size, peak_entry=a.peak_entry, arm_peak=a.arm_peak,
              realign=a.realign, minlot_gate=a.minlot_gate, daily_loss=a.daily_loss, weekly_loss=a.weekly_loss,
              max_open_risk=a.max_open_risk, fri_stop=a.fri_stop, fri_flat=a.fri_flat, q_from=qf, q_to=qt,
              streak_n=a.loss_streak, pause_min=int(a.pause_hours * 60) if a.loss_streak else 0, dd_at=a.dd_at,
              dd_factor=a.dd_factor, exit_max_spread=a.exit_max_spread, roll_spread=a.roll_spread)
    if a.recommended:
        fx.update(RECOMMENDED)

    risk = np.zeros_like(RISK_LIVE) if a.fixed_lot else RISK_LIVE * a.risk_scale
    s = Sim(a.pair, a.spread, risk, a.leverage, a.disaster, a.m5, a.contract, a.lot_min, **fx)
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
