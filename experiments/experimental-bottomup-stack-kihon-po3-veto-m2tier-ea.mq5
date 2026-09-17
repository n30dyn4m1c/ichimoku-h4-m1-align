//+------------------------------------------------------------------+
//| Ichimoku Bottom-Up Stack EA — KIHON + PO3 + VETOES + M2 TIER      |
//|                                                                  |
//| A fork of the kihon + PO3 + veto build                            |
//| (experimental-bottomup-stack-kihon-po3-veto-ea.mq5, magic          |
//| 20260867), which forks the kihon-suchi + PO3 gate experiment       |
//| (20260865), which forks the live VPS build (20260858). The         |
//| M1-strict cloud bias, the robustness pack (R2-R6), the daily H1    |
//| kihon time gate, the PO3 room/target gate and the two location     |
//| vetoes are all unchanged from that parent. What is new here is a   |
//| SIXTH TRADABLE TIER: M2, below M5.                                 |
//|                                                                  |
//| The entry chain it joins, unchanged and still five questions,      |
//| cheapest first:                                                   |
//|                                                                  |
//|   GATE 1 — TIME      : is a kihon suchi turn due, within +/-2?    |
//|   GATE 2 — STRUCTURE : does Ichimoku point a direction? (parent)  |
//|   GATE 3 — PRICE     : is there a PO3 level worth acting on, and  |
//|                        is there room to it?                       |
//|   GATE 4 — REACTION  : has price just been REJECTED at a major    |
//|                        PO3 level?                                 |
//|   GATE 5 — LOCATION  : is price on the right side of the PO3      |
//|                        dealing range?              (off by        |
//|                                                     default)      |
//|                                                                  |
//| Gates 1, 4 and 5 are market-wide (they do not depend on the        |
//| tier); gates 2 and 3 are per-tier — and there is now one more      |
//| tier for them to judge.                                           |
//|                                                                  |
//|------------------------------------------------------------------|
//| THE M2 TIER — WHAT CHANGED, AND WHY IT IS NOT JUST A SETTING     |
//|                                                                  |
//| The parent has M2 as a RUNG: a step inside the higher tiers'      |
//| chains, with no risk row, no ATR handle and no exits of its own.  |
//| This build makes M2 a TIER as well: M1 + M2 aligned opens an M2   |
//| trade that is managed exactly as an M5 trade is.                  |
//|                                                                  |
//| The two roles are INDEPENDENT switches (InpUseM2, InpM2Tier) and  |
//| both are on by default, so out of the box the stack is:           |
//|                                                                  |
//|   M2 tier  <- M1 + M2              (the new bottom)              |
//|   M5 tier  <- M1 + M2 + M5                                       |
//|   M15 tier <- M1 + M2 + M5 + M15                                 |
//|   ... and so on up to H4.                                        |
//|                                                                  |
//| Because levels are addressed by INDEX (0 = bottom), adding a tier |
//| at the bottom renumbered all five existing ones: M5 moved from    |
//| level 0 to level 1, H1 from 3 to 4, and so on. Every site that    |
//| hardcoded a level number had to move with it — the risk table,    |
//| the M1-full-cloud special case, the H1/H4 break-even bucket and   |
//| the H1-bias tier ceiling. The four that matter are named          |
//| (LVL_M2, LVL_M5, LVL_H1) rather than left as bare numbers.        |
//|                                                                  |
//| THE RUNG SKIP IS THE SUBTLE ONE. ChainAligned skips the M2 step   |
//| when the rung is inactive. With M2 as the bottom tier, that same  |
//| skip would have applied to the M2 tier's own chain — which IS M2  |
//| — leaving it validating on M1 alone and opening M2 trades on one  |
//| timeframe. The skip is now level-aware (`t < topIdx`), so it      |
//| cannot fire for the M2 tier and still does exactly what it did    |
//| for every tier above it.                                          |
//|                                                                  |
//| A symbol without an M2 feed loses BOTH roles and keeps the other  |
//| five tiers, the same non-fatal stance the rung already took.      |
//|                                                                  |
//|------------------------------------------------------------------|
//| GATE 1 — KIHON SUCHI TIME                                        |
//|                                                                  |
//| The Ichimoku basic time numbers, counted in candles from a        |
//| calendar anchor. Ported verbatim from experiments/po3-levels.mq5  |
//| (the PO3 + kihon indicator), so the EA and the chart agree on     |
//| what "on a kihon number" means.                                   |
//|                                                                  |
//|   9, 17, 26               simple (tanjun kihon suchi)            |
//|   33, 42, 51, 65, 76,     compound (fukugo kihon suchi)          |
//|   129, 172, 226, 257                                             |
//|                                                                  |
//| Counting is INCLUSIVE at both ends: the candle you start from is  |
//| candle 1, not candle 0. That one convention is the whole of the   |
//| arithmetic — two 17-spans laid end to end do not make 34, because |
//| the last candle of the first span IS the first candle of the      |
//| second: 17 + 17 - 1 = 33. Every compound number chains simple     |
//| spans that share their turning candle. 26 is the exception and    |
//| the only number that does not come out of that rule — it is a     |
//| calendar given (a month of trading days under the six-day week    |
//| Japan kept when this was written), and the rule builds on it.     |
//|                                                                  |
//| THE +/-2 RANGE. A kihon number is where a move is DUE to change   |
//| character, not the instant it must. So the gate does not require  |
//| an exact hit: it measures the signed distance from the count to   |
//| the NEAREST kihon number and accepts it within InpTimeTol         |
//| (default 2) either side.                                         |
//|                                                                  |
//| Nearest, not next, and either side, because a turn that was due   |
//| at 26 is not cancelled by the candle after it — a count two       |
//| candles PAST 26 is as much "around 26" as one two candles short.  |
//| The sign reads the way the chart does: negative is still short    |
//| of the number, positive is just past it.                          |
//|                                                                  |
//| Because the tolerance is in CANDLES OF THAT TIMEFRAME, the window |
//| scales itself: +/-2 on H4 is +/-8 hours, on M15 it is +/-30        |
//| minutes. No extra "sticky" state is needed — the window is the    |
//| tolerance.                                                        |
//|                                                                  |
//| ONE RULE, HARDCODED: THE DAILY H1 SETUP. Count H1 candles from     |
//| the DAY open and open the gate when that count is within           |
//| InpTimeTol of 9 or of 17.                                          |
//|                                                                  |
//| 9 and 17 are the only two kihon numbers a trading day can         |
//| deliver, because a day holds about 23-24 H1 candles. They are a    |
//| hardcoded PAIR rather than "the simple numbers" (which would be    |
//| 9, 17 AND 26) because of 26: a nearest-number test measures         |
//| distance and does not care that a number is out of reach, so on     |
//| the LAST candle of the day a {9,17,26} series reports "26, +2" and  |
//| opens the gate on a number the count never reached and never could. |
//| The tolerance that makes the gate useful for 9 and 17 is exactly     |
//| what makes it fire there. Measured on a 24-candle day: {9,17,26}    |
//| opens the gate on candles 7-11, 15-19 AND 24; {9,17} opens it on    |
//| 7-11 and 15-19 only. See the note on KihonDayH1.                    |
//|                                                                  |
//| With InpTimeTol at 2 that is candles 7-11 and 15-19 of the daily    |
//| count — 10 of a day's ~23-24 candles, so roughly 40% of the         |
//| session. Drop the tolerance to 0 to take only 9 and 17 exactly.     |
//|                                                                  |
//| THERE IS NO LADDER ANY MORE. An earlier version read a list of     |
//| TF:ANCHOR rungs judged N-of-M, which was the right shape while the  |
//| rungs were being chosen; the choice has been made, so the ladder    |
//| string, its parser, the rung arrays, the N-of-M count and the clamp |
//| that guarded it are all gone. That machinery also carried the cost  |
//| that dominated a backtest — every rung meant an anchor lookup and a |
//| Bars() window per symbol per M1 bar — and one fixed rule is a       |
//| single window. The multi-rung version is preserved in commit        |
//| c220059 if rungs are ever wanted back.                             |
//|                                                                  |
//| An unknown count (history still loading, or no D1 bar yet) is NOT  |
//| a pass: the gate cannot be evaluated, and an unevaluable filter     |
//| blocks rather than waves the trade through, the same stance the     |
//| cloud gate takes on unreadable buffers. It clears itself as soon as |
//| the history lands.                                                 |
//|                                                                  |
//|------------------------------------------------------------------|
//| GATE 3 — PO3 LEVELS                                              |
//|                                                                  |
//| Power-of-three levels: the grid is m x 3^n, and the rule that     |
//| makes it a ladder rather than a list is that the grids NEST —     |
//| every 27 level sits exactly on a 9 level — so a level's strength  |
//| is the HIGHEST power that lands on it.                            |
//|                                                                  |
//| That has a closed form, which is what makes it cheap enough to    |
//| run on every entry:                                               |
//|                                                                  |
//|     strength(R) = 3 ^ v3(R)                                       |
//|                                                                  |
//| where v3(R) is how many times R divides by 3. Gold at 4374        |
//| divides by 3 seven times, so it is a 2187 level — the same answer |
//| the indicator reaches by drawing every ticked grid and letting    |
//| the strongest one win, and the same label it writes on the line.  |
//| The EA therefore names levels exactly as the chart does.          |
//|                                                                  |
//| Two consequences the gate uses:                                   |
//|   1. The levels of power >= k are exactly the multiples of 3^k.   |
//|      So "the next level worth considering" is the next multiple   |
//|      of 3^k — one division, no grid walking.                      |
//|   2. Its ACTUAL power may be higher than k (a multiple of 243     |
//|      that is also a multiple of 729 IS a 729 level). The EA       |
//|      resolves and journals the real power, so a target that is    |
//|      stronger than the minimum is visible as such.                |
//|                                                                  |
//| WHAT IT DOES WITH THAT — gate 3 is a TP TARGET and a ROOM FILTER, |
//| and nothing else (this build does not fade levels or trade their  |
//| breakouts; PO3 supplies the exit and the veto, structure supplies |
//| the direction):                                                   |
//|                                                                  |
//|   * ROOM. Distance to the next level is measured in units of the  |
//|     same reference risk the sizing uses — ATR(tier TF) x          |
//|     InpRiskATRMult. Closer than InpPO3MinRR x that and price is   |
//|     trading INTO a level: the entry is skipped                    |
//|     (InpPO3RoomFilter, on by default).                            |
//|   * TARGET. Within the RR band [InpPO3MinRR, InpPO3MaxRR] the     |
//|     level becomes the trade's take profit, placed                |
//|     InpPO3BufferATR x ATR in FRONT of it so the fill happens      |
//|     before the level itself can reject price.                     |
//|   * RUNNER. Further than InpPO3MaxRR, the level is too far to be  |
//|     a target, so the trade opens with no TP and is left to the    |
//|     parent's exits (kumo touch, BE, chandelier) — a runner.       |
//|                                                                  |
//| A TP that the broker rejects (inside its minimum stop distance,   |
//| or on the wrong side of entry) degrades to a runner rather than   |
//| failing the entry, the same way the disaster stop degrades.       |
//|                                                                  |
//| THE REACTION IS USED AS A VETO, NOT AS AN ENTRY. This is the one  |
//| place this fork departs from its parent's stated stance. The      |
//| parent recorded fade and break-and-hold ENTRIES as deliberately   |
//| not implemented, and that warning still stands — they are not     |
//| added here either. Gate 4 is the other half of the same           |
//| observation: a kihon time landing on a strong PO3 level is where  |
//| a move often reverses, so an entry INTO a level that has just     |
//| rejected price is refused, while entries away from it are still   |
//| allowed. It restricts entries; it generates none. Two things are  |
//| worth reading before anyone touches it:                           |
//|   * §7 of EXPERIMENTAL-NOTES measured the analogous fade at the   |
//|     H4 Kijun and it won 0/13 — fading a breakout back, even with  |
//|     high ADX or a large extension, lost every time. The SAME      |
//|     level-touch entered WITH the trend won 61.6% against 26.5%    |
//|     for the opposite close. The reversal and the continuation are |
//|     not symmetric, which is why the veto is DIRECTIONAL rather    |
//|     than a flat block on both sides.                              |
//|   * §1 already implements this as a directional VETO (PO3Bias:    |
//|     price acting off a major level allows only trades away from   |
//|     it). Gate 4 is that function ported onto this build's level   |
//|     arithmetic, and §1 remains the reference implementation.      |
//|                                                                  |
//| WHY THE POWER IS PER TIER. The band is relative to ATR, so it is  |
//| tier-sensitive by construction, and the tiers differ by about an  |
//| order of magnitude: on gold ATR(M5) is a couple of dollars and    |
//| ATR(H4) a few dozen. One global power fails in opposite           |
//| directions at the two ends. Simulating the rr each tier sees, on  |
//| ATR scaled as sqrt(TF) from an assumed ATR(M5) of 2.0 dollars:    |
//|                                                                  |
//|   power 3 (step 27) for EVERY tier — the share of price           |
//|   positions where the room filter reads "no room" and blocks:     |
//|     M2 14%, M5 22%, M15 38%, M30 54%, H1 77%, H4 100%             |
//|   so the H4 tier would never trade again, and H1 nearly never.    |
//|                                                                  |
//|   InpPO3Power = "3,3,3,4,4,5" (the default here) instead:         |
//|     tier  ref risk  step  no room / target / runner               |
//|     M2       2.53     27     14%  /  86%  /   0%   (M2 is the new |
//|     M5       4.00     27     22%  /  78%  /   0%    bottom tier)  |
//|     M15      6.93     27     38%  /  62%  /   0%                  |
//|     M30      9.80     81     18%  /  79%  /   3%                  |
//|     H1      13.86     81     26%  /  74%  /   0%                  |
//|     H4      27.71    243     17%  /  74%  /   9%                  |
//|                                                                  |
//| Those ATRs are an ILLUSTRATION, not a measurement — the point is  |
//| the shape, not the numbers, and the real ones depend on the       |
//| instrument and the session. The startup read-out prints the step, |
//| the next level and the rr each tier actually sees at the current  |
//| price, so the powers should be set from that rather than from     |
//| this table.                                                      |
//|                                                                  |
//| This is NOT the model in experimental-h4-m1-po3-ea.mq5. That one  |
//| (§1) uses FIXED rungs (3^4/3^5/3^6) as dealing ranges with a      |
//| premium/discount read. Here the whole nest is one ladder and a    |
//| level's strength is measured by how far up it sits. The two        |
//| should not be conflated.                                          |
//|                                                                  |
//|------------------------------------------------------------------|
//| GATE 4 — THE PO3 REACTION VETO (new)                             |
//|                                                                  |
//| A level that has just rejected price is a level that price is     |
//| trading INTO, so an entry in the direction of that level is        |
//| refused until the level is reclaimed or a newer opposite tag       |
//| replaces it. The reading is taken from H4, and it is a TAG test,   |
//| not a distance test, for a reason specific to this grid: on gold   |
//| at ~4000 the only 2187-grade levels in view are around 2187 and    |
//| 4374, so "is price near a 2187 level right now" would almost       |
//| never fire. A tag-with-memory does: the lookback extreme stays     |
//| near the level for as long as the rejection stands.                |
//|                                                                  |
//| The test, ported from §1's PO3Bias():                             |
//|                                                                  |
//|   * scan the last InpPO3VetoBars closed H4 bars for the highest    |
//|     high and the lowest low;                                       |
//|   * round that extreme to the NEAREST multiple of 3^VetoPower      |
//|     (default 7 = 2187) and call it a TAG when the extreme came     |
//|     within InpPO3VetoTolFrac x 3^VetoBasePower of that multiple;   |
//|   * for a high tag the level is REJECTING while the latest closed  |
//|     H4 close is still back inside it by that same tolerance.       |
//|                                                                  |
//| The tolerance is measured off the BASE rung, not the level's own   |
//| grade, and that is deliberate: it is "how close counts as a tag"   |
//| in the instrument's fine-grid terms, a fixed distance in price.    |
//| Scaling it by the level's grade would make the tolerance 40% of    |
//| a 2187 step — a quarter of gold's whole range — and every bar      |
//| would tag every level. The base default is 4 (81 raw units), so    |
//| on gold the tag window is about +/-32 dollars.                     |
//|                                                                  |
//| RECLAIM CLEARS IT BY CONSTRUCTION. The rejection test is applied   |
//| to the LATEST closed H4 bar on every read, so the moment price     |
//| closes back through the level the tag stops binding — there is no  |
//| separate reclaim state to keep in step, which is why there is      |
//| none. When both sides are tagged inside one lookback the more      |
//| recent tag wins (series order: the lower index is the newer bar).  |
//|                                                                  |
//| The verdict is DIRECTIONAL: a tagged HIGH allows shorts only and   |
//| blocks longs, a tagged LOW allows longs only and blocks shorts,    |
//| and a lookback that tags neither leaves both directions open.      |
//|                                                                  |
//| An unreadable H4 history BLOCKS rather than waving trades          |
//| through — the same stance gates 1 and 3 take — so a symbol with    |
//| too little H4 history cannot trade until it loads. See             |
//| PO3VetoRead for the exact consequence.                             |
//|                                                                  |
//|------------------------------------------------------------------|
//| GATE 5 — THE DEALING-RANGE LOCATION VETO (new, off by default)   |
//|                                                                  |
//| The other half of the PO3 picture: not "is a level nearby" but     |
//| "where inside its range is price". floor(price/step) x step opens  |
//| the range price is in and the next rung closes it; the fraction    |
//| of the way across that range is the position, and the thirds of    |
//| it are the model's own reading — the lower third DISCOUNT, the     |
//| middle EQUILIBRIUM, the upper PREMIUM.                             |
//|                                                                  |
//| As a gate it is the classic location rule, buy discount and sell   |
//| premium, written as two independent thresholds so it can be        |
//| loosened or tightened without touching the range grade:            |
//|                                                                  |
//|   * a LONG is refused above InpPO3ZoneLongMaxPct of the range,     |
//|   * a SHORT is refused below InpPO3ZoneShortMinPct.                |
//|                                                                  |
//| Both default to 50 — the equilibrium line, the loosest sensible    |
//| setting: no buying in premium, no selling in discount. Set them    |
//| to 33.3 and 66.7 for the strict three-thirds model, where only     |
//| the discount third is bought, only the premium third is sold, and  |
//| the equilibrium middle is not traded at all.                       |
//|                                                                  |
//| The range grade is InpPO3ZonePower (default 5 = 243 on gold), and  |
//| NOT the per-tier search power: the zone is a property of where     |
//| price is, not of which tier is asking, so every tier reads the     |
//| same range.                                                        |
//|                                                                  |
//| Off by default, so a first run measures gate 4 alone. The two new  |
//| gates are independent and can be A/B'd against each other and      |
//| against the parent.                                                |
//|                                                                  |
//|------------------------------------------------------------------|
//| THE M2 RUNG AND THE M2 TIER (InpUseM2, InpM2Tier).               |
//|                                                                  |
//| M2 joins the stack twice, under two independent switches.         |
//|                                                                  |
//| THE RUNG (InpUseM2). M2 is a STEP IN THE CHAIN: with it on, the   |
//| M5 tier needs M1 + M2 + M5 aligned instead of M1 + M5, and every  |
//| higher tier inherits M2 because the chain grows through it on the |
//| way up. It also joins the cloud gate beside the M5 tier's         |
//| existing M1 check.                                                |
//|                                                                  |
//| THE TIER (InpM2Tier). M2 is TRADABLE: M1 + M2 aligned opens an M2 |
//| trade with its own risk row, its own ATR handle and its own       |
//| exits, managed by exactly the same code as an M5 trade. The M2    |
//| tier's whole chain is M2 — it does not need the rung, and the     |
//| rung does not need it. A build with the tier on and the rung off  |
//| is a coherent thing: M2 trades on M1 + M2, M5 trades on M1 + M5.  |
//|                                                                  |
//| M1 stays the only timeframe that must FULLY agree. M2 is checked  |
//| beside it, never instead of it, because loosening the rule this   |
//| build is named for would be a silent change of character. Whether |
//| M2 itself takes the full check or the M5+ future-only rule is     |
//| InpM2CloudFull (default: full, since a 2-minute bar is close in   |
//| character to M1) — and it applies to both roles: the rung's check |
//| beside M1, and the M2 tier's own cloud.                           |
//|                                                                  |
//| A BROKER WITHOUT M2 IS NOT A FAILURE. M2 is optional and skips    |
//| itself rather than blocking: a symbol that refuses an M2 handle   |
//| at init, or that has no M2 bars yet, drops BOTH roles and runs    |
//| its chains as M1 + M5 and up, with the M2 tier simply never       |
//| opening. That matters because CheckAlign returns 0 on unreadable  |
//| data — M2 enforced without an M2 feed would fail every chain      |
//| check and stop every entry on the symbol, leaving the EA silent   |
//| with nothing in the journal to say why.                           |
//|                                                                  |
//| Both switches off reproduces the parent's stack with the M2 tier  |
//| removed; InpM2Tier = false alone reproduces the parent exactly,   |
//| so the settings A/B cleanly against each other and against 20260867.|
//|                                                                  |
//| M2 IS NOT PART OF GATE 1. It briefly was, as a rung of the kihon  |
//| ladder; that ladder is gone and gate 1 is now the fixed daily H1   |
//| rule alone, so nothing about M2 touches the time gate any more.    |
//|                                                                  |
//|------------------------------------------------------------------|
//| Unchanged from the parent: per-TF alignment grown bottom-up from  |
//| M1, the cloud bias gate (M1 current+future, M5+ future only), the |
//| H4 bias with the H1 stand-in, the D1 filter on the H4 tier,       |
//| tier consolidation (largest aligned tier wins), the kumo-touch     |
//| exit, the optional rejection exit, break-even, the chandelier      |
//| trail, the disaster stop and margin-capped equity-tiered sizing.  |
//|                                                                  |
//| VPS-STYLE: no Alert() popups (SendNotification push + journal     |
//| Print instead), all logic once per closed M1 bar.                 |
//| Magic: 20260869 — free (20260868 was taken by the concurrent M2-RUNG  |
//|        fork while this build was being written; 20260867 is the veto   |
//|        build this forks). Shares positions with nothing, and NOT with  |
//|        the live build or with any of its relatives (20260858 live,     |
//|        20260865 kihon+PO3, 20260866 fixed-target, 20260867 +vetoes,    |
//|        20260868 M2-rung-only), so this can run beside production and   |
//|        beside all of them without any of them managing another's       |
//|        trades. Note the deliberate contrast with 20260868: that build  |
//|        adds the M2 RUNG to the live stack, this one adds the M2 TIER   |
//|        to the kihon+PO3+veto stack. They are different experiments and |
//|        must not be confused for one another.                           |
//| Author: Neo Malesa                                               |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

