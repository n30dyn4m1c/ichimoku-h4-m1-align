//+------------------------------------------------------------------+
//| EXPERIMENTAL — HTF KEY-LEVEL TP (notes §75, magic 20260895)       |
//| A copy of the live VPS build ichimoku-h4-m1-vps-ea.mq5 (which is  |
//| NOT changed) with five additions, each behind an input:           |
//|  1. KEY-LEVEL TP: every trend trade takes profit at the nearest   |
//|     tenkan, kijun, Span A or Span B of a timeframe ABOVE its tier |
//|     (M15 tier: M30, H1, H4, D1, W1, MN1 lines; H4 tier: D1, W1,   |
//|     MN1), at least InpKLFloorATR x ATR(tier) beyond the entry.    |
//|     It is a broker TP, refreshed every closed M1 bar; a line that |
//|     moves onto the price closes the trade at market. Lines are    |
//|     read on each TF's last closed bar (shift 1), the spans being  |
//|     the cloud drawn under that bar.                               |
//|  2. LATE-CANDLE HOLD: a touch inside the last InpKLLateMin        |
//|     minutes of the line's own TF bar (e.g. the final 10 minutes   |
//|     of the H4 candle) does not take profit — the trade is held    |
//|     and closed at market when that candle closes.                 |
//|  3. H4+D1 HOLD: a key-level exit where an H4 line and a D1 (or    |
//|     W1/MN1) line sit within InpKLConfTolATR x ATR(H4) of the exit |
//|     blocks EVERY new trend entry until the next H4 bar opens —    |
//|     even with M1, M5 and M15 aligned (overextension).             |
//|  4. RE-ENTRY LOCK: after a key-level exit no tier re-enters the   |
//|     same direction until a bar of the level's own TF closes       |
//|     beyond the line (default), or the TP tier's chain breaks and  |
//|     re-forms, or either (InpKLReentry).                           |
//|  5. REVERSAL (off by default — it lost in simulation): an entry   |
//|     signal whose price sits at a key line opens the opposite      |
//|     trade instead, one per signalling tier, every reversal taking |
//|     profit at the kijun of the LOWEST tier with one open, lots as |
//|     the trend trade's risk rule, stop beyond the line.            |
//| Hold and lock live in memory only: a restart clears them.         |
//| Everything else is the live build, byte for byte where possible.  |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Ichimoku Bottom-Up Stack EA (H1 bias) — M1-STRICT CLOUD BIAS      |
//| The live VPS build since 2026-08-23. The M1-strict cloud-bias     |
//| trading logic is unchanged (promoted 2026-08-20 from the most     |
//| profitable cloud-bias experiment, user report 2026-08-20;         |
//| $100 -> $14000 on Jan-Aug 2026 data); what is new is the          |
//| ROBUSTNESS PACK below — review recommendations R2-R6, built and   |
//| verified as experiments/experimental-bottomup-stack-m1-strict-    |
//| cloud-bias-robustness-vps-ea.mq5. It replaces the previous VPS    |
//| build, archived as archives/ichimoku-h4-m1-vps-ea-archived        |
//| 20260823.mq5 and no longer deployed.                              |
//| EXPERIMENTAL RULE — the only change vs the parent build: the      |
//| cloud-bias gate (Span A vs Span B) requires M1 to be twisted the  |
//| trade's way at BOTH the current bar (last closed bar) and the     |
//| far end of the future cloud (Kijun bars ahead) — the full check.  |
//| On M5 and above the CURRENT cloud may be any value, bullish or    |
//| bearish; only the FUTURE cloud must be in the trade's direction.  |
//| The gate applies to every tier (tier TF + the TF directly below   |
//| it): the tier's own M5+ TF is checked future-only, and the M5     |
//| tier additionally checks M1 with the full current+future rule —  |
//| M1 is the only timeframe that must fully agree.                   |
//| DIFFERENT MODEL: the top-down builds required every timeframe     |
//| from the anchor down to M1 to agree before a single trade could   |
//| open. This build is BOTTOM-UP — the stack is grown upward from    |
//| M1 and each tier trades its own chain — with DIRECTION granted    |
//| by a bias timeframe (H4 primary, H1 stand-in) instead of by       |
//| top-down agreement.                                               |
//| Entry: per-TF alignment (price + chikou above/below tenkan,       |
//|        kijun and cloud), checked BOTTOM-UP: a tier opens only     |
//|        when the full stack M1..tier TF is aligned in one          |
//|        direction:                                                 |
//|          Tier M5 : M1 + M5 aligned              -> open trade     |
//|          Tier M15: M1 + M5 + M15 aligned        -> open trade     |
//|          Tier M30: M1 + M5 + M15 + M30 aligned  -> open trade     |
//|          Tier H1 : M1 ... H1 aligned            -> open trade     |
//|          Tier H4 : M1 ... H4 aligned            -> open trade     |
//|        M1 alone never trades — it is only the start of the stack. |
//|        The cloud bias gate (Span A vs Span B) applies to the tier |
//|        TF and the TF directly below it: M1 must be twisted the     |
//|        trade's way at both the current bar and the far end of the |
//|        future cloud; M5 and above need only the far end — the     |
//|        current cloud may be either direction. H4 is the bias for  |
//|        the whole stack (H4 bullish -> buys only, bearish -> sells |
//|        only, flat -> no trades), and the H4 tier itself is also   |
//|        gated by the D1 bias: D1 bullish -> only H4 buys, D1       |
//|        bearish -> only H4 sells, D1 in the cloud -> no H4 trades. |
//|        H1 BIAS: an unaligned H4 would otherwise freeze the whole  |
//|        stack, including M5. The lower tiers get a second, smaller |
//|        bias to fall back on: when H4 carries no direction, a tier |
//|        at or below InpH1BiasMaxTier may open provided H1 itself   |
//|        is aligned (same price+chikou test) with the trade. H4     |
//|        aligned WITH the trade is still the primary path; H4       |
//|        aligned AGAINST the trade stays blocked unless             |
//|        InpH1BiasMode = H1BIAS_ALWAYS. The H4 tier never uses the  |
//|        stand-in, and the D1 filter on the H4 tier is untouched.   |
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
//| Risk:  single position per level per symbol, but consolidation:   |
//|        when several tiers align at once only the LARGEST opens,   |
//|        and any smaller tier already running on the symbol is      |
//|        closed first — so at most one position per symbol runs at  |
//|        a time (the highest aligned tier). Every trade risks a     |
//|        fixed % of the ACTUAL equity at entry, de-risking as the   |
//|        account grows: tier 1 below $7000 (M5/M15 1%, M30 5%, H1   |
//|        10%, H4 20%), tier 2 half regime $7000-$13000              |
//|        (0.5/0.5/2.5/5/10), tier 3 tiny regime $13000+             |
//|        (0.1/0.1/0.2/1/2), against the reference distance           |
//|        ATR(level TF) x InpRiskATRMult (sizing basis only — no     |
//|        entry stop is attached). No multipliers, no streak         |
//|        compounding.                                               |
//| VPS:   no Alert() popups and no equity alert — every entry/exit   |
//|        sends a SendNotification push and a journal Print, and all |
//|        logic runs only on closed M1 bars (once per minute) to     |
//|        keep CPU/network use on a cheap VPS negligible. The        |
//|        desktop counterpart ichimoku-h4-m1-mt5pc-ea.mq5 restores   |
//|        the popups and the weekly equity reminder.                 |
//| Magic: 20260858 — carried over from the experiment it was         |
//|        promoted from, so positions it already opened keep being   |
//|        managed. Distinct from the desktop twin (20260860) and     |
//|        from the retired builds (20260850 VPS / 20260852 desktop). |
//|                                                                  |
//| ROBUSTNESS PACK (live since 2026-08-23) — five hardening changes |
//| (review recommendations R2-R6), promoted verbatim from the       |
//| robustness experimental fork.                                    |
//|   R2 UNKNOWN-POSITION GUARD: a magic-matching position whose     |
//|      comment no longer names a level (brokers may rewrite or     |
//|      truncate comments on partial fills / server events) used to |
//|      be invisible — orphaned from BE/trail/cloud exits while the |
//|      EA opened duplicates behind it. It is now logged once per   |
//|      ticket and BLOCKS new entries on that symbol until it is    |
//|      gone. Exits/protection for known levels still run.          |
//|   R3 DISASTER STOP: every entry carries a wide hard SL of        |
//|      ATR(level TF) x InpDisasterATRMult (default 8) so a gap or  |
//|      a dead VPS/link cannot run unbounded. Break-even and the    |
//|      chandelier still take over once green; a missing stop       |
//|      self-heals in ManageLevelProtection().                      |
//|   R4 PEAK REBUILD: after a restart mid-trade the chandelier      |
//|      references are rebuilt from level-TF history since the      |
//|      position's open time instead of collapsing to the open      |
//|      price (which left the trail far looser than before).        |
//|   R5 ORDER ROBUSTNESS: SetTypeFillingBySymbol() before every     |
//|      order (the FOK default breaks on IOC-only brokers), and     |
//|      the margin cap commits at most InpMarginUsePct % (default   |
//|      80) of free margin per order instead of 100%.               |
//|   R6 TWIN RULE: the desktop build ichimoku-h4-m1-mt5pc-ea.mq5    |
//|      carries this exact pack; the only intended differences are  |
//|      the magic number, the Alert() popups and the weekly equity  |
//|      reminder (see AGENTS.md). Deliberately NOT implemented      |
//|      (user decision): recommendation R1, the supersede invariant |
//|      guard that would abort a new entry while an existing        |
//|      higher-tier position survives its close attempt.            |
//| Magic: 20260858 — carried over from the previous VPS build so    |
//|        positions it already opened keep being managed. Distinct  |
//|        from the desktop twin (20260860) and the retired builds.  |
//| M5 TIER DROPPED (2026-09-23): no new M5 entries (InpM5Tier =     |
//| false); M15, M30, H1 and H4 trade as before. Real-tick backtests |
//| on GOLDm# (notes §48): M5 was ~half of all trades at profit      |
//| factor ~1.1, and without it account PF rose 1.38 -> 1.52 (2026)  |
//| and 1.88 -> 2.03 (2025) at the same net profit. Because M5 was   |
//| the only tier checked against the full M1 cloud rule, that rule  |
//| now applies to no tier. Pre-change build archived as the         |
//| -archived20260923 pair. Magic unchanged, so an open M5 position  |
//| is still managed to its exit.                                    |
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
input bool   InpM5Tier           = false;  // M5 tier opens trades (dropped 2026-09-23 — see notes §48)

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

