//+------------------------------------------------------------------+
//| Ichimoku Bottom-Up Stack EA — KIHON SUCHI + PO3 GATES            |
//|                                                                  |
//| Fork of the live VPS build (ichimoku-h4-m1-vps-ea.mq5, magic      |
//| 20260858): the M1-strict cloud bias and the robustness pack       |
//| (R2-R6) are unchanged. What is new is a TWO-STAGE GATE CHAIN on   |
//| top of the structure gate that was already there, so an entry     |
//| now has to answer three questions in order, cheapest first:       |
//|                                                                  |
//|   GATE 1 — TIME  : is a kihon suchi turn due, within +/-2?        |
//|   GATE 2 — STRUCTURE : does Ichimoku point a direction? (parent)  |
//|   GATE 3 — PRICE : is there a PO3 level worth acting on, and is   |
//|                    there room to it?                              |
//|                                                                  |
//| The parent asked only gate 2. This build asks all three, and      |
//| each gate can veto on its own. Gate 1 is market-wide (it does     |
//| not depend on the tier); gates 2 and 3 are per-tier.              |
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
//| THE LADDER. One count landing on a number is a small turn due;    |
//| several timeframes landing together is a bigger one. So the gate  |
//| reads a LADDER of (timeframe, anchor) pairs — InpTimeLadder,      |
//| default "H4:W,H1:W,M30:W,M15:W", all counted from the WEEK open   |
//| so their times can be read against each other — and requires      |
//| InpTimeMinHits of them (default 2) inside the tolerance.          |
//|                                                                  |
//| Every pair carries its own anchor because a count has to be able  |
//| to REACH the numbers to say anything: M15 counted from the week   |
//| open passes 257 by midweek and is then past the end of the        |
//| series, while H4 from the week open reaches 26 but not 33. The    |
//| week ladder is the "bigger turn" reading; add the day-anchored    |
//| pairs (",H1:D,M30:D,M15:D") for the session reading beside it.    |
//|                                                                  |
//| A pair whose count is unknown (history still loading) or refused  |
//| (anchor further back than the span cap) is NOT a hit and does not |
//| block on its own — the other pairs can still carry the gate.      |
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
//| DELIBERATELY NOT IMPLEMENTED: trading the REACTION at these       |
//| levels. A kihon time that lands on a strong PO3 level is where a  |
//| move often reverses and sometimes continues, and an earlier draft |
//| of this file carried fade / break-and-hold entries for it. They   |
//| were dropped on the user's instruction to start simple, and they  |
//| should not be added back without being asked. Two things are      |
//| worth reading before anyone does:                                 |
//|   * §7 of EXPERIMENTAL-NOTES measured the analogous fade at the   |
//|     H4 Kijun and it won 0/13 — fading a breakout back, even with  |
//|     high ADX or a large extension, lost every time. The SAME      |
//|     level-touch entered WITH the trend won 61.6% against 26.5%    |
//|     for the opposite close. The reversal and the continuation are |
//|     not symmetric, so any such entry wants the bias with it.      |
//|   * §1 already implements the rejection as a directional VETO     |
//|     (PO3Bias: price acting off a major level allows only trades   |
//|     away from it). That is the family's existing answer, and it   |
//|     restricts entries rather than generating them.                |
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
//|     M5 22%, M15 38%, M30 54%, H1 77%, H4 100%                     |
//|   so the H4 tier would never trade again, and H1 nearly never.    |
//|                                                                  |
//|   InpPO3Power = "3,3,4,4,5" (the default) instead:                |
//|     tier  ref risk  step  no room / target / runner               |
//|     M5       4.00     27     22%  /  78%  /   0%                  |
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
//| THE M2 RUNG (optional, InpUseM2).                                |
//|                                                                  |
//| M2 joins the stack between M1 and M5 as a STEP IN THE CHAIN, not  |
//| as a tradable tier. With it on, the M5 tier needs M1 + M2 + M5    |
//| aligned instead of M1 + M5, and every higher tier inherits M2     |
//| because the chain grows through it on the way up. It also joins   |
//| the cloud gate beside the M5 tier's existing M1 check.            |
//|                                                                  |
//| There is deliberately no M2 tier: no risk row, no ATR handle, no  |
//| exit of its own, and the level->timeframe mapping is unchanged    |
//| (levels are still M5..H4). The stack array simply grows a step,   |
//| and every level-to-timeframe lookup now goes through              |
//| TfIdxOfLevel() rather than spelling "+1" at each site.            |
//|                                                                  |
//| M1 stays the only timeframe that must FULLY agree. M2 is checked  |
//| beside it, never instead of it, because loosening the rule this   |
//| build is named for would be a silent change of character. Whether |
//| M2 itself takes the full check or the M5+ future-only rule is     |
//| InpM2CloudFull (default: full, since a 2-minute bar is close in   |
//| character to M1).                                                 |
//|                                                                  |
//| A BROKER WITHOUT M2 IS NOT A FAILURE. M2 is optional and skips    |
//| itself rather than blocking: a symbol that refuses an M2 handle   |
//| at init, or that has no M2 bars yet, drops the rung with one      |
//| journal note and runs its chain as M1 + M5 and up. That matters   |
//| because CheckAlign returns 0 on unreadable data — an M2 rung      |
//| enforced without an M2 feed would fail every chain check and stop |
//| every entry on the symbol, leaving the EA silent with nothing in  |
//| the journal to say why.                                           |
//|                                                                  |
//| InpUseM2 = false reproduces the parent build exactly, so the two  |
//| settings are a clean A/B.                                         |
//|                                                                  |
//| M2 is also a rung in the kihon suchi ladder (gate 1), where it    |
//| wants a DAY anchor rather than the week one the other rungs use — |
//| see the note on InpTimeLadder.                                    |
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
//| Magic: 20260865 — free (20260864 is the highest in use). Shares   |
//|        positions with nothing, and NOT with the live build, so    |
//|        this experiment can run beside production without either   |
//|        managing the other's trades.                              |
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
input double InpRiskPctM5       = 1.0;    // M5   — tier 1 (equity < Tier2At)
input double InpRiskPctM15      = 1.0;    // M15  — tier 1
input double InpRiskPctM30      = 5.0;    // M30  — tier 1
input double InpRiskPctH1       = 10.0;   // H1   — tier 1
input double InpRiskPctH4       = 20.0;   // H4   — tier 1
input double InpRiskPctM5_T2    = 0.5;    // M5   — tier 2 (half regime)
input double InpRiskPctM15_T2   = 0.5;    // M15  — tier 2
input double InpRiskPctM30_T2   = 2.5;    // M30  — tier 2
input double InpRiskPctH1_T2    = 5.0;    // H1   — tier 2
input double InpRiskPctH4_T2    = 10.0;   // H4   — tier 2
input double InpRiskPctM5_T3    = 0.1;    // M5   — tier 3 (equity >= Tier3At)
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
enum ENUM_H1_BIAS_TIER { H1TIER_M5 = 0, H1TIER_M15 = 1, H1TIER_M30 = 2, H1TIER_H1 = 3 };