//--- Input Parameters ---
input string Symbols  = "GOLDm#";
input int    Tenkan   = 9;
input int    Kijun    = 26;
input int    SenkouB  = 52;
input int    Slippage = 30;

input group  "Risk Management (per level, % of actual equity)"
input double InpFixedLots       = 0.10;   // Fixed lots fallback (sizing data unavailable)
input double InpRiskATRMult     = 2.0;    // Reference stop distance = ATR(level TF) x this (risk sizing basis)
input double InpRiskTier2At     = 7000.0; // Equity where risk drops to tier 2 (half regime)
input double InpRiskTier3At     = 13000.0;// Equity where risk drops to tier 3 (tiny regime)
//--- The M2 tier is the new bottom of the stack and the thinnest data in it, so
//--- it is sized below M5 by default (0.5/0.25/0.05 against M5's 1/0.5/0.1).
//--- A 2-minute bar is close to the noise floor on a wide-spread feed, and a
//--- wrong M2 read costs the same dollars per lot as a wrong M5 read.
input double InpRiskPctM2       = 0.5;    // M2   — tier 1 (equity < Tier2At)
input double InpRiskPctM5       = 1.0;    // M5   — tier 1
input double InpRiskPctM15      = 1.0;    // M15  — tier 1
input double InpRiskPctM30      = 5.0;    // M30  — tier 1
input double InpRiskPctH1       = 10.0;   // H1   — tier 1
input double InpRiskPctH4       = 20.0;   // H4   — tier 1
input double InpRiskPctM2_T2    = 0.25;   // M2   — tier 2 (half regime)
input double InpRiskPctM5_T2    = 0.5;    // M5   — tier 2
input double InpRiskPctM15_T2   = 0.5;    // M15  — tier 2
input double InpRiskPctM30_T2   = 2.5;    // M30  — tier 2
input double InpRiskPctH1_T2    = 5.0;    // H1   — tier 2
input double InpRiskPctH4_T2    = 10.0;   // H4   — tier 2
input double InpRiskPctM2_T3    = 0.05;   // M2   — tier 3 (equity >= Tier3At)
input double InpRiskPctM5_T3    = 0.1;    // M5   — tier 3
input double InpRiskPctM15_T3   = 0.1;    // M15  — tier 3
input double InpRiskPctM30_T3   = 0.2;    // M30  — tier 3
input double InpRiskPctH1_T3    = 1.0;    // H1   — tier 3
input double InpRiskPctH4_T3    = 2.0;    // H4   — tier 3
input double InpMarginUsePct     = 80.0;   // Max % of FREE margin one order may commit (R5; parent used 100%)

// H1 stand-in bias mode — what the lower tiers may do when the H4 bias
// does not carry the trade.
//   H1BIAS_OFF     : no stand-in; H4 governs every tier on its own
//   H1BIAS_FLAT_H4 : stand-in allowed only while H4 is FLAT (unaligned /
//                    in its cloud) — never against an aligned H4
//   H1BIAS_ALWAYS  : stand-in allowed even when H4 is aligned the OTHER
//                    way (counter-H4 trading on the lower tiers)
enum ENUM_H1_BIAS_MODE { H1BIAS_OFF = 0, H1BIAS_FLAT_H4 = 1, H1BIAS_ALWAYS = 2 };

// Highest tier permitted to enter on the H1 stand-in bias. The H4 tier is
// deliberately absent — it always needs H4 (and D1) itself.
//---
//--- The values ARE level indices, so they all moved up by one when the M2 tier
//--- took index 0: M5 is level 1 now, not level 0. The M2 tier is deliberately
//--- NOT named in the enum but IS covered by it — M2 is level 0, below every
//--- setting, so any mode but OFF lets the stand-in carry the M2 tier too,
//--- which is the same "lower tiers may stand in" rule read one rung further
//--- down. H1TIER_M5 therefore means "M5 and the M2 tier under it".
enum ENUM_H1_BIAS_TIER { H1TIER_M5 = 1, H1TIER_M15 = 2, H1TIER_M30 = 3, H1TIER_H1 = 4 };

input group  "Entry Filters"
input bool   InpCloudBiasEnabled = true;   // Require Span A vs Span B bias: M1 current+future must agree; M5+ future cloud only
input bool   InpH4Bias           = true;   // H4 is the bias — tiers trade in H4's direction (H4 flat = no trades unless the H1 bias stands in)
input bool   InpD1Filter         = true;   // D1 filter for the H4 tier: H4 trades only in the D1's direction; D1 in the cloud = no H4 trades
input int    InpMaxSpreadPoints  = 60;     // Max spread in points to allow entry (0 = no limit)

input group  "M2 (rung inside the higher chains, and a tier of its own)"
//--- M2 plays TWO independent roles, with two independent switches.
//---
//--- THE RUNG (InpUseM2): M2 is a step in the chain, so the M5 tier needs
//--- M1 + M2 + M5 aligned instead of M1 + M5, and every higher tier inherits it
//--- because the chain grows through it on the way up. Off reproduces the parent
//--- exactly (M1 + M5 and up), so the two settings are a clean A/B.
//---
//--- THE TIER (InpM2Tier): M2 is tradable in its own right — M1 + M2 aligned
//--- opens an M2 trade, with its own risk row, its own ATR handle and its own
//--- exits, exactly as M5 has. No rung is needed for this: the M2 tier's whole
//--- chain IS M2.
//---
//--- Either role needs the same M2 feed. If the symbol has no M2 (no handle at
//--- init, or no bars yet) both drop out with one journal note rather than
//--- blocking the expert — see M2RungActive and M2TierActive. With the tier on
//--- and no M2 feed, the M2 tier simply never opens; the rest of the stack is
//--- unaffected.
input bool   InpUseM2            = true;   // RUNG: insert M2 into the higher tiers' chains (off = parent chains)
input bool   InpM2Tier           = true;   // TIER: let M1+M2 open an M2 trade, with its own risk row and exits
input bool   InpM2CloudFull      = true;   // M2 cloud check is the M1-style FULL one (current AND future), not the M5+ future-only rule — applies to the rung AND the M2 tier's own cloud

input group  "H1 Bias (lets the lower tiers trade when H4 is flat)"
input ENUM_H1_BIAS_MODE InpH1BiasMode    = H1BIAS_FLAT_H4; // 0=off (H4 only), 1=stand in only while H4 is flat, 2=stand in even against an aligned H4
input ENUM_H1_BIAS_TIER InpH1BiasMaxTier = H1TIER_M30;     // Highest tier allowed to enter on the H1 bias (1=M5, 2=M15, 3=M30, 4=H1; the M2 tier is always included)
input bool   InpH1BiasCloudCheck = true;   // Also require the H1 cloud (Span A vs Span B) to carry the trade's bias

input group  "Profit Protection"
input int    InpATRPeriod         = 14;    // ATR period (each level uses its own TF's ATR)
input double InpBEProfitATR       = 1.0;   // BE arms once profit >= this x ATR (M2/M5/M15/M30 levels)
input double InpBEProfitH1H4      = 0.5;   // BE arms once profit >= this x ATR (H1/H4 levels — tighter)
input int    InpBECoverPoints     = 15;    // Points beyond entry for the BE stop (covers spread)
input double InpSpikeLockATR      = 2.0;   // Chandelier trail arms once profit >= this x ATR (M2/M5/M15/M30 spike lock)
input double InpTrailActivateATR  = 0.5;   // H1/H4 chandelier trail arms once profit >= this x ATR
input double InpTrailATR          = 1.0;   // Trail distance behind the peak, x ATR (level TF)

input group  "Disaster Stop (hard tail-risk stop)"
input bool   InpDisasterStopEnabled = true;   // Attach a wide hard SL at entry (bounds gap/disconnect loss)
input double InpDisasterATRMult     = 8.0;    // Disaster stop distance = ATR(level TF) x this

input group  "Rejection Exit (strong rejection candle)"
input bool   InpRejectionExit = false;  // Close a trade when a very strong rejection candle forms against it on the tier TF
input int    InpRejSwingBars  = 8;      // Recent swing window (bars) the rejection candle must sweep
input double InpRejWickPct    = 0.5;    // Wick must be >= this fraction of the candle's total range
input double InpRejClosePct   = 0.35;   // Close must sit in the outermost this fraction of the range (strong close-back)

//--- GATE 1: the kihon suchi time gate — the DAILY H1 setup, and only that.
input group  "Gate 1 - Daily H1 Kihon Suchi"
//--- One rule, hardcoded: count H1 candles from the DAY open and open the gate
//--- when that count sits within InpTimeTol of 9 or of 17. Those are the only
//--- two kihon numbers a trading day can deliver (~23-24 H1 candles), and they
//--- are a hardcoded PAIR rather than "the simple numbers" because 26 is not
//--- reachable while a nearest-number test would still fire on it at the day's
//--- last candle — see the note on KihonDayH1.
//---
//--- There is deliberately no ladder left here. It carried a list of
//--- TF:ANCHOR rungs judged N-of-M, which was the right shape while the rungs
//--- were being chosen, but the choice has been made: daily H1 on 9 and 17 is
//--- the whole gate. The rung machinery (the ladder string, its parser, the
//--- N-of-M count and the clamp that guarded it) is gone with it. The
//--- multi-rung version is preserved in commit c220059 if rungs are ever
//--- wanted back.
//---
//--- Each rung used to cost an anchor lookup and a Bars() window per symbol
//--- per M1 bar, which was the heaviest thing gate 1 did and the cost that
//--- dominated a backtest; one fixed rule is a single window.
//---
//--- With InpTimeTol at 2 the gate is open on H1 candles 7-11 and 15-19 of the
//--- daily count — 10 of a day's ~23-24 candles, so roughly 40% of the
//--- session. Drop the tolerance to 0 to take only candles 9 and 17 exactly.
input bool   InpTimeGateEnabled = true;   // Require the daily H1 kihon window (count from the day open, candles 9 and 17)
input int    InpTimeTol         = 2;      // +/- H1 candles counted as ON 9 or 17 (0 = only those two candles)

//--- GATE 3: the PO3 level gate.
input group  "Gate 3 - PO3 Levels"
input bool   InpPO3Enabled     = true;   // Require the next PO3 level to give the trade room (gate 3)
input double InpPO3Scale       = 1.0;    // Scale divisor (1 = whole numbers, 100 = workbook 2dp) — as the indicator
//--- Level power PER TIER, in tier order M2, M5, M15, M30, H1, H4. A single
//--- number applies to every tier. The step for a tier is 3^its power, and
//--- the reason it cannot be one global number is set out under PO3PowerParse:
//--- the room band is measured in the tier's own ATR, and those differ by
//--- about an order of magnitude across the stack.
//---
//--- M2 keeps M5's power (3, step 27) rather than dropping to 2 (step 9). The
//--- blocking fraction is roughly InpPO3MinRR x refRisk / step, and M2's refRisk
//--- is about 0.6 of M5's, so step 9 would read "no room" on about 40% of
//--- positions where step 27 reads about 14% — and over-blocking the thinnest
//--- tier is the worse error. The startup read-out prints what M2 actually
//--- sees, so this should be set from that rather than from this argument.
input string InpPO3Power       = "3,3,3,4,4,5"; // Level power per tier (a single number = all tiers)
input int    InpPO3MaxPower    = 9;      // Cap on the power reported (9 = 19683, the indicator's top grid)
input double InpPO3MinRR       = 1.5;    // Min reward:risk for a level to qualify as a take profit
input double InpPO3MaxRR       = 8.0;    // Levels beyond this R are runners — no PO3 take profit
input double InpPO3BufferATR   = 0.25;   // Front-run the target level by ATR(tier TF) x this
input bool   InpPO3RoomFilter  = true;   // Skip entries with no room to the next PO3 level
input bool   InpPO3TpEnabled   = true;   // Attach the PO3 level as the trade's take profit
input bool   InpPO3LogSetup    = true;   // Journal the per-tier step / next level / rr at startup