// §75 key-level TFs. A tier only ever uses lines of TFs ABOVE its own.
enum ENUM_KL_TF { KLTF_M15 = 0, KLTF_M30 = 1, KLTF_H1 = 2, KLTF_H4 = 3, KLTF_D1 = 4, KLTF_W1 = 5, KLTF_MN1 = 6 };
enum ENUM_KL_REENTRY { KLRE_NONE = 0, KLRE_REALIGN = 1, KLRE_BREACH = 2, KLRE_EITHER = 3 };

input group  "HTF Key-Level TP (notes §75)"
input bool   InpKLTP            = true;     // TP at the nearest tenkan/kijun/Span A/Span B of a TF above the tier
input ENUM_KL_TF InpKLMinTF     = KLTF_M15; // Lowest TF whose lines count (a tier never uses its own TF or below)
input double InpKLFloorATR      = 1.0;      // A line must be at least this x ATR(tier) beyond the entry to be a target
input int    InpKLLateMin       = 10;       // Touch in the last N minutes of the line's TF bar: hold, close at its close (0 = off)
input bool   InpKLConfHold      = true;     // H4 + D1/W1/MN1 line at the exit: no new trend entries until the next H4 bar
input double InpKLConfTolATR    = 0.25;     // ... lines within this x ATR(H4) of the exit price count as confluence
input ENUM_KL_REENTRY InpKLReentry = KLRE_BREACH; // Same-direction re-entry after a key-level exit waits for: 0 none, 1 realign, 2 close beyond, 3 either
input bool   InpKLBreachLevelTF = true;     // The close beyond is on the line's own TF (false = on the tier's TF)
input double InpKLBreachBufATR  = 0.0;      // ... beyond the line by this x ATR of that TF
input bool   InpKLLockAllTiers  = true;     // The lock covers every tier (false = the TP tier and smaller only)

