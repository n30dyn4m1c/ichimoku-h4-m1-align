//+------------------------------------------------------------------+
//| Ichimoku Bottom-Up Stack EA (H1 bias) — MARKET PROFILE (EXPERIMENT)|
//| EXPERIMENT — NOT DEPLOYED. Fork of ichimoku-h4-m1-vps-ea.mq5    |
//| (the live VPS build: bottom-up H1-bias stack, M1-strict cloud    |
//| bias, robustness pack R2-R6) with a MARKET PROFILE layer added.  |
//| The production VPS file is untouched.                            |
//|                                                                  |
//| MARKET PROFILE LAYER — a TPO (time-price-opportunity) profile     |
//| rebuilt on every new M1 bar: each bar distributes one TPO-minute  |
//| across the price buckets its [low, high] range covers (weighted   |
//| by coverage), so a bar that spends its minute across several      |
//| buckets spreads its single TPO between them. The POC is the       |
//| bucket with the most TPOs (fair value) and the VALUE AREA is the  |
//| tightest range around it holding InpMPValuePct % of all TPOs      |
//| (VAH = top, VAL = bottom). Bucket height: fixed points via        |
//| InpMPBucketPoints, or adaptive ATR(M1)/10 when 0, clamped so the  |
//| profile always spans 8..2000 buckets.                             |
//|   Profile window (InpMPProfileType):                              |
//|     0 ROLLING  the last InpMPBars closed M1 bars (default 1440 =  |
//|                 one day)                                          |
//|     1 SESSIONS the CURRENT session's profile, the three standard  |
//|                 sessions measured in server time (matching the    |
//|                 MT5 market profile indicator): Tokyo from         |
//|                 InpMPTokyoStart (default 00:00), London from      |
//|                 InpMPLondonStart (default 10:00), New York from   |
//|                 InpMPNYStart (default 16:00) until midnight.      |
//|                 The session that is running right now builds its  |
//|                 profile from its start (filters stay neutral      |
//|                 until InpMPMinBars); when the next session opens, |
//|                 the finished session's final profile is journaled |
//|                 and the new session starts fresh.                 |
//|   DAILY POC KEY LEVELS (always on while InpMPEnabled): the last   |
//|   InpMPDays (default 8, max 8) COMPLETED days' profiles are kept  |
//|   per symbol — each day built from the whole calendar day in      |
//|   server time (00:00-24:00, i.e. all three sessions combined).    |
//|   A day can yield SEVERAL key levels: the significant areas of    |
//|   interest are found by PEAK PROMINENCE analysis (up to 3 — a     |
//|   multi-distribution day, e.g. a morning range and an afternoon   |
//|   range with different POCs); each area's POC is a key level.     |
//|   TREND DAYS are rejected: when the primary POC does not stand    |
//|   out from the distribution — TPO count < InpMPPocMinRatio x the  |
//|   mean bucket count, or the value area spans > InpMPVaMaxSpan of  |
//|   the day's range — the day yields NO key level (journaled as     |
//|   "no sig. POC" with the metrics). Dead days (weekends/holidays,  |
//|   < 60 bars) are skipped entirely. Levels are backfilled at       |
//|   startup, finalized at every server-day rollover, journaled when |
//|   price crosses one, and usable as an entry gate via entry mode   |
//|   4 (daily POC side: longs only at/above the primary POC of the   |
//|   most recent day WITH a significant POC, shorts only at/below    |
//|   it).                                                            |
//|   SHAPE READ (always on): every completed day is classified       |
//|   [N] normal, [2D] double distribution, [TU]/[TD] trend up/down   |
//|   (a one-timeframe market: no significant POC and the close       |
//|   exited value). The days' directions plus the session stack      |
//|   feed a directional read (MPShapeBias).                          |
//|   SESSION STACKING (always on): the last 8 completed sessions     |
//|   (Tokyo/London/New York) are kept per symbol. When consecutive   |
//|   sessions' value areas pile up in one direction — each entirely  |
//|   above the previous (Tokyo flat, London higher, New York         |
//|   higher) — the auction is one-directional; the stack length and  |
//|   direction are journaled at every session close.                 |
//|   AUCTION ENTRY MODES (InpMPEntryMode — default 7 AUTO):         |
//|     5 STACK      enter WITH a session stack on a pullback into    |
//|                  the last session's value area                    |
//|     6 OLD POC    enter when the last closed bar touched an old    |
//|                  daily POC (a key level from days back — the      |
//|                  magnet) and closed back on the near side: the    |
//|                  level rejected price                             |
//|     7 AUTO       (DEFAULT) the EA reads the auction and picks the |
//|                  regime itself, in this order:                    |
//|                    STACK    sessions stacking (>= InpMPStackMin)  |
//|                             = one-directional auction -> trade    |
//|                             WITH it on a pullback into the last   |
//|                             session's value area                  |
//|                    MAGNET   price within InpMPAutoNearATR x       |
//|                             ATR(M1) of an old daily POC -> enter  |
//|                             on the level's rejection              |
//|                    BREAKOUT price exited the active profile's     |
//|                             value area -> enter with the          |
//|                             expansion                             |
//|                    BALANCE  price inside value -> fade the value  |
//|                             area edges, filtered to the multi-day |
//|                             shape read when it has an opinion     |
//|                    DAILY    fallback (or while the active profile |
//|                             builds) -> trade with the primary     |
//|                             daily POC                             |
//|                  The active regime is journaled whenever it       |
//|                  changes.                                         |
//|   AUCTION EXITS: InpMPExitOldPOC — take profit when price reaches |
//|   the next old daily POC in the trade's direction (the magnet     |
//|   target). InpMPExitVA — take profit at the value-area edge       |
//|   (auto-disabled in VA-breakout mode and in AUTO while the regime |
//|   is BREAKOUT, where it would exit entries instantly).            |
//|   InpMPShapeBias — never enter against the multi-day shape read.  |
//|   InpMPEntryMode (default 0 — every filter OFF):                 |
//|     0 OFF         engine builds and journals the profile only;   |
//|                   the EA trades exactly like the parent build    |
//|     1 POC side    longs only at/above the POC, shorts only       |
//|                   at/below it (trade WITH fair value)            |
//|     2 VA breakout longs only above the VAH, shorts only below    |
//|                   the VAL (expansion / trend mode)               |
//|     3 VA reject   long when the last closed M1 bar traded at/    |
//|                   below the VAL and closed back above it (the    |
//|                   value-area edge rejected price); short         |
//|                   mirrored at the VAH                            |
//|     4 daily POC   the primary POC of the most recent completed   |
//|                   day WITH a significant POC is the key level:   |
//|                   longs at/above it, shorts at/below it          |
//|     5 stack       consecutive sessions stacking (each value area |
//|                   above the previous) = a one-directional auction:|
//|                   enter WITH it on a pullback into the last       |
//|                   session's value area                           |
//|     6 old POC     the last closed bar TOUCHED an old daily POC    |
//|                   (a key level from a completed day) and closed   |
//|                   back on the near side — the level rejected      |
//|                   price (magnet reaction)                        |
//|     7 AUTO        (default) the EA reads the auction and picks    |
//|                   the regime itself: STACK -> MAGNET -> BREAKOUT  |
//|                   -> BALANCE -> DAILY-POC fallback                |
//|   InpMPExitVA (default false): a long closes when the bid        |
//|      touches the VAH, a short when the ask touches the VAL — a   |
//|      profile take-profit at the far edge of value. Deliberately  |
//|      ignored in VA-breakout entry mode: an entry beyond the edge |
//|      would exit itself on the very next bar.                     |
//|   While the profile is not ready (fewer than InpMPMinBars in the |
//|   window, or unreadable history) every MP filter PASSES — the    |
//|   layer is neutral and never blocks the parent logic.            |
//|   Validation flow: first run with the defaults (filters OFF) and |
//|   compare the journaled POC/VAH/VAL against a market profile     |
//|   indicator on the chart; then flip InpMPEntryMode and/or        |
//|   InpMPExitVA on for backtests.                                  |
//| Magic: 20260864 — fresh, shares positions with nothing (live VPS |
//|        20260858, desktop 20260860, robustness fork 20260863).    |
//+------------------------------------------------------------------+
//| DIFFERENT MODEL: the top-down builds required every timeframe    |
//| from the anchor down to M1 to agree before a single trade could  |
//| open. This build is BOTTOM-UP — the stack is grown upward from   |
//| M1 and each tier trades its own chain — with DIRECTION granted   |
//| by a bias timeframe (H4 primary, H1 stand-in) instead of by      |
//| top-down agreement.                                              |
//| Entry: per-TF alignment (price + chikou above/below tenkan,      |
//|        kijun and cloud), checked BOTTOM-UP: a tier opens only    |
//|        when the full stack M1..tier TF is aligned in one         |
//|        direction:                                                |
//|          Tier M5 : M1 + M5 aligned              -> open trade    |
//|          Tier M15: M1 + M5 + M15 aligned        -> open trade    |
//|          Tier M30: M1 + M5 + M15 + M30 aligned  -> open trade    |
//|          Tier H1 : M1 ... H1 aligned            -> open trade    |
//|          Tier H4 : M1 ... H4 aligned            -> open trade    |
//|        M1 alone never trades — it is only the start of the stack.|
//|        The cloud bias gate (Span A vs Span B) applies to the tier|
//|        TF and the TF directly below it: M1 must be twisted the   |
//|        trade's way at both the current bar and the far end of the|
//|        future cloud; M5 and above need only the far end — the    |
//|        current cloud may be either direction. H4 is the bias for |
//|        the whole stack (H4 bullish -> buys only, bearish -> sells|
//|        only, flat -> no trades), and the H4 tier itself is also  |
//|        gated by the D1 bias: D1 bullish -> only H4 buys, D1      |
//|        bearish -> only H4 sells, D1 in the cloud -> no H4 trades.|
//|        H1 BIAS: an unaligned H4 would otherwise freeze the whole |
//|        stack, including M5. The lower tiers get a second, smaller|
//|        bias to fall back on: when H4 carries no direction, a tier|
//|        at or below InpH1BiasMaxTier may open provided H1 itself  |
//|        is aligned (same price+chikou test) with the trade. H4    |
//|        aligned WITH the trade is still the primary path; H4      |
//|        aligned AGAINST the trade stays blocked unless            |
//|        InpH1BiasMode = H1BIAS_ALWAYS. The H4 tier never uses the |
//|        stand-in, and the D1 filter on the H4 tier is untouched.  |
//| Exit:  price TOUCHES the level TF's cloud edge (no wait for a  |
//|        candle close inside the kumo). A long exits when the bid |
//|        touches the cloud's upper edge; a short when the ask     |
//|        touches the lower edge. A very strong REJECTION candle   |
//|        against the trade also closes it (sweeps the recent      |
//|        swing extreme of InpRejSwingBars bars, wick >=           |
//|        InpRejWickPct of the range, close in the outer           |
//|        InpRejClosePct — all four conditions must hold). No      |
//|        entry stop loss in this build — the trade runs until an |
//|        exit, with the profit protection layer taking over once  |
//|        it turns green:                                          |
//|          Break-even   : profit >= ATR threshold (tighter for the  |
//|                         H1/H4 levels) -> SL to entry + cover      |
//|          Chandelier   : H1/H4 levels trail the stop behind the    |
//|                         peak once profitable (InpTrailActivateATR);|
//|                         M5/M15/M30 keep the spike-gated trail     |
//|                         (InpSpikeLockATR), only ever tightening   |
//|        ATR comes from each level's own TF.                        |
//| Risk:  single position per level per symbol, but consolidation:  |
//|        when several tiers align at once only the LARGEST opens,  |
//|        and any smaller tier already running on the symbol is     |
//|        closed first — so at most one position per symbol runs at |
//|        a time (the highest aligned tier). Every trade risks a    |
//|        fixed % of the ACTUAL equity at entry, de-risking as the  |
//|        account grows: tier 1 below $7000 (M5/M15 1%, M30 5%, H1  |
//|        10%, H4 20%), tier 2 half regime $7000-$13000             |
//|        (0.5/0.5/2.5/5/10), tier 3 tiny regime $13000+            |
//|        (0.1/0.1/0.2/1/2), against the reference distance          |
//|        ATR(level TF) x InpRiskATRMult (sizing basis only — no     |
//|        entry stop is attached). No multipliers, no streak         |
//|        compounding.                                               |
//| VPS:   no Alert() popups and no equity alert — every entry/exit  |
//|        sends a SendNotification push and a journal Print, and all |
//|        logic runs only on closed M1 bars (once per minute) to     |
//|        keep CPU/network use on a cheap VPS negligible.            |
//| Robustness pack (inherited from the parent, live since           |
//|        2026-08-23): R2 unknown-position guard, R3 disaster stop,  |
//|        R4 peak rebuild after restart, R5 filling/margin          |
//|        robustness, R6 desktop-twin rule (N/A here — experiment). |
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