//--- GATE 4: the reaction veto. Read from H4 for EVERY tier, because the
//--- level a rejection matters at is the one the whole stack is trading
//--- against, not the tier's own rung. Cached per closed H4 bar — the reading
//--- can only change when one closes, so it costs one CopyRates per symbol per
//--- four hours, not one per M1 bar the way §1's PO3Bias does.
input group  "Gate 4 - PO3 Reaction Veto (rejection at a major level)"
input bool   InpPO3VetoEnabled   = true;  // Block entries TOWARD a PO3 level that has just rejected price
input int    InpPO3VetoPower     = 7;     // Major level power: 3^7 = 2187, the grade a reversal is read at
input int    InpPO3VetoBars      = 180;   // Closed H4 bars scanned for the tagging extreme
//--- The tag tolerance comes off the BASE rung rather than the level's own
//--- grade — a fixed distance in price, not a fraction of a 2187 step. See the
//--- GATE 4 header section for why scaling it by the grade breaks the test.
input int    InpPO3VetoBasePower = 4;     // Tag tolerance is a fraction of 3^this (4 = 81)
input double InpPO3VetoTolFrac   = 0.4;   // ... that fraction; 0.4 x 81 is about +/-32 dollars on gold
input bool   InpPO3VetoLogSetup  = true;  // Journal the current tag state per symbol at startup

//--- GATE 5: the dealing-range location veto. Independently switchable and
//--- OFF by default, so a first run of this build measures gate 4 alone.
input group  "Gate 5 - PO3 Dealing-Range Zone (off by default)"
input bool   InpPO3ZoneEnabled    = false; // Require price to be on the right side of its PO3 range
input int    InpPO3ZonePower      = 5;     // Range grade: 3^5 = 243. One range, read by every tier
input double InpPO3ZoneLongMaxPct = 50.0;  // A LONG is refused ABOVE this % of the range (50 = equilibrium)
input double InpPO3ZoneShortMinPct = 50.0; // A SHORT is refused BELOW this % (33.3 / 66.7 = the strict thirds)

//--- Constants and Global Variables ---
#define MAX_SYMS 60
#define LEVELS   6      // tradable levels: M2, M5, M15, M30, H1, H4
#define TFS      7      // stack: M1, M2, M5, M15, M30, H1, H4
#define IDX_M1   0      // index of M1 — the start of every chain
#define IDX_M2   1      // index of M2 in tfs[] — the TIER below M5, and the optional rung inside it
#define TIER0    1      // index of the first TRADABLE tier (M2) in tfs[]
#define IDX_H1   5      // index of H1 in tfs[] — the stand-in bias TF
#define IDX_H4   6      // index of H4 in tfs[] — the primary bias TF

//--- Level indices that code actually depends on. The parent spelled these as
//--- bare numbers (`lvl == 0` for its bottom tier, `lvl >= 3` for the H1/H4 BE
//--- bucket); the M2 tier took index 0 and pushed all five of them up by one,
//--- which is exactly the change that leaves a bare number behind. Named here so
//--- the two that mean something say what they mean.
#define LVL_M2   0      // the M2 tier — bottom of the stack (was not a tier in the parent)
#define LVL_M5   1      // the M5 tier — the parent's bottom, one up
#define LVL_H1   4      // the H1 tier — first of the two that take the tighter BE/trail

ENUM_TIMEFRAMES tfs[TFS] = { PERIOD_M1, PERIOD_M2, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4 };
string          tfName[TFS] = { "M1", "M2", "M5", "M15", "M30", "H1", "H4" };

//--- A tradable level's position in tfs[]. The levels are M2..H4 and M1 is the
//--- shared first leg of every chain, so a level's timeframe is its own index
//--- plus one. Every level-to-timeframe lookup goes through here rather than
//--- spelling "+1" at each site.
//---
//--- Note that TfIdxOfLevel(LVL_M2) == IDX_M2: the M2 tier reads the SAME
//--- timeframe the rung does. That is what forced the rung-skip in ChainAligned
//--- to become level-aware — see the note there.
int TfIdxOfLevel(const int lvl)
  {
   return(lvl + TIER0);
  }

int      ich[MAX_SYMS][TFS];
int      ichD1[MAX_SYMS];           // D1 ichimoku handle — H4-tier bias filter
int      atr[MAX_SYMS][LEVELS];       // ATR(level TF) — BE and spike-lock trail sizing
string   syms[MAX_SYMS];
int      symsCount = 0;
datetime lastM1bar[MAX_SYMS];
int      state[MAX_SYMS][LEVELS];     // per level: 0 = flat, 1 = long, -1 = short
int      lastMinuteKey = -1;

double   entryPrice[MAX_SYMS][LEVELS];   // reference entry price per level (BE + trail arming)
double   peakHigh[MAX_SYMS][LEVELS];     // highest high since entry (long chandelier reference)
double   peakLow[MAX_SYMS][LEVELS];      // lowest low since entry (short chandelier reference)
bool     beMoved[MAX_SYMS][LEVELS];      // BE stop already moved to break even (one-shot)

//--- M2 rung state, per symbol. M2 is optional, and it is SKIPPED rather than
//--- fatal when it cannot be used — see M2RungActive for why that matters.
bool     m2Ok[MAX_SYMS];      // the symbol accepted an M2 handle at init
bool     m2Warned[MAX_SYMS];  // the "no M2 history yet" note, once per symbol

// The kihon suchi reading that let this symbol through gate 1, written by
// OnTick into the entry journal so a reviewed entry records WHY the time gate
// passed — the only way to judge the gate afterwards. Held in the loop as a
// local; nothing else reads it.

// R2: unknown-position guard. A position carrying our magic whose comment
// no longer names a level cannot be managed (no BE/trail/cloud exit can
// find it) — track it, block new entries on its symbol until it is gone,
// and log it once per ticket (not once per minute).
bool              symBlockedUnknown[MAX_SYMS];
ulong             unknownLoggedTickets[64];
int               unknownLoggedCount   = 0;

int MAGIC = 20260869;   // free — 20260868 is the M2-RUNG fork. Shares nothing.

CTrade trade;

//==============================================================
// KIHON SUCHI CORE
//
// Ported from experiments/po3-levels.mq5 (the PO3 + kihon indicator)
// so the EA and the chart cannot disagree about where a count stands.
// Comment and arithmetic are kept as they are there, including the
// inclusive counting convention and the nearest-not-next tolerance.
//==============================================================

//--- Only what the daily H1 gate needs is carried over. The full twelve-number
//--- series, its compound/simple split, and the general nearest-number scan
//--- (KihonIs / KihonNext / KihonAtOrBelow / KihonOffset over all twelve) all
//--- live in the indicator, which is where they are actually read. The gate
//--- here asks one question — is the daily H1 count on 9 or 17 — so that is
//--- what is kept, and the series that supported every other reading is gone
//--- with the ladder that used it.

//+------------------------------------------------------------------+
//| THE DAILY H1 NUMBERS — 9 and 17, and nothing else.               |
//|                                                                  |
//| Counted from the DAY open an H1 series is about 23-24 candles    |
//| long, so 9 and 17 are the only kihon numbers a trading day can    |
//| actually deliver. Those are the two this build trades off.        |
//|                                                                  |
//| 26 IS THE TRAP, and it is why this is a hardcoded pair rather    |
//| than "the simple numbers" (which would be 9, 17 AND 26). A        |
//| nearest-number test does not care that a number is out of reach — |
//| it only measures distance. 26 sits two candles past candle 24, so |
//| on the LAST candle of the day a {9, 17, 26} series reports        |
//| "26, offset +2" and the gate opens on a number the count never    |
//| reached and never could. The tolerance that makes the gate useful  |
//| for 9 and 17 is exactly what makes it fire there.                 |
//|                                                                  |
//| Measured, on a 24-candle day: {9,17,26} opens the gate on candles |
//| 7-11, 15-19 AND 24; {9,17} opens it on 7-11 and 15-19 only.       |
//+------------------------------------------------------------------+
#define KIHON_DAY_H1_COUNT 2
const int KihonDayH1[KIHON_DAY_H1_COUNT] = { 9, 17 };

//+------------------------------------------------------------------+
//| Signed distance from n to the nearest of the daily H1 pair.      |
//|                                                                  |
//| Same convention as KihonOffset — n minus the number, so negative  |
//| reads as still short of it and positive as just past — and the    |
//| same nearest-not-next rule, because a turn due at 9 is not        |
//| cancelled by the candle after it.                                 |
//+------------------------------------------------------------------+
int KihonOffsetDayH1(const int n)
  {
   int best = n - KihonDayH1[0];

   for(int i = 1; i < KIHON_DAY_H1_COUNT; i++)
     {
      int d  = n - KihonDayH1[i];
      int ad = (d    < 0) ? -d    : d;
      int ab = (best < 0) ? -best : best;
      if(ad < ab)
         best = d;
     }
   return(best);
  }

//+------------------------------------------------------------------+
//| Where the candle count starts.                                   |
//--- Ceiling on how many candles a count will chase. Past 257 every count
//--- reads the same - there is no kihon number above it - so an exact figure
//--- buys nothing, while getting one forces the history to load. Beyond this
//--- the count reports "too far" instead. Deliberately far above 257 so a
//--- legitimate deep count is still exact.
//---
//--- The anchor enum, the month/year calendar builder and the multi-anchor
//--- selector (KihonAnchor) that stood here are gone: the gate counts from the
//--- DAY open and nothing else, so the anchor is now the single line inside
//--- KihonCountDayH1(). The day open comes from the D1 bar itself rather than
//--- from the calendar, so it follows the BROKER's day boundary - on a broker
//--- rolling at 00:00 server that is midnight, on a New York close broker it
//--- is not, and the bar knows which.
#define KIHON_SPAN_CAP  20000

//+------------------------------------------------------------------+
//| Midnight on the first day of the current server month, or of     |
//| the current server year.                                         |
//|                                                                  |
//| Built from the calendar rather than from a bar. There is no      |
//| yearly candle to read a year off, and the monthly candle would   |
//| only tell you what the calendar already does. Counts against     |
//| these therefore start at the first candle that OPENS inside the  |
//| period: a weekly candle straddling New Year belongs to the old   |
//| year, which is the same rule the day and week anchors follow.    |
//+------------------------------------------------------------------+
//| The time the count starts from.                                  |
//|                                                                  |
//| Day and week open come from the D1 and W1 bars themselves, so    |
//| they follow the broker's own day boundary rather than a guess at |
//| it - on a five-decimal broker rolling at 00:00 server that is    |
//| midnight, on a New York close broker it is not, and the bar      |
//| knows which.                                                     |
//|                                                                  |
//| A custom time is today's date at that hour and minute, rolled    |
//| back a day if it has not come round yet, and then CLAMPED to the |
//| day open, so a session anchor never counts across a day boundary |
//| and the weekend gap.                                             |
//+------------------------------------------------------------------+
//| How many candles of this timeframe have printed since the        |
//| anchor, on the inclusive rule: the candle at the anchor is 1, so |
//| the developing candle carries the number this returns. Bar       |
//| indices run unbroken, so candle 1 sits at shift (count - 1).     |
//|                                                                  |
//| Returns 0 when the answer is not known yet - history still       |
//| loading, or the anchor older than the bars this chart holds -    |
//| so a caller can tell "nothing to show" from "candle zero", which |
//| does not exist under inclusive counting. Returns -1 when the     |
//| anchor is further back than KIHON_SPAN_CAP periods, which is a   |
//| refusal rather than a failure.                                   |
//|                                                                  |
//| Bars() over the window rather than iBarShift() on the anchor.    |
//| The difference shows up whenever the anchor lands in a gap: a    |
//| day opening at 00:00 whose first M1 candle is 00:01 has no       |
//| candle at the anchor, and iBarShift with exact=false answers    |
//| with the nearest EARLIER bar, which is last night's close. That  |
//| would put candle 1 on the wrong side of the open and shift every |
//| kihon mark by one. Bars() counts open times inside the window,   |
//| so a candle before the anchor is simply not in it.               |
//+------------------------------------------------------------------+
int KihonCount(const string sym, const ENUM_TIMEFRAMES tf, const datetime anchor)
  {
   if(anchor <= 0)
      return(0);

   datetime cur = iTime(sym, tf, 0);
   if(cur == 0)
      return(0);                       // history not ready on this timeframe
   if(anchor >= cur)
      return(1);                       // anchor falls inside the developing candle

   //--- Estimate the span before asking for the bars. The estimate is from
   //--- elapsed time, so it ignores weekends and overstates - which is the
   //--- safe direction for a cost guard.
   int secs = PeriodSeconds(tf);
   if(secs > 0 && ((long)TimeCurrent() - (long)anchor) / secs > KIHON_SPAN_CAP)
      return(-1);

   //--- inclusive of both ends, and the developing candle's open time is
   //--- always at or before now, so it is the last one counted
   int n = Bars(sym, tf, anchor, TimeCurrent());
   return(n > 0 ? n : 0);
  }

//==============================================================
// KIHON TIME GATE (gate 1) - the daily H1 setup
//
// One rule: count H1 candles from the DAY open and ask whether that
// count sits within InpTimeTol of 9 or of 17. There is no ladder
// here any more and no rung parsing, no N-of-M count and no clamp to
// guard one — the rung has been chosen, so the machinery that existed
// to choose it is gone with it. The multi-rung version is preserved
// in commit c220059 if rungs are ever wanted back.
//==============================================================

//--- The count the gate judges: H1 candles since the day open, inclusive.
//--- Zero when the answer is not known yet (history still loading), -1 when
//--- the anchor is further back than KIHON_SPAN_CAP.
int KihonCountDayH1(const string sym)
  {
   datetime anchor = iTime(sym, PERIOD_D1, 0);
   return(KihonCount(sym, PERIOD_H1, anchor));
  }

//+------------------------------------------------------------------+
//| Gate 1. Is the daily H1 count within the tolerance of 9 or 17?   |
//|                                                                  |
//| Writes the reading into 'info' for the journal, so a reviewed    |
//| entry records what judged it — "H1:D10+1(9)" is count 10, one     |
//| candle past 9. The count is in there so the reading can be        |
//| checked by hand against the indicator's panel, and the tag saves  |
//| working the number back out.                                      |
//|                                                                  |
//| An unknown count (history still loading, or no D1 bar yet) is NOT |
//| a pass. The gate cannot be evaluated, and an unevaluable filter   |
//| blocks rather than waves the trade through — the same stance the  |
//| cloud gate takes on unreadable buffers. It clears itself as soon  |
//| as the history lands.                                             |
//+------------------------------------------------------------------+
bool TimeGateOK(const int s, string &info)
  {
   info = "off";
   if(!InpTimeGateEnabled)
      return(true);

   int c = KihonCountDayH1(syms[s]);
   if(c <= 0)
     {
      info = (c < 0) ? "H1:D too far" : "H1:D no data";
      return(false);
     }

   int tol = (int)MathMax(0, MathMin(8, InpTimeTol));
   int off = KihonOffsetDayH1(c);
   int mag = (off < 0) ? -off : off;
   if(mag > tol)
     {
      info = "H1:D" + IntegerToString(c) + " out of range";
      return(false);
     }

   //--- "+2" is two candles past the number, "-1" one short, "=" on it.
   int num = (off > 0) ? c - mag : c + mag;   // the number the count is near
   info = "H1:D" + IntegerToString(c) +
          ((off > 0) ? "+" : (off < 0) ? "-" : "=") +
          IntegerToString(mag) +
          ((mag > 0) ? "(" + IntegerToString(num) + ")" : "");
   return(true);
  }

//==============================================================
// PO3 CORE (gate 3)
//
// Levels are m x 3^n in a scaled integer space (price = raw /
// scale). The grids nest, so a level's strength is the HIGHEST
// power that lands on it, and that is 3^v3(raw) where v3 is how
// many times raw divides by 3. Verified against the indicator's
// own merge rule: 222 level assignments, no disagreements, and
// its worked example (4374 -> 2187) reproduces.
//
// The one fact the gate leans on: the levels of power >= k are
// exactly the multiples of 3^k. So the next level worth looking
// at is the next multiple of 3^k, found in one division.
//==============================================================

