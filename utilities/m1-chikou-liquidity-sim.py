"""Simulator for experimental-m1-chikou-liquidity-ea.mq5 (notes §70), on the vps-sim data.
Gold M1 bid bars from HistData. Usage (needs numpy, pandas, numba):
    m = runpy.run_path("utilities/m1-chikou-liquidity-sim.py")
    P = m["prep"]();  print(m["stats"](m["go"](P, 2025, 2026, slmode=2)))
Decision on closed bar i, entry at the open of i+1 (buy at bid+spread). Exits on bid bars,
a sell's stops checked against ask = bid + spread. SL and TP in the same bar -> SL.
Results in R (risk = entry-to-stop distance), spread included."""
import os, sys, numpy as np, pandas as pd
from numba import njit
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'vps-sim'))
from vpssim import load

K = 26

def prep():
    df = load()
    h, l, c, o = df.h.values, df.l.values, df.c.values, df.o.values
    mid = lambda n: ((df.h.rolling(n).max() + df.l.rolling(n).min()) / 2).values
    t, k = mid(9), mid(26)
    fa = (t + k) / 2; fb = mid(52)
    sa = np.r_[np.full(K, np.nan), fa[:-K]]; sb = np.r_[np.full(K, np.nan), fb[:-K]]
    tr = np.maximum.reduce([h - l, np.abs(h - np.r_[np.nan, c[:-1]]), np.abs(l - np.r_[np.nan, c[:-1]])])
    atr = pd.Series(tr).rolling(14).mean().values
    hour = df.index.hour.values.astype(np.int64)
    year = df.index.year.values.astype(np.int64)
    dow = df.index.dayofweek.values.astype(np.int64)
    # gap guard: bar i+1 must follow bar i by one minute (no weekend/holiday gap)
    ts = df.index.values.astype('datetime64[m]').astype(np.int64)
    contig = np.r_[ts[1:] - ts[:-1] == 1, False]
    return dict(o=o, h=h, l=l, c=c, t=t, k=k, sa=sa, sb=sb, atr=atr, hour=hour, year=year,
                dow=dow, contig=contig, idx=df.index)


@njit(cache=True)
def blocks(v, a, b):
    if np.isnan(v):
        return False
    if b > a:
        return v > a and v < b
    return v < a and v > b


@njit(cache=True)
def chik_clear(i, c, h, l, t, k, sa, sb, both, needprice):
    j = i - 26
    if j < 0:
        return 0
    ct = max(sa[j], sb[j]); cb = min(sa[j], sb[j])
    if np.isnan(ct) or np.isnan(t[j]):
        return 0
    up_l = (c[i] > t[j] and c[i] > k[j]) if both else (c[i] > t[j] or c[i] > k[j])
    dn_l = (c[i] < t[j] and c[i] < k[j]) if both else (c[i] < t[j] or c[i] < k[j])
    r = 0
    if c[i] > ct and c[i] > h[j] and up_l:
        r = 1
    elif c[i] < cb and c[i] < l[j] and dn_l:
        r = -1
    if r != 0 and needprice:      # optional: price itself beyond tenkan, kijun and cloud
        pct = max(sa[i], sb[i]); pcb = min(sa[i], sb[i])
        if r == 1 and not (c[i] > t[i] and c[i] > k[i] and c[i] > pct):
            r = 0
        if r == -1 and not (c[i] < t[i] and c[i] < k[i] and c[i] < pcb):
            r = 0
    return r