// Market profile entry modes (EXPERIMENTAL) — see the header block.
//   0 OFF         engine + journal only, trading unchanged
//   1 POC side    trade with fair value: longs at/above POC, shorts at/below
//   2 VA breakout trade the expansion: longs above VAH, shorts below VAL
//   3 VA reject   trade the edge rejection: closed M1 bar reclaims the VAL
//                 (long) or the VAH (short) after trading beyond it
//   4 daily POC   the most recent completed day WITH a significant POC:
//                 longs at/above its primary POC, shorts at/below it
//   5 stack       consecutive sessions stacking (each value area above the
//                 previous) = a one-directional auction: enter WITH it on a
//                 pullback into the last session's value area
//   6 old POC     the last closed bar TOUCHED an old daily POC (a key level
//                 from a completed day) and closed back on the near side —
//                 the level rejected price (magnet reaction)
//   7 AUTO        the EA reads the auction and picks the regime itself
//                 (default): STACK -> MAGNET -> BREAKOUT -> BALANCE ->
//                 daily-POC fallback. See the header block.
enum ENUM_MP_MODE { MPMODE_OFF = 0, MPMODE_POC = 1, MPMODE_VA_OUT = 2, MPMODE_VA_REJECT = 3,
                    MPMODE_DAILY_POC = 4, MPMODE_STACK = 5, MPMODE_OLDPOC = 6, MPMODE_AUTO = 7 };

// The auction regime AUTO mode selects between:
//   STACK    consecutive sessions stacking = one-directional auction —
//            enter WITH it on a pullback into the last session's VA
//   MAGNET   price is within InpMPAutoNearATR x ATR(M1) of an old daily
//            POC — the level is the magnet; enter on its rejection
//   BREAKOUT price has exited the active profile's value area — enter
//            in the direction of the expansion
//   BALANCE  price is inside value — fade the value-area edges, but only
//            with the multi-day shape read when it has an opinion
//   DAILY    fallback when nothing else applies (or the active profile
//            is not ready) — trade with the primary daily POC
enum MP_REGIME { MPREG_DAILY = 0, MPREG_BALANCE = 1, MPREG_BREAK = 2, MPREG_MAGNET = 3, MPREG_STACK = 4 };

// Completed-day profile shapes (the auction's fingerprint):
//   NORMAL    one significant distribution — a balanced day
//   DOUBLE    two or three significant areas of interest — the auction
//             stepped from one value to another (multi-distribution day)
//   TREND_UP  no significant POC (flat/stretched distribution) AND the day
//             closed at/above its value area — a one-timeframe market up
//   TREND_DOWN mirrored — a one-timeframe market down
//   NONE      not classified (dead day, no data)
enum MP_SHAPE { MPSHAPE_NONE = 0, MPSHAPE_NORMAL = 1, MPSHAPE_DOUBLE = 2,
                MPSHAPE_TREND_UP = 3, MPSHAPE_TREND_DOWN = 4 };

// Profile window (EXPERIMENTAL):
//   0 ROLLING  the last InpMPBars closed M1 bars
//   1 SESSIONS the current session's bars since its start — Tokyo
//              (InpMPTokyoStart), London (InpMPLondonStart), New York
//              (InpMPNYStart), in server time; the finished session's
//              final profile is journaled when the next one opens
enum ENUM_MP_PROFILE { MP_PROFILE_ROLLING = 0, MP_PROFILE_SESSIONS = 1 };

input group  "Market Profile (EXPERIMENTAL)"
input bool   InpMPEnabled      = true;    // Master switch: build + journal the TPO profile every M1 bar (filters below default OFF)
input ENUM_MP_PROFILE InpMPProfileType = MP_PROFILE_ROLLING; // 0=rolling window (InpMPBars M1 bars), 1=current session (Tokyo/London/New York)
input int    InpMPBars         = 1440;    // Rolling profile window in M1 bars (1440 = one day; rolling mode only — sessions mode ignores it)
input int    InpMPTokyoStart   = 0;       // Tokyo session start — hour, SERVER time (sessions mode)
input int    InpMPLondonStart  = 10;      // London session start — hour, SERVER time (sessions mode)
input int    InpMPNYStart      = 16;      // New York session start — hour, SERVER time (sessions mode)
input int    InpMPMinBars      = 240;     // Minimum window bars before the profile is READY (session mode: minutes into the current session); filters stay neutral below this
input int    InpMPBucketPoints = 0;       // TPO bucket height in points; 0 = adaptive ATR(M1)/10 (profile clamped to 8..2000 buckets)
input double InpMPValuePct     = 70.0;    // % of TPOs the value area must contain (classic 70)
input int    InpMPDays         = 8;       // Keep this many COMPLETED days of market profiles (1..8); each day's areas of interest yield key levels
input double InpMPPocMinRatio  = 2.0;     // A day's POC is significant only when its TPO count >= this x the mean bucket count (trend-day filter)
input double InpMPVaMaxSpan    = 0.75;    // A day's POC is also rejected when the value area spans > this fraction of the day's range (trend-day filter)
input double InpMPPeakMinPct   = 25.0;    // A secondary area of interest must stand out by >= this % of the main POC's count (prominence)
input int    InpMPStackMin     = 2;       // Consecutive sessions stacked in one direction required for entry mode 5 (stack continuation)
input int    InpMPShapeDays    = 3;       // How many completed days of shapes feed the directional read (1..8)
input bool   InpMPShapeBias    = false;   // Block entries against the multi-day shape read (day shapes + session stacking)
input bool   InpMPExitOldPOC   = false;   // Take profit when price reaches the next old daily POC in the trade's direction
input double InpMPAutoNearATR  = 1.5;     // AUTO mode: within this x ATR(M1) of an old daily POC = magnet regime
input ENUM_MP_MODE InpMPEntryMode = MPMODE_AUTO; // Entry filter: 0=off (log only), 1=POC side, 2=outside value area, 3=value-area edge rejection, 4=daily POC side, 5=stack continuation, 6=old-POC rejection, 7=AUTO (regime auto-selection, default)
input bool   InpMPExitVA       = false;   // Take profit: long closes when bid touches the VAH, short when ask touches the VAL (ignored with entry mode 2)
input bool   InpMPLog          = true;    // Journal profile events: ready, movement (once per H4 bar max), price crossings of POC/VAH/VAL, day close, daily POC crossings

//--- Constants and Global Variables ---
#define MAX_SYMS 60
#define LEVELS   5      // tradable levels: M5, M15, M30, H1, H4
#define TFS      6      // stack: M1, M5, M15, M30, H1, H4
#define IDX_H1   4      // index of H1 in tfs[] — the stand-in bias TF
#define IDX_H4   5      // index of H4 in tfs[] — the primary bias TF

// Market profile: the histogram is capped at this many price buckets so a
// pathological bucket size can never blow up the rebuild cost.
#define MP_MAX_BUCKETS 2000

// Daily POC key levels: keep up to this many COMPLETED days of market
// profiles (InpMPDays, clamped to 1..8). A day may hold up to this many
// significant areas of interest (multi-distribution days), or none at
// all (trend days — no significant POC).
#define MP_MAX_DAYS 8
#define MP_MAX_PEAKS 3

// Session history for the stacking read: keep up to this many COMPLETED
// sessions (2 full days = 6 sessions, plus headroom).
#define MP_MAX_SESS 8

// A day profile needs at least this many M1 bars to count as a level —
// filters out dead days (weekends, exchange holidays) that have no
// meaningful TPO distribution.
#define MP_MIN_DAY_BARS 60

// Result of one profile rebuild — a value struct, assigned wholesale into
// the per-symbol mp[] slot.
struct MPData
{
   double bucketSize;     // height of one TPO bucket in price
   double profileHigh;    // highest high in the window
   double profileLow;     // lowest low in the window
   double poc;            // point of control — bucket center with the most TPOs
   double vah;            // value area high — top of the highest VA bucket
   double val;            // value area low — bottom of the lowest VA bucket
   double pocCount;       // TPO count of the POC bucket
   double totalTpo;       // total TPOs in the window
   int    buckets;        // number of buckets in the histogram
   int    bars;           // bars actually used from the window
   int    sessionId;      // 0 = Tokyo, 1 = London, 2 = New York, -1 = rolling window
   bool   ready;          // window large enough and history readable
};

// One COMPLETED day's profile — kept in a rolling history of the last
// InpMPDays days. A day can have SEVERAL significant areas of interest
// (multi-distribution days — up to MP_MAX_PEAKS of them) or NONE (trend
// days, where the TPO distribution is too flat/stretched for any POC to
// be a meaningful key level). Each significant area's POC is a key level.
// The day is also classified by SHAPE and given a directional read that
// feeds the multi-day shape bias.
struct MPDayLevel
{
   datetime day;              // 00:00 server time of the completed day
   double   poc[MP_MAX_PEAKS];     // POC of each significant area, strongest first
   double   pocCount[MP_MAX_PEAKS];// TPO count at each area's POC
   double   vah;              // whole-day value area high (around the primary POC)
   double   val;              // whole-day value area low
   double   high;             // the day's high
   double   low;              // the day's low
   double   close;            // last closed price of the day
   double   pocRatio;         // primary POC count / mean bucket count (trend-day metric)
   double   vaSpanRatio;      // (vah - val) / (high - low) (trend-day metric)
   int      bars;             // M1 bars the profile was built from
   int      peaks;            // significant areas of interest (0 = trend day / none)
   int      shape;            // MP_SHAPE classification
   int      dir;              // directional read: 1 up, -1 down, 0 balance
   bool     valid;            // profile built successfully
};