input group  "Entry Filters"
input bool   InpCloudBiasEnabled = true;   // Require Span A vs Span B bias: M1 current+future must agree; M5+ future cloud only
input bool   InpH4Bias           = true;   // H4 is the bias — tiers trade in H4's direction (H4 flat = no trades unless the H1 bias stands in)
input bool   InpD1Filter         = true;   // D1 filter for the H4 tier: H4 trades only in the D1's direction; D1 in the cloud = no H4 trades
input int    InpMaxSpreadPoints  = 60;     // Max spread in points to allow entry (0 = no limit)

input group  "M2 Rung (optional step between M1 and M5)"
//--- M2 is a RUNG in the chain, not a tradable tier: with it on, the M5 tier
//--- needs M1 + M2 + M5 aligned instead of M1 + M5, and it joins the cloud
//--- gate beside the tier's own check. No new tier, no new risk row, no new
//--- ATR handle — the stack simply grows a step.
//---
//--- Off reproduces the parent build exactly (M1 + M5 and up), so the two
//--- settings are a clean A/B. If the symbol has no M2 feed the rung is
//--- skipped with one journal note rather than blocking — see M2RungActive.
input bool   InpUseM2            = true;   // Insert M2 as a rung between M1 and M5 (off = parent behaviour)
input bool   InpM2CloudFull      = true;   // M2 takes the M1-style full cloud check (current AND future), not the M5+ future-only rule