//--- 3^power as an integer. Clamped well short of any overflow; the
//--- largest power the inputs allow is 9 (19683) but the guard means a
//--- wild input cannot wrap the step into a negative number.
long PO3Step(const int power)
  {
   long v = 1;
   int  n = (power < 0) ? 0 : (power > 20 ? 20 : power);
   for(int i = 0; i < n; i++)
      v *= 3;
   return(v);
  }

//--- How many times raw divides by 3 — the exponent of the strongest PO3
//--- level that lands exactly on it. 4374 returns 7, i.e. a 2187 level.
int PO3Power(long raw)
  {
   if(raw <= 0)
      return(0);
   int n = 0;
   while(n < 30 && (raw % 3) == 0)
     {
      raw /= 3;
      n++;
     }
   return(n);
  }

//+------------------------------------------------------------------+
//| Level power PER TIER.                                            |
//|                                                                  |
//| Room is measured in reference-risk units — ATR(tier TF) x        |
//| InpRiskATRMult — and those differ by roughly an order of         |
//| magnitude across the stack: on gold ATR(M5) is a couple of        |
//| dollars and ATR(H4) a few dozen. One global power cannot serve    |
//| both ends of that, and it fails in opposite directions:           |
//|                                                                  |
//|   power 3 (step 27) — the nearest level is at most 27 away. On    |
//|     M5 that is a comfortable 3-8 R, so the gate works. On H4 it   |
//|     is under half an R, so the room filter would read "no room"   |
//|     on EVERY entry and the H4 tier would never trade again.       |
//|   power 6 (step 729) — the reverse: M5 would see nothing but      |
//|     runners beyond InpPO3MaxRR.                                   |
//|                                                                  |
//| So the power is per tier and the higher tiers get the coarser     |
//| ladder their risk needs. The default "3,3,4,4,5" is a starting    |
//| point scaled to gold's ATR by tier — not a fitted answer. The     |
//| startup read-out prints the rr each tier actually sees at the     |
//| current price, so it can be tuned from the numbers.               |
//+------------------------------------------------------------------+
int g_po3Pow[LEVELS];

//--- Parse "3,3,4,4,5" (M5, M15, M30, H1, H4). One value applies to every
//--- tier; fewer values than tiers means the last one carries on down the
//--- stack. A token that is not a plain number, or is outside 0-20, is
//--- reported and replaced by the value before it rather than failing the
//--- load — a typo should cost you that one tier, not the whole expert.
void PO3PowerParse()
  {
   for(int l = 0; l < LEVELS; l++)
      g_po3Pow[l] = 3;

   string parts[];
   int    n   = StringSplit(InpPO3Power, ',', parts);
   int    got = 0;
   int    last = 3;

   for(int i = 0; i < n && got < LEVELS; i++)
     {
      string tok = parts[i];
      StringTrimLeft(tok);
      StringTrimRight(tok);
      if(StringLen(tok) == 0)
         continue;

      //--- Digits only: StringToInteger would quietly read "abc" as 0 and
      //--- hand back a step of 1, which is a grid of every price.
      bool numeric = true;
      for(int c = 0; c < StringLen(tok) && numeric; c++)
        {
         ushort ch = StringGetCharacter(tok, c);
         if(ch < '0' || ch > '9')
            numeric = false;
        }

      int v = numeric ? (int)StringToInteger(tok) : -1;
      if(v < 0 || v > 20)
        {
         PrintFormat("PO3 gate: power \"%s\" for tier %s is not a number in 0-20 - using %d.",
                     tok, tfName[TfIdxOfLevel(got)], last);
         v = last;
        }

      g_po3Pow[got] = v;
      last = v;
      got++;
     }

   for(int l = got; l < LEVELS; l++)
      g_po3Pow[l] = last;
  }

//--- What the gate decided about the next level, so the caller can tell a
//--- blocked entry from a runner without re-deriving anything.
enum ENUM_PO3_VERDICT
  {
   PO3_UNKNOWN = 0,   // could not be measured (ATR or price not ready) — blocks
   PO3_NO_ROOM = 1,   // a level sits closer than InpPO3MinRR — blocks
   PO3_TARGET  = 2,   // a level is inside the RR band — trade it as the TP
   PO3_RUNNER  = 3    // the next level is beyond InpPO3MaxRR — no TP
  };

//--- One reading of the gate: the verdict plus the numbers behind it, so the
//--- caller can journal the level, its power and the rr without re-deriving
//--- any of them. A second copy of that arithmetic is a second copy that will
//--- eventually disagree with the first.
struct PO3Read
  {
   ENUM_PO3_VERDICT verdict;
   double           level;   // the level's price (0 when unmeasured)
   double           tp;      // buffered target (0 unless the verdict is PO3_TARGET)
   double           rr;      // distance to the level, in reference-risk units
   int              power;   // the level's real power, capped at InpPO3MaxPower
  };

//+------------------------------------------------------------------+
//| Gate 3. Find the next PO3 level in the trade's direction and     |
//| decide what it is worth.                                         |
//|                                                                  |
//| The distance is measured against the SAME reference risk the      |
//| sizing uses — ATR(tier TF) x InpRiskATRMult — so "room" means     |
//| room in units of what the trade is actually risking, not in       |
//| points, and it is therefore tier-sensitive by construction: a     |
//| 27-dollar level that is a 3 R target on M5 is a fraction of an R  |
//| on H4, where the same level will read as no room and block.       |
//|                                                                  |
//| The level's ACTUAL power is reported, not the search power: the   |
//| next multiple of 27 may be a 2187 level, and the journal says so  |
//| — the same number the indicator would label that line with.       |
//+------------------------------------------------------------------+
PO3Read PO3Verdict(const int s, const int lvl, const int dir, const double refPrice)
  {
   PO3Read r;
   r.verdict = PO3_UNKNOWN;
   r.level   = 0.0;
   r.tp      = 0.0;
   r.rr      = 0.0;
   r.power   = 0;

   if(!InpPO3Enabled)
     {
      r.verdict = PO3_RUNNER;             // gate off: no TP from PO3 either
      return(r);
     }

   if(InpPO3Scale <= 0.0 || refPrice <= 0.0)
      return(r);

   //--- Reference risk, the same basis the sizing uses. No ATR means the
   //--- gate cannot be evaluated, and an unevaluable filter blocks rather
   //--- than waves the trade through — the same stance the cloud gate takes
   //--- on unreadable buffers.
   double a[1];
   if(CopyBuffer(atr[s][lvl], 0, 1, 1, a) <= 0 || a[0] <= 0)
      return(r);
   double refRisk = a[0] * InpRiskATRMult;
   if(refRisk <= 0.0)
      return(r);

   int kLo   = g_po3Pow[(lvl < 0) ? 0 : ((lvl >= LEVELS) ? LEVELS - 1 : lvl)];
   int kCap  = (kLo > InpPO3MaxPower) ? kLo : InpPO3MaxPower;
   long step = PO3Step(kLo);

   //--- The next multiple of step strictly beyond price, in the trade's
   //--- direction. The epsilon keeps a price sitting exactly on a level from
   //--- being read as one step past it — the same float guard the indicator
   //--- uses when it anchors its window.
   double scaled = refPrice * InpPO3Scale;
   long   m;
   if(dir == 1)
      m = (long)MathFloor(scaled / (double)step + 1e-9) + 1;
   else
      m = (long)MathCeil(scaled / (double)step - 1e-9) - 1;

   long raw = m * step;
   if(raw <= 0)
      return(r);

   double	lvlPrice = (double)raw / InpPO3Scale;
   double dist     = (dir == 1) ? (lvlPrice - refPrice) : (refPrice - lvlPrice);
   if(dist <= 0.0)
      return(r);

   double rr = dist / refRisk;
   r.level   = lvlPrice;
   r.rr      = rr;

   //--- The real power, not the search power — but capped at InpPO3MaxPower,
   //--- which is what makes the journal agree with the chart: the indicator
   //--- labels a level with the highest grid it DRAWS, and 19683 (3^9) is the
   //--- top of that nest. A level divisible by 3^12 is a 19683 level to both,
   //--- because neither of them has a rung above it to say otherwise.
   int pwReal = PO3Power(raw);
   r.power    = (pwReal < kCap) ? pwReal : kCap;

   if(rr < InpPO3MinRR)
     {
      r.verdict = PO3_NO_ROOM;
      return(r);
     }

   //--- Beyond the band the level is not a target, it is a destination for
   //--- some later trade: open anyway and let the parent's exits run it.
   if(rr > InpPO3MaxRR)
     {
      r.verdict = PO3_RUNNER;
      return(r);
     }

   //--- Front-run the level: fill before it can reject price. A long takes
   //--- profit just UNDER the level, a short just OVER it.
   double point   = SymbolInfoDouble(syms[s], SYMBOL_POINT);
   double minDist = SymbolInfoInteger(syms[s], SYMBOL_TRADE_STOPS_LEVEL) * point;
   int    digits  = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);

   double buffer = a[0] * InpPO3BufferATR;
   double tp     = NormalizeDouble(lvlPrice - (double)dir * buffer, digits);

   //--- A TP the broker would reject (inside its minimum stop distance, or
   //--- on the wrong side of entry once the buffer is applied) degrades to a
   //--- runner rather than failing the entry.
   double bid = SymbolInfoDouble(syms[s], SYMBOL_BID);
   double ask = SymbolInfoDouble(syms[s], SYMBOL_ASK);
   bool tpOK = (dir == 1) ? (tp > ask + minDist) : (tp < bid - minDist);
   if(!tpOK)
     {
      r.verdict = PO3_RUNNER;
      return(r);
     }

   r.tp      = tp;
   r.verdict = PO3_TARGET;
   return(r);
  }

//--- "PO3 2916 (p6=729)" — the level, its power, and the grid that power
//--- names, so the journal can be read straight against the chart's labels.
string PO3Tag(const string sym, const double lvlPrice, const int power)
  {
   if(power <= 0)
      return("PO3 --");
   return("PO3 " + DoubleToString(lvlPrice, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)) +
          " (p" + IntegerToString(power) + "=" + IntegerToString((int)PO3Step(power)) + ")");
  }

//+------------------------------------------------------------------+
//| Startup read-out for gate 3.                                     |
//|                                                                  |
//| The band is measured in each tier's own ATR, so whether the gate  |
//| ever fires is a question about this instrument's ATR against the  |
//| power chosen FOR THAT TIER — not something that can be settled in |
//| the abstract, and the reason the powers are per tier at all. This |
//| walks every symbol and every tier and prints the step, the next   |
//| level and the rr that tier would actually see, so the powers can  |
//| be set from the numbers instead of by guesswork.                  |
//+------------------------------------------------------------------+
void PO3LogSetup()
  {
   if(!InpPO3Enabled || !InpPO3LogSetup)
      return;

   string pows = "";
   for(int l = 0; l < LEVELS; l++)
      pows += (StringLen(pows) > 0 ? " " : "") + tfName[TfIdxOfLevel(l)] + "=" +
              IntegerToString(g_po3Pow[l]) + "(" + IntegerToString((int)PO3Step(g_po3Pow[l])) + ")";

   PrintFormat("PO3 gate: powers %s | scale x%g, band %.2f-%.2f R, buffer %.2f x ATR, "
               "room filter %s, TP %s.",
               pows, InpPO3Scale, InpPO3MinRR, InpPO3MaxRR,
               InpPO3BufferATR, InpPO3RoomFilter ? "ON" : "off", InpPO3TpEnabled ? "ON" : "off");

   for(int s = 0; s < symsCount; s++)
     {
      double ask = SymbolInfoDouble(syms[s], SYMBOL_ASK);
      if(ask <= 0.0)
         continue;

      int dg = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);
      PrintFormat("PO3 gate: %s ask %s - room to the next level, per tier (read as a long):",
                  syms[s], DoubleToString(ask, dg));

      for(int l = 0; l < LEVELS; l++)
        {
         double a[1];
         if(CopyBuffer(atr[s][l], 0, 1, 1, a) <= 0 || a[0] <= 0)
           {
            PrintFormat("PO3 gate:   %-3s ATR not ready, no read-out.", tfName[TfIdxOfLevel(l)]);
            continue;
           }

         //--- Read it the way the entry path would: as a long, from the ask.
         PO3Read r = PO3Verdict(s, l, 1, ask);

         string word = (r.verdict == PO3_NO_ROOM) ? "NO ROOM - every entry blocked here"
                       : (r.verdict == PO3_TARGET) ? "TAKE PROFIT"
                       : (r.verdict == PO3_RUNNER) ? "runner, no TP"
                       : "unmeasurable - entries blocked here";

         bool   known = (r.verdict != PO3_UNKNOWN);
         string nextTxt = known ? DoubleToString(r.level, dg) : "--";
         string po3Txt  = known ? PO3Tag(syms[s], r.level, r.power) : "PO3 --";

         PrintFormat("PO3 gate:   %-3s step %-6d ATR %s ref %s | next %s (rr %.2f) %s -> %s",
                     tfName[TfIdxOfLevel(l)], (int)PO3Step(g_po3Pow[l]),
                     DoubleToString(a[0], dg), DoubleToString(a[0] * InpRiskATRMult, dg),
                     nextTxt, r.rr, po3Txt, word);
        }
     }
  }

//==============================================================
// GATE 4 — THE PO3 REACTION VETO
//
// A level that has just rejected price is a level price is
// trading INTO, so an entry toward it is refused until the level
// is reclaimed or a newer opposite tag replaces it. Ported from
// §1's PO3Bias() onto this build's level arithmetic, where a
// price is raw = price x scale and the levels are the multiples
// of 3^power in that raw space.
//
// Read from H4 for EVERY tier: the level a rejection matters at
// is the one the whole stack is trading against, not the tier's
// own rung. Cached per closed H4 bar, so the CopyRates below runs
// once per symbol per four hours rather than once per M1 bar the
// way §1 runs it.
//==============================================================

enum ENUM_PO3_VETO
  {
   VETO_UNKNOWN = 0,   // H4 history unreadable — blocks, like gates 1 and 3
   VETO_NONE    = 1,   // nothing tagged — both directions open
   VETO_LONGS   = 2,   // a LOW was tagged and rejected up — longs only
   VETO_SHORTS  = 3    // a HIGH was tagged and rejected down — shorts only
  };

struct PO3VetoRead
  {
   ENUM_PO3_VETO verdict;
   double        level;   // the level that was tagged (0 when none)
   datetime      bar;     // closed H4 bar the reading was taken on (0 = none)
  };

//--- The cache, per symbol. Global and file-scope rather than static inside the
//--- function so the startup read-out and the entry path read the same state.
PO3VetoRead g_veto[MAX_SYMS];

//--- A price at the symbol's own digits, for the journal.
string PO3Px(const string sym, const double price)
  {
   return(DoubleToString(price, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)));
  }