input group  "Reversal at a key level (notes §75 — lost in simulation, off)"
input bool   InpRevEnabled      = false;    // Entry signal at a key line opens the opposite trade instead
input double InpRevTolATR       = 0.25;     // Price within this x ATR(tier) of a line of a TF above the tier
input double InpRevStopATR      = 1.0;      // Stop this x ATR(tier) beyond the line
input double InpRevMinRR        = 0.0;      // Skip when (distance to the kijun) / (distance to the stop) is below this
input double InpRevLotMult      = 1.0;      // x the trend trade's lots (the same risk rule)
input int    InpRevMinTier      = 1;        // Lowest tier that may fade (0=M5 1=M15 2=M30 3=H1 4=H4)
input int    InpRevMaxTier      = 3;        // Highest tier that may fade

//--- Constants and Global Variables ---
#define MAX_SYMS 60
#define LEVELS   5      // tradable levels: M5, M15, M30, H1, H4
#define TFS      6      // stack: M1, M5, M15, M30, H1, H4
#define IDX_H1   4      // index of H1 in tfs[] — the stand-in bias TF
#define IDX_H4   5      // index of H4 in tfs[] — the primary bias TF

ENUM_TIMEFRAMES tfs[TFS] = { PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4 };
string          tfName[TFS] = { "M1", "M5", "M15", "M30", "H1", "H4" };

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

// R2: unknown-position guard. A position carrying our magic whose comment
// no longer names a level cannot be managed (no BE/trail/cloud exit can
// find it) — track it, block new entries on its symbol until it is gone,
// and log it once per ticket (not once per minute).
bool              symBlockedUnknown[MAX_SYMS];
ulong             unknownLoggedTickets[64];
int               unknownLoggedCount   = 0;