// One COMPLETED session's profile — the stacking read. When consecutive
// sessions' value areas pile up in one direction (each entirely above or
// below the previous), the auction is one-directional.
struct MPSessionLevel
{
   datetime start;            // session start (server time)
   int      sessionId;        // 0 = Tokyo, 1 = London, 2 = New York
   double   poc;              // the session's POC
   double   vah;              // the session's value area high
   double   val;              // the session's value area low
   double   high;             // the session's high
   double   low;              // the session's low
   int      bars;             // M1 bars the profile was built from
   bool     valid;            // profile built successfully
};

ENUM_TIMEFRAMES tfs[TFS] = { PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4 };
string          tfName[TFS] = { "M1", "M5", "M15", "M30", "H1", "H4" };

int      ich[MAX_SYMS][TFS];
int      ichD1[MAX_SYMS];           // D1 ichimoku handle — H4-tier bias filter
int      atr[MAX_SYMS][LEVELS];       // ATR(level TF) — BE and spike-lock trail sizing
int      atrM1[MAX_SYMS];             // ATR(M1) — market profile adaptive bucket size
string   syms[MAX_SYMS];
int      symsCount = 0;
datetime lastM1bar[MAX_SYMS];
int      state[MAX_SYMS][LEVELS];     // per level: 0 = flat, 1 = long, -1 = short
int      lastMinuteKey = -1;

double   entryPrice[MAX_SYMS][LEVELS];   // reference entry price per level (BE + trail arming)
double   peakHigh[MAX_SYMS][LEVELS];     // highest high since entry (long chandelier reference)
double   peakLow[MAX_SYMS][LEVELS];      // lowest low since entry (short chandelier reference)
bool     beMoved[MAX_SYMS][LEVELS];      // BE stop already moved to break even (one-shot)

// R2: unknown-position guard. A position carrying our magic whose comment
// no longer names a level cannot be managed (no BE/trail/cloud exit can
// find it) — track it, block new entries on its symbol until it is gone,
// and log it once per ticket (not once per minute).
bool              symBlockedUnknown[MAX_SYMS];
ulong             unknownLoggedTickets[64];
int               unknownLoggedCount   = 0;

// Market profile state per symbol (EXPERIMENTAL)
MPData   mp[MAX_SYMS];
int      mpSession[MAX_SYMS];       // session the stored profile belongs to (-2 none, -1 rolling, 0 Tokyo, 1 London, 2 New York)
datetime mpLastMoveLog[MAX_SYMS];   // H4 bar of the last "profile moved" journal line (max ~6/hour)

// Daily POC key levels (EXPERIMENTAL): the last InpMPDays COMPLETED days,
// index 0 = most recent. Each day's areas of interest yield key levels.
MPDayLevel mpDays[MAX_SYMS][MP_MAX_DAYS];
int        mpDaysCount[MAX_SYMS];       // days actually stored for the symbol
int        mpDaysKeep = MP_MAX_DAYS;    // InpMPDays clamped to 1..MP_MAX_DAYS
int        mpDayKey[MAX_SYMS];          // server date key (YYYYMMDD) of the last seen day — rollover detection
bool       mpDaysBackfilled[MAX_SYMS];  // startup backfill done

// Session stacking (EXPERIMENTAL): the last COMPLETED sessions, index 0 =
// most recent. Consecutive value areas piling in one direction = a
// one-directional auction (e.g. Tokyo flat, London higher, New York higher).
MPSessionLevel mpSess[MAX_SYMS][MP_MAX_SESS];
int        mpSessCount[MAX_SYMS];       // sessions actually stored
bool       mpSessBackfilled[MAX_SYMS];  // startup backfill done
int        mpShapeDays = 3;             // InpMPShapeDays clamped to 1..MP_MAX_DAYS

// AUTO regime (EXPERIMENTAL): the regime selected on the last M1 bar by
// MPAutoDetect() — MPREG_* (or -1 before the first detection). Cached so
// the entry gate and the VA-exit guard share one decision per bar.
int        mpAutoRegime[MAX_SYMS];

int MAGIC = 20260864;   // MARKET PROFILE experiment — fresh, shares positions with nothing (VPS 20260858, desktop 20260860, robustness 20260863)

CTrade trade;

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
   symsCount = ParseSymbols(Symbols);
   if(symsCount <= 0) return(INIT_FAILED);

   for(int s = 0; s < symsCount; s++)
   {
      lastM1bar[s] = 0;
      symBlockedUnknown[s] = false;
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
         ich[s][t] = iIchimoku(syms[s], tfs[t], Tenkan, Kijun, SenkouB);
         if(ich[s][t] == INVALID_HANDLE) return(INIT_FAILED);
      }

      ichD1[s] = iIchimoku(syms[s], PERIOD_D1, Tenkan, Kijun, SenkouB);
      if(ichD1[s] == INVALID_HANDLE) return(INIT_FAILED);

      for(int l = 0; l < LEVELS; l++)
      {
         atr[s][l] = iATR(syms[s], tfs[l + 1], InpATRPeriod);
         if(atr[s][l] == INVALID_HANDLE) return(INIT_FAILED);
      }

      // Market profile state (EXPERIMENTAL)
      atrM1[s] = INVALID_HANDLE;
      mp[s].ready = false;
      mpSession[s] = -2;             // no profile stored yet
      mpLastMoveLog[s] = 0;
      mpDaysCount[s] = 0;
      mpDayKey[s] = 0;               // no day seen yet — first tick backfills
      mpDaysBackfilled[s] = false;
      mpSessCount[s] = 0;
      mpSessBackfilled[s] = false;
      mpAutoRegime[s] = -1;          // no regime detected yet
   }

   // Market profile: M1 ATR handle — the adaptive bucket size AND the AUTO
   // magnet-regime distance both need it, so it is always created.
   if(InpMPEnabled)
   {
      mpDaysKeep = MathMax(1, MathMin(MP_MAX_DAYS, (int)InpMPDays));
      if((int)InpMPDays != mpDaysKeep)
         Print("MP warning: InpMPDays clamped to " + IntegerToString(mpDaysKeep) +
               " (allowed 1.." + IntegerToString(MP_MAX_DAYS) + ")");
      mpShapeDays = MathMax(1, MathMin(MP_MAX_DAYS, (int)InpMPShapeDays));
      if((int)InpMPShapeDays != mpShapeDays)
         Print("MP warning: InpMPShapeDays clamped to " + IntegerToString(mpShapeDays) +
               " (allowed 1.." + IntegerToString(MP_MAX_DAYS) + ")");
      if(InpMPMinBars > InpMPBars && InpMPProfileType == MP_PROFILE_ROLLING)
         Print("MP warning: InpMPMinBars > InpMPBars — the rolling profile can never become ready");
      if(InpMPProfileType == MP_PROFILE_SESSIONS &&
         (InpMPTokyoStart >= InpMPLondonStart || InpMPLondonStart >= InpMPNYStart))
         Print("MP warning: session starts must be ordered Tokyo < London < New York (server hours)");
      for(int s = 0; s < symsCount; s++)
      {
         atrM1[s] = iATR(syms[s], PERIOD_M1, InpATRPeriod);
         if(atrM1[s] == INVALID_HANDLE) return(INIT_FAILED);
      }
   }

   trade.SetDeviationInPoints(Slippage);
   trade.SetExpertMagicNumber(MAGIC);
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
      if(atrM1[s] != INVALID_HANDLE) IndicatorRelease(atrM1[s]);
   }
}

//==============================================================
// Position State Sync (recover after restart)
//==============================================================

