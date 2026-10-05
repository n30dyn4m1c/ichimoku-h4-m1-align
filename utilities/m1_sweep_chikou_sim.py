"""Simulator for experimental-m1-liquidity-sweep-chikou-ea.mq5 (notes §71). Sweep-then-turn on M1. An unraided swing (po3 rules: L/R, lookback LB) is raided by a wick;
the trade goes the OTHER way: low swept -> long, high swept -> short.
trig 0: the first chikou breakout in the reversal direction within W bars of the raid (raid bar incl.)
trig 1: the first close back inside the level within W bars (sweep and reject)
SL: the sweep extreme (furthest wick from the raid to the trigger bar) +/- slbuf*ATR.
TP: tpmode 0 = nearest unraided opposite level (needs RR >= minrr); tpmode>0 = fixed RR of tpmode.
Entry at the open after the trigger bar; $spread; SL first on a tie. Results in R.
minusd = minimum stop in price. placebo = seed: every sweep moved 500-5000 bars at random.
Usage (needs numpy, pandas, numba), from utilities/:
    from m1_sweep_chikou_sim import *;  P = prep()
    print(stats(go(P, 2023, 2026, W=90, minusd=2, tpmode=3)))"""
import numpy as np, pandas as pd
from numba import njit
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from m1_chikou_liquidity_sim import prep, stats, chik_clear, htf_state


@njit(cache=True)
def nearest_level(i, o, h, l, hi, trip, L, R, LB):
    best = np.nan
    reach = o[i + 1]
    for j in range(i, i - LB, -1):
        if j + R <= i and j - L >= 0:
            v = h[j] if hi else l[j]
            sw = True
            for q in range(1, L + 1):
                w = h[j - q] if hi else l[j - q]
                if (v <= w) if hi else (v >= w):
                    sw = False; break
            if sw:
                for q in range(1, R + 1):
                    w = h[j + q] if hi else l[j + q]
                    if (v < w) if hi else (v > w):
                        sw = False; break
            if sw:
                raided = (reach > v) if hi else (reach < v)
                ok = (v > trip) if hi else (v < trip)
                if not raided and ok:
                    if np.isnan(best) or ((v < best) if hi else (v > best)):
                        best = v
        w = h[j] if hi else l[j]
        reach = max(reach, w) if hi else min(reach, w)
    return best