// §75 key levels: M15 .. MN1. A tier's own TF has index lvl-1 (M15 tier = 0), so the lines
// above tier lvl start at index lvl.
#define KLN 7
#define KL_H4 3
ENUM_TIMEFRAMES klTf[KLN]   = { PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4, PERIOD_D1, PERIOD_W1, PERIOD_MN1 };
string          klName[KLN] = { "M15", "M30", "H1", "H4", "D1", "W1", "MN1" };
int      klIch[MAX_SYMS][KLN];
int      klAtr[MAX_SYMS][KLN];
double   klFloor[MAX_SYMS][LEVELS];     // profit floor a target line must lie beyond (fixed at entry)
double   tpLine[MAX_SYMS][LEVELS];      // the line the broker TP sits on
int      tpLi[MAX_SYMS][LEVELS];        // ... and its TF index
long     posId[MAX_SYMS][LEVELS];       // position identifier, to read a broker TP fill from history
datetime pendBar[MAX_SYMS][LEVELS];     // late-candle hold: open time of the line-TF bar to wait out (0 = none)
int      pendLi[MAX_SYMS][LEVELS];
double   pendLine[MAX_SYMS][LEVELS];
datetime holdUntil[MAX_SYMS];           // H4+D1 hold: no trend entries before this time
int      lockDir[MAX_SYMS];             // re-entry lock: direction (0 = none)
int      lockTier[MAX_SYMS];
double   lockLine[MAX_SYMS];
int      lockLi[MAX_SYMS];              // TF index the close beyond is read on
datetime lockBar[MAX_SYMS];             // open time of that TF's bar holding the exit
int      revState[MAX_SYMS][LEVELS];    // reversal trade per tier: 0 / 1 / -1

int MAGIC = 20260895;   // §75 HTF key-level TP experiment (the live VPS build runs 20260858)

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

      // §75 key-level handles and memory
      holdUntil[s] = 0; lockDir[s] = 0; lockTier[s] = 0; lockLine[s] = 0.0; lockLi[s] = 0; lockBar[s] = 0;
      for(int l = 0; l < LEVELS; l++) ResetKLMemory(s, l);
      for(int i = 0; i < KLN; i++)
      {
         klIch[s][i] = iIchimoku(syms[s], klTf[i], Tenkan, Kijun, SenkouB);
         klAtr[s][i] = iATR(syms[s], klTf[i], InpATRPeriod);
         if(klIch[s][i] == INVALID_HANDLE || klAtr[s][i] == INVALID_HANDLE) return(INIT_FAILED);
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
      for(int i = 0; i < KLN; i++)
      {
         if(klIch[s][i] != INVALID_HANDLE) IndicatorRelease(klIch[s][i]);
         if(klAtr[s][i] != INVALID_HANDLE) IndicatorRelease(klAtr[s][i]);
      }
   }
}

//==============================================================
// Position State Sync (recover after restart)
//==============================================================

string LevelComment(int lvl, int dir)
{
   return (dir == 1 ? "Exp Buy " : "Exp Sell ") + tfName[lvl + 1];
}

// §75 reversal trades carry their own comment so the sync and the R2 guard know them.
string RevComment(int lvl, int dir)
{
   return (dir == 1 ? "Exp RevBuy " : "Exp RevSell ") + tfName[lvl + 1];
}