input group  "H1 Bias (lets the lower tiers trade when H4 is flat)"
input ENUM_H1_BIAS_MODE InpH1BiasMode    = H1BIAS_FLAT_H4; // 0=off (H4 only), 1=stand in only while H4 is flat, 2=stand in even against an aligned H4
input ENUM_H1_BIAS_TIER InpH1BiasMaxTier = H1TIER_M30;     // Highest tier allowed to enter on the H1 bias (0=M5, 1=M15, 2=M30, 3=H1)
input bool   InpH1BiasCloudCheck = true;   // Also require the H1 cloud (Span A vs Span B) to carry the trade's bias

input group  "Profit Protection"
input int    InpATRPeriod         = 14;    // ATR period (each level uses its own TF's ATR)
input double InpBEProfitATR       = 1.0;   // BE arms once profit >= this x ATR (M5/M15/M30 levels)
input double InpBEProfitH1H4      = 0.5;   // BE arms once profit >= this x ATR (H1/H4 levels — tighter)
input int    InpBECoverPoints     = 15;    // Points beyond entry for the BE stop (covers spread)
input double InpSpikeLockATR      = 2.0;   // Chandelier trail arms once profit >= this x ATR (M5/M15/M30 spike lock)
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

//--- GATE 1: the kihon suchi time gate.
input group  "Gate 1 - Kihon Suchi Time"
input bool   InpTimeGateEnabled = true;                  // Require a kihon suchi turn to be due (gate 1)
// One ladder entry is TIMEFRAME:ANCHOR. Timeframes M1 M2 M5 M15 M30 H1 H4
// D1 W1 MN1; anchors D day, W week, M month, Y year, T custom time of day
// (InpTimeAnchorHour/Min, server clock). Every pair carries its own anchor
// because a count has to be able to REACH the numbers to say anything —
// see the GATE 1 note in the header.
//
// M2 is in the list, and it wants a DAY anchor rather than the week one the
// other rungs use. A trading day holds around 690 M2 candles, so every kihon
// number up to 257 is reachable from the day open. From the WEEK open the
// count passes 257 about eight hours into Monday and is then past the end of
// the series for the rest of the week, where it can never register a hit —
// so "M2:W" is a rung that silently does nothing. The default pair is
// therefore "M2:D"; use "M2:T" with InpTimeAnchorHour/Min for a session count.
input string InpTimeLadder      = "H4:W,H1:W,M30:W,M15:W,M2:D"; // Ladder of TF:ANCHOR pairs to read
input int    InpTimeTol         = 2;                     // +/- candles counted as ON the number (the +/-2 range)
input int    InpTimeMinHits     = 2;                     // How many ladder entries must be within the range (N of M)
input bool   InpTimeCompound    = true;                  // Include the compound numbers (33 and up); false = 9, 17, 26 only
input int    InpTimeAnchorHour  = 0;                     // Custom anchor hour, server (for a TF:T pair)
input int    InpTimeAnchorMin   = 0;                     // Custom anchor minute, server (for a TF:T pair)