//+------------------------------------------------------------------+
//| The reaction veto, cached on the closed H4 bar.                  |
//|                                                                  |
//| UNREADABLE HISTORY BLOCKS. CopyRates returning nothing means the  |
//| H4 series is not there yet — a newly added symbol, or a load in   |
//| progress — and the gate answers VETO_UNKNOWN, which blocks. That  |
//| is the stance gates 1 and 3 already take on unreadable data. The  |
//| consequence is worth stating plainly: a symbol with fewer than    |
//| InpPO3VetoBars closed H4 bars, or one whose H4 history the        |
//| terminal has not served yet, cannot open a trade until it loads.  |
//| 180 H4 bars is about five weeks of trading, so this is a warm-up   |
//| on a new symbol rather than a standing condition — and the        |
//| startup read-out prints it so a silent symbol is visible.         |
//|                                                                  |
//| Only a SUCCESSFUL read is cached. A failure is retried on the next |
//| entry check rather than remembered, so the gate clears itself the  |
//| moment the history lands.                                         |
//+------------------------------------------------------------------+
PO3VetoRead PO3VetoReadSym(const int s)
  {
   PO3VetoRead r;
   r.verdict = VETO_UNKNOWN;
   r.level   = 0.0;
   r.bar     = 0;

   //--- gate off: nothing is blocked, and no history is asked for
   if(!InpPO3VetoEnabled)
     {
      r.verdict = VETO_NONE;
      return(r);
     }

   //--- A configuration that cannot be evaluated blocks. The bounds mirror
   //--- PO3Step's own clamp so a wild input cannot wrap the step.
   if(InpPO3Scale <= 0.0 || InpPO3VetoBars <= 0 ||
      InpPO3VetoPower < 0 || InpPO3VetoPower > 20 ||
      InpPO3VetoBasePower < 0 || InpPO3VetoBasePower > 20)
      return(r);

   //--- The verdict can only change when a new H4 bar closes, so the bar time
   //--- IS the cache key.
   datetime h4 = iTime(syms[s], PERIOD_H4, 1);
   if(h4 <= 0)
      return(r);
   if(g_veto[s].bar == h4)
      return(g_veto[s]);

   MqlRates rt[];
   int n = CopyRates(syms[s], PERIOD_H4, 1, InpPO3VetoBars, rt);
   if(n <= 0)
      return(r);                         // unreadable: blocks, and is not cached
   ArraySetAsSeries(rt, true);

   long step = PO3Step(InpPO3VetoPower);                              // raw units
   long tol  = (long)MathRound(InpPO3VetoTolFrac *
                               (double)PO3Step(InpPO3VetoBasePower)); // raw units
   if(step <= 0)
      return(r);
   //--- A zero tolerance is a legitimate setting — it means "an exact hit on the
   //--- level counts, nothing near it" — so it is clamped rather than treated as
   //--- an unevaluable configuration. A negative fraction clamps to the same.
   if(tol < 0)
      tol = 0;

   //--- The lookback extreme, and which of the two is the more recent. The
   //--- index is into a series array, so the LOWER index is the NEWER bar.
   int hhI = 0, llI = 0;
   for(int i = 1; i < n; i++)
     {
      if(rt[i].high > rt[hhI].high) hhI = i;
      if(rt[i].low  < rt[llI].low)  llI = i;
     }

   long closeRaw = (long)MathRound(rt[0].close * InpPO3Scale);

   //--- A high TAGS the level it came nearest, and the level is REJECTING
   //--- while the latest closed bar is still back inside it by the tolerance.
   //--- Nothing else is needed for the reclaim: the test is applied to the
   //--- newest close on every read, so a close back through the level simply
   //--- stops the tag from being true.
   long hiRaw = (long)MathRound(rt[hhI].high * InpPO3Scale);
   long hiLvl = (long)MathRound((double)hiRaw / (double)step) * step;
   bool hTag  = (hiLvl > 0) &&
                (MathAbs((double)(hiRaw - hiLvl)) <= (double)tol) &&
                (closeRaw < hiLvl - tol);

   long loRaw = (long)MathRound(rt[llI].low * InpPO3Scale);
   long loLvl = (long)MathRound((double)loRaw / (double)step) * step;
   bool lTag  = (loLvl > 0) &&
                (MathAbs((double)(loRaw - loLvl)) <= (double)tol) &&
                (closeRaw > loLvl + tol);

   if(hTag && lTag)
     {
      bool hiWins = (hhI < llI);         // the newer tag supersedes the older
      r.verdict = hiWins ? VETO_SHORTS : VETO_LONGS;
      r.level   = (double)(hiWins ? hiLvl : loLvl) / InpPO3Scale;
     }
   else if(hTag)
     {
      r.verdict = VETO_SHORTS;           // resistance held: no longs into it
      r.level   = (double)hiLvl / InpPO3Scale;
     }
   else if(lTag)
     {
      r.verdict = VETO_LONGS;            // support held: no shorts into it
      r.level   = (double)loLvl / InpPO3Scale;
     }
   else
      r.verdict = VETO_NONE;

   r.bar     = h4;
   g_veto[s] = r;
   return(r);
  }

//--- The reading as one journal line.
string PO3VetoTag(const string sym, const PO3VetoRead &r)
  {
   if(r.verdict == VETO_UNKNOWN)
      return("veto UNKNOWN (H4 history unreadable) - blocks every entry");
   if(r.verdict == VETO_NONE)
      return("no major-level rejection");

   string side = (r.verdict == VETO_SHORTS) ? " - shorts only" : " - longs only";
   return("rejected at PO3 " + PO3Px(sym, r.level) + side);
  }

//==============================================================
// GATE 5 — THE PO3 DEALING-RANGE ZONE
//
// floor(price/step) x step opens the range price is in and the
// next rung closes it; the fraction across that range is the
// position. The gate refuses a long in the premium part of the
// range and a short in the discount part — buy discount, sell
// premium. The two thresholds are independent so the strict
// thirds (33.3 / 66.7) and the equilibrium line (50 / 50) are the
// same code.
//
// Stateless and tier-independent: it is a question about where
// price is, not about which tier is asking, so every tier reads
// the one range.
//==============================================================

enum ENUM_PO3_ZONE
  {
   ZONE_UNKNOWN     = 0,   // price or range grade unreadable — blocks
   ZONE_DISCOUNT    = 1,   // lower third of the range
   ZONE_EQUILIBRIUM = 2,   // middle third
   ZONE_PREMIUM     = 3    // upper third
  };

struct PO3ZoneRead
  {
   ENUM_PO3_ZONE zone;
   double        lo;    // the range floor
   double        hi;    // the rung above it
   double        pct;   // price's position across the range, 0-100
  };

PO3ZoneRead PO3ZoneReadSym(const int s, const double price)
  {
   PO3ZoneRead r;
   r.zone = ZONE_UNKNOWN;
   r.lo   = 0.0;
   r.hi   = 0.0;
   r.pct  = 0.0;

   //--- gate off: report a zone so the caller's test is never reached
   if(!InpPO3ZoneEnabled)
     {
      r.zone = ZONE_EQUILIBRIUM;
      return(r);
     }

   if(price <= 0.0 || InpPO3Scale <= 0.0 ||
      InpPO3ZonePower < 0 || InpPO3ZonePower > 20)
      return(r);

   double step = (double)PO3Step(InpPO3ZonePower) / InpPO3Scale;
   if(step <= 0.0)
      return(r);

   double lo  = MathFloor(price / step + 1e-9) * step;
   double pct = (price - lo) / step * 100.0;
   if(pct < 0.0)   pct = 0.0;            // a price exactly on the rung
   if(pct > 100.0) pct = 100.0;

   r.lo  = lo;
   r.hi  = lo + step;
   r.pct = pct;

   //--- The LABEL is always the model's thirds, whatever the gate thresholds
   //--- are set to, so the journal means one thing. The thresholds below are
   //--- the gate, and are free to be looser than the thirds.
   double third = 100.0 / 3.0;
   r.zone = (pct < third) ? ZONE_DISCOUNT
            : ((pct > 2.0 * third) ? ZONE_PREMIUM : ZONE_EQUILIBRIUM);
   return(r);
  }

//+------------------------------------------------------------------+
//| Startup read-out for the two new gates.                          |
//|                                                                  |
//| Prints where each symbol stands right now: the reaction verdict   |
//| with the level it came from, and the dealing range price sits in. |
//| A veto is a STATE, not an event, and a state that silently blocks |
//| every entry for days is the failure mode worth designing against  |
//| — so the same reading the entry path takes is printed at load,    |
//| and printed again only when a block's reason changes (BlockNote). |
//+------------------------------------------------------------------+
void PO3VetoLogSetup()
  {
   if(!InpPO3VetoEnabled && !InpPO3ZoneEnabled)
     {
      Print("PO3 vetoes: gate 4 (reaction) OFF and gate 5 (zone) OFF - "
            "entries run on gates 1-3 alone.");
      return;
     }

   if(InpPO3VetoEnabled)
     {
      double tolRaw = InpPO3VetoTolFrac * (double)PO3Step(InpPO3VetoBasePower);
      PrintFormat("PO3 veto: gate 4 ON - major level 3^%d=%d raw, lookback %d closed H4 bars, "
                  "tag tolerance %.2f x 3^%d = %.1f raw = %.1f price units at scale x%g.",
                  InpPO3VetoPower, (int)PO3Step(InpPO3VetoPower), InpPO3VetoBars,
                  InpPO3VetoTolFrac, InpPO3VetoBasePower, tolRaw, tolRaw / InpPO3Scale,
                  InpPO3Scale);
     }
   else
      Print("PO3 veto: gate 4 (reaction) OFF - no rejection veto, entries run as the parent did.");

   if(InpPO3ZoneEnabled)
     {
      PrintFormat("PO3 veto: gate 5 ON - range 3^%d = %.1f price units, long refused above %.1f%%, "
                  "short refused below %.1f%%.",
                  InpPO3ZonePower, (double)PO3Step(InpPO3ZonePower) / InpPO3Scale,
                  InpPO3ZoneLongMaxPct, InpPO3ZoneShortMinPct);
     }
   else
      Print("PO3 veto: gate 5 (zone) OFF - no dealing-range location filter.");

   for(int s = 0; s < symsCount; s++)
     {
      double bid = SymbolInfoDouble(syms[s], SYMBOL_BID);
      if(bid <= 0.0)
         continue;

      if(InpPO3VetoEnabled)
        {
         PO3VetoRead v = PO3VetoReadSym(s);
         //--- the bar note as its own string: a ternary inside the argument list
         //--- is readable here and the codebase avoids it elsewhere
         string barNote = "";
         if(v.bar > 0)
            barNote = " | read on H4 bar " + TimeToString(v.bar);
         PrintFormat("PO3 veto:   %s %s%s", syms[s], PO3VetoTag(syms[s], v), barNote);
        }

      if(InpPO3ZoneEnabled)
        {
         PO3ZoneRead z = PO3ZoneReadSym(s, bid);
         if(z.zone == ZONE_UNKNOWN)
            PrintFormat("PO3 veto:   %s zone UNREADABLE - gate 5 blocks here until it reads.",
                        syms[s]);
         else
           {
            string zoneWord = "equilibrium";
            if(z.zone == ZONE_DISCOUNT)
               zoneWord = "discount";
            else if(z.zone == ZONE_PREMIUM)
               zoneWord = "premium";

            PrintFormat("PO3 veto:   %s range %s..%s %.1f%% -> %s (long max %.1f%%, short min %.1f%%)",
                        syms[s], PO3Px(syms[s], z.lo), PO3Px(syms[s], z.hi), z.pct,
                        zoneWord, InpPO3ZoneLongMaxPct, InpPO3ZoneShortMinPct);
           }
        }
     }
  }

//==============================================================
// Initialization and Deinitialization
//==============================================================

int ParseSymbols(string list)
{
   string parts[];
   int n = StringSplit(list, ',', parts);
   int cnt = 0;
   for(int i = 0; i < n && cnt < MAX_SYMS; i++)
   {
      string sym = parts[i];
      StringTrimLeft(sym);
      StringTrimRight(sym);
      if(StringLen(sym) == 0) continue;
      bool dup = false;
      for(int j = 0; j < cnt; j++)
         if(syms[j] == sym) { dup = true; break; }
      if(dup) continue;
      if(SymbolSelect(sym, true)) syms[cnt++] = sym;
   }
   return cnt;
}

int OnInit()
{
   if(InpPO3Scale <= 0.0)
   {
      Print("PO3 gate: scale divisor must be greater than zero.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   symsCount = ParseSymbols(Symbols);
   if(symsCount <= 0) return(INIT_FAILED);

   PO3PowerParse();

   for(int s = 0; s < symsCount; s++)
   {
      lastM1bar[s] = 0;
      symBlockedUnknown[s] = false;
      g_lastBlock[s] = "";
      m2Ok[s]        = false;
      m2Warned[s]    = false;
      //--- gate 4's cache starts empty: bar 0 means "never read", so the first
      //--- entry check takes a fresh reading rather than trusting a stale one
      g_veto[s].verdict = VETO_UNKNOWN;
      g_veto[s].level   = 0.0;
      g_veto[s].bar     = 0;
      for(int l = 0; l < LEVELS; l++)
      {
         state[s][l] = 0;
         entryPrice[s][l] = 0.0;
         peakHigh[s][l]   = 0.0;
         peakLow[s][l]    = 0.0;
         beMoved[s][l]    = false;
      }

      for(int t = 0; t < TFS; t++)
      {
         //--- M2 is optional and non-fatal: a symbol that refuses it loses the
         //--- rung AND the M2 tier, not the whole expert. It is only asked for
         //--- when one of the two roles actually wants it. Every other timeframe
         //--- is required.
         if(t == IDX_M2 && !InpUseM2 && !InpM2Tier)
         {
            ich[s][t] = INVALID_HANDLE;
            continue;
         }

         ich[s][t] = iIchimoku(syms[s], tfs[t], Tenkan, Kijun, SenkouB);
         if(ich[s][t] == INVALID_HANDLE)
         {
            if(t == IDX_M2)
            {
               Print("M2: " + syms[s] + " refused an M2 Ichimoku handle - BOTH M2 roles are "
                     "DISABLED for this symbol: the rung is gone, so its higher chains run "
                     "as M1 + M5 and up, and the M2 tier cannot open. This broker does not "
                     "serve M2; InpUseM2 and InpM2Tier can be turned off to match.");
               continue;
            }
            return(INIT_FAILED);
         }

         if(t == IDX_M2)
            m2Ok[s] = true;
      }

      ichD1[s] = iIchimoku(syms[s], PERIOD_D1, Tenkan, Kijun, SenkouB);
      if(ichD1[s] == INVALID_HANDLE) return(INIT_FAILED);

      for(int l = 0; l < LEVELS; l++)
      {
         //--- The M2 tier is optional in exactly the way the rung is: a symbol
         //--- without an M2 feed loses the tier, not the expert. Its ATR handle
         //--- is only asked for when the feed exists, so the required-handle
         //--- branch below stays a genuine failure for the other five tiers.
         if(l == LVL_M2 && !m2Ok[s])
         {
            atr[s][LVL_M2] = INVALID_HANDLE;
            continue;
         }

         atr[s][l] = iATR(syms[s], tfs[TfIdxOfLevel(l)], InpATRPeriod);
         if(atr[s][l] == INVALID_HANDLE) return(INIT_FAILED);
      }
   }

   trade.SetDeviationInPoints(Slippage);
   trade.SetExpertMagicNumber(MAGIC);

   //--- Gate 1 as it is actually configured. There is no ladder to print any
   //--- more, but the tolerance is worth stating in the terms it is applied in,
   //--- so the journal says which candles the gate will open on.
   if(InpTimeGateEnabled)
      PrintFormat("Kihon gate: daily H1 — count H1 candles from the day open, open the gate "
                  "within +/-%d of 9 or 17, that is candles %d-%d and %d-%d of the session.",
                  InpTimeTol, 9 - InpTimeTol, 9 + InpTimeTol, 17 - InpTimeTol, 17 + InpTimeTol);
   else
      Print("Kihon gate: OFF — no time filter; entries run on the structure and PO3 gates alone.");

   //--- The M2 roles, per symbol. Both are optional and either can drop out
   //--- silently (no handle, or no history yet), so both are printed rather than
   //--- left to be inferred from a chain that never seems to align or a tier that
   //--- never opens.
   if(!InpUseM2 && !InpM2Tier)
      Print("M2: BOTH roles off - no rung in the higher chains and no M2 tier; "
            "the stack is the parent's with the M2 tier removed.");
   else
      for(int s = 0; s < symsCount; s++)
        {
         string rung = "rung OFF";
         if(InpUseM2)
           {
            if(!m2Ok[s])
               rung = "rung UNAVAILABLE (higher chains run M1 + M5 and up)";
            else
               rung = "rung ON (M1 + M2 + M5 and up; M2 cloud check " +
                      (InpM2CloudFull ? "FULL current+future)" : "future-only)");
           }

         string tier = "M2 tier OFF";
         if(InpM2Tier)
            tier = M2TierActive(s) ? "M2 tier ON (M1 + M2 opens it)"
                                   : "M2 tier UNAVAILABLE (no M2 feed)";

         Print("M2: " + syms[s] + " - " + rung + "; " + tier + ".");
        }

   PO3LogSetup();
   PO3VetoLogSetup();

   SyncStateFromPositions();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   for(int s = 0; s < symsCount; s++)
   {
      for(int t = 0; t < TFS; t++)
         if(ich[s][t] != INVALID_HANDLE) IndicatorRelease(ich[s][t]);
      if(ichD1[s] != INVALID_HANDLE) IndicatorRelease(ichD1[s]);
      for(int l = 0; l < LEVELS; l++)
         if(atr[s][l] != INVALID_HANDLE) IndicatorRelease(atr[s][l]);
   }
}

//==============================================================
// Position State Sync (recover after restart)
//==============================================================

string LevelComment(int lvl, int dir)
{
   return (dir == 1 ? "Exp Buy " : "Exp Sell ") + tfName[TfIdxOfLevel(lvl)];
}

// R2: log an unparseable magic position once per ticket — without the
// ticket memory this would repeat every minute while the position lives.
// After 64 distinct tickets the log goes quiet but the block stays on.
void LogUnknownOnce(ulong ticket, string sym, string comm)
{
   for(int i = 0; i < unknownLoggedCount; i++)
      if(unknownLoggedTickets[i] == ticket) return;
   if(unknownLoggedCount < 64) unknownLoggedTickets[unknownLoggedCount++] = ticket;
   Print(PCTime() + " | !! " + sym + " position #" + IntegerToString((long)ticket) +
         " carries this EA's magic but its comment \"" + comm +
         "\" names no level — BE/trail/cloud exits CANNOT manage it." +
         " New entries on " + sym + " are blocked until it is closed.");
}

// Rebuild per-level state from the positions on the account so a restart
// mid-trade resumes the correct levels. The position comment carries the
// level (e.g. "Exp Buy M15"). Entry/peak/BE memory is rebuilt for a
// restart mid-trade — the chandelier references from the level-TF history
// since the position opened (R4) — and cleared when the level is flat.
void SyncStateFromPositions()
{
   bool hasPos[MAX_SYMS][LEVELS];
   for(int s = 0; s < symsCount; s++)
   {
      symBlockedUnknown[s] = false;              // R2: re-evaluated every sync
      for(int l = 0; l < LEVELS; l++)
      {
         state[s][l] = 0;
         hasPos[s][l] = false;
      }
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      string sym   = PositionGetString(POSITION_SYMBOL);
      int    magic = (int)PositionGetInteger(POSITION_MAGIC);
      int    type  = (int)PositionGetInteger(POSITION_TYPE);
      string comm  = PositionGetString(POSITION_COMMENT);

      if(magic != MAGIC) continue;

      int dir = (type == POSITION_TYPE_BUY) ? 1 : -1;

      for(int s = 0; s < symsCount; s++)
      {
         if(syms[s] != sym) continue;

         // R2: resolve the level from the comment; an unmatched comment on
         // a magic position means the identity is lost (broker rewrite,
         // partial fill suffix, manual tampering) — block the symbol.
         int lvlMatch = -1;
         for(int l = 0; l < LEVELS; l++)
            if(comm == LevelComment(l, 1) || comm == LevelComment(l, -1))
            {
               lvlMatch = l;
               break;
            }

         if(lvlMatch < 0)
         {
            symBlockedUnknown[s] = true;
            LogUnknownOnce(ticket, sym, comm);
            continue;
         }

         state[s][lvlMatch] = dir;
         hasPos[s][lvlMatch] = true;

         // EA (re)started mid-trade — rebuild the protection references.
         // R4: peaks come from the level-TF bars since the position actually
         // opened, so the chandelier resumes where it left off instead of
         // restarting from the open price.
         if(entryPrice[s][lvlMatch] == 0.0)
         {
            entryPrice[s][lvlMatch] = PositionGetDouble(POSITION_PRICE_OPEN);
            double hi = entryPrice[s][lvlMatch];
            double lo = entryPrice[s][lvlMatch];
            MqlRates hist[];
            int nb = CopyRates(sym, tfs[TfIdxOfLevel(lvlMatch)],
                               (datetime)PositionGetInteger(POSITION_TIME),
                               TimeCurrent(), hist);
            for(int b = 0; b < nb; b++)
            {
               if(hist[b].high > hi) hi = hist[b].high;
               if(hist[b].low  < lo) lo = hist[b].low;
            }
            peakHigh[s][lvlMatch] = hi;
            peakLow[s][lvlMatch]  = lo;
         }
         break;
      }
   }

   // Levels with no open position get their protection memory cleared
   for(int s = 0; s < symsCount; s++)
   {
      for(int l = 0; l < LEVELS; l++)
      {
         if(!hasPos[s][l])
         {
            entryPrice[s][l] = 0.0;
            peakHigh[s][l]   = 0.0;
            peakLow[s][l]    = 0.0;
            beMoved[s][l]    = false;
         }
      }
   }
}

//==============================================================
// Alignment Check: price and chikou both above/below tenkan,
// kijun, and cloud on one timeframe. Returns 1 (bullish),
// -1 (bearish), 0 (none) — identical to the live VPS build.
//==============================================================

int CheckAlign(int s, int tfIdx)
{
   ENUM_TIMEFRAMES tf = tfs[tfIdx];

   int sh      = 1;              // last closed bar
   int chShift = sh + Kijun;     // chikou's chart position for bar sh (Kijun bars back)

   MqlRates rt[];
   if(CopyRates(syms[s], tf, 0, chShift + 1, rt) <= 0) return 0;
   ArraySetAsSeries(rt, true);

   if(ArraySize(rt) <= chShift) return 0;

   double tenkan[1], kijun[1], senA[1], senB[1];
   if(CopyBuffer(ich[s][tfIdx], 0, sh, 1, tenkan) <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 1, sh, 1, kijun)  <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 2, sh, 1, senA)   <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 3, sh, 1, senB)   <= 0) return 0;

   double closeP = rt[sh].close;
   double cHi    = MathMax(senA[0], senB[0]);
   double cLo    = MathMin(senA[0], senB[0]);

   bool above = closeP > tenkan[0] && closeP > kijun[0] && closeP > cHi;
   bool below = closeP < tenkan[0] && closeP < kijun[0] && closeP < cLo;
   if(!above && !below) return 0;

   double tenkan_ch[1], kijun_ch[1], senA_ch[1], senB_ch[1];
   if(CopyBuffer(ich[s][tfIdx], 0, chShift, 1, tenkan_ch) <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 1, chShift, 1, kijun_ch)  <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 2, chShift, 1, senA_ch)   <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 3, chShift, 1, senB_ch)   <= 0) return 0;

   double chik = closeP;
   double cHiC = MathMax(senA_ch[0], senB_ch[0]);
   double cLoC = MathMin(senA_ch[0], senB_ch[0]);

   if(above && chik > rt[chShift].high &&
      chik > tenkan_ch[0] && chik > kijun_ch[0] && chik > cHiC) return  1;

   if(below && chik < rt[chShift].low &&
      chik < tenkan_ch[0] && chik < kijun_ch[0] && chik < cLoC) return -1;

   return 0;
}