void ResetKLMemory(int s, int l)
{
   klFloor[s][l] = 0.0; tpLine[s][l] = 0.0; tpLi[s][l] = -1; posId[s][l] = 0;
   pendBar[s][l] = 0; pendLi[s][l] = 0; pendLine[s][l] = 0.0;
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
         revState[s][l] = 0;                      // §75
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
            // §75: a reversal trade is known, not an orphan
            int revMatch = -1;
            for(int l = 0; l < LEVELS; l++)
               if(comm == RevComment(l, 1) || comm == RevComment(l, -1)) { revMatch = l; break; }
            if(revMatch >= 0)
            {
               revState[s][revMatch] = dir;
               continue;
            }
            symBlockedUnknown[s] = true;
            LogUnknownOnce(ticket, sym, comm);
            continue;
         }

         state[s][lvlMatch] = dir;
         hasPos[s][lvlMatch] = true;
         posId[s][lvlMatch] = PositionGetInteger(POSITION_IDENTIFIER);   // §75

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
         // §75: rebuild the profit floor after a restart (ATR now, not at entry)
         if(klFloor[s][lvlMatch] == 0.0)
         {
            double fa[1];
            if(CopyBuffer(atr[s][lvlMatch], 0, 1, 1, fa) > 0 && fa[0] > 0)
               klFloor[s][lvlMatch] = entryPrice[s][lvlMatch] + dir * InpKLFloorATR * fa[0];
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
            ResetKLMemory(s, l);                 // §75
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
// Level Cloud Bias Gate (EXPERIMENTAL CHANGE): applies to every
// tier — the tier's TF (lvl+1, always M5 or above) needs only
// the FUTURE cloud in the trade's direction; the TF directly
// below it is M1 for the M5 tier (full check: current AND future
// must agree with the trade) and M5 or above for the higher
// tiers (future-only). So: M1 = both cloud values must agree;
// M5 upwards = current cloud may be any value, future cloud must
// be in the trade's direction.
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
      ResetKLMemory(s, lvl);                                         // §75
      double fa[1];
      if(CopyBuffer(atr[s][lvl], 0, 1, 1, fa) > 0 && fa[0] > 0)
         klFloor[s][lvl] = price + dir * InpKLFloorATR * fa[0];
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
   double tpCur = PositionGetDouble(POSITION_TP);   // §75: every modify keeps the key-level TP

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
         if(trade.PositionModify(ticket, dSl, tpCur))
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
            if(!trade.PositionModify(ticket, slNew, tpCur))
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
   tpCur = PositionGetDouble(POSITION_TP);

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
         if(!trade.PositionModify(ticket, slNew, tpCur))
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
// §75 HTF key levels
//==============================================================

// Lines above tier lvl start at KL index lvl (the tier's own TF is lvl-1).
int KLFirst(int lvl)
{
   return (lvl > (int)InpKLMinTF) ? lvl : (int)InpKLMinTF;
}

// Line q (0 tenkan, 1 kijun, 2 Span A, 3 Span B) of key TF i on its last closed bar.
bool KLLine(int s, int i, int q, double &v)
{
   double b[1];
   if(CopyBuffer(klIch[s][i], q, 1, 1, b) <= 0) return false;
   if(b[0] <= 0 || b[0] == EMPTY_VALUE) return false;
   v = b[0];
   return true;
}

// Nearest line at or beyond the profit floor in the trade's direction.
bool KLNext(int s, int lvl, int dir, double floorPx, double &L, int &li)
{
   li = -1; L = 0.0;
   for(int i = KLFirst(lvl); i < KLN; i++)
      for(int q = 0; q < 4; q++)
      {
         double v;
         if(!KLLine(s, i, q, v)) continue;
         if(dir == 1) { if(v >= floorPx && (li < 0 || v < L)) { L = v; li = i; } }
         else         { if(v <= floorPx && (li < 0 || v > L)) { L = v; li = i; } }
      }
   return li >= 0;
}

// The line above tier lvl closest to px, if within tol.
bool KLNear(int s, int lvl, double px, double tol, double &L, int &li)
{
   li = -1; L = 0.0;
   double best = tol;
   for(int i = KLFirst(lvl); i < KLN; i++)
      for(int q = 0; q < 4; q++)
      {
         double v;
         if(!KLLine(s, i, q, v)) continue;
         if(MathAbs(v - px) <= best) { best = MathAbs(v - px); L = v; li = i; }
      }
   return li >= 0;
}

// An H4 line and a D1/W1/MN1 line both within InpKLConfTolATR x ATR(H4) of px.
bool KLConfluence(int s, double px)
{
   double a[1];
   if(CopyBuffer(klAtr[s][KL_H4], 0, 1, 1, a) <= 0 || a[0] <= 0) return false;
   double tol = InpKLConfTolATR * a[0];
   bool h4 = false, d1 = false;
   for(int q = 0; q < 4; q++)
   {
      double v;
      if(KLLine(s, KL_H4, q, v) && MathAbs(v - px) <= tol) h4 = true;
      for(int i = KL_H4 + 1; i < KLN; i++)
         if(KLLine(s, i, q, v) && MathAbs(v - px) <= tol) d1 = true;
   }
   return h4 && d1;
}

// Open time of the TF-i bar that holds t.
datetime KLBarOpen(int s, int i, datetime t)
{
   int sh = iBarShift(syms[s], klTf[i], t);
   return (sh >= 0) ? iTime(syms[s], klTf[i], sh) : 0;
}

// Close time of the forming TF-i bar (MN1: the 1st of next month).
datetime KLBarEnd(int s, int i)
{
   datetime t0 = iTime(syms[s], klTf[i], 0);
   if(klTf[i] != PERIOD_MN1) return t0 + PeriodSeconds(klTf[i]);
   MqlDateTime dt;
   TimeToStruct(t0, dt);
   dt.mon++;
   if(dt.mon > 12) { dt.mon = 1; dt.year++; }
   return StructToTime(dt);
}

// After a key-level exit at px on line L of TF li, at time t: the H4+D1 hold and the re-entry lock.
void KLAfterExit(int s, int lvl, int dir, double px, double L, int li, datetime t)
{
   if(InpKLConfHold && KLConfluence(s, px))
   {
      holdUntil[s] = KLBarOpen(s, KL_H4, t) + PeriodSeconds(PERIOD_H4);
      string msg = PCTime() + " | " + syms[s] + " H4+D1 key level at " + DoubleToString(px, 2) +
                   ": no new trend entries until the next H4 bar";
      Print(msg); SendNotification(msg);
   }
   if(InpKLReentry != KLRE_NONE)
   {
      lockDir[s]  = dir;
      lockTier[s] = lvl;
      lockLine[s] = L;
      lockLi[s]   = (InpKLBreachLevelTF && li >= 0) ? li : (int)MathMax(0, lvl - 1);
      lockBar[s]  = KLBarOpen(s, lockLi[s], t);
      Print(PCTime() + " | " + syms[s] + " re-entry " + (dir == 1 ? "long" : "short") + " locked at " +
            DoubleToString(L, 2) + " until a " + klName[lockLi[s]] + " close beyond it" +
            (InpKLReentry == KLRE_EITHER ? " or a " + tfName[lvl + 1] + " realign" :
             InpKLReentry == KLRE_REALIGN ? " (realign mode)" : ""));
   }
}

// Release the re-entry lock once its condition is met (checked every closed M1 bar).
void KLReleaseLock(int s)
{
   if(lockDir[s] == 0) return;
   bool rel = false;
   if(InpKLReentry == KLRE_REALIGN || InpKLReentry == KLRE_EITHER)
      if(ChainAligned(s, lockTier[s] + 1) != lockDir[s]) rel = true;
   if(!rel && (InpKLReentry == KLRE_BREACH || InpKLReentry == KLRE_EITHER))
   {
      int i = lockLi[s];
      double a[1];
      if(iTime(syms[s], klTf[i], 1) >= lockBar[s] && CopyBuffer(klAtr[s][i], 0, 1, 1, a) > 0 &&
         (iClose(syms[s], klTf[i], 1) - lockLine[s]) * lockDir[s] > InpKLBreachBufATR * a[0])
         rel = true;
   }
   if(rel)
   {
      Print(PCTime() + " | " + syms[s] + " re-entry lock released");
      lockDir[s] = 0;
   }
}

bool SetTP(int s, int lvl, ulong ticket, double sl, double tp)
{
   if(trade.PositionModify(ticket, sl, tp)) return true;
   Print(PCTime() + " | " + syms[s] + " " + tfName[lvl + 1] + " key-level TP modify failed, retcode " +
         IntegerToString(trade.ResultRetcode()));
   return false;
}

// Per closed M1 bar for an open trend level: refresh the broker TP, take a touch at market,
// or hold a late-candle touch until the line's bar closes.
void ManageKeyLevel(int s, int l)
{
   int dir = state[s][l];
   if(dir == 0) return;
   ulong ticket;
   if(!LevelTicket(s, l, ticket)) return;
   double   slCur  = PositionGetDouble(POSITION_SL);
   double   tpCur  = PositionGetDouble(POSITION_TP);
   datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
   string sym   = syms[s];
   double bid   = SymbolInfoDouble(sym, SYMBOL_BID);
   double ask   = SymbolInfoDouble(sym, SYMBOL_ASK);
   double px    = (dir == 1) ? bid : ask;
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   double minDist = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * point;
   int    digits  = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);

   if(pendBar[s][l] != 0)                     // late-candle hold in progress
   {
      int li = pendLi[s][l];
      if(iTime(sym, klTf[li], 0) != pendBar[s][l])
      {
         double L = pendLine[s][l];
         if(ExitLevel(s, l, "key level " + klName[li] + ", held to its candle close"))
            KLAfterExit(s, l, dir, px, L, li, TimeCurrent());
         return;
      }
      if(tpCur != 0.0) SetTP(s, l, ticket, slCur, 0.0);
      return;
   }

   double L; int li;
   if(klFloor[s][l] == 0.0 || !KLNext(s, l, dir, klFloor[s][l], L, li))
   {
      if(tpCur != 0.0) SetTP(s, l, ticket, slCur, 0.0);
      return;
   }
   bool late    = InpKLLateMin > 0 && KLBarEnd(s, li) - TimeCurrent() <= InpKLLateMin * 60;
   bool touched = (px - L) * dir >= 0;
   if(late && !touched)
   {
      MqlRates m1[];
      if(CopyRates(sym, PERIOD_M1, 1, 1, m1) == 1 && m1[0].time >= opened)
         touched = (dir == 1) ? (m1[0].high >= L) : (m1[0].low + (ask - bid) <= L);
   }
   if(touched && late)
   {
      pendBar[s][l] = iTime(sym, klTf[li], 0); pendLi[s][l] = li; pendLine[s][l] = L;
      string msg = PCTime() + " | " + sym + " " + tfName[l + 1] + " touched the " + klName[li] +
                   " key level in its last " + IntegerToString(InpKLLateMin) + " min: holding to the candle close";
      Print(msg); SendNotification(msg);
      if(tpCur != 0.0) SetTP(s, l, ticket, slCur, 0.0);
      return;
   }
   if(touched)
   {
      if(ExitLevel(s, l, "HTF key level " + klName[li]))
         KLAfterExit(s, l, dir, px, L, li, TimeCurrent());
      return;
   }
   tpLine[s][l] = L; tpLi[s][l] = li;
   double want = late ? 0.0 : NormalizeDouble(L, digits);
   if(want != 0.0 && !((dir == 1) ? want > bid + minDist : want < ask - minDist)) want = 0.0;
   if(MathAbs(want - tpCur) >= point) SetTP(s, l, ticket, slCur, want);
}