//--- GATE 3: the PO3 level gate.
input group  "Gate 3 - PO3 Levels"
input bool   InpPO3Enabled     = true;   // Require the next PO3 level to give the trade room (gate 3)
input double InpPO3Scale       = 1.0;    // Scale divisor (1 = whole numbers, 100 = workbook 2dp) — as the indicator
//--- Level power PER TIER, in tier order M5, M15, M30, H1, H4. A single
//--- number applies to every tier. The step for a tier is 3^its power, and
//--- the reason it cannot be one global number is set out under PO3PowerParse:
//--- the room band is measured in the tier's own ATR, and those differ by
//--- about an order of magnitude across the stack.
input string InpPO3Power       = "3,3,4,4,5"; // Level power per tier (a single number = all tiers)
input int    InpPO3MaxPower    = 9;      // Cap on the power reported (9 = 19683, the indicator's top grid)
input double InpPO3MinRR       = 1.5;    // Min reward:risk for a level to qualify as a take profit
input double InpPO3MaxRR       = 8.0;    // Levels beyond this R are runners — no PO3 take profit
input double InpPO3BufferATR   = 0.25;   // Front-run the target level by ATR(tier TF) x this
input bool   InpPO3RoomFilter  = true;   // Skip entries with no room to the next PO3 level
input bool   InpPO3TpEnabled   = true;   // Attach the PO3 level as the trade's take profit
input bool   InpPO3LogSetup    = true;   // Journal the per-tier step / next level / rr at startup

//--- Constants and Global Variables ---
#define MAX_SYMS 60
#define LEVELS   5      // tradable levels: M5, M15, M30, H1, H4
#define TFS      7      // stack: M1, M2, M5, M15, M30, H1, H4
#define IDX_M1   0      // index of M1 — the start of every chain
#define IDX_M2   1      // index of M2 — the OPTIONAL rung between M1 and M5
#define TIER0    2      // index of the first TRADABLE tier (M5) in tfs[]
#define IDX_H1   5      // index of H1 in tfs[] — the stand-in bias TF
#define IDX_H4   6      // index of H4 in tfs[] — the primary bias TF

ENUM_TIMEFRAMES tfs[TFS] = { PERIOD_M1, PERIOD_M2, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4 };
string          tfName[TFS] = { "M1", "M2", "M5", "M15", "M30", "H1", "H4" };

//--- A tradable level's position in tfs[]. The levels are M5..H4 and M2 sits
//--- between M1 and M5 as a rung rather than a tier, so a level's timeframe is
//--- always its own index plus two. Every level-to-timeframe lookup goes
//--- through here rather than spelling "+1" at each site — M2's arrival is
//--- exactly the kind of change that leaves one of those sites behind.
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

int MAGIC = 20260865;   // free — 20260864 is the highest in use. Shares nothing.

CTrade trade;

//==============================================================
// KIHON SUCHI CORE
//
// Ported from experiments/po3-levels.mq5 (the PO3 + kihon indicator)
// so the EA and the chart cannot disagree about where a count stands.
// Comment and arithmetic are kept as they are there, including the
// inclusive counting convention and the nearest-not-next tolerance.
//==============================================================

//--- 3 simple + 9 compound. The simple ones come first and the whole list is
//--- ascending, so a scan can stop early and the first KIHON_SIMPLE entries
//--- are exactly the simple numbers.
#define KIHON_SIMPLE   3
#define KIHON_COUNT    12

const int KihonNumbers[KIHON_COUNT] =
  {
   9, 17, 26,                                   // simple
   33, 42, 51, 65, 76, 129, 172, 226, 257       // compound
  };

//--- Only the offset test is carried over: the EA needs to ask "is the count
//--- ON a number, within the tolerance", and nothing else from the series.
//--- KihonIs / KihonNext / KihonAtOrBelow stay in the indicator, where the
//--- panel and the schedule actually print them.

//+------------------------------------------------------------------+
//| Signed distance from n to the NEAREST kihon suchi number.        |
//|                                                                  |
//| 0 means n is one. Negative means the number is still ahead: 7    |
//| returns -2, two candles short of 9. Positive means it has just   |
//| gone by: 11 returns +2, two candles past 9.                      |
//|                                                                  |
//| The sign convention is n minus the number, so it reads the way   |
//| the chart does - a count running up towards a level shows a      |
//| negative gap closing to zero, then goes positive as it leaves.   |
//|                                                                  |
//| Nearest, not next, because either side matters. A count two       |
//| candles PAST 26 is as much "around 26" as one two candles short  |
//| of it, and a turn that was due at 26 is not cancelled by the     |
//| candle after it.                                                 |
//+------------------------------------------------------------------+
int KihonOffset(const int n, const bool withCompound = true)
  {
   int last = withCompound ? KIHON_COUNT : KIHON_SIMPLE;
   int best = n - KihonNumbers[0];

   for(int i = 1; i < last; i++)
     {
      int d  = n - KihonNumbers[i];
      int ad = (d    < 0) ? -d    : d;
      int ab = (best < 0) ? -best : best;
      if(ad < ab)
         best = d;
     }
   return(best);
  }