//==============================================================
// M2 Rung
//
// M2 is optional and sits between M1 and M5 as a step in the
// chain rather than as a tradable tier — no risk row, no ATR
// handle, no exit of its own. With it on, the M5 tier needs
// M1 + M2 + M5 aligned; every higher tier inherits it, because
// the chain grows through M2 on the way up.
//
// It is SKIPPED rather than enforced when the symbol cannot
// serve it, and that is the important part. CheckAlign returns 0
// on unreadable data, so an M2 rung that was enforced without an
// M2 feed would fail every chain check and stop every entry on
// the symbol — the EA would go silent with nothing in the journal
// to say why. A symbol that refuses an M2 handle at init, or that
// has no M2 bars yet, therefore drops the rung: the chain runs as
// M1 + M5 and up, which is the parent's behaviour, and the
// journal says once per symbol that it did so.
//==============================================================

bool M2RungActive(const int s)
  {
   if(!InpUseM2)  return false;
   if(!m2Ok[s])   return false;

   //--- History loads asynchronously, so a valid handle can still have no
   //--- bars for a while after init. iTime is a local read.
   if(iTime(syms[s], PERIOD_M2, 0) == 0)
     {
      if(!m2Warned[s])
        {
         m2Warned[s] = true;
         Print("M2 rung: " + syms[s] + " has no M2 history yet - the rung is being SKIPPED "
               "and the chain is running as M1 + M5 and up. It joins automatically once the "
               "timeframe loads; if it never does, this symbol's broker does not serve M2 and "
               "InpUseM2 should be turned off.");
        }
      return false;
     }
   return true;
  }

//==============================================================
// Is the M2 TIER live on this symbol?
//
// The rung and the tier are independent switches and this is the
// tier's own: the rung puts M2 into the HIGHER tiers' chains, the
// tier trades M1 + M2 on its own. They share one requirement —
// the M2 feed — but neither implies the other, so this does not
// consult InpUseM2.
//
// Like the rung, a missing M2 feed drops the tier rather than
// blocking the expert: a symbol without M2 loses its M2 tier and
// keeps the other five. No warning is printed here because
// M2RungActive already warns once per symbol, and the rung is on
// by default; the OnInit read-out says which of the two roles is
// live either way.
//==============================================================

bool M2TierActive(const int s)
  {
   if(!InpM2Tier) return false;
   if(!m2Ok[s])   return false;
   if(iTime(syms[s], PERIOD_M2, 0) == 0) return false;   // history not loaded yet
   return true;
  }

//==============================================================
// Chain Check (bottom-up): the full stack M1..topIdx must be
// aligned in the SAME direction for a level to open. With the M2
// rung on, M2 is one of the steps the chain has to pass through.
//==============================================================

int ChainAligned(int s, int topIdx)
{
   int dir = CheckAlign(s, IDX_M1);
   if(dir == 0) return 0;

   for(int t = IDX_M2; t <= topIdx; t++)
   {
      //--- The rung may be SKIPPED when it is inactive — but never for the M2
      //--- TIER itself, whose whole chain IS M2. `t < topIdx` is that guard: for
      //--- the M2 tier topIdx is IDX_M2, so this cannot fire and M2 is required;
      //--- for every tier above it topIdx is larger, and the skip is the rung
      //--- switch. Without the guard an inactive rung would leave the M2 tier
      //--- validating on M1 alone and opening M2 trades on one timeframe — the
      //--- whole point of the tier is that it needs two.
      //---
      //--- A symbol with no M2 feed needs no special case here: CheckAlign on an
      //--- unreadable M2 returns 0, so the M2 tier simply never opens.
      if(t == IDX_M2 && t < topIdx && !M2RungActive(s)) continue;   // rung off, or no M2 feed
      if(CheckAlign(s, t) != dir) return 0;
   }
   return dir;
}

//==============================================================
// Daily Bias Filter (H4 tier): D1 is the bias for H4 trades.
// Same alignment semantics as CheckAlign but on D1 — D1 bullish
// (price + chikou above tenkan, kijun and cloud) allows only H4
// buys, D1 bearish only H4 sells. A D1 close INSIDE the cloud
// (or unreadable) returns 0 — no new H4 trades then.
//==============================================================

int DailyAlign(int s)
{
   ENUM_TIMEFRAMES tf = PERIOD_D1;

   int sh      = 1;
   int chShift = sh + Kijun;

   MqlRates rt[];
   if(CopyRates(syms[s], tf, 0, chShift + 1, rt) <= 0) return 0;
   ArraySetAsSeries(rt, true);
   if(ArraySize(rt) <= chShift) return 0;

   double tenkan[1], kijun[1], senA[1], senB[1];
   if(CopyBuffer(ichD1[s], 0, sh, 1, tenkan) <= 0) return 0;
   if(CopyBuffer(ichD1[s], 1, sh, 1, kijun)  <= 0) return 0;
   if(CopyBuffer(ichD1[s], 2, sh, 1, senA)   <= 0) return 0;
   if(CopyBuffer(ichD1[s], 3, sh, 1, senB)   <= 0) return 0;

   double closeP = rt[sh].close;
   double cHi    = MathMax(senA[0], senB[0]);
   double cLo    = MathMin(senA[0], senB[0]);

   bool above = closeP > tenkan[0] && closeP > kijun[0] && closeP > cHi;
   bool below = closeP < tenkan[0] && closeP < kijun[0] && closeP < cLo;
   if(!above && !below) return 0;   // D1 close inside the cloud — no H4 trades

   double tenkan_ch[1], kijun_ch[1], senA_ch[1], senB_ch[1];
   if(CopyBuffer(ichD1[s], 0, chShift, 1, tenkan_ch) <= 0) return 0;
   if(CopyBuffer(ichD1[s], 1, chShift, 1, kijun_ch)  <= 0) return 0;
   if(CopyBuffer(ichD1[s], 2, chShift, 1, senA_ch)   <= 0) return 0;
   if(CopyBuffer(ichD1[s], 3, chShift, 1, senB_ch)   <= 0) return 0;

   double chik = closeP;
   double cHiC = MathMax(senA_ch[0], senB_ch[0]);
   double cLoC = MathMin(senA_ch[0], senB_ch[0]);

   if(above && chik > rt[chShift].high &&
      chik > tenkan_ch[0] && chik > kijun_ch[0] && chik > cHiC) return  1;

   if(below && chik < rt[chShift].low &&
      chik < tenkan_ch[0] && chik < kijun_ch[0] && chik < cLoC) return -1;

   return 0;
}

//==============================================================
// Cloud Bias Filter: the cloud must carry the trade's bias
// (Span A above Span B for a long, below for a short) at BOTH
// the last closed bar (the immediate cloud where price sits)
// and the far end of the future-cloud window. Used ONLY on the
// M1 timeframe (see LevelCloudBiasOK). Unreadable values count
// as blocking.
//==============================================================

bool CloudBiasOK(int s, int tfIdx, int dir)
{
   double aNow[1], bNow[1], aFar[1], bFar[1];
   if(CopyBuffer(ich[s][tfIdx], 2, 1,         1, aNow) <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 3, 1,         1, bNow) <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 2, 1 - Kijun, 1, aFar) <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 3, 1 - Kijun, 1, bFar) <= 0) return false;

   if(dir == 1) return aNow[0] > bNow[0] && aFar[0] > bFar[0];
   return aNow[0] < bNow[0] && aFar[0] < bFar[0];
}

//==============================================================
// Cloud Bias Filter — FUTURE-ONLY: the far end of the future-
// cloud window (Kijun bars ahead of the last closed bar) must
// carry the trade's bias; the immediate cloud where price sits
// may be either direction. Used for every timeframe from M5 up
// in the level gate, and for the H1 stand-in bias confirmation
// (InpH1BiasCloudCheck).
//==============================================================

bool CloudBiasFarOK(int s, int tfIdx, int dir)
{
   double aFar[1], bFar[1];
   if(CopyBuffer(ich[s][tfIdx], 2, 1 - Kijun, 1, aFar) <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 3, 1 - Kijun, 1, bFar) <= 0) return false;

   if(dir == 1) return aFar[0] > bFar[0];
   return aFar[0] < bFar[0];
}

//==============================================================
// Level Cloud Bias Gate (M1-strict): applies to every tier —
// the tier's TF (M5 or above) needs only the FUTURE cloud in the
// trade's direction; the TF directly below it is M1 for the M5
// tier (full check: current AND future must agree with the trade)
// and M5 or above for the higher tiers (future-only).
//
// With the M2 rung on, M2 is the timeframe directly below the
// M5 tier, so it is checked BESIDE M1 rather than instead of it
// — M1 stays the only timeframe that must fully agree, which is
// the rule this build is named for, and the rung must not
// quietly loosen it. The higher tiers are untouched: they still
// check their own TF and the one below, and inherit M1 and M2
// through the chain check instead.
//
// With the rung off, the M5 branch is line-for-line what the
// parent does — M1 in full for the M5 tier, the TF below for
// the rest — so the two settings are a clean A/B.
//
// THE M2 TIER is the new bottom branch. Its own cloud follows the
// M2 rule rather than the M5+ future-only rule — InpM2CloudFull,
// full by default, because a 2-minute bar is close in character
// to M1 — and it sits on M1, which always takes the full
// current+future check. If InpM2CloudFull is switched off, the M2
// tier's own cloud degrades to future-only but the M1 leg stays
// full: M1 is never loosened.
//==============================================================

bool LevelCloudBiasOK(int s, int lvl, int dir)
{
   int tier = TfIdxOfLevel(lvl);

   if(lvl == LVL_M2)
     {
      //--- The M2 tier's OWN cloud, on the M2 rule.
      if(InpM2CloudFull)
        {
         if(!CloudBiasOK(s, IDX_M2, dir)) return false;
        }
      else if(!CloudBiasFarOK(s, IDX_M2, dir)) return false;

      return CloudBiasOK(s, IDX_M1, dir);   // and M1 in full, always
     }

   if(!CloudBiasFarOK(s, tier, dir)) return false;      // tier TF — M5+ — future cloud only

   if(lvl == LVL_M5)
     {
      //--- The M5 tier sits on M1, so it — and only it — carries the full
      //--- current+future M1 check, plus M2 while the rung is active.
      if(!CloudBiasOK(s, IDX_M1, dir)) return false;

      if(M2RungActive(s))
        {
         if(InpM2CloudFull) return CloudBiasOK(s, IDX_M2, dir);
         return CloudBiasFarOK(s, IDX_M2, dir);
        }
      return true;                                      // rung off: M1 was the check below
     }

   return CloudBiasFarOK(s, tier - 1, dir);             // TF below (M5+) — future cloud only
}

//==============================================================
// H4 Bias Filter: H4 is the bias for the whole stack. Every tier
// only trades in H4's direction — H4 bullish means only buys on
// all timeframes (a lower-TF sell is just a pullback), H4 bearish
// means only sells. If H4 has no alignment, no trades open —
// except on the tiers the H1 stand-in bias covers (below).
//==============================================================

int H4Bias(int s)
{
   return CheckAlign(s, IDX_H4);    // 1 = bullish, -1 = bearish, 0 = flat/unreadable
}

//==============================================================
// H1 Bias Filter. The stand-in bias for the lower tiers: same
// alignment test as the H4 bias, one timeframe down, with an
// optional H1 cloud-bias confirmation on top.
//==============================================================

bool H1BiasOK(int s, int dir)
{
   int h1 = CheckAlign(s, IDX_H1);
   if(h1 != dir) return false;      // H1 flat or opposed — nothing to stand in with

   // Optional extra confirmation: the H1 kumo's far end (future
   // cloud) must be twisted the trade's way — the same future-only
   // rule that applies to every M5+ timeframe in the level gate.
   if(InpH1BiasCloudCheck && !CloudBiasFarOK(s, IDX_H1, dir)) return false;

   return true;
}