// A level that the sync found closed by the broker: was it the key-level TP?
void DetectBrokerTP(int s, int l, int dir, long pid, double line, int li)
{
   if(pid == 0 || !HistorySelectByPosition(pid)) return;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong d = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      if(HistoryDealGetInteger(d, DEAL_REASON) == DEAL_REASON_TP)
      {
         double px = HistoryDealGetDouble(d, DEAL_PRICE);
         string msg = PCTime() + " | Close " + syms[s] + " " + tfName[l + 1] + " (key-level TP " +
                      (li >= 0 ? klName[li] : "?") + " @ " + DoubleToString(px, 2) + ")";
         Print(msg); SendNotification(msg);
         KLAfterExit(s, l, dir, px, line > 0 ? line : px, li, (datetime)HistoryDealGetInteger(d, DEAL_TIME));
      }
      return;
   }
}

//==============================================================
// §75 Reversal trades (off by default)
//==============================================================

bool RevTicket(int s, int lvl, ulong &ticket)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != syms[s]) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MAGIC) continue;
      string comm = PositionGetString(POSITION_COMMENT);
      if(comm == RevComment(lvl, 1) || comm == RevComment(lvl, -1)) return true;
   }
   return false;
}

// Every open reversal takes profit at the kijun of the LOWEST tier with one open; a kijun at or
// past the price closes them at market.
void ManageReversals(int s)
{
   int lo = -1;
   for(int l = 0; l < LEVELS; l++)
      if(revState[s][l] != 0) { lo = l; break; }
   if(lo < 0) return;
   double kj[1];
   if(CopyBuffer(ich[s][lo + 1], 1, 1, 1, kj) <= 0 || kj[0] <= 0) return;
   string sym = syms[s];
   double bid = SymbolInfoDouble(sym, SYMBOL_BID), ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   double minDist = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * point;
   int    digits  = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   for(int l = 0; l < LEVELS; l++)
   {
      int dir = revState[s][l];
      if(dir == 0) continue;
      ulong ticket;
      if(!RevTicket(s, l, ticket)) continue;
      double px = (dir == 1) ? bid : ask;
      if((px - kj[0]) * dir >= 0)
      {
         if(trade.PositionClose(ticket))
         {
            revState[s][l] = 0;
            string msg = PCTime() + " | Close " + sym + " reversal " + tfName[l + 1] + " (at the " + tfName[lo + 1] + " kijun)";
            Print(msg); SendNotification(msg);
         }
         continue;
      }
      double tp = NormalizeDouble(kj[0], digits);
      bool ok = (dir == 1) ? tp > bid + minDist : tp < ask - minDist;
      if(ok && MathAbs(tp - PositionGetDouble(POSITION_TP)) >= point)
         trade.PositionModify(ticket, PositionGetDouble(POSITION_SL), tp);
   }
}