@njit(cache=True)
def run(o, h, l, c, t, k, sa, sb, atr, hour, contig, allow, i0, i1, spread, L, R, LB,
        trig, W, slbuf, tpmode, minrr, minstop, maxstop, h0, h1, needprice, minusd, placebo):
    n = len(c)
    # chikou breakout state per bar
    st = np.zeros(n, np.int64)
    for i in range(max(i0 - 5, 60), i1):
        st[i] = chik_clear(i, c, h, l, t, k, sa, sb, True, needprice)
    # raid events: (bar, direction of the trade, level)
    ev_b = np.zeros(400000, np.int64); ev_d = np.zeros(400000, np.int64); ev_v = np.zeros(400000)
    ne = 0
    for j in range(max(i0 - LB, L), i1 - R - 1):
        for side in range(2):
            hi = side == 0          # swing high -> a raid of it gives a SHORT
            v = h[j] if hi else l[j]
            sw = True
            for q in range(1, L + 1):
                w = h[j - q] if hi else l[j - q]
                if (v <= w) if hi else (v >= w):
                    sw = False; break
            if sw:
                for q in range(1, R + 1):
                    w = h[j + q] if hi else l[j + q]
                    if (v < w) if hi else (v > w):
                        sw = False; break
            if not sw:
                continue
            # raided before confirmation is impossible (it would fail the right side)
            for e in range(j + R + 1, min(j + LB, i1 - 2)):
                w = h[e] if hi else l[e]
                if (w > v) if hi else (w < v):
                    if e >= i0 and ne < 400000:
                        ev_b[ne] = e; ev_d[ne] = -1 if hi else 1; ev_v[ne] = v; ne += 1
                    break
    if placebo > 0:
        np.random.seed(placebo)
        for x in range(ne):
            nb = ev_b[x] + np.random.randint(500, 5000)
            ev_b[x] = nb if nb < i1 - 100 else ev_b[x] - np.random.randint(500, 5000)
    order = np.argsort(ev_b[:ne], kind='mergesort')
    out_i = np.zeros(200000, np.int64); out_r = np.zeros(200000); out_d = np.zeros(200000, np.int64)
    out_rr = np.zeros(200000)
    nt = 0
    busy = -1
    lastsig = -1
    for oi in range(ne):
        x = order[oi]
        e = ev_b[x]; d = ev_d[x]; lv = ev_v[x]
        if e <= busy:
            continue
        lg = d == 1
        # find the trigger
        ti = -1
        ext = l[e] if lg else h[e]
        for i in range(e, min(e + W + 1, i1 - 2)):
            ext = min(ext, l[i]) if lg else max(ext, h[i])
            if trig == 0:
                if st[i] == d and st[i - 1] != d:
                    ti = i; break
            else:
                if (c[i] > lv) if lg else (c[i] < lv):
                    ti = i; break
        if ti < 0 or ti <= busy or ti == lastsig or not contig[ti]:
            continue
        if allow[ti] != 2 and allow[ti] != d:
            continue
        hr = hour[ti + 1]
        if h0 <= h1:
            if hr < h0 or hr >= h1:
                continue
        elif hr < h0 and hr >= h1:
            continue
        bid = o[ti + 1]; ask = bid + spread
        price = ask if lg else bid
        trip = bid if lg else ask
        sl = ext - slbuf * atr[ti] if lg else ext + slbuf * atr[ti] + spread
        risk = (price - sl) if lg else (sl - price)
        if risk <= 0:
            continue
        if risk < minusd:
            continue
        if minstop > 0 and risk < minstop * atr[ti]:
            continue
        if maxstop > 0 and risk > maxstop * atr[ti]:
            continue
        if tpmode == 0:
            tg = nearest_level(ti, o, h, l, lg, trip, L, R, LB)
            if np.isnan(tg):
                continue
            tp = tg
        else:
            tp = price + tpmode * risk if lg else price - tpmode * risk
        rew = (tp - price) if lg else (price - tp)
        if rew <= 0 or rew / risk < minrr:
            continue
        lastsig = ti
        res = np.nan
        b = ti + 1
        while b < i1:
            if lg:
                if b > ti + 1 and o[b] <= sl:
                    res = (o[b] - price) / risk; break
                if l[b] <= sl:
                    res = (sl - price) / risk; break
                if h[b] >= tp:
                    res = (tp - price) / risk; break
            else:
                if b > ti + 1 and o[b] + spread >= sl:
                    res = (price - o[b] - spread) / risk; break
                if h[b] + spread >= sl:
                    res = (price - sl) / risk; break
                if l[b] + spread <= tp:
                    res = (price - tp) / risk; break
            b += 1
        if np.isnan(res):
            continue
        out_i[nt] = ti; out_r[nt] = res; out_d[nt] = d; out_rr[nt] = rew / risk
        nt += 1
        busy = b
    return out_i[:nt], out_r[:nt], out_d[:nt], out_rr[:nt]


DEF = dict(spread=0.30, L=6, R=6, LB=100, trig=0, W=30, slbuf=0.0, tpmode=0, minrr=0.0,
           minstop=0.0, maxstop=0.0, h0=0, h1=24, needprice=False, allow=None, minusd=0.0, placebo=0)


def go(P, y0=2023, y1=2026, **kw):
    a = dict(DEF); a.update(kw)
    yr = P['year']
    i0 = int(np.searchsorted(yr, y0)); i1 = int(np.searchsorted(yr, y1 + 1))
    al = a['allow'] if a['allow'] is not None else np.full(len(P['c']), 2, np.int64)
    ii, r, d, rr = run(P['o'], P['h'], P['l'], P['c'], P['t'], P['k'], P['sa'], P['sb'], P['atr'],
                       P['hour'], P['contig'], al, i0, i1, a['spread'], a['L'], a['R'], a['LB'],
                       a['trig'], a['W'], a['slbuf'], a['tpmode'], a['minrr'], a['minstop'],
                       a['maxstop'], a['h0'], a['h1'], a['needprice'], a['minusd'], a['placebo'])
    return pd.DataFrame(dict(i=ii, r=r, d=d, rr=rr))