// Is this tier allowed to fall back on the H1 bias at all?
bool H1BiasTier(int lvl)
{
   if(InpH1BiasMode == H1BIAS_OFF)     return false;
   if(lvl >= LEVELS - 1)               return false;   // never the H4 tier
   return lvl <= (int)InpH1BiasMaxTier;
}

//==============================================================
// Entry Bias Gate: H4 primary, H1 stand-in for the lower tiers.
//
//   1. H4 aligned WITH the trade  -> allowed, whatever the tier.
//      This is the primary path.
//   2. H4 FLAT -> the tiers at or below InpH1BiasMaxTier may still
//      open if H1 carries the trade — an undecided H4 no longer
//      freezes the whole stack.
//   3. H4 aligned AGAINST the trade -> still blocked, unless the
//      user opts into H1BIAS_ALWAYS.
//
// Writes into 'via' the bias that authorised the entry so the caller
// can log it: "H4", "H1" (stand-in on a flat H4), "H1x" (stand-in
// against an aligned H4), "--" when no bias gate applied at all.
//==============================================================

bool EntryBiasOK(int s, int lvl, int dir, string &via)
{
   via = "--";

   if(!InpH4Bias)
   {
      // H4 bias switched off: the H1 stand-in, where enabled, is the only
      // directional gate left on those tiers. Higher tiers stay ungated,
      // exactly as they were when the H4 bias is switched off.
      if(!H1BiasTier(lvl)) return true;
      if(!H1BiasOK(s, dir)) return false;
      via = "H1";
      return true;
   }

   int h4 = H4Bias(s);
   if(h4 == dir) { via = "H4"; return true; }          // primary path

   if(!H1BiasTier(lvl)) return false;                  // H1/H4 tiers need H4 itself
   if(h4 != 0 && InpH1BiasMode != H1BIAS_ALWAYS)       // H4 is aligned the other way
      return false;
   if(!H1BiasOK(s, dir)) return false;

   via = (h4 == 0) ? "H1" : "H1x";   // H1x = taken against an aligned H4
   return true;
}

//==============================================================
// Exit Check: price TOUCHES the level TF's cloud edge — no wait
// for a candle to close inside it. A long (entered above the
// cloud) exits when the bid touches the cloud's upper edge; a
// short (entered below) exits when the ask touches the lower
// edge. Evaluated once per closed M1 bar, so a touch triggers
// the exit within a minute. This is the trade's main exit; the
// BE/chandelier stop is the profit-protection layer on top, and
// the PO3 take profit (gate 3) is a target on the same trade.
//==============================================================

bool InCloudTouch(int s, int tfIdx, int dir)
{
   double senA[1], senB[1];
   if(CopyBuffer(ich[s][tfIdx], 2, 1, 1, senA) <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 3, 1, 1, senB) <= 0) return false;

   if(dir ==  1)
   {
      double bid = SymbolInfoDouble(syms[s], SYMBOL_BID);
      return bid <= MathMax(senA[0], senB[0]);
   }
   if(dir == -1)
   {
      double ask = SymbolInfoDouble(syms[s], SYMBOL_ASK);
      return ask >= MathMin(senA[0], senB[0]);
   }
   return false;
}

//==============================================================
// Utility Functions
//==============================================================

string PCTime()
{
   MqlDateTime dt;
   TimeToStruct(TimeLocal(), dt);
   int h = dt.hour;
   string ampm = (h >= 12) ? "PM" : "AM";
   if(h == 0) h = 12;
   else if(h > 12) h -= 12;
   return IntegerToString(h) + ":" + StringFormat("%02d", dt.min) + " " + ampm;
}

bool SpreadOK(string sym)
{
   if(InpMaxSpreadPoints <= 0) return true;
   return SymbolInfoInteger(sym, SYMBOL_SPREAD) <= InpMaxSpreadPoints;
}

//==============================================================
// Gate block notes (gates 3, 4 and 5).
//
// A gate-3, gate-4 or gate-5 block holds for as long as price sits
// against a level or on the wrong side of a range, which can be
// many minutes, and the check runs once a minute. Printing every
// time would put a line a minute in a VPS journal for as long as
// the condition lasts. So the reason is printed only when it
// CHANGES for that symbol, and the note is cleared when an entry
// does go through — the next block is then news again.
//
// The gate is NOT named in the line. All three share the one
// throttle, so a block that moves from gate 3 to gate 4 and back
// would otherwise print an alternating pair every minute; and the
// reason string itself says which gate it came from.
//==============================================================

string g_lastBlock[MAX_SYMS];

void BlockNote(const int s, const string why)
  {
   if(g_lastBlock[s] == why)
      return;
   g_lastBlock[s] = why;
   PrintFormat("%s | %s entry blocked: %s", PCTime(), syms[s], why);
  }

//--- an entry went through, so the next block is worth reporting again
void BlockClear(const int s)
  {
   g_lastBlock[s] = "";
  }

//==============================================================
// Risk Management — per-level risk as a fixed % of the ACTUAL
// equity at entry, in three equity tiers that DE-RISK as the
// account grows: full regime below InpRiskTier2At (M2 0.5%,
// M5/M15 1%, M30 5%, H1 10%, H4 20%), half regime between the
// tiers (0.25/0.5/0.5/2.5/5/10), and the tiny regime at
// InpRiskTier3At and above (0.05/0.1/0.1/0.2/1/2). The M2 row is
// the new one and deliberately sits below M5: a 2-minute bar is
// close to the noise floor on a wide-spread feed, and a wrong M2
// read costs the same dollars per lot as a wrong M5 read.
// Sizing measures the % against a reference distance of
// ATR(level TF) x InpRiskATRMult — the same reference gate 3
// measures its room in, so "room" and "risk" are in the same
// units by construction. Falls back to InpFixedLots when the
// sizing data is unavailable, and every order is capped to the
// free margin so it fills fully.
//==============================================================

double LevelRiskPct(int lvl)
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   bool t3 = (eq >= InpRiskTier3At);
   bool t2 = (eq >= InpRiskTier2At);
   switch(lvl)
   {
      case LVL_M2: return t3 ? InpRiskPctM2_T3  : t2 ? InpRiskPctM2_T2  : InpRiskPctM2;
      case 1:  return t3 ? InpRiskPctM5_T3  : t2 ? InpRiskPctM5_T2  : InpRiskPctM5;
      case 2:  return t3 ? InpRiskPctM15_T3 : t2 ? InpRiskPctM15_T2 : InpRiskPctM15;
      case 3:  return t3 ? InpRiskPctM30_T3 : t2 ? InpRiskPctM30_T2 : InpRiskPctM30;
      case 4:  return t3 ? InpRiskPctH1_T3  : t2 ? InpRiskPctH1_T2  : InpRiskPctH1;
      case 5:  return t3 ? InpRiskPctH4_T3  : t2 ? InpRiskPctH4_T2  : InpRiskPctH4;
   }
   return 0.0;
}

double RiskLots(int s, int lvl)
{
   double riskPct = LevelRiskPct(lvl);
   if(riskPct <= 0) return InpFixedLots;

   double a[1];
   if(CopyBuffer(atr[s][lvl], 0, 1, 1, a) <= 0 || a[0] <= 0) return InpFixedLots;
   double stopDist = a[0] * InpRiskATRMult;

   double tickValue = SymbolInfoDouble(syms[s], SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(syms[s], SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0 || tickSize <= 0) return InpFixedLots;

   double moneyPerLot = (stopDist / tickSize) * tickValue;
   if(moneyPerLot <= 0) return InpFixedLots;

   double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * (riskPct / 100.0);
   double lots      = riskMoney / moneyPerLot;

   double lotStep = SymbolInfoDouble(syms[s], SYMBOL_VOLUME_STEP);
   double lotMin  = SymbolInfoDouble(syms[s], SYMBOL_VOLUME_MIN);
   double lotMax  = SymbolInfoDouble(syms[s], SYMBOL_VOLUME_MAX);
   if(lotStep > 0) lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(lotMin, MathMin(lotMax, lots));

   return (lots > 0) ? lots : InpFixedLots;
}

// Scale a single order down so it commits at most InpMarginUsePct % of the
// free margin (R5: the parent committed up to 100%, leaving nothing against
// floating drawdown). lots never drops below the broker minimum.
void CapLotsToMargin(string sym, bool isBuy, double &lots)
{
   if(lots <= 0) return;
   double price = isBuy ? SymbolInfoDouble(sym, SYMBOL_ASK)
                        : SymbolInfoDouble(sym, SYMBOL_BID);
   double marginOne = 0.0;
   if(!OrderCalcMargin(isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, sym, lots, price, marginOne))
      return;
   if(marginOne <= 0) return;
   double budget  = AccountInfoDouble(ACCOUNT_MARGIN_FREE) * (InpMarginUsePct / 100.0);
   double maxLots = budget * lots / marginOne;
   double lotStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double lotMin  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   if(lotStep > 0) maxLots = MathFloor(maxLots / lotStep) * lotStep;
   maxLots = MathMax(lotMin, maxLots);
   if(lots > maxLots) lots = maxLots;
}

//==============================================================
// Trading Functions
//==============================================================

// 'via' names the bias that authorised the entry ("H4", "H1" stand-in,
// "H1x" counter-H4 stand-in, "--" none) and 'ks'/'po3' record the two new
// gates, so a reviewed journal entry says which reading let gate 1 through and
// which level the take profit was taken from. tp is 0 for a runner.
bool OpenLevel(int s, int lvl, int dir, double lots, string via, double tp,
               string ks, string po3)
{
   string sym = syms[s];
   string comment = LevelComment(lvl, dir);
   double price = (dir == 1) ? SymbolInfoDouble(sym, SYMBOL_ASK)
                             : SymbolInfoDouble(sym, SYMBOL_BID);

   // R5: pick a filling mode this symbol actually supports — CTrade's FOK
   // default gets retcode 10030 (invalid fill) on IOC-only brokers.
   trade.SetTypeFillingBySymbol(sym);

   // R3: disaster stop — a wide hard SL bounding gap/disconnect loss.
   // Anchored at the entry price so the tail definition is fixed; the BE/
   // chandelier layer takes it over once the trade turns green. If ATR or
   // the broker distance check makes it invalid right now, the order goes
   // out without it and ManageLevelProtection re-attaches next minute.
   double sl = 0.0;
   if(InpDisasterStopEnabled)
   {
      double a[1];
      if(CopyBuffer(atr[s][lvl], 0, 1, 1, a) > 0 && a[0] > 0)
      {
         double point   = SymbolInfoDouble(sym, SYMBOL_POINT);
         double minDist = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * point;
         int    digits  = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
         double dist    = MathMax(a[0] * InpDisasterATRMult, minDist + point);
         sl             = NormalizeDouble((dir == 1) ? price - dist : price + dist, digits);

         // A long's SL triggers on the BID, a short's on the ASK — validate
         // against the side that will actually trip it.
         double bidNow  = SymbolInfoDouble(sym, SYMBOL_BID);
         double askNow  = SymbolInfoDouble(sym, SYMBOL_ASK);
         bool   slValid = (dir == 1) ? (sl > 0 && sl < bidNow - minDist)
                                     : (sl > 0 && sl > askNow + minDist);
         if(!slValid) sl = 0.0;
      }
   }

   // Gate 3: the PO3 level as a take profit. Re-validated here rather than
   // trusted from the gate, because price moved between the two calls.
   double useTp = 0.0;
   if(InpPO3TpEnabled && tp > 0.0)
   {
      double point   = SymbolInfoDouble(sym, SYMBOL_POINT);
      double minDist = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * point;
      double bidNow  = SymbolInfoDouble(sym, SYMBOL_BID);
      double askNow  = SymbolInfoDouble(sym, SYMBOL_ASK);
      bool   tpValid = (dir == 1) ? (tp > askNow + minDist) : (tp < bidNow - minDist);
      if(tpValid) useTp = tp;
   }

   bool ok = (dir == 1) ? trade.Buy(lots, sym, price, sl, useTp, comment)
                        : trade.Sell(lots, sym, price, sl, useTp, comment);
   if(ok)
   {
      state[s][lvl] = dir;
      entryPrice[s][lvl] = price;   // BE + spike-lock trail references
      peakHigh[s][lvl]   = price;
      peakLow[s][lvl]    = price;
      beMoved[s][lvl]    = false;
      string action = (dir == 1) ? "Buy" : "Sell";
      string msg = PCTime() + " | " + action + " " + sym + " " + tfName[TfIdxOfLevel(lvl)] +
                   " @ " + DoubleToString(lots, 2) + " (bottom-up, bias " + via + ")" +
                   " | KS " + ks + " | " + ((useTp > 0.0) ? po3 : po3 + " -> runner (no TP)");
      Print(msg); SendNotification(msg);
   }
   return ok;
}

// Close all positions of the level; returns true only when none remain
// open, so a failed close (requote, halt) is retried instead of freeing
// the level for a fresh entry.
bool CloseLevelPositions(int s, int lvl)
{
   string sym = syms[s];
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) == sym &&
         (int)PositionGetInteger(POSITION_MAGIC) == MAGIC &&
         (PositionGetString(POSITION_COMMENT) == LevelComment(lvl, 1) ||
          PositionGetString(POSITION_COMMENT) == LevelComment(lvl, -1)))
      {
         if(!trade.PositionClose(ticket))
            Print(PCTime() + " | " + sym + " " + tfName[TfIdxOfLevel(lvl)] + " close failed, retcode " +
                  IntegerToString(trade.ResultRetcode()));
      }
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) == sym &&
         (int)PositionGetInteger(POSITION_MAGIC) == MAGIC &&
         (PositionGetString(POSITION_COMMENT) == LevelComment(lvl, 1) ||
          PositionGetString(POSITION_COMMENT) == LevelComment(lvl, -1))) return false;
   }
   return true;
}

//==============================================================
// Profit Protection (VPS-style systems, per level):
//   * Break-even — once the trade is in profit by >= the ATR
//     threshold (InpBEProfitATR x ATR for M2/M5/M15/M30, the tighter
//     InpBEProfitH1H4 x ATR for H1/H4), the stop moves to entry
//     plus InpBECoverPoints. One-shot per trade (beMoved).
//   * Chandelier trail — H1/H4 levels trail the stop behind the
//     peak once profitable by InpTrailActivateATR x ATR; the
//     lower levels arm it only on a spike (InpSpikeLockATR x ATR).
//     The reference is the highest high / lowest low of the level
//     TF, including the bar still forming; it only ever tightens
//     and never sits inside the broker minimum stop.
// ATR comes from the level's own TF, so H4/H1 protection is sized
// to those timeframes. The only hard stop is the wide R3 disaster
// SL; if it ever goes missing, it is re-attached here.
//
// Note for this fork: the PO3 take profit (when one was attached)
// may fire first and close the position. Everything here reads the
// position fresh each minute, so a closed trade simply stops being
// found by LevelTicket and the level's state is cleared by the next
// SyncStateFromPositions — a TP fill needs no special handling.
//==============================================================

bool LevelTicket(int s, int lvl, ulong &ticket)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != syms[s]) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MAGIC) continue;
      string comm = PositionGetString(POSITION_COMMENT);
      if(comm == LevelComment(lvl, 1) || comm == LevelComment(lvl, -1)) return true;
   }
   return false;
}

