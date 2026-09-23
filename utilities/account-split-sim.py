#!/usr/bin/env python3
"""Monte Carlo of the bottom-up stack's money management: one account vs
splitting profit into new accounts, and what to do once the accounts are
maxed out.

This is a MODEL, not a backtest. Trades are drawn from per-tier statistics
of the real-tick backtests in experiments/EXPERIMENTAL-NOTES.md (§47, §48,
§50) and sized the way the EA sizes them (risk % of equity by regime,
against a 2 x ATR reference distance, the broker's minimum lot, the 80%
free-margin cap). Every account on a path takes the SAME trades - same EA,
same symbol, same signals - so a bad year hits all of them at once.

Calibration (standard 0.01-lot account, live regime, $100 start): a good
year gives a ~$15k median (real 2025/2026: $13-15k); a 2024-like year from
$10k gives ~+44% (real: +50%) and ruins most $100 accounts (real: ruined).

Why withdrawing beats letting maxed accounts run: the risk regime is per
account. An account withdrawn back under a threshold keeps trading at the
higher regime's risk, and its gains leave as they are made; an account left
to grow passes $13k and sits in the smallest regime for good. Splitting
works for the same reason. Both are choices to take more risk.

Usage (defaults: XM Micro, 8 accounts, start $100, split at $5k into $1k
accounts, every account splits, 3 years, 400 paths):

    python3 utilities/account-split-sim.py
    python3 utilities/account-split-sim.py --years 2 --split-at 3000
    python3 utilities/account-split-sim.py --harvest-at 13000 --keep 5000
    python3 utilities/account-split-sim.py --compare-harvest

Needs numpy.
"""
import argparse
import numpy as np

# --- trade model (notes §47/§48/§50, the no-M5 live build on GOLDm#) -------
TIERS = ["M15", "M30", "H1", "H4"]
N_YR = np.array([715, 453, 255, 52])            # trades per year per tier
WIN = np.array([0.705, 0.76, 0.832, 0.838])     # win rate incl. BE scratches
PF_GOOD = np.array([1.27, 1.70, 1.80, 1.75])    # 2025/2026-like year
PF_BAD = np.array([0.87, 0.90, 1.08, 2.03])     # 2024-like year
ATR2 = np.array([9.0, 13.0, 22.0, 56.0])        # 2 x ATR per tier, $ of gold
GOLD_PRICE = 4000.0
RUIN = 5.0                                      # below this an account is dead

# risk % per tier (M15, M30, H1, H4) by equity regime (the live VPS build)
LIVE = [(0, [1, 5, 10, 20]), (7000, [.5, 2.5, 5, 10]), (13000, [.1, .2, 1, 2])]
FIVE = [(0, [1.25, 6.25, 12.5, 25]), (7000, [.625, 3.125, 6.25, 12.5]),
        (13000, [.25, .5, 2.5, 5]), (17000, [.125, .25, 1.25, 2.5]),
        (20000, [.0625, .125, .625, 1.25])]
REGIMES = {"live": LIVE, "five": FIVE}


class Model:
    def __init__(self, a, rng):
        self.a, self.rng = a, rng
        self.regime = REGIMES[a.regime]
        # $ moved per $1 of gold by one minimum-lot unit: 0.01 standard lot
        # = 1 oz; 0.1 micro lot = 0.1 oz
        oz = 0.1 if a.account == "micro" else 1.0
        self.unit_risk = ATR2 * oz                 # $ at the 2 x ATR distance
        self.unit_margin = oz * GOLD_PRICE / a.leverage

    def outcome_R(self, t, pf, n):
        """R multiples: losses lognormal (mean ~0.9R, capped at the 4R
        disaster stop), wins exponential with the mean that hits the PF."""
        w = WIN[t]
        win = self.rng.random(n) < w
        loss = np.minimum(self.rng.lognormal(np.log(0.75), 0.6, n), 4.0)
        gain = self.rng.exponential(pf * (1 - w) * 0.9 / w, n)
        return np.where(win, gain, -loss)

    def year(self):
        bad = self.rng.random() < self.a.p_bad
        pf = PF_BAD if bad else PF_GOOD
        ts, rs = [], []
        for t in range(4):
            n = self.rng.poisson(N_YR[t])
            ts.append(np.full(n, t)); rs.append(self.outcome_R(t, pf[t], n))
        ts = np.concatenate(ts); rs = np.concatenate(rs)
        o = self.rng.permutation(len(ts))
        return ts[o], rs[o]

    def risk(self, eq, t):
        pct = self.regime[0][1][t]
        for lo, p in self.regime:
            if eq >= lo:
                pct = p[t]
        return pct / 100

    def pnl(self, eq, t, r):
        units = max(np.floor(eq * self.risk(eq, t) / self.unit_risk[t]), 1.0)
        units = min(units, np.floor(0.8 * eq / self.unit_margin))
        if units < 1:
            return 0.0
        return max(units * self.unit_risk[t] * r, -eq)

    def path(self):
        """One simulated path. Returns (accounts total, banked, live accounts,
        dead accounts)."""
        a = self.a
        accts, bank, dead = [a.start], 0.0, 0
        for _ in range(a.years):
            for t, r in zip(*self.year()):
                new = []
                live = sum(1 for x in accts if x >= RUIN)
                for i, eq in enumerate(accts):
                    if eq < RUIN:
                        continue
                    eq += self.pnl(eq, t, r)
                    if eq < RUIN:
                        dead += 1; bank += max(eq, 0.0); accts[i] = 0.0
                        live -= 1
                        continue
                    maxed = live + len(new) >= a.max_accounts
                    if a.split_at and eq >= a.split_at and not maxed and \
                            (a.mode == "all" or i == max(j for j, x in enumerate(accts) if x >= RUIN)):
                        eq -= a.child; new.append(a.child)
                    elif a.harvest_at and eq >= a.harvest_at and \
                            (maxed or not a.split_at):
                        bank += eq - a.keep; eq = a.keep
                    accts[i] = eq
                accts += new
        return sum(x for x in accts if x >= RUIN), bank, \
            sum(1 for x in accts if x >= RUIN), dead