@njit(cache=True)
def run(o, h, l, c, t, k, sa, sb, atr, hour, contig, i0, i1, spread,
        L, R, LB, freebars, pricefree, formfree, both, needprice,
        slmode, slbufatr, minrr, minstopatr, maxstopatr, h0, h1, beR, maxbars, tpfrac, allow, fade):
    out_i = np.zeros(200000, np.int64); out_r = np.zeros(200000); out_d = np.zeros(200000, np.int64)
    out_rr = np.zeros(200000); out_sd = np.zeros(200000)
    nt = 0
    busy_until = -1
    prev = 0
    for i in range(max(i0, 200), i1 - 2):
        cur = chik_clear(i, c, h, l, t, k, sa, sb, both, needprice)
        brk = cur != 0 and cur != prev
        prev = cur
        if not brk or i <= busy_until or not contig[i]:
            continue
        hr = hour[i + 1]
        if h0 <= h1:
            if hr < h0 or hr >= h1:
                continue
        else:
            if hr < h0 and hr >= h1:
                continue
        d = -cur if fade else cur
        if allow[i] != 2 and allow[i] != d:
            continue
        hi = d == 1
        bid = o[i + 1]; ask = bid + spread
        price = ask if hi else bid
        trip = bid if hi else ask
        # confirmed unraided level: swing j with j+R <= i, unraided by bars j+1..i and the live open
        best = np.nan
        reach = o[i + 1] if hi else o[i + 1] + 0.0
        if not hi:
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
        if np.isnan(best):
            continue
        tgt = best
        # free to move
        free = True
        if pricefree:
            if blocks(t[i], price, tgt) or blocks(k[i], price, tgt) or blocks(sa[i], price, tgt) or blocks(sb[i], price, tgt):
                free = False
        if free:
            for q in range(freebars):
                j = i - 26 + 1 + q
                cv = h[j] if hi else l[j]
                if blocks(cv, c[i], tgt) or blocks(t[j], c[i], tgt) or blocks(k[j], c[i], tgt) \
                   or blocks(sa[j], c[i], tgt) or blocks(sb[j], c[i], tgt):
                    free = False; break
        if free and formfree:
            for jj in range(1, R):            # shifts 2..R  ->  bars i-1 .. i-R+1
                j = i - jj
                v = h[j] if hi else l[j]
                ok = True
                for q in range(1, L + 1):
                    w = h[j - q] if hi else l[j - q]
                    if (v <= w) if hi else (v >= w):
                        ok = False; break
                if ok:
                    for q in range(j + 1, i + 1):
                        w = h[q] if hi else l[q]
                        if (w > v) if hi else (w < v):
                            ok = False; break
                    w = o[i + 1]
                    if (w > v) if hi else (w < v):
                        ok = False
                if ok and blocks(v, price, tgt):
                    free = False; break
        if not free:
            continue
        # stop
        kij = k[i]
        far = min(sa[i], sb[i]) if hi else max(sa[i], sb[i])
        kok = (kij < trip) if hi else (kij > trip)
        cok = (far < trip) if hi else (far > trip)
        line = np.nan
        if slmode == 0:
            if kok: line = kij
        elif slmode == 1:
            if cok: line = far
        else:
            if kok and cok:
                line = min(kij, far) if hi else max(kij, far)
            elif kok:
                line = kij
            elif cok:
                line = far
        if np.isnan(line):
            continue
        buf = slbufatr * atr[i]
        sl = line - buf if hi else line + buf
        risk = (price - sl) if hi else (sl - price)
        if risk <= 0:
            continue
        if minstopatr > 0 and risk < minstopatr * atr[i]:
            continue
        if maxstopatr > 0 and risk > maxstopatr * atr[i]:
            continue
        tp = price + tpfrac * (tgt - price)
        rew = (tp - price) if hi else (price - tp)
        if rew <= 0 or rew / risk < minrr:
            continue
        # walk
        res = np.nan
        be = False
        curs = sl
        e = i + 1
        endb = min(i1 - 1, i + 1 + maxbars) if maxbars > 0 else i1 - 1
        while e <= endb:
            if hi:
                if e > i + 1 and o[e] <= curs:
                    res = (o[e] - price) / risk; break
                if l[e] <= curs:
                    res = (curs - price) / risk; break
                if h[e] >= tp:
                    res = (tp - price) / risk; break
                if beR > 0 and not be and h[e] - price >= beR * risk:
                    be = True; curs = price + 0.1 * spread
            else:
                if e > i + 1 and o[e] + spread >= curs:
                    res = (price - o[e] - spread) / risk; break
                if h[e] + spread >= curs:
                    res = (price - curs) / risk; break
                if l[e] + spread <= tp:
                    res = (price - tp) / risk; break
                if beR > 0 and not be and price - (l[e] + spread) >= beR * risk:
                    be = True; curs = price - 0.1 * spread
            e += 1
        if np.isnan(res):
            ex = c[min(e, i1 - 1)]
            res = ((ex - price) if hi else (price - ex - spread)) / risk
        out_i[nt] = i; out_r[nt] = res; out_d[nt] = d; out_rr[nt] = rew / risk; out_sd[nt] = risk
        nt += 1
        busy_until = e
    return out_i[:nt], out_r[:nt], out_d[:nt], out_rr[:nt], out_sd[:nt]