string LevelComment(int lvl, int dir)
{
   return (dir == 1 ? "Exp Buy " : "Exp Sell ") + tfName[lvl + 1];
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
            int nb = CopyRates(sym, tfs[lvlMatch + 1],
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
// -1 (bearish), 0 (none) — identical to the H4 VPS build.
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
// Chain Check (bottom-up): the full stack M1..topIdx must be
// aligned in the SAME direction for a level to open.
//==============================================================

int ChainAligned(int s, int topIdx)
{
   int dir = CheckAlign(s, 0);
   if(dir == 0) return 0;

   for(int t = 1; t <= topIdx; t++)
   {
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
// and the far end of the future-cloud window. This is the
// parent's full check — the strictest form. Used ONLY on the
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
// Level Cloud Bias Gate: applies to every tier — the tier's TF
// (lvl+1, always M5 or above) needs only the FUTURE cloud in
// the trade's direction; the TF directly below it is M1 for the
// M5 tier (full check: current AND future must agree with the
// trade) and M5 or above for the higher tiers (future-only).
// So: M1 = both cloud values must agree; M5 upwards = current
// cloud may be any value, future cloud must be in the trade's
// direction.
//==============================================================

bool LevelCloudBiasOK(int s, int lvl, int dir)
{
   if(!CloudBiasFarOK(s, lvl + 1, dir)) return false;   // tier TF — always M5+ — future cloud only
   if(lvl == 0) return CloudBiasOK(s, 0, dir);          // M1 (below the M5 tier) — current AND future
   return CloudBiasFarOK(s, lvl, dir);                  // TF below (M5+) — future cloud only
}

//==============================================================
// H4 Bias Filter: H4 is the bias for the whole stack. Every tier
// only trades in H4's direction — H4 bullish means only buys on
// all timeframes (a lower-TF sell is just a pullback), H4 bearish
// means only sells. If H4 has no alignment, no trades open —
// except on the tiers the new H1 stand-in bias covers (below).
//==============================================================

int H4Bias(int s)
{
   return CheckAlign(s, IDX_H4);    // 1 = bullish, -1 = bearish, 0 = flat/unreadable
}

//==============================================================
// H1 Bias Filter (NEW). The stand-in bias for the lower tiers:
// same alignment test as the H4 bias, one timeframe down, with
// an optional H1 cloud-bias confirmation on top. It is only ever
// consulted by EntryBiasOK() below, and only for the tiers the
// user has opened up via InpH1BiasMaxTier.
//==============================================================

bool H1BiasOK(int s, int dir)
{
   int h1 = CheckAlign(s, IDX_H1);
   if(h1 != dir) return false;      // H1 flat or opposed — nothing to stand in with

   // Optional extra confirmation: the H1 kumo's far end (future
   // cloud) must be twisted the trade's way — the same future-only
   // rule that applies to every M5+ timeframe in the level gate.
   // The immediate cloud is NOT required to match.
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
// BE/chandelier stop is the profit-protection layer on top.
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
// Risk Management — per-level risk as a fixed % of the ACTUAL
// equity at entry, in three equity tiers that DE-RISK as the
// account grows: full regime below InpRiskTier2At (M5/M15 1%,
// M30 5%, H1 10%, H4 20%), half regime between the tiers
// (0.5/0.5/2.5/5/10), and the tiny regime at InpRiskTier3At and
// above (0.1/0.1/0.2/1/2). Sizing measures the % against a
// reference distance of ATR(level TF) x InpRiskATRMult, the same
// ATR-based sizing philosophy as the H4 VPS build. More equity
// -> more risk money -> bigger lots at the same ATR distance;
// no multipliers on top. Falls back to InpFixedLots when the
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
// "H1x" counter-H4 stand-in, "--" none) — logged so the H1-bias trades
// are separable from the H4 ones when reviewing the journal.
bool OpenLevel(int s, int lvl, int dir, double lots, string via)
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

   bool ok = (dir == 1) ? trade.Buy(lots, sym, price, sl, 0, comment)
                        : trade.Sell(lots, sym, price, sl, 0, comment);
   if(ok)
   {
      state[s][lvl] = dir;
      entryPrice[s][lvl] = price;   // BE + spike-lock trail references
      peakHigh[s][lvl]   = price;
      peakLow[s][lvl]    = price;
      beMoved[s][lvl]    = false;
      string action = (dir == 1) ? "Buy" : "Sell";
      string msg = PCTime() + " | " + action + " " + sym + " " + tfName[lvl + 1] +
                   " @ " + DoubleToString(lots, 2) + " (bottom-up, bias " + via + ")";
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
            Print(PCTime() + " | " + sym + " " + tfName[lvl + 1] + " close failed, retcode " +
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
   if(CopyRates(syms[s], tfs[lvl + 1], 0, 1, tfx) <= 0) return;
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
            Print(PCTime() + " | " + syms[s] + " " + tfName[lvl + 1] + " disaster SL attach failed, retcode " +
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
               Print(PCTime() + " | " + syms[s] + " " + tfName[lvl + 1] + " BE SL modify failed, retcode " +
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
            Print(PCTime() + " | " + syms[s] + " " + tfName[lvl + 1] + " trail SL modify failed, retcode " +
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
//       (closed strongly back from the sweep high)
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
                 tfName[l + 1] + " (" + reason + ")";
   Print(msg); SendNotification(msg);

   if(CloseLevelPositions(s, l))
   {
      state[s][l] = 0;
      msg = PCTime() + " | " + syms[s] + " " + tfName[l + 1] + " level closed";
      Print(msg); SendNotification(msg);
      return true;
   }
   Print(PCTime() + " | " + syms[s] + " " + tfName[l + 1] + " exit signal but positions still open — will retry");
   return false;
}

//==============================================================
// MARKET PROFILE LAYER (EXPERIMENT)
// A TPO (time-price-opportunity) profile rebuilt on every new M1
// bar over either window:
//   ROLLING  — the last InpMPBars closed M1 bars;
//   SESSIONS — the CURRENT session's closed bars since its start,
//              where the sessions are Tokyo (InpMPTokyoStart),
//              London (InpMPLondonStart) and New York
//              (InpMPNYStart), all in SERVER time — the same
//              three-session split the MT5 market profile
//              indicator measures.
// In both modes:
//   - each M1 bar distributes ONE TPO-minute across the price
//     buckets its [low, high] range covers, weighted by coverage,
//     so a bar that trades across several buckets spreads its
//     single TPO between them (a flat bar puts it in the bucket
//     of its close)
//   - POC = bucket with the most TPOs (fair value); ties widen to
//     the whole plateau and take the middle bucket
//   - VALUE AREA = the tightest range around the POC holding
//     InpMPValuePct % of all TPOs; VAH = top of the highest
//     included bucket, VAL = bottom of the lowest. Expansion picks
//     the adjacent bucket with the higher count (farther from the
//     POC on a tie), the classic rule.
// Bucket height: fixed points (InpMPBucketPoints) or adaptive
// ATR(M1)/10 (clamped to >= 2 points and to 8..2000 buckets).
//==============================================================

// Session id for a server-time instant: 0 = Tokyo, 1 = London,
// 2 = New York. Hour comparisons in server time; a wrap hour
// (before the Tokyo start when it is not 0) still belongs to the
// previous New York session.
int MPSessionId(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   if(dt.hour >= InpMPNYStart)     return 2;
   if(dt.hour >= InpMPLondonStart) return 1;
   if(dt.hour >= InpMPTokyoStart)  return 0;
   return 2;                       // before Tokyo start — previous NY session
}

// Start of the given session on the day of 't'. Only ever called with
// the ACTIVE session, so the start is always <= t.
datetime MPSessionStart(datetime t, int sid)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = (sid == 2) ? InpMPNYStart : (sid == 1) ? InpMPLondonStart : InpMPTokyoStart;
   dt.min = 0;
   dt.sec = 0;
   return StructToTime(dt);
}

string MPSessionName(int sid)
{
   if(sid == 2) return "New York";
   if(sid == 1) return "London";
   if(sid == 0) return "Tokyo";
   return "rolling";
}

// Bucket height for a profile over the given price range: fixed points via
// InpMPBucketPoints, or adaptive ATR(M1)/10 when 0, clamped to >= 2 points
// and to 8..MP_MAX_BUCKETS buckets across the range. 0 = unusable.
double MPBucketSize(int s, double point, double lo, double hi)
{
   double bs = (InpMPBucketPoints > 0) ? InpMPBucketPoints * point : 0.0;
   if(bs <= 0.0)
   {
      double a[1];
      if(CopyBuffer(atrM1[s], 0, 1, 1, a) <= 0 || a[0] <= 0.0) return 0.0;
      bs = a[0] / 10.0;
      if(bs < 2.0 * point) bs = 2.0 * point;
   }
   double range = hi - lo;
   if(range <= 0.0) return 0.0;
   if(range / bs < 8.0)            bs = range / 8.0;
   if(range / bs > MP_MAX_BUCKETS) bs = range / MP_MAX_BUCKETS;
   return bs;
}

// Count TPOs over 'count' closed bars of 'r' (as-series, index 0 newest,
// first bar used = fromIdx) into a histogram of nb buckets of height bs,
// based at 'base' = lo. Returns false when the histogram cannot be built.
bool MPCountTPO(int s, MqlRates &r[], int fromIdx, int count,
                double lo, double hi, double &counts[], int &nb,
                double &base, double &bs, double &total)
{
   double point = SymbolInfoDouble(syms[s], SYMBOL_POINT);
   bs = MPBucketSize(s, point, lo, hi);
   if(bs <= 0.0) return false;

   nb   = (int)MathCeil((hi - lo) / bs) + 1;
   base = lo;
   if(!ArrayResize(counts, nb)) return false;
   ArrayInitialize(counts, 0.0);

   // TPO counts — every closed bar contributes one TPO-minute, spread
   // across the buckets its range covers proportionally
   total = 0.0;
   for(int i = fromIdx; i < fromIdx + count; i++)
   {
      double bLow = r[i].low, bHigh = r[i].high;
      double bRange = bHigh - bLow;
      if(bRange <= 0.0)
      {
         int k = (int)MathFloor((r[i].close - base) / bs);
         if(k < 0) k = 0;
         else if(k >= nb) k = nb - 1;
         counts[k] += 1.0;
         total += 1.0;
         continue;
      }

      int i0 = (int)MathFloor((bLow  - base) / bs);
      int i1 = (int)MathFloor((bHigh - base) / bs);
      if(i0 < 0)    i0 = 0;
      if(i1 >= nb)  i1 = nb - 1;
      for(int k = i0; k <= i1; k++)
      {
         double bBot = base + k * bs;
         double bTop = bBot + bs;
         double ov = MathMin(bHigh, bTop) - MathMax(bLow, bBot);
         if(ov > 0.0) counts[k] += ov / bRange;
      }
      total += 1.0;
   }
   return (total > 0.0);
}

// Single POC + value area from a histogram — the classic one-distribution
// view used by the active profile and as the day's primary value area.
// Fills the price fields of 'out' and sets ready.
void MPPocVA(double &counts[], int nb, double base, double bs, double total,
             double lo, double hi, MPData &out)
{
   // Point of control — the bucket with the most TPOs; on a tie the
   // middle bucket of the whole plateau wins
   int pocIdx = 0;
   double maxC = counts[0];
   for(int k = 1; k < nb; k++)
      if(counts[k] > maxC) { maxC = counts[k]; pocIdx = k; }

   int runLo = pocIdx, runHi = pocIdx;
   while(runLo > 0     && MathAbs(counts[runLo - 1] - maxC) < 1e-9) runLo--;
   while(runHi < nb - 1 && MathAbs(counts[runHi + 1] - maxC) < 1e-9) runHi++;
   pocIdx = (runLo + runHi) / 2;

   // Value area — expand from the POC, always adding the adjacent bucket
   // with the higher count (farther from the POC on a tie), until it
   // holds InpMPValuePct % of all TPOs
   double target = InpMPValuePct / 100.0 * total;
   double cum    = counts[pocIdx];
   int lowIdx = pocIdx, highIdx = pocIdx;
   while(cum < target && (lowIdx > 0 || highIdx < nb - 1))
   {
      double cL = (lowIdx > 0)     ? counts[lowIdx - 1] : -1.0;
      double cH = (highIdx < nb-1) ? counts[highIdx + 1] : -1.0;
      if(cL < 0.0 && cH < 0.0) break;
      if(cH > cL) { highIdx++; cum += counts[highIdx]; }
      else if(cL > cH) { lowIdx--; cum += counts[lowIdx]; }
      else if(cH >= 0.0)                     // exact tie — take the farther side
      {
         if((highIdx + 1 - pocIdx) > (pocIdx - (lowIdx - 1))) { highIdx++; cum += counts[highIdx]; }
         else                                               { lowIdx--;  cum += counts[lowIdx]; }
      }
   }

   out.bucketSize   = bs;
   out.profileHigh  = hi;
   out.profileLow   = lo;
   out.poc          = base + (pocIdx + 0.5) * bs;
   out.vah          = base + (highIdx + 1) * bs;
   out.val          = base + lowIdx * bs;
   out.pocCount     = counts[pocIdx];
   out.totalTpo     = total;
   out.buckets      = nb;
   out.ready        = true;
}

// Collect the histogram's local maxima (plateau-aware): idx[] bucket
// indices, val[] counts at them. Returns the number found.
int MPCollectPeaks(double &counts[], int nb, int &idx[], double &val[])
{
   int n = 0;
   int k = 0;
   while(k < nb)
   {
      int runEnd = k;
      while(runEnd + 1 < nb && MathAbs(counts[runEnd + 1] - counts[k]) < 1e-9)
         runEnd++;
      bool isMax = true;
      if(k > 0 && counts[k - 1] > counts[k]) isMax = false;
      if(runEnd + 1 < nb && counts[runEnd + 1] > counts[k]) isMax = false;
      if(isMax)
      {
         idx[n] = (k + runEnd) / 2;
         val[n] = counts[k];
         n++;
      }
      k = runEnd + 1;
   }
   return n;
}

// Multi-distribution detection: the significant areas of interest in a
// day's histogram, up to MP_MAX_PEAKS. The strongest peak is always an
// area; a secondary peak counts only when its PROMINENCE — its count
// minus the highest saddle (valley) on any path to a higher peak — is
// >= InpMPPeakMinPct % of the strongest count. That rejects shoulder
// bumps on a big peak while accepting genuinely separate distributions
// (a 2-3 distribution day). Fills dayPocs[] (prices) and dayCounts[]
// (TPO counts), strongest first.
int MPDayAreas(double &counts[], int nb, double base, double bs,
               double &dayPocs[], double &dayCounts[])
{
   int    pkIdx[MP_MAX_BUCKETS];
   double pkVal[MP_MAX_BUCKETS];
   int npk = MPCollectPeaks(counts, nb, pkIdx, pkVal);
   if(npk <= 0) return 0;

   // Sort peaks by count, strongest first (insertion sort — npk is small
   // on real profiles; worst case it is bounded by the bucket count)
   for(int i = 1; i < npk; i++)
   {
      int    ii = pkIdx[i];
      double vv = pkVal[i];
      int j = i - 1;
      while(j >= 0 && pkVal[j] < vv)
      {
         pkIdx[j + 1] = pkIdx[j];
         pkVal[j + 1] = pkVal[j];
         j--;
      }
      pkIdx[j + 1] = ii;
      pkVal[j + 1] = vv;
   }

   double mainCount = pkVal[0];
   double minProm   = InpMPPeakMinPct / 100.0 * mainCount;

   int n = 0;
   for(int i = 0; i < npk && n < MP_MAX_PEAKS; i++)
   {
      if(i > 0)
      {
         // Prominence: the highest valley on any path to a higher peak
         double bestSaddle = -1.0;
         for(int h = 0; h < i; h++)
         {
            int a = (int)MathMin(pkIdx[i], pkIdx[h]);
            int b = (int)MathMax(pkIdx[i], pkIdx[h]);
            double saddle = DBL_MAX;
            for(int k = a; k <= b; k++)
               if(counts[k] < saddle) saddle = counts[k];
            if(saddle > bestSaddle) bestSaddle = saddle;
         }
         if(pkVal[i] - bestSaddle < minProm) continue;
      }
      dayPocs[n]    = base + (pkIdx[i] + 0.5) * bs;
      dayCounts[n]  = pkVal[i];
      n++;
   }
   return n;
}

// Trend-day test: is the day's POC significant at all? A trend day has a
// flat, stretched distribution — its POC barely stands above the mean
// bucket count and/or the value area covers most of the day's range.
bool MPDayPocSignificant(double mainCount, double total, int nb,
                         double vaSpan, double range)
{
   double mean = (nb > 0) ? total / nb : 0.0;
   if(mean <= 0.0) return false;
   if(mainCount / mean < InpMPPocMinRatio) return false;
   if(range > 0.0 && vaSpan / range > InpMPVaMaxSpan) return false;
   return true;
}

// Rebuild the profile for one symbol into 'out'. Returns false when the
// history is unreadable or the window is too thin — the caller keeps the
// old values and treats every MP filter as neutral.
bool BuildMarketProfile(int s, MPData &out)
{
   out.ready       = false;
   out.bucketSize  = 0.0;
   out.profileHigh = 0.0;
   out.profileLow  = 0.0;
   out.poc         = 0.0;
   out.vah         = 0.0;
   out.val         = 0.0;
   out.pocCount    = 0.0;
   out.totalTpo    = 0.0;
   out.buckets     = 0;
   out.bars        = 0;
   out.sessionId   = -1;

   // Window selection: rolling bars, or the active session's bars
   MqlRates r[];
   if(InpMPProfileType == MP_PROFILE_SESSIONS)
   {
      int sid = MPSessionId(TimeCurrent());
      datetime from = MPSessionStart(TimeCurrent(), sid);
      if(CopyRates(syms[s], PERIOD_M1, from, TimeCurrent(), r) <= 0) return false;
      out.sessionId = sid;
   }
   else
   {
      int need = InpMPBars + 1;                    // +1: index 0 is the bar still forming
      if(CopyRates(syms[s], PERIOD_M1, 0, need, r) <= 0) return false;
   }
   ArraySetAsSeries(r, true);
   int bars = ArraySize(r) - 1;                    // closed bars in the window
   if(bars < InpMPMinBars) return false;

   // Pass 1: the window's price range
   double lo = DBL_MAX, hi = -DBL_MAX;
   for(int i = 1; i <= bars; i++)
   {
      if(r[i].low  < lo) lo = r[i].low;
      if(r[i].high > hi) hi = r[i].high;
   }
   if(hi - lo <= 0.0) return false;

   double counts[];
   int    nb;
   double base, bs, total;
   if(!MPCountTPO(s, r, 1, bars, lo, hi, counts, nb, base, bs, total)) return false;
   MPPocVA(counts, nb, base, bs, total, lo, hi, out);
   out.bars = bars;
   return true;
}

//==============================================================
// DAILY POC KEY LEVELS (EXPERIMENTAL)
// The last InpMPDays COMPLETED days' profiles are kept per symbol
// (index 0 = most recent), each built from the whole calendar day
// in server time (00:00-24:00, i.e. Tokyo + London + New York
// combined). A day yields 0-3 key levels: the significant areas of
// interest found by peak-prominence analysis (multi-distribution
// days) — each area's POC is a key level. Trend days (flat,
// stretched distribution — no significant POC) yield none and are
// journaled with their metrics. Backfilled at startup for the days
// before today, finalized at each server-day rollover. Dead days
// (weekends, holidays — fewer than MP_MIN_DAY_BARS bars) are
// skipped.
//==============================================================

// YYYYMMDD key of a server-time instant (day rollover detection)
int MPDateKey(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return dt.year * 10000 + dt.mon * 100 + dt.day;
}

// 00:00 server time of the day containing 't'
datetime MPDayStart(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   return StructToTime(dt);
}

// Build one completed day's profile (dayStart = 00:00 server time of that
// day). Only bars with an open time inside [dayStart, dayStart + 86400)
// are used; the day is skipped when it has fewer than MP_MIN_DAY_BARS.
// The day's areas of interest are detected by prominence: 1-3 significant
// peaks (multi-distribution days) or none at all (trend days — the POC
// does not stand out from the distribution).
// Shared range-profile builder: all closed M1 bars with an open time in
// [from, to). Fills the range, bar count, the range's last closed price,
// a built MPData (POC + value area) and the raw TPO histogram (for the
// multi-distribution / shape analysis).
bool MPRangeProfile(int s, datetime from, datetime to, int minBars,
                    double &lo, double &hi, int &bars, double &closePrice, MPData &d,
                    double &counts[], int &nb, double &base, double &bs, double &tpo)
{
   MqlRates r[];
   if(CopyRates(syms[s], PERIOD_M1, from, to, r) <= 0) return false;
   ArraySetAsSeries(r, true);
   int total = ArraySize(r);
   if(total <= 0) return false;

   // Defensive: never count a bar whose open time is outside the range
   bars    = total;
   int fromIdx = 0;
   if(r[0].time >= to)                // bar still forming after the range ended
   {
      bars--;
      fromIdx = 1;
   }
   if(bars < minBars) return false;

   lo = DBL_MAX;
   hi = -DBL_MAX;
   for(int i = fromIdx; i < fromIdx + bars; i++)
   {
      if(r[i].low  < lo) lo = r[i].low;
      if(r[i].high > hi) hi = r[i].high;
   }
   if(hi - lo <= 0.0) return false;
   closePrice = r[fromIdx].close;

   if(!MPCountTPO(s, r, fromIdx, bars, lo, hi, counts, nb, base, bs, tpo)) return false;
   MPPocVA(counts, nb, base, bs, tpo, lo, hi, d);
   return true;
}

// Build one completed day's profile (dayStart = 00:00 server time of that
// day; the day = all three sessions combined). The day is skipped when it
// has fewer than MP_MIN_DAY_BARS. The day's areas of interest are found by
// prominence (1-3 significant peaks or none on trend days) and the day is
// classified by SHAPE with a directional read:
//   TREND_UP/DOWN  — no significant POC AND the close exited value to the
//                    upside/downside (one-timeframe market)
//   DOUBLE         — 2-3 areas; dir = where the auction ended up vs where
//                    it started (last area POC vs first)
//   NORMAL         — one balanced distribution, no directional read
bool BuildDayProfile(int s, datetime dayStart, MPDayLevel &out)
{
   out.valid = false;
   out.day   = dayStart;
   out.vah   = 0.0;
   out.val   = 0.0;
   out.high  = 0.0;
   out.low   = 0.0;
   out.close = 0.0;
   out.pocRatio = 0.0;
   out.vaSpanRatio = 0.0;
   out.bars  = 0;
   out.peaks = 0;
   out.shape = MPSHAPE_NONE;
   out.dir   = 0;
   for(int p = 0; p < MP_MAX_PEAKS; p++)
   {
      out.poc[p]      = 0.0;
      out.pocCount[p] = 0.0;
   }

   double lo, hi;
   int    bars;
   double closePrice;
   MPData d;
   double counts[];
   int    nb;
   double base, bs, tpo;
   if(!MPRangeProfile(s, dayStart, dayStart + 86400, MP_MIN_DAY_BARS,
                      lo, hi, bars, closePrice, d, counts, nb, base, bs, tpo)) return false;

   double dayPocs[MP_MAX_PEAKS], dayCounts[MP_MAX_PEAKS];
   int areas = MPDayAreas(counts, nb, base, bs, dayPocs, dayCounts);
   bool significant = MPDayPocSignificant(d.pocCount, tpo, nb, d.vah - d.val, hi - lo);

   out.vah   = d.vah;
   out.val   = d.val;
   out.high  = hi;
   out.low   = lo;
   out.close = closePrice;
   out.pocRatio    = (tpo > 0.0 && nb > 0) ? d.pocCount / (tpo / nb) : 0.0;
   out.vaSpanRatio = (hi - lo > 0.0) ? (d.vah - d.val) / (hi - lo) : 0.0;
   out.bars  = bars;
   out.peaks = significant ? (int)MathMin(areas, MP_MAX_PEAKS) : 0;
   for(int p = 0; p < out.peaks; p++)
   {
      out.poc[p]      = dayPocs[p];
      out.pocCount[p] = dayCounts[p];
   }

   // Shape classification + directional read
   if(!significant)
   {
      if(closePrice >= d.vah)
      {
         out.shape = MPSHAPE_TREND_UP;
         out.dir   = 1;
      }
      else if(closePrice <= d.val)
      {
         out.shape = MPSHAPE_TREND_DOWN;
         out.dir   = -1;
      }
      else
         out.shape = MPSHAPE_NORMAL;      // wide neutral day — no read
   }
   else if(out.peaks >= 2)
   {
      out.shape = MPSHAPE_DOUBLE;
      out.dir   = (out.poc[out.peaks - 1] > out.poc[0]) ? 1 : -1;
   }
   else
      out.shape = MPSHAPE_NORMAL;

   out.valid = true;
   return true;
}

// Insert a finished day at the front of the ring (most recent first),
// dropping the oldest beyond mpDaysKeep.
void MPPushDayLevel(int s, MPDayLevel &dl)
{
   for(int j = (int)MathMin(mpDaysCount[s], mpDaysKeep - 1); j > 0; j--)
      mpDays[s][j] = mpDays[s][j - 1];
   mpDays[s][0] = dl;
   if(mpDaysCount[s] < mpDaysKeep) mpDaysCount[s]++;
}

// One journal line listing the stored daily key levels, most recent
// first, with the day's shape code ([N] normal, [2D] double distribution,
// [TU]/[TD] trend days): "2026.08.22 [N] POCs 2654.10/2671.30 (VA
// 2648.2..2662.4)" or "2026.08.22 [TU] no sig. POC (max/mean 1.4x, VA span
// 81%)" for a trend day.
string MPDaysList(int s)
{
   string res = "";
   int digits = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);
   for(int i = 0; i < mpDaysCount[s]; i++)
   {
      if(i > 0) res += " | ";
      res += TimeToString(mpDays[s][i].day, TIME_DATE) + " [" +
             MPShapeCode(mpDays[s][i].shape) + "]";
      if(mpDays[s][i].peaks <= 0)
      {
         res += " no sig. POC (max/mean " + DoubleToString(mpDays[s][i].pocRatio, 1) +
                "x, VA span " + DoubleToString(100.0 * mpDays[s][i].vaSpanRatio, 0) + "%)";
         continue;
      }
      res += " POC" + (mpDays[s][i].peaks > 1 ? "s" : "") + " ";
      for(int p = 0; p < mpDays[s][i].peaks; p++)
      {
         if(p > 0) res += "/";
         res += DoubleToString(mpDays[s][i].poc[p], digits);
      }
      res += " (VA " + DoubleToString(mpDays[s][i].val, digits) +
             ".." + DoubleToString(mpDays[s][i].vah, digits) + ")";
   }
   return res;
}

// Startup: build the profiles of the last mpDaysKeep COMPLETED days
// (yesterday back), most recent first.
void MPBackfillDays(int s)
{
   mpDaysCount[s] = 0;
   datetime today = MPDayStart(TimeCurrent());
   for(int k = 1; k <= mpDaysKeep; k++)
   {
      MPDayLevel dl;
      if(BuildDayProfile(s, today - k * 86400, dl))
         MPPushDayLevel(s, dl);
   }
   if(InpMPLog && mpDaysCount[s] > 0)
      Print(PCTime() + " | MP " + syms[s] + " daily POC key levels (backfill, " +
            IntegerToString(mpDaysCount[s]) + " day(s)): " + MPDaysList(s));
}

//==============================================================
// SESSION STACKING + SHAPE READ (EXPERIMENTAL)
// The auction's direction can be read from the shapes of recent days
// and from how the sessions stack: when each completed session's value
// area ends up entirely ABOVE the previous one's (Tokyo flat, London
// higher, New York higher), the auction is one-directional — stacked
// sessions. The shape read combines the last mpShapeDays completed
// days' directions (trend days +/-1, double-distribution days the way
// the auction stepped) with the session stack into one bias.
//==============================================================

// [from, to) of the given session on the day starting at 'dayStart'
void MPSessionBounds(datetime dayStart, int sid, datetime &from, datetime &to)
{
   MqlDateTime dt;
   TimeToStruct(dayStart, dt);
   dt.hour = (sid == 2) ? InpMPNYStart : (sid == 1) ? InpMPLondonStart : InpMPTokyoStart;
   dt.min  = 0;
   dt.sec  = 0;
   from = StructToTime(dt);

   int nextH = (sid == 2) ? InpMPTokyoStart + 24
              : (sid == 1) ? InpMPNYStart
                           : InpMPLondonStart;
   dt.hour = nextH % 24;
   to = StructToTime(dt);
   if(nextH >= 24) to += 86400;          // New York ends on the next day
}

// Build one completed session's profile
bool BuildSessionProfile(int s, int sid, datetime from, datetime to, MPSessionLevel &out)
{
   out.valid     = false;
   out.start     = from;
   out.sessionId = sid;
   out.poc       = 0.0;
   out.vah       = 0.0;
   out.val       = 0.0;
   out.high      = 0.0;
   out.low       = 0.0;
   out.bars      = 0;

   double lo, hi;
   int    bars;
   double closePrice;
   MPData d;
   double counts[];
   int    nb;
   double base, bs, tpo;
   if(!MPRangeProfile(s, from, to, MP_MIN_DAY_BARS, lo, hi, bars, closePrice, d,
                      counts, nb, base, bs, tpo)) return false;

   out.poc  = d.poc;
   out.vah  = d.vah;
   out.val  = d.val;
   out.high = hi;
   out.low  = lo;
   out.bars = bars;
   out.valid = true;
   return true;
}

// Insert a finished session at the front of the ring (most recent first)
void MPPushSessionLevel(int s, MPSessionLevel &sl)
{
   for(int j = (int)MathMin(mpSessCount[s], MP_MAX_SESS - 1); j > 0; j--)
      mpSess[s][j] = mpSess[s][j - 1];
   mpSess[s][0] = sl;
   if(mpSessCount[s] < MP_MAX_SESS) mpSessCount[s]++;
}

// Startup: build the sessions of the two completed days before today
// (most recent first), so the stack read works from the first tick.
void MPBackfillSessions(int s)
{
   mpSessCount[s] = 0;
   datetime today = MPDayStart(TimeCurrent());
   for(int d = 2; d >= 1; d--)           // older day first, so the newest ends up at index 0
   {
      for(int sid = 0; sid <= 2; sid++)  // Tokyo, London, New York
      {
         datetime from, to;
         MPSessionBounds(today - d * 86400, sid, from, to);
         if(to > TimeCurrent()) continue;   // session still forming — skip
         MPSessionLevel sl;
         if(BuildSessionProfile(s, sid, from, to, sl))
            MPPushSessionLevel(s, sl);
      }
   }
}

// Session stack: 1 = the recent sessions' value areas are piling UP (each
// entirely above the previous), -1 DOWN, 0 none. 'count' = consecutive
// stacked sessions ending at the most recent one.
int MPSessionStack(int s, int &count)
{
   count = 0;
   if(mpSessCount[s] < 2) return 0;
   int dir = 0;
   if(mpSess[s][0].val > mpSess[s][1].vah)      dir =  1;
   else if(mpSess[s][0].vah < mpSess[s][1].val) dir = -1;
   if(dir == 0) return 0;
   count = 1;
   for(int i = 0; i + 1 < mpSessCount[s]; i++)
   {
      bool stacked = (dir ==  1) ? (mpSess[s][i].val > mpSess[s][i + 1].vah)
                                 : (mpSess[s][i].vah < mpSess[s][i + 1].val);
      if(!stacked) break;
      count++;
   }
   return dir;
}

// The multi-day shape read: sum of the last mpShapeDays completed days'
// directions (+/-1 each), plus up to +/-1.5 from the session stack
// (0.5 x stack length, capped at 3). Returns 1 bullish, -1 bearish,
// 0 flat/no data.
int MPShapeBias(int s)
{
   double score = 0.0;
   for(int i = 0; i < mpDaysCount[s] && i < mpShapeDays; i++)
   {
      if(!mpDays[s][i].valid) continue;
      score += mpDays[s][i].dir;
   }
   int stkCnt = 0;
   int stk = MPSessionStack(s, stkCnt);
   score += stk * 0.5 * MathMin(stkCnt, 3);
   if(score >  0.25) return  1;
   if(score < -0.25) return -1;
   return 0;
}

string MPShapeName(int shape)
{
   if(shape == MPSHAPE_NORMAL)    return "normal";
   if(shape == MPSHAPE_DOUBLE)    return "double-distribution";
   if(shape == MPSHAPE_TREND_UP)  return "trend-up";
   if(shape == MPSHAPE_TREND_DOWN)return "trend-down";
   return "none";
}

string MPShapeCode(int shape)
{
   if(shape == MPSHAPE_NORMAL)    return "N";
   if(shape == MPSHAPE_DOUBLE)    return "2D";
   if(shape == MPSHAPE_TREND_UP)  return "TU";
   if(shape == MPSHAPE_TREND_DOWN)return "TD";
   return "-";
}

// Has a new H4 bar closed since the last "profile moved" journal line?
// Caps movement logging at ~6 lines per hour per symbol.
bool MPNewH4Bar(int s)
{
   MqlRates h4[];
   if(CopyRates(syms[s], PERIOD_H4, 0, 2, h4) < 2) return false;
   ArraySetAsSeries(h4, true);
   if(h4[1].time == mpLastMoveLog[s]) return false;
   mpLastMoveLog[s] = h4[1].time;
   return true;
}

// Rebuild the profile for one symbol and journal the interesting events:
// first readiness, POC/VA movement (max once per H4 bar), price crossings
// of the POC / VAH / VAL since the previous M1 bar, and — in sessions
// mode — the finished session's final profile when the next session opens.
// Also maintains the daily POC key levels: backfilled at startup, one new
// level per server-day rollover, and journaled when price crosses one.
void UpdateMarketProfile(int s)
{
   // The active session — tracked in BOTH profile modes: the session ring
   // (stacking read) must keep receiving completed sessions even when the
   // active profile is a rolling window.
   int sid = MPSessionId(TimeCurrent());

   // Session stacking (EXPERIMENTAL): backfill the completed sessions once
   // so the stack read works from the first tick.
   if(!mpSessBackfilled[s])
   {
      MPBackfillSessions(s);
      mpSessBackfilled[s] = true;
   }

   // Daily POC key levels (EXPERIMENTAL): backfill the completed days once,
   // then finalize each day when the server date rolls over.
   if(!mpDaysBackfilled[s])
   {
      MPBackfillDays(s);
      mpDaysBackfilled[s] = true;
   }
   int dayKey = MPDateKey(TimeCurrent());
   if(dayKey != mpDayKey[s])
   {
      if(mpDayKey[s] > 0)                    // a full day just ended — finalize it
      {
         MPDayLevel dl;
         if(BuildDayProfile(s, MPDayStart(TimeCurrent()) - 86400, dl))
         {
            MPPushDayLevel(s, dl);
            if(InpMPLog)
            {
               int bias = MPShapeBias(s);
               string biasS = (bias > 0) ? "up" : (bias < 0) ? "down" : "flat";
               if(mpDays[s][0].peaks > 0)
               {
                  string lv = "";
                  for(int p = 0; p < mpDays[s][0].peaks; p++)
                  {
                     if(p > 0) lv += "/";
                     lv += DoubleToString(mpDays[s][0].poc[p],
                                          (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS));
                  }
                  Print(PCTime() + " | MP " + syms[s] + " day closed " +
                        TimeToString(dl.day, TIME_DATE) + " [" + MPShapeCode(mpDays[s][0].shape) +
                        "] — POC" + (mpDays[s][0].peaks > 1 ? "s" : "") + " " + lv +
                        " added as key level(s) (" + IntegerToString(mpDaysCount[s]) + "/" +
                        IntegerToString(mpDaysKeep) + " kept) | shape read: " + biasS);
               }
               else
                  Print(PCTime() + " | MP " + syms[s] + " day closed " +
                        TimeToString(dl.day, TIME_DATE) + " [" + MPShapeCode(mpDays[s][0].shape) +
                        "] — NO significant POC (max/mean " +
                        DoubleToString(mpDays[s][0].pocRatio, 1) + "x, VA span " +
                        DoubleToString(100.0 * mpDays[s][0].vaSpanRatio, 0) +
                        "%) — no key level added | shape read: " + biasS);
            }
         }
      }
      mpDayKey[s] = dayKey;
   }

   // Sessions mode: the active session just changed — store the finished
   // session's final profile into the stacking ring (mp[s] still holds its
   // last build), journal it with the current stack, and start the new
   // session fresh: its profile stays neutral until it has collected
   // InpMPMinBars minutes of its own.
   if(sid != mpSession[s])
   {
      if(mpSession[s] >= 0 && mp[s].ready)
      {
         MPSessionLevel sl;
         sl.start = MPSessionStart(TimeCurrent(), mpSession[s]);
         if(sl.start > TimeCurrent()) sl.start -= 86400;   // NY closing at midnight
         sl.sessionId = mpSession[s];
         sl.poc  = mp[s].poc;
         sl.vah  = mp[s].vah;
         sl.val  = mp[s].val;
         sl.high = mp[s].profileHigh;
         sl.low  = mp[s].profileLow;
         sl.bars = mp[s].bars;
         sl.valid = true;
         MPPushSessionLevel(s, sl);

         if(InpMPLog)
         {
            int stkCnt = 0;
            int stk = MPSessionStack(s, stkCnt);
            Print(PCTime() + " | MP " + syms[s] + " " + MPSessionName(mpSession[s]) +
                  " session CLOSED (" + IntegerToString(mp[s].bars) + " bars, " +
                  IntegerToString(mp[s].totalTpo) + " TPO): POC " +
                  DoubleToString(mp[s].poc, (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS)) +
                  " VA " + DoubleToString(mp[s].val, (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS)) +
                  ".." + DoubleToString(mp[s].vah, (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS)) +
                  " range " + DoubleToString(mp[s].profileLow, (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS)) +
                  ".." + DoubleToString(mp[s].profileHigh, (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS)) +
                  (stk != 0 ? " | stack: " + IntegerToString(stkCnt) + " " + (stk == 1 ? "UP" : "DOWN")
                            : " | stack: flat"));
         }
      }
      mpSession[s] = sid;
      if(InpMPProfileType == MP_PROFILE_SESSIONS) mp[s].ready = false;
   }

   // AUTO regime (EXPERIMENTAL): detect the auction regime once per M1
   // bar and journal every change. Runs before the profile build so a
   // build failure never leaves the regime stale.
   if(InpMPEntryMode == MPMODE_AUTO)
   {
      int reg = MPAutoDetect(s);
      if(reg != mpAutoRegime[s])
      {
         if(mpAutoRegime[s] >= 0 && InpMPLog)
         {
            string extra = "";
            if(reg == MPREG_STACK)
            {
               int stkCnt = 0;
               int stk = MPSessionStack(s, stkCnt);
               extra = " (" + IntegerToString(stkCnt) + " " + (stk == 1 ? "UP" : "DOWN") + ")";
            }
            Print(PCTime() + " | MP " + syms[s] + " auto regime: " + MPRegimeName(reg) + extra);
         }
         mpAutoRegime[s] = reg;
      }
   }

   MPData built;
   if(!BuildMarketProfile(s, built))
   {
      if(mp[s].ready)
         Print(PCTime() + " | MP " + syms[s] + " profile unavailable — filters neutral");
      mp[s].ready = false;
      return;
   }

   bool wasReady = mp[s].ready;

   int digits = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);
   string fmt = DoubleToString(built.bucketSize / SymbolInfoDouble(syms[s], SYMBOL_POINT), 1);

   if(!wasReady)
   {
      mp[s] = built;
      if(InpMPLog)
         Print(PCTime() + " | MP " + syms[s] + " profile READY (" +
               (InpMPProfileType == MP_PROFILE_SESSIONS ? MPSessionName(built.sessionId) + " session, " : "") +
               IntegerToString(built.bars) + " M1 bars, " + IntegerToString(built.buckets) +
               " buckets of " + fmt + " pts): POC " + DoubleToString(built.poc, digits) +
               " VA " + DoubleToString(built.val, digits) + ".." + DoubleToString(built.vah, digits) +
               " (" + DoubleToString(100.0 * built.pocCount / built.totalTpo, 0) + "% POC share)");
      return;
   }

   bool moved = (MathAbs(built.poc - mp[s].poc) >= 0.5 * built.bucketSize) ||
                (MathAbs(built.vah - mp[s].vah) >= 0.5 * built.bucketSize) ||
                (MathAbs(built.val - mp[s].val) >= 0.5 * built.bucketSize);
   mp[s] = built;

   // Price crossing a profile level between the two last closed M1 bars
   string crossed = "";
   double c1 = 0.0, c2 = 0.0;
   MqlRates m1[];
   if(CopyRates(syms[s], PERIOD_M1, 0, 3, m1) >= 3)
   {
      ArraySetAsSeries(m1, true);
      c1 = m1[1].close;
      c2 = m1[2].close;
   }
   if(c2 != 0.0 && c1 != 0.0)
   {
      if((c2 - mp[s].poc) * (c1 - mp[s].poc) <= 0.0) crossed = " POC";
      if((c2 - mp[s].vah) * (c1 - mp[s].vah) <= 0.0) crossed += " VAH";
      if((c2 - mp[s].val) * (c1 - mp[s].val) <= 0.0) crossed += " VAL";
   }

   // Price crossing a stored daily key level (any area of interest of any
   // stored day) between the two last closed M1 bars
   string dayCross = "";
   for(int i = 0; i < mpDaysCount[s]; i++)
   {
      if(!mpDays[s][i].valid || mpDays[s][i].peaks <= 0) continue;
      for(int p = 0; p < mpDays[s][i].peaks; p++)
      {
         double lvl = mpDays[s][i].poc[p];
         if((c2 - lvl) * (c1 - lvl) <= 0.0)
            dayCross += (dayCross == "" ? "" : " ; ") +
                        TimeToString(mpDays[s][i].day, TIME_DATE) +
                        (mpDays[s][i].peaks > 1 ? " #" + IntegerToString(p + 1) : "") +
                        " (" + DoubleToString(lvl, digits) + ")";
      }
   }
   if(InpMPLog && dayCross != "")
      Print(PCTime() + " | MP " + syms[s] + " price crossed daily key level(s): " + dayCross);

   if(InpMPLog && (crossed != "" || (moved && MPNewH4Bar(s))))
      Print(PCTime() + " | MP " + syms[s] + (moved ? " moved" : "") +
            (crossed != "" ? " — price crossed:" + crossed : "") +
            " — POC " + DoubleToString(mp[s].poc, digits) +
            " VA " + DoubleToString(mp[s].val, digits) + ".." + DoubleToString(mp[s].vah, digits));
}

//==============================================================
// ENTRY GATE + AUTO REGIME (EXPERIMENTAL)
//==============================================================

// 4 — daily POC side: the PRIMARY POC of the most recent COMPLETED day
//     that has a significant area of interest is the key level — longs
//     only at/above it, shorts only at/below it. Trend days (no
//     significant POC) are skipped.
bool MPDailyPocEntryOK(int s, int dir)
{
   for(int i = 0; i < mpDaysCount[s]; i++)
   {
      if(!mpDays[s][i].valid || mpDays[s][i].peaks <= 0) continue;
      double lvl = mpDays[s][i].poc[0];
      MqlRates m1[];
      if(CopyRates(syms[s], PERIOD_M1, 0, 2, m1) < 2) return true;
      ArraySetAsSeries(m1, true);
      double c1 = m1[1].close;
      return (dir == 1) ? (c1 >= lvl) : (c1 <= lvl);
   }
   return true;
}

// 5 — stack continuation: consecutive sessions stacking (each value area
//     entirely above the previous) = a one-directional auction. Enter
//     WITH the stack when the last closed bar pulled back into the most
//     recent session's value area (upper half for a long, lower half for
//     a short). No stack = no signal.
bool MPStackEntryOK(int s, int dir)
{
   int stkCnt = 0;
   int stk = MPSessionStack(s, stkCnt);
   if(stk == 0 || stkCnt < InpMPStackMin) return false;
   if(mpSessCount[s] <= 0 || !mpSess[s][0].valid) return false;

   MqlRates m1[];
   if(CopyRates(syms[s], PERIOD_M1, 0, 2, m1) < 2) return false;
   ArraySetAsSeries(m1, true);
   double c1 = m1[1].close;

   if(stk ==  1 && dir ==  1) return (c1 >= mpSess[s][0].poc && c1 <= mpSess[s][0].vah);
   if(stk == -1 && dir == -1) return (c1 <= mpSess[s][0].poc && c1 >= mpSess[s][0].val);
   return false;
}

// 6 — old-POC reaction: the last closed bar TOUCHED an old daily POC
//     (a key level from a completed day — the magnet) and closed back on
//     the near side of it: the level rejected price. Long when a support
//     POC was touched from above and held; short when a resistance POC
//     was touched from below and held.
bool MPOldPocEntryOK(int s, int dir)
{
   MqlRates m1[];
   if(CopyRates(syms[s], PERIOD_M1, 0, 3, m1) < 3) return false;
   ArraySetAsSeries(m1, true);
   double c1 = m1[1].close;
   double c2 = m1[2].close;
   double h1 = m1[1].high;
   double l1 = m1[1].low;

   for(int i = 0; i < mpDaysCount[s]; i++)
   {
      if(!mpDays[s][i].valid || mpDays[s][i].peaks <= 0) continue;
      for(int p = 0; p < mpDays[s][i].peaks; p++)
      {
         double lvl = mpDays[s][i].poc[p];
         if(dir ==  1 && l1 <= lvl && lvl <= h1 && c2 > lvl && c1 > lvl) return true;
         if(dir == -1 && l1 <= lvl && lvl <= h1 && c2 < lvl && c1 < lvl) return true;
      }
   }
   return false;
}

// 2 — VA breakout: the market expanded beyond value — enter in the
//     direction of the expansion
bool MPBreakEntryOK(int s, int dir)
{
   if(!mp[s].ready) return false;
   MqlRates m1[];
   if(CopyRates(syms[s], PERIOD_M1, 0, 2, m1) < 2) return false;
   ArraySetAsSeries(m1, true);
   double c1 = m1[1].close;
   return (dir == 1) ? (c1 > mp[s].vah) : (c1 < mp[s].val);
}

// 3 — VA edge rejection: the last closed bar traded at/beyond the edge
//     and closed back inside it — the edge rejected price
bool MPRejectEntryOK(int s, int dir)
{
   if(!mp[s].ready) return false;
   MqlRates m1[];
   if(CopyRates(syms[s], PERIOD_M1, 0, 3, m1) < 3) return false;
   ArraySetAsSeries(m1, true);
   double c1 = m1[1].close;
   double c2 = m1[2].close;
   if(dir == 1) return (c2 <= mp[s].val && c1 > mp[s].val);
   return (c2 >= mp[s].vah && c1 < mp[s].vah);
}

// Is price within InpMPAutoNearATR x ATR(M1) of any old daily key level?
bool MPNearOldPoc(int s)
{
   double a[1];
   if(CopyBuffer(atrM1[s], 0, 1, 1, a) <= 0 || a[0] <= 0.0) return false;
   MqlRates m1[];
   if(CopyRates(syms[s], PERIOD_M1, 0, 2, m1) < 2) return false;
   ArraySetAsSeries(m1, true);
   double c = m1[1].close;
   double near = InpMPAutoNearATR * a[0];
   for(int i = 0; i < mpDaysCount[s]; i++)
   {
      if(!mpDays[s][i].valid || mpDays[s][i].peaks <= 0) continue;
      for(int p = 0; p < mpDays[s][i].peaks; p++)
         if(MathAbs(c - mpDays[s][i].poc[p]) <= near) return true;
   }
   return false;
}

// AUTO regime selection — the auction is always in one of five states:
//   1. STACK    — sessions stacking = one-directional auction (strongest)
//   2. MAGNET   — price is within InpMPAutoNearATR x ATR(M1) of an old
//                 daily POC — the magnet is in play
//   3. BREAKOUT — price has exited the active profile's value area
//   4. BALANCE  — price is inside value: fade the edges
//   5. DAILY    — fallback (also while the active profile is building)
// Called once per M1 bar; journals every regime change.
int MPAutoDetect(int s)
{
   int stkCnt = 0;
   int stk = MPSessionStack(s, stkCnt);
   if(stk != 0 && stkCnt >= InpMPStackMin) return MPREG_STACK;

   if(MPNearOldPoc(s)) return MPREG_MAGNET;

   if(mp[s].ready)
   {
      MqlRates m1[];
      if(CopyRates(syms[s], PERIOD_M1, 0, 2, m1) >= 2)
      {
         ArraySetAsSeries(m1, true);
         double c1 = m1[1].close;
         if(c1 > mp[s].vah || c1 < mp[s].val) return MPREG_BREAK;
      }
      return MPREG_BALANCE;
   }
   return MPREG_DAILY;
}

string MPRegimeName(int r)
{
   if(r == MPREG_STACK)   return "STACK";
   if(r == MPREG_MAGNET)  return "MAGNET";
   if(r == MPREG_BREAK)   return "BREAKOUT";
   if(r == MPREG_BALANCE) return "BALANCE";
   return "DAILY-POC";
}

// 7 — AUTO: delegate to the entry logic of the regime selected on the
//     last M1 bar. In BALANCE, a non-flat shape read filters the fade to
//     its direction (trend-aware fading).
bool MPAutoEntryOK(int s, int dir)
{
   int reg = mpAutoRegime[s];
   if(reg == MPREG_STACK)   return MPStackEntryOK(s, dir);
   if(reg == MPREG_MAGNET)  return MPOldPocEntryOK(s, dir);
   if(reg == MPREG_BREAK)   return MPBreakEntryOK(s, dir);
   if(reg == MPREG_BALANCE)
   {
      if(MPShapeBias(s) != 0 && MPShapeBias(s) != dir) return false;
      return MPRejectEntryOK(s, dir);
   }
   return MPDailyPocEntryOK(s, dir);
}

// May the VA-edge take profit run in the current mode? Off in VA-breakout
// mode and in AUTO while the regime is BREAKOUT — an entry beyond the
// edge would close itself on the very next bar.
bool MPExitVAAllowed(int s)
{
   if(InpMPEntryMode == MPMODE_VA_OUT) return false;
   if(InpMPEntryMode == MPMODE_AUTO && mpAutoRegime[s] == MPREG_BREAK) return false;
   return true;
}

// Market profile ENTRY gate (EXPERIMENTAL). Neutral (passes) while the
// data it needs is not ready — the layer never blocks the parent logic
// on its own. Modes 1-3 use the active profile (rolling/session); mode 4
// uses the daily POC key levels; modes 5-6 use the session stack and the
// old daily key levels; mode 7 (AUTO) picks the regime itself.
// InpMPShapeBias, when on, blocks entries against the multi-day shape
// read in every mode.
bool MPEntryOK(int s, int dir)
{
   if(InpMPEntryMode == MPMODE_OFF) return true;

   // Shape-bias gate: never trade against the multi-day shape read
   // (day shapes + session stacking)
   if(InpMPShapeBias)
   {
      int bias = MPShapeBias(s);
      if(dir ==  1 && bias < 0) return false;
      if(dir == -1 && bias > 0) return false;
   }

   // Mode 4 — daily POC side
   if(InpMPEntryMode == MPMODE_DAILY_POC) return MPDailyPocEntryOK(s, dir);

   // Mode 5 — stack continuation
   if(InpMPEntryMode == MPMODE_STACK)     return MPStackEntryOK(s, dir);

   // Mode 6 — old-POC reaction
   if(InpMPEntryMode == MPMODE_OLDPOC)    return MPOldPocEntryOK(s, dir);

   // Mode 7 — AUTO regime selection
   if(InpMPEntryMode == MPMODE_AUTO)      return MPAutoEntryOK(s, dir);

   // Modes 1-3 use the active profile — neutral while it is not ready
   if(!mp[s].ready) return true;

   MqlRates m1[];
   if(CopyRates(syms[s], PERIOD_M1, 0, 3, m1) < 3) return true;
   ArraySetAsSeries(m1, true);
   double c1 = m1[1].close;   // last closed bar
   double c2 = m1[2].close;   // bar before it

   // 1 — POC side: trade with fair value
   if(InpMPEntryMode == MPMODE_POC)
      return (dir == 1) ? (c1 >= mp[s].poc) : (c1 <= mp[s].poc);

   // 2 — VA breakout: the market expanded beyond value
   if(InpMPEntryMode == MPMODE_VA_OUT)
      return (dir == 1) ? (c1 > mp[s].vah) : (c1 < mp[s].val);

   // 3 — VA edge rejection: the last closed bar traded at/beyond the
   //     edge and closed back inside it — the edge rejected price
   if(dir == 1) return (c2 <= mp[s].val && c1 > mp[s].val);
   return (c2 >= mp[s].vah && c1 < mp[s].vah);
}

//==============================================================
// Main Loop
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

      // Market profile (EXPERIMENTAL): rebuild the rolling TPO profile on
      // each new closed M1 bar — the same cadence as every other check.
      if(InpMPEnabled) UpdateMarketProfile(s);

      // Sync position state once per tick on the first new M1 bar instead of
      // rebuilding it on every single tick.
      if(!synced) { SyncStateFromPositions(); synced = true; }

      // Exits and profit protection per level
      for(int l = 0; l < LEVELS; l++)
      {
         // Exit check: price touched the level TF's cloud edge
         if(state[s][l] != 0 && InCloudTouch(s, l + 1, state[s][l]))
            ExitLevel(s, l, "kumo touch");

         // Market profile take-profit (EXPERIMENTAL): a long exits when the
         // bid touches the VA high, a short when the ask touches the VA low.
         // Skipped in VA-breakout mode and in AUTO while the regime is
         // BREAKOUT — an entry beyond the edge would close itself on the
         // very next bar.
         if(InpMPEnabled && InpMPExitVA && MPExitVAAllowed(s) &&
            state[s][l] != 0 && mp[s].ready)
         {
            double bid = SymbolInfoDouble(syms[s], SYMBOL_BID);
            double ask = SymbolInfoDouble(syms[s], SYMBOL_ASK);
            if(state[s][l] == 1 && bid >= mp[s].vah)
               ExitLevel(s, l, "VA high");
            else if(state[s][l] == -1 && ask <= mp[s].val)
               ExitLevel(s, l, "VA low");
         }

         // Old-POC take profit (EXPERIMENTAL): price gravitates toward old
         // daily POCs (the magnet) — a long exits when the bid reaches the
         // next stored key level ABOVE the current price, a short when the
         // ask reaches the next stored key level BELOW it.
         if(InpMPEnabled && InpMPExitOldPOC && state[s][l] != 0)
         {
            double bid = SymbolInfoDouble(syms[s], SYMBOL_BID);
            double ask = SymbolInfoDouble(syms[s], SYMBOL_ASK);
            double best = 0.0;
            if(state[s][l] == 1)
            {
               best = DBL_MAX;
               for(int i = 0; i < mpDaysCount[s]; i++)
               {
                  if(!mpDays[s][i].valid || mpDays[s][i].peaks <= 0) continue;
                  for(int p = 0; p < mpDays[s][i].peaks; p++)
                  {
                     double lvl = mpDays[s][i].poc[p];
                     if(lvl > bid && lvl < best) best = lvl;
                  }
               }
               if(best != DBL_MAX && bid >= best) ExitLevel(s, l, "old POC");
            }
            else
            {
               best = 0.0;
               for(int i = 0; i < mpDaysCount[s]; i++)
               {
                  if(!mpDays[s][i].valid || mpDays[s][i].peaks <= 0) continue;
                  for(int p = 0; p < mpDays[s][i].peaks; p++)
                  {
                     double lvl = mpDays[s][i].poc[p];
                     if(lvl < ask && lvl > best) best = lvl;
                  }
               }
               if(best > 0.0 && ask <= best) ExitLevel(s, l, "old POC");
            }
         }

         // Rejection exit: a very strong rejection candle formed on
         // the tier TF against the trade (bearish kills a long,
         // bullish kills a short)
         if(InpRejectionExit && state[s][l] != 0)
         {
            int rj = RejectionCandle(s, l + 1);
            if(rj != 0 && rj == -state[s][l])
               ExitLevel(s, l, "rejection");
         }

         // Profit protection: BE + spike-lock chandelier trail
         if(state[s][l] != 0) ManageLevelProtection(s, l);
      }

      // Entry consolidation: when several tiers align at once, only the
      // LARGEST one opens (highest TF wins). Any smaller tier already
      // running on the symbol is closed first — e.g. M15 and M30 align
      // together: the running M15 trade closes and only M30 opens.
      int    topTier = -1;
      int    topDir  = 0;
      string topVia  = "--";
      // R2: never add exposure while an unmanageable (unparseable-comment)
      // magic position sits on this symbol; exits/protection still run.
      if(!symBlockedUnknown[s] && SpreadOK(syms[s]))
      {
         for(int l = LEVELS - 1; l >= 0; l--)
         {
            if(state[s][l] != 0) continue;
            int st = ChainAligned(s, l + 1);
            if(st == 0) continue;
            if(InpCloudBiasEnabled && !LevelCloudBiasOK(s, l, st)) continue;

            // Market profile gate (EXPERIMENTAL): POC side / VA breakout /
            // VA edge rejection. Neutral while the profile is not ready.
            if(InpMPEnabled && !MPEntryOK(s, st)) continue;

            // Directional bias: H4 as before, with the new H1 stand-in for
            // the lower tiers when H4 has no direction of its own.
            string via = "--";
            if(!EntryBiasOK(s, l, st, via)) continue;

            // H4 tier: D1 must carry the same bias (D1 in the cloud = no H4 trades)
            if(l == LEVELS - 1 && InpD1Filter && DailyAlign(s) != st) continue;

            topTier = l;
            topDir  = st;
            topVia  = via;
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
               string msg = PCTime() + " | Close " + syms[s] + " " + tfName[l + 1] +
                            " (superseded by " + tfName[topTier + 1] + ")";
               Print(msg); SendNotification(msg);

               if(CloseLevelPositions(s, l))
                  state[s][l] = 0;
               else
                  Print(PCTime() + " | " + syms[s] + " " + tfName[l + 1] + " superseded but positions still open — will retry");
            }
         }

         // Open only the largest tier
         double lots = RiskLots(s, topTier);
         CapLotsToMargin(syms[s], (topDir == 1), lots);

         if(!OpenLevel(s, topTier, topDir, lots, topVia))
            Print(PCTime() + " | " + syms[s] + " " + tfName[topTier + 1] +
                  " entry signal but order failed, retcode " + IntegerToString(trade.ResultRetcode()));
      }
   }
}
//This work is my worship unto GOD