//+------------------------------------------------------------------+
//| Where the candle count starts.                                   |
//+------------------------------------------------------------------+
enum ENUM_KIHON_ANCHOR
  {
   KIHON_ANCHOR_DAY   = 0,  // Day open (the D1 candle)
   KIHON_ANCHOR_WEEK  = 1,  // Week open
   KIHON_ANCHOR_MONTH = 2,  // Month open (the 1st)
   KIHON_ANCHOR_YEAR  = 3,  // Year open (1 January)
   KIHON_ANCHOR_TIME  = 4   // Custom time of day (server)
  };

//--- Ceiling on how many candles a count will chase. Past 257 every count
//--- reads the same - there is no kihon number above it - so an exact figure
//--- buys nothing, while getting one forces the history to load. Beyond this
//--- the count reports "too far" instead. Deliberately far above 257 so a
//--- legitimate deep count, a week of M15 at around 480, is still exact.
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
datetime KihonPeriodOpen(const bool year)
  {
   MqlDateTime st;
   TimeToStruct(TimeCurrent(), st);

   if(year)
      st.mon = 1;
   st.day  = 1;
   st.hour = 0;
   st.min  = 0;
   st.sec  = 0;

   //--- day_of_week and day_of_year are ignored by StructToTime, so the
   //--- stale values left in the struct cannot move the result
   return(StructToTime(st));
  }

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
datetime KihonAnchor(const string sym, const ENUM_KIHON_ANCHOR mode,
                     const int hour = 0, const int minute = 0)
  {
   datetime day = iTime(sym, PERIOD_D1, 0);

   if(mode == KIHON_ANCHOR_WEEK)
      return(iTime(sym, PERIOD_W1, 0));
   if(mode == KIHON_ANCHOR_MONTH)
      return(KihonPeriodOpen(false));
   if(mode == KIHON_ANCHOR_YEAR)
      return(KihonPeriodOpen(true));
   if(mode == KIHON_ANCHOR_DAY || day == 0)
      return(day);

   //--- Midnight of the current server day, then the wanted time of day. The
   //--- arithmetic is done in long rather than on datetime: a datetime is
   //--- unsigned, so an intermediate that goes below zero would wrap to the
   //--- far end of the epoch instead of clamping.
   long now = (long)TimeCurrent();
   long mid = now - (now % 86400);
   long h   = (hour   < 0) ? 0 : (hour   > 23 ? 23 : hour);
   long m   = (minute < 0) ? 0 : (minute > 59 ? 59 : minute);
   long at  = mid + h * 3600 + m * 60;

   if(at > now)
      at -= 86400;                    // that time of day has not come round yet

   return((datetime)at < day ? day : (datetime)at);
  }

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
// KIHON TIME GATE (gate 1)
//
// The ladder is parsed once at init from InpTimeLadder, so the
// per-minute path does no string work at all.
//==============================================================

#define TGLADDER_MAX 16

ENUM_TIMEFRAMES    g_tgTf[TGLADDER_MAX];
ENUM_KIHON_ANCHOR  g_tgAnchor[TGLADDER_MAX];
string             g_tgLabel[TGLADDER_MAX];   // "H4:W", for the journal
int                g_tgCount = 0;

//--- "M15" -> PERIOD_M15, and so on. False when the token is not one of
//--- the nine timeframes the ladder accepts.
bool TgTimeframe(const string tok, ENUM_TIMEFRAMES &tf)
  {
   string s = tok;
   StringToUpper(s);

   if(s == "M1")  { tf = PERIOD_M1;  return(true); }
   if(s == "M2")  { tf = PERIOD_M2;  return(true); }
   if(s == "M5")  { tf = PERIOD_M5;  return(true); }
   if(s == "M15") { tf = PERIOD_M15; return(true); }
   if(s == "M30") { tf = PERIOD_M30; return(true); }
   if(s == "H1")  { tf = PERIOD_H1;  return(true); }
   if(s == "H4")  { tf = PERIOD_H4;  return(true); }
   if(s == "D1")  { tf = PERIOD_D1;  return(true); }
   if(s == "W1")  { tf = PERIOD_W1;  return(true); }
   if(s == "MN1") { tf = PERIOD_MN1; return(true); }
   return(false);
  }