DEF = dict(spread=0.30, L=6, R=6, LB=100, freebars=9, pricefree=True, formfree=True, both=True,
           needprice=False, slmode=0, slbufatr=0.0, minrr=0.0, minstopatr=0.0, maxstopatr=0.0,
           h0=0, h1=24, beR=0.0, maxbars=0, tpfrac=1.0, allow=None, fade=False)


def go(P, y0=2023, y1=2026, **kw):
    a = dict(DEF); a.update(kw)
    yr = P['year']
    i0 = int(np.searchsorted(yr, y0)); i1 = int(np.searchsorted(yr, y1 + 1))
    ii, r, d, rr, sd = run(P['o'], P['h'], P['l'], P['c'], P['t'], P['k'], P['sa'], P['sb'], P['atr'],
                           P['hour'], P['contig'], i0, i1, a['spread'], a['L'], a['R'], a['LB'],
                           a['freebars'], a['pricefree'], a['formfree'], a['both'], a['needprice'],
                           a['slmode'], a['slbufatr'], a['minrr'], a['minstopatr'], a['maxstopatr'],
                           a['h0'], a['h1'], a['beR'], a['maxbars'], a['tpfrac'],
                           a['allow'] if a['allow'] is not None else np.full(len(P['c']), 2, np.int64), a['fade'])
    return pd.DataFrame(dict(i=ii, r=r, d=d, rr=rr, sd=sd))


def stats(df):
    if len(df) == 0:
        return "0 trades"
    w = df.r[df.r > 0].sum(); ls = -df.r[df.r < 0].sum()
    pf = w / ls if ls > 0 else np.inf
    eq = df.r.cumsum(); dd = (eq.cummax() - eq).max()
    return "n=%5d win=%4.1f%% exp=%+.3fR tot=%+7.1fR PF=%.2f maxDD=%.1fR" % (
        len(df), 100 * (df.r > 0).mean(), df.r.mean(), df.r.sum(), pf, dd)


def htf_state(P, rule):
    """Per M1 bar, the CheckAlign-style direction (price+chikou beyond tenkan, kijun, cloud)
    of the last CLOSED bar of timeframe rule ('1h','4h'). 0 = none -> mapped to 'no trade'."""
    df = pd.DataFrame(dict(o=P['o'], h=P['h'], l=P['l'], c=P['c']), index=P['idx'])
    b = df.resample(rule, label='left', closed='left').agg(dict(o='first', h='max', l='min', c='last')).dropna()
    mid = lambda n: (b.h.rolling(n).max() + b.l.rolling(n).min()) / 2
    t, k = mid(9), mid(26); sa = ((t + k) / 2).shift(26); sb = mid(52).shift(26)
    ct, cb = np.fmax(sa, sb), np.fmin(sa, sb)
    s26 = lambda x: x.shift(26)
    up = (b.c > t) & (b.c > k) & (b.c > ct) & (b.c > s26(b.h)) & (b.c > s26(t)) & (b.c > s26(k)) & (b.c > s26(ct))
    dn = (b.c < t) & (b.c < k) & (b.c < cb) & (b.c < s26(b.l)) & (b.c < s26(t)) & (b.c < s26(k)) & (b.c < s26(cb))
    st = up.astype(int) - dn.astype(int)
    st.index = st.index + pd.Timedelta(rule)          # known once the bar has closed
    m = st.reindex(P['idx'], method='ffill').fillna(0).values.astype(np.int64)
    # the decision on M1 bar i is made at the open of i+1: shift by one minute is close enough
    m[m == 0] = 0
    return m