void ManageLevelProtection(int s, int lvl)
{
   int dir = state[s][lvl];
   if(dir == 0) return;

   double a[1];
   if(CopyBuffer(atr[s][lvl], 0, 1, 1, a) <= 0 || a[0] <= 0) return;
   double atrVal = a[0];

   // The reference point is the extreme of the level-TF bar that is still
   // forming, so a peak is locked in before it retraces
   MqlRates tfx[];
   if(CopyRates(syms[s], tfs[TfIdxOfLevel(lvl)], 0, 1, tfx) <= 0) return;
   ArraySetAsSeries(tfx, true);

   bool isLong = (dir == 1);
   if(isLong)
   {
      if(tfx[0].high > peakHigh[s][lvl]) peakHigh[s][lvl] = tfx[0].high;
   }
   else
   {
      if(tfx[0].low < peakLow[s][lvl]) peakLow[s][lvl] = tfx[0].low;
   }

   double point   = SymbolInfoDouble(syms[s], SYMBOL_POINT);
   double minDist = SymbolInfoInteger(syms[s], SYMBOL_TRADE_STOPS_LEVEL) * point;
   int    digits  = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);

   ulong ticket;
   if(!LevelTicket(s, lvl, ticket)) return;
   double slCur = PositionGetDouble(POSITION_SL);

   double bid = SymbolInfoDouble(syms[s], SYMBOL_BID);
   double ask = SymbolInfoDouble(syms[s], SYMBOL_ASK);

   // R3: self-heal a missing disaster stop (it was skipped at send time
   // because it was invalid then, or stripped later). Anchored at the ENTRY
   // price so the tail definition never drifts; only attaches while no
   // other stop exists — BE/chandelier take over from there and only ever
   // tighten.
   if(InpDisasterStopEnabled && slCur == 0.0)
   {
      double dSl = NormalizeDouble(isLong ? entryPrice[s][lvl] - InpDisasterATRMult * atrVal
                                          : entryPrice[s][lvl] + InpDisasterATRMult * atrVal,
                                   digits);
      bool okD = isLong ? (dSl > 0 && dSl < bid - minDist)
                        : (dSl > ask + minDist);
      if(okD)
      {
         if(trade.PositionModify(ticket, dSl, 0))
            slCur = dSl;
         else
            Print(PCTime() + " | " + syms[s] + " " + tfName[TfIdxOfLevel(lvl)] + " disaster SL attach failed, retcode " +
                  IntegerToString(trade.ResultRetcode()));
      }
   }

   // Break-even: tighter arming threshold on the long-running H1/H4 levels.
   // LVL_H1 is the level index, not a count of tiers: the M2 tier took index 0
   // and pushed H1 from 3 to 4, so this was a bare `lvl >= 3` in the parent.
   double beATR = (lvl >= LVL_H1) ? InpBEProfitH1H4 : InpBEProfitATR;
   if(!beMoved[s][lvl])
   {
      bool armed = isLong ? (bid >= entryPrice[s][lvl] + beATR * atrVal)
                          : (ask <= entryPrice[s][lvl] - beATR * atrVal);
      if(armed)
      {
         double slNew = isLong ? entryPrice[s][lvl] + InpBECoverPoints * point
                               : entryPrice[s][lvl] - InpBECoverPoints * point;
         slNew = NormalizeDouble(slNew, digits);

         bool ok = isLong ? (slNew > slCur + point && slNew < bid - minDist)
                          : (slNew < slCur - point && slNew > ask + minDist);
         if(ok)
         {
            if(!trade.PositionModify(ticket, slNew, 0))
               Print(PCTime() + " | " + syms[s] + " " + tfName[TfIdxOfLevel(lvl)] + " BE SL modify failed, retcode " +
                     IntegerToString(trade.ResultRetcode()));
            else
               beMoved[s][lvl] = true;
         }
      }
   }

   // Chandelier trail behind the peak. H1/H4 levels get the full
   // chandelier: it arms once the trade is profitable by InpTrailActivateATR
   // x ATR so long-running higher-TF trades are always protected. The lower
   // levels keep the spike-gated trail (InpSpikeLockATR x ATR). Only ever
   // tightens, keeps out of the broker minimum stop distance, and skips
   // microscopic improvements (0.3x ATR).
   // Re-read the current stop first — the BE block above may have moved it.
   if(!LevelTicket(s, lvl, ticket)) return;
   slCur = PositionGetDouble(POSITION_SL);

   double armATR = (lvl >= LVL_H1) ? InpTrailActivateATR : InpSpikeLockATR;
   bool armed = isLong ? (bid >= entryPrice[s][lvl] + armATR * atrVal)
                       : (ask <= entryPrice[s][lvl] - armATR * atrVal);
   if(armed)
   {
      double slNew = isLong ? peakHigh[s][lvl] - InpTrailATR * atrVal
                            : peakLow[s][lvl] + InpTrailATR * atrVal;
      slNew = NormalizeDouble(slNew, digits);

      bool ok = isLong ? (slNew > slCur + point && slNew < bid - minDist &&
                          slNew - slCur >= 0.3 * atrVal)
                       : (slNew < slCur - point && slNew > ask + minDist &&
                          slCur - slNew >= 0.3 * atrVal);
      if(ok)
      {
         if(!trade.PositionModify(ticket, slNew, 0))
            Print(PCTime() + " | " + syms[s] + " " + tfName[TfIdxOfLevel(lvl)] + " trail SL modify failed, retcode " +
                  IntegerToString(trade.ResultRetcode()));
      }
   }
}

//==============================================================
// Rejection Candle Exit: closes a trade when a VERY STRONG
// rejection forms against it on the tier TF (last closed bar).
// All four conditions must hold — a swing sweep plus a dominant
// wick plus a strong close-back on a candle whose body opposes
// the trade:
//   Bearish rejection (kills a LONG):
//     - bearish body (c1 < o1)
//     - takes out the swing high of the previous
//       InpRejSwingBars bars (h1 > highest high before it)
//     - upper wick >= InpRejWickPct of the candle's total range
//     - close in the bottom InpRejClosePct of the range
//   Bullish rejection (kills a SHORT): mirrored.
// Returns 1 (bullish), -1 (bearish), 0 (none).
//==============================================================

int RejectionCandle(int s, int tfIdx)
{
   int need = 2 + InpRejSwingBars;
   MqlRates r[];
   if(CopyRates(syms[s], tfs[tfIdx], 0, need, r) < need) return 0;
   ArraySetAsSeries(r, true);

   double o1 = r[1].open, c1 = r[1].close, h1 = r[1].high, l1 = r[1].low;

   // Swing extreme of the InpRejSwingBars bars before the rejection candle
   double swingHi = r[2].high, swingLo = r[2].low;
   for(int i = 3; i < need; i++)
   {
      if(r[i].high > swingHi) swingHi = r[i].high;
      if(r[i].low  < swingLo) swingLo = r[i].low;
   }

   double range = h1 - l1;
   if(range <= 0) return 0;

   // Bearish rejection: sweeps the swing high and closes strongly back
   if(c1 < o1 && h1 > swingHi)
   {
      double upperWick = h1 - o1;               // bearish: high minus open
      double closeBack = c1 - l1;               // distance closed back from the low
      if(upperWick >= InpRejWickPct * range &&
         closeBack <= InpRejClosePct * range)
         return -1;
   }

   // Bullish rejection: sweeps the swing low and closes strongly back
   if(c1 > o1 && l1 < swingLo)
   {
      double lowerWick = o1 - l1;               // bullish: open minus low
      double closeBack = h1 - c1;               // distance closed back from the high
      if(lowerWick >= InpRejWickPct * range &&
         closeBack <= InpRejClosePct * range)
         return 1;
   }
   return 0;
}

// Close a level's positions with a notification; returns true only
// when nothing remains open, so a failed close is retried next bar.
bool ExitLevel(int s, int l, string reason)
{
   string side = (state[s][l] == 1) ? "Long" : "Short";
   string msg  = PCTime() + " | Close " + syms[s] + " " + side + " " +
                 tfName[TfIdxOfLevel(l)] + " (" + reason + ")";
   Print(msg); SendNotification(msg);

   if(CloseLevelPositions(s, l))
   {
      state[s][l] = 0;
      msg = PCTime() + " | " + syms[s] + " " + tfName[TfIdxOfLevel(l)] + " level closed";
      Print(msg); SendNotification(msg);
      return true;
   }
   Print(PCTime() + " | " + syms[s] + " " + tfName[TfIdxOfLevel(l)] + " exit signal but positions still open — will retry");
   return false;
}

//==============================================================
// Main Loop
//
// The gate chain runs in the order the header sets out: gate 1
// (time) once per symbol, then per tier gate 2 (structure, which
// is what the parent already did) and finally gate 3 (PO3).
// Gate 1 is checked before the tier loop because it does not
// depend on the tier — one reading covers the whole symbol, and
// it is the cheapest veto available.
//==============================================================

void OnTick()
{
   // VPS perf: all logic runs only on closed M1 bars, which change at most
   // once per minute. Skip every intermediate tick entirely.
   int nowKey = (int)(TimeCurrent() / 60);
   if(nowKey == lastMinuteKey) return;
   lastMinuteKey = nowKey;

   bool synced = false;
   for(int s = 0; s < symsCount; s++)
   {
      // Per-symbol M1 bar gating — only act on a new closed M1 bar for this symbol
      MqlRates m1[];
      if(CopyRates(syms[s], PERIOD_M1, 0, 2, m1) < 2) continue;
      ArraySetAsSeries(m1, true);
      if(m1[1].time == lastM1bar[s]) continue;
      lastM1bar[s] = m1[1].time;

      // Sync position state once per tick on the first new M1 bar instead of
      // rebuilding it on every single tick.
      if(!synced) { SyncStateFromPositions(); synced = true; }

      // Exits and profit protection per level
      for(int l = 0; l < LEVELS; l++)
      {
         // Exit check: price touched the level TF's cloud edge
         if(state[s][l] != 0 && InCloudTouch(s, TfIdxOfLevel(l), state[s][l]))
            ExitLevel(s, l, "kumo touch");

         // Rejection exit: a very strong rejection candle formed on
         // the tier TF against the trade (bearish kills a long,
         // bullish kills a short)
         if(InpRejectionExit && state[s][l] != 0)
         {
            int rj = RejectionCandle(s, TfIdxOfLevel(l));
            if(rj != 0 && rj == -state[s][l])
               ExitLevel(s, l, "rejection");
         }

         // Profit protection: BE + spike-lock chandelier trail
         if(state[s][l] != 0) ManageLevelProtection(s, l);
      }

      //--- GATE 1 (time): is a kihon suchi turn due, within the +/- range?
      //--- Read once per symbol per minute; it is tier-independent, and it
      //--- is the first veto so the alignment work below is skipped entirely
      //--- on the minutes it fails.
      string tinfo  = "";
      bool   timeOK = TimeGateOK(s, tinfo);

      //--- GATES 4 and 5 are symbol-wide, like gate 1, and read once per symbol
      //--- per minute rather than per tier: the reaction verdict (a cache hit on
      //--- most minutes, since it only changes when an H4 bar closes) and the
      //--- dealing-range zone. Both are DIRECTIONAL, so each is tested per tier
      //--- against that tier's own direction inside the loop below.
      //---
      //--- The zone is read off the BID for both directions. The spread is a
      //--- rounding error against a range of hundreds of units, and using one
      //--- price keeps the two tiers' readings comparable.
      PO3VetoRead veto = PO3VetoReadSym(s);
      PO3ZoneRead zone = PO3ZoneReadSym(s, SymbolInfoDouble(syms[s], SYMBOL_BID));

      // Entry consolidation: when several tiers align at once, only the
      // LARGEST one opens (highest TF wins). Any smaller tier already
      // running on the symbol is closed first — e.g. M15 and M30 align
      // together: the running M15 trade closes and only M30 opens.
      int    topTier = -1;
      int    topDir  = 0;
      string topVia  = "--";
      double topTp   = 0.0;
      string topPo3  = "PO3 off";
      // R2: never add exposure while an unmanageable (unparseable-comment)
      // magic position sits on this symbol; exits/protection still run.
      if(!symBlockedUnknown[s] && SpreadOK(syms[s]) && timeOK)
      {
         for(int l = LEVELS - 1; l >= 0; l--)
         {
            if(state[s][l] != 0) continue;

            //--- The M2 tier is the one optional TIER: off by request, or
            //--- unavailable because this symbol has no M2 feed. Either way it
            //--- simply never opens and nothing else about the stack changes —
            //--- the higher tiers keep their own chains and the exits for an
            //--- already-open M2 trade still run below, above this loop.
            if(l == LVL_M2 && !M2TierActive(s)) continue;

            //--- GATE 2 (structure): the parent's chain, cloud bias and
            //--- directional bias gates, unchanged.
            int st = ChainAligned(s, TfIdxOfLevel(l));
            if(st == 0) continue;
            if(InpCloudBiasEnabled && !LevelCloudBiasOK(s, l, st)) continue;

            // Directional bias: H4 as before, with the H1 stand-in for
            // the lower tiers when H4 has no direction of its own.
            string via = "--";
            if(!EntryBiasOK(s, l, st, via)) continue;

            // H4 tier: D1 must carry the same bias (D1 in the cloud = no H4 trades)
            if(l == LEVELS - 1 && InpD1Filter && DailyAlign(s) != st) continue;

            //--- GATE 3 (price): is there a PO3 level worth acting on, and
            //--- is there room to it? A level closer than InpPO3MinRR means
            //--- price is trading INTO it — that is the veto. Inside the band
            //--- the level becomes the take profit; beyond it, a runner.
            double  refPrice = (st == 1) ? SymbolInfoDouble(syms[s], SYMBOL_ASK)
                                         : SymbolInfoDouble(syms[s], SYMBOL_BID);
            PO3Read po3 = PO3Verdict(s, l, st, refPrice);

            if(po3.verdict == PO3_NO_ROOM && InpPO3RoomFilter)
            {
               BlockNote(s, "no room - next PO3 level only " +
                           DoubleToString(po3.rr, 2) + " R away (min " +
                           DoubleToString(InpPO3MinRR, 2) + ")");
               continue;
            }
            if(po3.verdict == PO3_UNKNOWN && InpPO3RoomFilter)
            {
               BlockNote(s, "PO3 room unknown - ATR not readable");
               continue;
            }

            //--- GATE 4 (reaction): a major PO3 level that has just rejected
            //--- price is a level price is trading INTO, so the entry toward it
            //--- is refused. The verdict is DIRECTIONAL, so only the trade that
            //--- pushes into the level is blocked — entries away from it are
            //--- still allowed, which is the asymmetry §7 measured: the
            //--- level-touch entered WITH the trend won 61.6% against 26.5%
            //--- for the opposite close. This generates nothing; it restricts.
            if(InpPO3VetoEnabled)
            {
               if(veto.verdict == VETO_UNKNOWN)
               {
                  BlockNote(s, "PO3 reaction veto unreadable - H4 history not served");
                  continue;
               }
               if(veto.verdict == VETO_SHORTS && st == 1)
               {
                  BlockNote(s, "rejected at PO3 " + PO3Px(syms[s], veto.level) +
                              " - no longs into it");
                  continue;
               }
               if(veto.verdict == VETO_LONGS && st == -1)
               {
                  BlockNote(s, "rejected at PO3 " + PO3Px(syms[s], veto.level) +
                              " - no shorts into it");
                  continue;
               }
            }

            //--- GATE 5 (location): buy discount, sell premium. Off by default,
            //--- so a first run measures gate 4 alone. The thresholds are what
            //--- the gate tests; the label in the journal is always the model's
            //--- thirds, so the two do not have to be set to the same thing.
            if(InpPO3ZoneEnabled)
            {
               if(zone.zone == ZONE_UNKNOWN)
               {
                  BlockNote(s, "PO3 zone unreadable - price or range grade not available");
                  continue;
               }
               if(st == 1 && zone.pct > InpPO3ZoneLongMaxPct)
               {
                  BlockNote(s, "price at " + DoubleToString(zone.pct, 1) +
                              "% of the PO3 range - no long above " +
                              DoubleToString(InpPO3ZoneLongMaxPct, 1) + "%");
                  continue;
               }
               if(st == -1 && zone.pct < InpPO3ZoneShortMinPct)
               {
                  BlockNote(s, "price at " + DoubleToString(zone.pct, 1) +
                              "% of the PO3 range - no short below " +
                              DoubleToString(InpPO3ZoneShortMinPct, 1) + "%");
                  continue;
               }
            }

            if(!InpPO3Enabled)
               topPo3 = "PO3 gate off";
            else if(po3.verdict == PO3_TARGET)
               topPo3 = PO3Tag(syms[s], po3.level, po3.power) +
                        StringFormat(" @%.2fR", po3.rr);
            else if(po3.verdict == PO3_RUNNER)
               topPo3 = StringFormat("no TP - next level %.2fR away", po3.rr);
            else if(po3.verdict == PO3_NO_ROOM)
               topPo3 = StringFormat("no room (%.2fR) - room filter OFF, so traded with no TP",
                                     po3.rr);
            else
               topPo3 = "PO3 unmeasured";

            topTier = l;
            topDir  = st;
            topVia  = via;
            topTp   = (po3.verdict == PO3_TARGET) ? po3.tp : 0.0;
            break;
         }
      }

      if(topTier >= 0)
      {
         // Close any smaller (lower-tier) trades still running
         for(int l = 0; l < topTier; l++)
         {
            if(state[s][l] != 0)
            {
               string msg = PCTime() + " | Close " + syms[s] + " " + tfName[TfIdxOfLevel(l)] +
                            " (superseded by " + tfName[TfIdxOfLevel(topTier)] + ")";
               Print(msg); SendNotification(msg);

               if(CloseLevelPositions(s, l))
                  state[s][l] = 0;
               else
                  Print(PCTime() + " | " + syms[s] + " " + tfName[TfIdxOfLevel(l)] + " superseded but positions still open — will retry");
            }
         }

         // Open only the largest tier
         double lots = RiskLots(s, topTier);
         CapLotsToMargin(syms[s], (topDir == 1), lots);

         if(OpenLevel(s, topTier, topDir, lots, topVia, topTp, tinfo, topPo3))
            BlockClear(s);
         else
            Print(PCTime() + " | " + syms[s] + " " + tfName[TfIdxOfLevel(topTier)] +
                  " entry signal but order failed, retcode " + IntegerToString(trade.ResultRetcode()));
      }
   }
}
//This work is my worship unto GOD