//--- A single anchor letter. D/W/M/Y/T, case-insensitive.
bool TgAnchor(const string tok, ENUM_KIHON_ANCHOR &an)
  {
   string s = tok;
   StringToUpper(s);

   if(s == "D") { an = KIHON_ANCHOR_DAY;   return(true); }
   if(s == "W") { an = KIHON_ANCHOR_WEEK;  return(true); }
   if(s == "M") { an = KIHON_ANCHOR_MONTH; return(true); }
   if(s == "Y") { an = KIHON_ANCHOR_YEAR;  return(true); }
   if(s == "T") { an = KIHON_ANCHOR_TIME;  return(true); }
   return(false);
  }

//+------------------------------------------------------------------+
//| Parse "H4:W,H1:W,M30:W,M15:W" into the ladder arrays.            |
//|                                                                  |
//| A malformed pair is REPORTED and dropped rather than failing the |
//| load: a typo in one rung should cost you that rung, not the whole |
//| expert. A ladder that parses to nothing leaves the gate disabled |
//| with a warning, which is the honest reading of "no rungs".       |
//+------------------------------------------------------------------+
void TimeLadderParse()
  {
   g_tgCount = 0;

   string parts[];
   int n = StringSplit(InpTimeLadder, ',', parts);

   for(int i = 0; i < n && g_tgCount < TGLADDER_MAX; i++)
     {
      string item = parts[i];
      StringTrimLeft(item);
      StringTrimRight(item);
      if(StringLen(item) == 0)
         continue;

      string sides[];
      if(StringSplit(item, ':', sides) != 2)
        {
         PrintFormat("Kihon gate: ladder entry \"%s\" is not TIMEFRAME:ANCHOR — dropped.", item);
         continue;
        }

      string tfTok = sides[0];
      string anTok = sides[1];
      StringTrimLeft(tfTok);  StringTrimRight(tfTok);
      StringTrimLeft(anTok);  StringTrimRight(anTok);

      ENUM_TIMEFRAMES   tf;
      ENUM_KIHON_ANCHOR an;
      if(!TgTimeframe(tfTok, tf))
        {
         PrintFormat("Kihon gate: ladder entry \"%s\" — \"%s\" is not a timeframe (M1 M2 M5 M15 M30 H1 H4 D1 W1 MN1) — dropped.",
                     item, tfTok);
         continue;
        }
      if(!TgAnchor(anTok, an))
        {
         PrintFormat("Kihon gate: ladder entry \"%s\" — \"%s\" is not an anchor (D W M Y T) — dropped.",
                     item, anTok);
         continue;
        }

      g_tgTf[g_tgCount]     = tf;
      g_tgAnchor[g_tgCount] = an;
      g_tgLabel[g_tgCount]  = tfTok + ":" + anTok;
      g_tgCount++;
     }

   if(InpTimeGateEnabled && g_tgCount <= 0)
      Print("Kihon gate: no usable ladder entries — gate 1 is DISABLED (every entry passes it).");
  }