// Tier lvl signalled dir with every gate passed: if the price sits at a key line of a TF above
// the tier, open the opposite trade (lots as the trend trade's risk rule).
bool TryReversal(int s, int lvl, int dir)
{
   string sym = syms[s];
   double a[1];
   if(CopyBuffer(atr[s][lvl], 0, 1, 1, a) <= 0 || a[0] <= 0) return false;
   double ra  = a[0];
   double bid = SymbolInfoDouble(sym, SYMBOL_BID), ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double L; int li;
   if(!KLNear(s, lvl, (dir == 1) ? ask : bid, InpRevTolATR * ra, L, li)) return false;
   double kj[1];
   if(CopyBuffer(ich[s][lvl + 1], 1, 1, 1, kj) <= 0 || kj[0] <= 0) return false;
   int    r  = -dir;
   double rp = (r == 1) ? ask : bid;
   double rs = (r == 1) ? MathMin(L, bid) - InpRevStopATR * ra : MathMax(L, ask) + InpRevStopATR * ra;
   double sd = (rp - rs) * r, gain = (kj[0] - rp) * r;
   if(sd <= 0 || gain <= 0 || gain < InpRevMinRR * sd) return false;

   double point   = SymbolInfoDouble(sym, SYMBOL_POINT);
   double minDist = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * point;
   int    digits  = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   rs = NormalizeDouble(rs, digits);
   double tp = NormalizeDouble(kj[0], digits);
   if(!((r == 1) ? rs < bid - minDist : rs > ask + minDist)) return false;
   if(!((r == 1) ? tp > bid + minDist : tp < ask - minDist)) tp = 0.0;

   double lots = RiskLots(s, lvl) * InpRevLotMult;
   double lotStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP), lotMin = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   if(lotStep > 0) lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(lotMin, lots);
   CapLotsToMargin(sym, (r == 1), lots);

   trade.SetTypeFillingBySymbol(sym);
   bool ok = (r == 1) ? trade.Buy(lots, sym, rp, rs, tp, RevComment(lvl, r))
                      : trade.Sell(lots, sym, rp, rs, tp, RevComment(lvl, r));
   if(ok)
   {
      revState[s][lvl] = r;
      string msg = PCTime() + " | " + (r == 1 ? "Buy" : "Sell") + " " + sym + " reversal " + tfName[lvl + 1] +
                   " @ " + DoubleToString(lots, 2) + " (" + tfName[lvl + 1] + " " + (dir == 1 ? "buy" : "sell") +
                   " signal at the " + klName[li] + " key level " + DoubleToString(L, 2) + ")";
      Print(msg); SendNotification(msg);
   }
   else
      Print(PCTime() + " | " + sym + " reversal " + tfName[lvl + 1] + " order failed, retcode " +
            IntegerToString(trade.ResultRetcode()));
   return ok;
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

      // Sync position state once per tick on the first new M1 bar instead of
      // rebuilding it on every single tick.
      if(!synced)
      {
         // §75: remember what was open, so a level the broker closed at its key-level TP is seen
         int    prevSt[MAX_SYMS][LEVELS];
         long   prevPid[MAX_SYMS][LEVELS];
         double prevLine[MAX_SYMS][LEVELS];
         int    prevLi[MAX_SYMS][LEVELS];
         for(int a = 0; a < symsCount; a++)
            for(int l = 0; l < LEVELS; l++)
            {
               prevSt[a][l] = state[a][l]; prevPid[a][l] = posId[a][l];
               prevLine[a][l] = tpLine[a][l]; prevLi[a][l] = tpLi[a][l];
            }
         SyncStateFromPositions();
         synced = true;
         if(InpKLTP)
            for(int a = 0; a < symsCount; a++)
               for(int l = 0; l < LEVELS; l++)
                  if(prevSt[a][l] != 0 && state[a][l] == 0)
                     DetectBrokerTP(a, l, prevSt[a][l], prevPid[a][l], prevLine[a][l], prevLi[a][l]);
      }

      // Exits and profit protection per level
      for(int l = 0; l < LEVELS; l++)
      {
         // Exit check: price touched the level TF's cloud edge
         if(state[s][l] != 0 && InCloudTouch(s, l + 1, state[s][l]))
            ExitLevel(s, l, "kumo touch");

         // Rejection exit: a very strong rejection candle formed on
         // the tier TF against the trade (bearish kills a long,
         // bullish kills a short)
         if(InpRejectionExit && state[s][l] != 0)
         {
            int rj = RejectionCandle(s, l + 1);
            if(rj != 0 && rj == -state[s][l])
               ExitLevel(s, l, "rejection");
         }

         // §75: key-level TP, late-candle hold
         if(InpKLTP && state[s][l] != 0) ManageKeyLevel(s, l);

         // Profit protection: BE + spike-lock chandelier trail
         if(state[s][l] != 0) ManageLevelProtection(s, l);
      }

      // §75: reversal TPs, and the re-entry lock
      ManageReversals(s);
      KLReleaseLock(s);
      bool klHold  = InpKLTP && TimeCurrent() < holdUntil[s];
      bool revFired = false;

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
            // M5 tier dropped (2026-09-23): no new M5 entries. An M5 position
            // already open keeps its exits and protection until it closes.
            if(l == 0 && !InpM5Tier) continue;
            int st = ChainAligned(s, l + 1);
            if(st == 0) continue;
            if(InpCloudBiasEnabled && !LevelCloudBiasOK(s, l, st)) continue;

            // Directional bias: H4 as before, with the new H1 stand-in for
            // the lower tiers when H4 has no direction of its own.
            string via = "--";
            if(!EntryBiasOK(s, l, st, via)) continue;

            // H4 tier: D1 must carry the same bias (D1 in the cloud = no H4 trades)
            if(l == LEVELS - 1 && InpD1Filter && DailyAlign(s) != st) continue;

            // §75 reversal: a signal at a key line fades it; every smaller tier that signals too
            // fades with it, and no trend trade opens this minute
            if(InpRevEnabled && revState[s][l] == 0 && l >= InpRevMinTier && l <= InpRevMaxTier &&
               TryReversal(s, l, st))
            {
               revFired = true;
               continue;
            }
            if(revFired) continue;

            // §75: H4+D1 hold blocks every trend entry; the re-entry lock blocks the locked direction
            if(klHold) break;
            if(InpKLTP && lockDir[s] == st && (InpKLLockAllTiers || l <= lockTier[s])) continue;

            topTier = l;
            topDir  = st;
            topVia  = via;
            break;
         }
      }

      if(revFired) ManageReversals(s);   // §75: all reversals to the lowest tier's kijun

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
//Fear God and Live