def run(a, label=None):
    rng = np.random.default_rng(a.seed)
    m = Model(a, rng)
    res = np.array([m.path() for _ in range(a.paths)])
    total = res[:, 0] + res[:, 1]
    q = np.percentile(total, [10, 25, 50, 75, 90])
    bq = np.percentile(res[:, 1], [10, 50, 90])
    print(f"{label or describe(a)}")
    print(f"  total   P10 {q[0]:>10,.0f}  P25 {q[1]:>10,.0f}  median {q[2]:>10,.0f}"
          f"  P75 {q[3]:>10,.0f}  P90 {q[4]:>10,.0f}   P(<start) {np.mean(total < a.start):5.1%}")
    print(f"  banked  P10 {bq[0]:>10,.0f}  median {bq[1]:>10,.0f}  P90 {bq[2]:>10,.0f}"
          f"   accounts {res[:, 2].mean():.1f} live, {res[:, 3].mean():.1f} died")


def describe(a):
    s = f"{a.account}, {a.regime} regime, {a.years}y, start ${a.start:,.0f}"
    if a.split_at:
        s += f", split at ${a.split_at:,.0f} into ${a.child:,.0f} ({a.mode}), max {a.max_accounts}"
    if a.harvest_at:
        s += f", harvest at ${a.harvest_at:,.0f} down to ${a.keep:,.0f}"
    return s


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--account", choices=["micro", "standard"], default="micro",
                   help="micro: 0.1 oz minimum (XM Micro); standard: 1 oz (0.01 lot)")
    p.add_argument("--regime", choices=list(REGIMES), default="live")
    p.add_argument("--years", type=int, default=3)
    p.add_argument("--paths", type=int, default=400)
    p.add_argument("--seed", type=int, default=11)
    p.add_argument("--start", type=float, default=100.0, help="first account's deposit")
    p.add_argument("--split-at", type=float, default=5000.0, help="0 = never split")
    p.add_argument("--child", type=float, default=1000.0, help="new account's starting equity")
    p.add_argument("--mode", choices=["all", "chain"], default="all",
                   help="all: every account splits; chain: only the newest")
    p.add_argument("--max-accounts", type=int, default=8)
    p.add_argument("--harvest-at", type=float, default=0.0,
                   help="once the accounts are maxed, withdraw when an account reaches this (0 = never)")
    p.add_argument("--keep", type=float, default=5000.0, help="equity left after a harvest")
    p.add_argument("--p-bad", type=float, default=1 / 3, help="chance a year is 2024-like")
    p.add_argument("--leverage", type=float, default=1000.0)
    p.add_argument("--compare-harvest", action="store_true",
                   help="run the what-to-do-once-maxed comparison")
    a = p.parse_args()

    if not a.compare_harvest:
        run(a)
        return
    for h, k, label in [(0, 0, "no withdrawals - let the accounts run"),
                        (13000, 13000, "withdraw everything above $13k"),
                        (13000, 7000, "at $13k, withdraw down to $7k"),
                        (13000, 5000, "at $13k, withdraw down to $5k"),
                        (7000, 5000, "at $7k, withdraw down to $5k")]:
        a.harvest_at, a.keep = h, k
        run(a, label)


if __name__ == "__main__":
    main()