//+------------------------------------------------------------------+
//| Gate 1. Read every rung and count the hits.                      |
//|                                                                  |
//| A rung whose count is unknown (0) or refused (-1) is not a hit   |
//| and is not held against the trade — history still loading on one |
//| timeframe must not veto an entry the other rungs approve.        |
//|                                                                  |
//| Writes the hits into 'info' for the journal, so a reviewed entry |
//| says which counts were standing on a number and by how much.     |
//+------------------------------------------------------------------+
bool TimeGateOK(const int s, string &info)
  {
   info = "off";
   if(!InpTimeGateEnabled || g_tgCount <= 0)
      return(true);

   int    hits = 0;
   int    tol  = (int)MathMax(0, MathMin(8, InpTimeTol));
   string txt  = "";

   for(int i = 0; i < g_tgCount; i++)
     {
      datetime anchor = KihonAnchor(syms[s], g_tgAnchor[i], InpTimeAnchorHour, InpTimeAnchorMin);
      int      c      = KihonCount(syms[s], g_tgTf[i], anchor);
      if(c <= 0)
         continue;                        // unknown or refused — not a hit

      int off = KihonOffset(c, InpTimeCompound);
      int mag = (off < 0) ? -off : off;
      if(mag > tol)
         continue;

      hits++;
      //--- "+2" is two candles past the number, "-1" one short, "0" on it.
      //--- The count itself goes in too, so the reading can be checked by
      //--- hand against the indicator's panel.
      txt += (StringLen(txt) > 0 ? " " : "") + g_tgLabel[i] +
             IntegerToString(c) +
             ((off > 0) ? "+" : (off < 0) ? "-" : "=") +
             IntegerToString(mag);
     }

   int need = (int)MathMax(1, InpTimeMinHits);
   info = (hits > 0) ? txt : "none";

   return(hits >= need);
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

   TimeLadderParse();
   PO3PowerParse();

   for(int s = 0; s < symsCount; s++)
   {
      lastM1bar[s] = 0;
      symBlockedUnknown[s] = false;
      g_lastBlock[s] = "";
      m2Ok[s]        = false;
      m2Warned[s]    = false;
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
         //--- rung, not the whole expert. Every other timeframe is required.
         if(t == IDX_M2 && !InpUseM2)
         {
            ich[s][t] = INVALID_HANDLE;
            continue;
         }

         ich[s][t] = iIchimoku(syms[s], tfs[t], Tenkan, Kijun, SenkouB);
         if(ich[s][t] == INVALID_HANDLE)
         {
            if(t == IDX_M2)
            {
               Print("M2 rung: " + syms[s] + " refused an M2 Ichimoku handle - the rung is "
                     "DISABLED for this symbol and its chain will run as M1 + M5 and up. "
                     "This broker does not serve M2; InpUseM2 can be turned off to match.");
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
         atr[s][l] = iATR(syms[s], tfs[TfIdxOfLevel(l)], InpATRPeriod);
         if(atr[s][l] == INVALID_HANDLE) return(INIT_FAILED);
      }
   }

   trade.SetDeviationInPoints(Slippage);
   trade.SetExpertMagicNumber(MAGIC);

   //--- The ladder as parsed, so a typo is visible without hunting for it.
   if(InpTimeGateEnabled)
   {
      string lad = "";
      for(int i = 0; i < g_tgCount; i++)
         lad += (StringLen(lad) > 0 ? " " : "") + g_tgLabel[i];
      PrintFormat("Kihon gate: %d rung(s) [%s], +/-%d candles, %d of %d must hit, compounds %s.",
                  g_tgCount, lad, InpTimeTol, InpTimeMinHits, g_tgCount,
                  InpTimeCompound ? "included" : "OFF (9/17/26 only)");
   }

   //--- The M2 rung, per symbol. It is optional and can drop out silently
   //--- (no handle, or no history yet), so its state is printed rather than
   //--- left to be inferred from a chain that never seems to align.
   if(!InpUseM2)
      Print("M2 rung: OFF - the chain runs M1 + M5 and up, the parent build's behaviour.");
   else
      for(int s = 0; s < symsCount; s++)
        {
         if(m2Ok[s])
            Print("M2 rung: " + syms[s] + " ON - the chain is M1 + M2 + M5 and up; M2 takes the "
                  + (InpM2CloudFull ? "M1-style FULL cloud check (current AND future)."
                                    : "M5+ FUTURE-ONLY cloud check."));
         else
            Print("M2 rung: " + syms[s] + " UNAVAILABLE - rung disabled for this symbol; "
                  "this symbol's chain runs M1 + M5 and up.");
        }

   PO3LogSetup();

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
      if(t == IDX_M2 && !M2RungActive(s)) continue;   // rung off, or no M2 feed
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
// the tier's TF (always M5 or above) needs only the FUTURE
// cloud in the trade's direction; the TF directly below it is
// M1 for the M5 tier (full check: current AND future must
// agree with the trade) and M5 or above for the higher tiers
// (future-only).
//
// With the M2 rung on, M2 is the timeframe directly below the
// M5 tier, so it is checked BESIDE M1 rather than instead of it
// — M1 stays the only timeframe that must fully agree, which is
// the rule this build is named for, and the rung must not
// quietly loosen it. The higher tiers are untouched: they still
// check their own TF and the one below, and inherit M1 and M2
// through the chain check instead.
//
// With the rung off this function is line-for-line what the
// parent does — M1 in full for the M5 tier, the TF below for
// the rest — so the two settings are a clean A/B.
//==============================================================

bool LevelCloudBiasOK(int s, int lvl, int dir)
{
   int tier = TfIdxOfLevel(lvl);

   if(!CloudBiasFarOK(s, tier, dir)) return false;      // tier TF — always M5+ — future cloud only

   if(lvl == 0)
     {
      //--- The M5 tier sits on M1, so it — and only it — carries the full
      //--- current+future check.
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
// Gate 3 block notes.
//
// A gate-3 block holds for as long as price sits against a level,
// which can be many minutes, and the check runs once a minute. Printing
// every time would put a line a minute in a VPS journal for as long as
// the condition lasts. So the reason is printed only when it CHANGES
// for that symbol, and the note is cleared when an entry does go
// through — the next block is then news again.
//==============================================================

string g_lastBlock[MAX_SYMS];

void BlockNote(const int s, const string why)
  {
   if(g_lastBlock[s] == why)
      return;
   g_lastBlock[s] = why;
   PrintFormat("%s | %s entry blocked by gate 3: %s", PCTime(), syms[s], why);
  }

//--- an entry went through, so the next block is worth reporting again
void BlockClear(const int s)
  {
   g_lastBlock[s] = "";
  }

//==============================================================
// Risk Management — per-level risk as a fixed % of the ACTUAL
// equity at entry, in three equity tiers that DE-RISK as the
// account grows: full regime below InpRiskTier2At (M5/M15 1%,
// M30 5%, H1 10%, H4 20%), half regime between the tiers
// (0.5/0.5/2.5/5/10), and the tiny regime at InpRiskTier3At and
// above (0.1/0.1/0.2/1/2). Sizing measures the % against a
// reference distance of ATR(level TF) x InpRiskATRMult — the
// same reference gate 3 measures its room in, so "room" and
// "risk" are in the same units by construction. Falls back to
// InpFixedLots when the sizing data is unavailable, and every
// order is capped to the free margin so it fills fully.
//==============================================================

double LevelRiskPct(int lvl)
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   bool t3 = (eq >= InpRiskTier3At);
   bool t2 = (eq >= InpRiskTier2At);
   switch(lvl)
   {
      case 0:  return t3 ? InpRiskPctM5_T3  : t2 ? InpRiskPctM5_T2  : InpRiskPctM5;
      case 1:  return t3 ? InpRiskPctM15_T3 : t2 ? InpRiskPctM15_T2 : InpRiskPctM15;
      case 2:  return t3 ? InpRiskPctM30_T3 : t2 ? InpRiskPctM30_T2 : InpRiskPctM30;
      case 3:  return t3 ? InpRiskPctH1_T3  : t2 ? InpRiskPctH1_T2  : InpRiskPctH1;
      case 4:  return t3 ? InpRiskPctH4_T3  : t2 ? InpRiskPctH4_T2  : InpRiskPctH4;
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
// gates, so a reviewed journal entry says which rungs hit and which level
// the take profit was taken from. tp is 0 for a runner.
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
//     threshold (InpBEProfitATR x ATR for M5/M15/M30, the tighter
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

   // Break-even: tighter arming threshold on the long-running H1/H4 levels
   double beATR = (lvl >= 3) ? InpBEProfitH1H4 : InpBEProfitATR;
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

   double armATR = (lvl >= 3) ? InpTrailActivateATR : InpSpikeLockATR;
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
