//+------------------------------------------------------------------+
//| Ichimoku Bottom-Up Stack EA — VPS REVAMP (experiment, notes §74)  |
//| Magic 20260894. A revamp of the live VPS build                    |
//| (ichimoku-h4-m1-vps-ea.mq5, magic 20260858, NOT touched), built   |
//| on the §73 review fork. Headless: no Alert(), one closed M1 bar   |
//| at a time, state rebuilt from the account after a restart.        |
//|                                                                   |
//| STRATEGY (unchanged from the live build)                          |
//|  Entry  A tier (M15, M30, H1, H4; M5 is off) opens when the whole |
//|         stack M1..tier TF is aligned one way: price and chikou    |
//|         beyond tenkan, kijun and the cloud. The far end of the    |
//|         future cloud must agree on the tier TF and the TF below.  |
//|         H4 is the bias for every tier; while H4 is flat, H1       |
//|         stands in for M15/M30. The H4 tier also needs D1.         |
//|         The scan runs H4 -> M15 and the largest free tier opens;  |
//|         smaller tiers already running are closed into it.         |
//|  Exit   The bid/ask touches the tier TF's cloud edge. Before      |
//|         that: break-even (1 ATR; 0.5 on H1/H4) and a chandelier   |
//|         trail 1 ATR behind the peak (armed at 2 ATR; 0.5 on       |
//|         H1/H4). Hard stop: 8 x ATR ("disaster stop").             |
//|  Risk   % of equity per tier in three equity bands, measured      |
//|         against 2 x ATR. The real exit is the cloud or the        |
//|         8 x ATR stop, so a loser can cost up to 4x the nominal %. |
//|                                                                   |
//| SWITCHES. With every revamp switch off this is the live build's   |
//| logic exactly. Group A is on by default (defect fixes); groups B  |
//| and C are off by default (they change results or add limits).     |
//|  A. Defect fixes                                                  |
//|   #1  InpOnePosition         a running tier blocks itself and     |
//|                              every smaller tier                   |
//|   #3  InpPeakSinceEntry      chandelier peak from M1 bars since   |
//|                              entry, not the forming tier bar      |
//|   #8  InpDisasterBreachClose no stop could be attached and price  |
//|                              is past its level: close at market   |
//|   #9  InpSkipOnNoSizing      no ATR/tick data: skip, do not open  |
//|                              InpFixedLots                         |
//|   #11 InpUseFillPrice        BE/trail measure from the fill       |
//|   #14 InpQuietRetries        a retried exit pushes once           |
//|   #16 InpShortStopFix        a short with no stop can still get   |
//|                              break-even and the trail             |
//|  B. Strategy switches                                             |
//|   #2  InpSizeOnCloudDist     size on the distance to the cloud    |
//|   #4  InpArmOnPeak           trail arms on the peak, not the bid  |
//|   #5  InpRealignAfterStop    re-align before re-entering          |
//|   #6  InpExitMaxSpread       kumo exit waits out a wide spread    |
//|   #10 InpMaxMinLotRiskPct    skip a tier the minimum lot oversizes|
//|   #17 InpSupersedeGuard      no new tier while a superseded one   |
//|                              could not be closed (review R1)      |
//|       InpRiskScale           multiplies every risk band           |
//|  C. Capital protection                                            |
//|       InpMaxOpenRiskPct      cap on the loss at all hard stops    |
//|       InpDailyLossPct / InpWeeklyLossPct   no entries after it    |
//|       InpDDRiskAtPct / InpDDRiskFactor     risk cut in drawdown   |
//|       InpMaxConsecLosses / InpLossPauseHours  loss-streak pause   |
//|       InpFriNoEntryHour / InpFriFlatHour      weekend guard       |
//|       InpQuietFromHHMM / InpQuietToHHMM       rollover window     |
//| Every blocked or skipped entry is written to the journal once per |
//| tier bar. A push goes out only when a loss limit or the loss-     |
//| streak pause engages, once each time.                             |
//|                                                                   |
//| STATUS: not compiled in MetaEditor and not run in the MT5 tester  |
//| (see notes §74). Simulated in utilities/vps-sim.                  |
//| Author: Neo Malesa                                                |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

//==================================================================
// 1. INPUTS
// The first block is the live build's inputs, unchanged in name,
// order and default. The revamp switches follow.
//==================================================================

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

input group  "Revamp A — defect fixes (all off = the live build)"
input bool   InpOnePosition         = true;   // #1 A running tier blocks itself and every smaller tier (a bigger tier may still supersede)
input bool   InpPeakSinceEntry      = true;   // #3 Chandelier peak from M1 bars since entry (live: the forming tier bar, incl. pre-entry prices)
input bool   InpDisasterBreachClose = true;   // #8 Close at market when price is past the disaster level and no SL could be attached
input bool   InpSkipOnNoSizing      = true;   // #9 Skip the entry when sizing data is missing (live: open InpFixedLots)
input bool   InpUseFillPrice        = true;   // #11 BE/trail reference = the fill price (live: the requested price)
input bool   InpQuietRetries        = true;   // #14 A retried exit sends one push, not one per minute
input bool   InpShortStopFix        = true;   // #16 A short with NO stop can still get break-even and the trail (live: never)

input group  "Revamp B — strategy switches (off = the live build)"
input bool   InpSizeOnCloudDist     = false;  // #2 Size on max(ATR x InpRiskATRMult, distance to the tier cloud), capped at the disaster distance
input bool   InpArmOnPeak           = false;  // #4 Chandelier arms once the peak reached the threshold (live: the bid, once a minute)
input bool   InpRealignAfterStop    = false;  // #5 After a broker-side stop the tier must lose alignment before re-entering
input int    InpExitMaxSpread       = 0;      // #6 Kumo-touch exit waits while spread > this many points (0 = off)
input double InpMaxMinLotRiskPct    = 0.0;    // #10 Skip a tier whose MINIMUM lot risks more than this % at the sizing distance (0 = off)
input bool   InpSupersedeGuard      = false;  // #17 Do not open the bigger tier while a superseded smaller one failed to close
input double InpRiskScale           = 1.0;    // Multiplies every risk band (1.0 = the live bands, 0.5 = half)

input group  "Revamp C — capital protection (0 / -1 = off)"
input double InpMaxOpenRiskPct      = 0.0;    // Cap lots so the loss at every hard stop on the symbol, the new one included, is within this % of equity
input double InpDailyLossPct        = 0.0;    // No new entries for the rest of the server day once equity is this % below the day's start
input double InpWeeklyLossPct       = 0.0;    // No new entries for the rest of the week once equity is this % below the week's start
input double InpDDRiskAtPct         = 0.0;    // While equity is this % or more below its high-water mark, risk is multiplied by InpDDRiskFactor
input double InpDDRiskFactor        = 0.5;    // Risk multiplier while in that drawdown
input bool   InpDDResetHWM          = false;  // Reset the stored high-water mark to the current equity at start-up (after a deposit/withdrawal)
input int    InpMaxConsecLosses     = 0;      // Pause entries after a loss that makes this many losing trades in a row
input double InpLossPauseHours      = 24.0;   // Length of that pause, from the last losing close
input int    InpFriNoEntryHour      = -1;     // No new entries on Friday from this server hour (0-23)
input int    InpFriFlatHour         = -1;     // Close every position on Friday at this server hour, and no entries after it
input int    InpQuietFromHHMM       = 0;      // No new entries from this server time (HHMM, e.g. 2330) ...
input int    InpQuietToHHMM         = 0;      // ... until this one (e.g. 130). May wrap midnight. Equal = off
input bool   InpNotifyGuards        = true;   // One push when a loss limit or the loss-streak pause engages

//==================================================================
// 2. CONSTANTS AND STATE
//==================================================================

#define MAX_SYMS 60
#define LEVELS   5      // tradable levels: M5, M15, M30, H1, H4
#define TFS      6      // stack: M1, M5, M15, M30, H1, H4
#define IDX_H1   4      // index of H1 in tfs[] — the stand-in bias TF
#define IDX_H4   5      // index of H4 in tfs[] — the primary bias TF

ENUM_TIMEFRAMES tfs[TFS] = { PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4 };
string          tfName[TFS] = { "M1", "M5", "M15", "M30", "H1", "H4" };

int MAGIC = 20260894;   // VPS revamp experiment (§74) — distinct from the live 20260858

CTrade trade;

// Symbols and indicator handles
string   syms[MAX_SYMS];
int      symsCount = 0;
int      ich[MAX_SYMS][TFS];
int      ichD1[MAX_SYMS];              // D1 ichimoku — H4-tier bias filter
int      atr[MAX_SYMS][LEVELS];        // ATR(level TF)

// Loop gating
datetime lastM1bar[MAX_SYMS];
int      lastMinuteKey = -1;

// Per-tier trade state, rebuilt by SyncStateFromPositions()
int      state[MAX_SYMS][LEVELS];        // 0 = flat, 1 = long, -1 = short
double   entryPrice[MAX_SYMS][LEVELS];   // BE and trail reference
double   peakHigh[MAX_SYMS][LEVELS];     // long chandelier reference
double   peakLow[MAX_SYMS][LEVELS];      // short chandelier reference
bool     beMoved[MAX_SYMS][LEVELS];      // break-even stop already set (one-shot)
datetime peakFrom[MAX_SYMS][LEVELS];     // #3: first M1 bar not yet folded into the peak
int      needRealign[MAX_SYMS][LEVELS];  // #5: side that must drop out of alignment first (0 = none)
bool     exitNotified[MAX_SYMS][LEVELS]; // #14: this trade's exit push already went out

// R2: a magic position whose comment names no level cannot be managed.
// It blocks new entries on its symbol and is logged once per ticket.
bool     symBlockedUnknown[MAX_SYMS];
ulong    unknownLoggedTickets[64];
int      unknownLoggedCount = 0;

// Account guards (section 7). Day/week start equity and the high-water
// mark live in terminal global variables, so a restart keeps them.
double   dayStartEq   = 0.0;
int      dayKey       = -1;            // server day (days since 1970)
double   weekStartEq  = 0.0;
int      weekKey      = -1;            // server week, Monday start
double   equityHWM    = 0.0;
int      lossStreak   = 0;             // losing closes in a row, newest first
datetime lastLossTime = 0;             // close time of the newest of them
bool     streakDirty  = true;          // re-read the streak from the deal history
string   guardPushed  = "";            // the guard event already pushed

// Journal de-duplication: one line per symbol, tier and tier bar
datetime lastLogBar[MAX_SYMS][LEVELS];
string   lastLogMsg[MAX_SYMS][LEVELS];

//==================================================================
// 3. UTILITIES
// Time stamp, level comment, logging that cannot spam.
//==================================================================

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

string LevelComment(int lvl, int dir)
{
   return (dir == 1 ? "Exp Buy " : "Exp Sell ") + tfName[lvl + 1];
}

// Journal line for a blocked or skipped entry: written when the message for
// this symbol and tier changes, and at most once per tier bar otherwise.
// Never a push notification.
void LogOncePerBar(int s, int lvl, string msg)
{
   datetime bar = iTime(syms[s], tfs[lvl + 1], 0);
   if(bar == lastLogBar[s][lvl] && msg == lastLogMsg[s][lvl]) return;
   lastLogBar[s][lvl] = bar;
   lastLogMsg[s][lvl] = msg;
   Print(PCTime() + " | " + syms[s] + " " + tfName[lvl + 1] + " entry not taken: " + msg);
}

// Name of a terminal global variable owned by this EA.
string GVName(string what)
{
   return "ICHI_" + IntegerToString(MAGIC) + "_" + what;
}

// Value in money of a price distance for one lot; 0 when the symbol's tick
// data is unreadable.
double MoneyPerLot(string sym, double priceDist)
{
   double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0 || tickSize <= 0) return 0.0;
   return (priceDist / tickSize) * tickValue;
}

// Tier index named by a position comment ("Exp Buy M15"), or -1.
int LevelFromComment(string comm)
{
   for(int l = 0; l < LEVELS; l++)
      if(comm == LevelComment(l, 1) || comm == LevelComment(l, -1)) return l;
   return -1;
}

//==================================================================
// 4. SIGNAL
// Alignment on one timeframe, the bottom-up chain, the cloud-bias gate, the
// kumo-touch exit and the rejection candle. Unchanged from the live build;
// CheckAlign and DailyAlign were two copies of one test and now share AlignOn.
//==================================================================

// Price and chikou both beyond tenkan, kijun and the cloud on one timeframe,
// on the last closed bar. 1 = bullish, -1 = bearish, 0 = neither/unreadable.
int AlignOn(string sym, ENUM_TIMEFRAMES tf, int handle)
{
   int sh      = 1;              // last closed bar
   int chShift = sh + Kijun;     // chikou's chart position for bar sh (Kijun bars back)

   MqlRates rt[];
   if(CopyRates(sym, tf, 0, chShift + 1, rt) <= 0) return 0;
   ArraySetAsSeries(rt, true);

   if(ArraySize(rt) <= chShift) return 0;

   double tenkan[1], kijun[1], senA[1], senB[1];
   if(CopyBuffer(handle, 0, sh, 1, tenkan) <= 0) return 0;
   if(CopyBuffer(handle, 1, sh, 1, kijun)  <= 0) return 0;
   if(CopyBuffer(handle, 2, sh, 1, senA)   <= 0) return 0;
   if(CopyBuffer(handle, 3, sh, 1, senB)   <= 0) return 0;

   double closeP = rt[sh].close;
   double cHi    = MathMax(senA[0], senB[0]);
   double cLo    = MathMin(senA[0], senB[0]);

   bool above = closeP > tenkan[0] && closeP > kijun[0] && closeP > cHi;
   bool below = closeP < tenkan[0] && closeP < kijun[0] && closeP < cLo;
   if(!above && !below) return 0;

   double tenkan_ch[1], kijun_ch[1], senA_ch[1], senB_ch[1];
   if(CopyBuffer(handle, 0, chShift, 1, tenkan_ch) <= 0) return 0;
   if(CopyBuffer(handle, 1, chShift, 1, kijun_ch)  <= 0) return 0;
   if(CopyBuffer(handle, 2, chShift, 1, senA_ch)   <= 0) return 0;
   if(CopyBuffer(handle, 3, chShift, 1, senB_ch)   <= 0) return 0;

   double chik = closeP;
   double cHiC = MathMax(senA_ch[0], senB_ch[0]);
   double cLoC = MathMin(senA_ch[0], senB_ch[0]);

   if(above && chik > rt[chShift].high &&
      chik > tenkan_ch[0] && chik > kijun_ch[0] && chik > cHiC) return  1;

   if(below && chik < rt[chShift].low &&
      chik < tenkan_ch[0] && chik < kijun_ch[0] && chik < cLoC) return -1;

   return 0;
}

int CheckAlign(int s, int tfIdx) { return AlignOn(syms[s], tfs[tfIdx], ich[s][tfIdx]); }

// D1 bias for the H4 tier: same test on D1 (a close inside the cloud = 0).
int DailyAlign(int s) { return AlignOn(syms[s], PERIOD_D1, ichD1[s]); }

// The full stack M1..topIdx aligned in ONE direction, else 0.
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

// Span A vs Span B at the last closed bar AND at the far end of the future
// cloud. Used on M1 only.
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

// Span A vs Span B at the far end of the future cloud only (M5 and above).
bool CloudBiasFarOK(int s, int tfIdx, int dir)
{
   double aFar[1], bFar[1];
   if(CopyBuffer(ich[s][tfIdx], 2, 1 - Kijun, 1, aFar) <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 3, 1 - Kijun, 1, bFar) <= 0) return false;

   if(dir == 1) return aFar[0] > bFar[0];
   return aFar[0] < bFar[0];
}

// Cloud gate of a tier: the tier TF and the TF directly below it.
bool LevelCloudBiasOK(int s, int lvl, int dir)
{
   if(!CloudBiasFarOK(s, lvl + 1, dir)) return false;   // tier TF — always M5+ — future cloud only
   if(lvl == 0) return CloudBiasOK(s, 0, dir);          // M1 (below the M5 tier) — current AND future
   return CloudBiasFarOK(s, lvl, dir);                  // TF below (M5+) — future cloud only
}

// Kumo-touch exit: a long exits when the bid touches the tier cloud's upper
// edge, a short when the ask touches the lower edge.
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

// Strong rejection candle on the tier TF against the trade (InpRejectionExit).
// 1 = bullish, -1 = bearish, 0 = none.
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

//==================================================================
// 5. BIAS
// H4 is the bias for every tier; H1 stands in for the lower tiers while H4
// is flat (InpH1BiasMode). Unchanged from the live build.
//==================================================================

int H4Bias(int s)
{
   return CheckAlign(s, IDX_H4);    // 1 = bullish, -1 = bearish, 0 = flat/unreadable
}

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

bool H1BiasTier(int lvl)
{
   if(InpH1BiasMode == H1BIAS_OFF)     return false;
   if(lvl >= LEVELS - 1)               return false;   // never the H4 tier
   return lvl <= (int)InpH1BiasMaxTier;
}

// 'via' reports which bias authorised the entry: "H4", "H1" (stand-in on a
// flat H4), "H1x" (stand-in against an aligned H4), "--" (no gate applied).
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

//==================================================================
// 6. SIZING
// Risk % of equity per tier in three equity bands, measured against a
// reference distance, floored to the lot step, capped by margin. The revamp
// adds: a global risk scale, the drawdown cut, sizing on the distance to
// the cloud (#2), the min-lot gate (#10) and the open-risk cap.
//==================================================================

// The live risk bands: % of equity per tier, de-risking as the account
// grows (band 2 from InpRiskTier2At, band 3 from InpRiskTier3At).
double BandRiskPct(int lvl)
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

// InpDDRiskFactor while equity sits InpDDRiskAtPct % or more below its
// high-water mark, else 1. The mark is kept by RefreshAccountGuards().
double DrawdownFactor()
{
   if(InpDDRiskAtPct <= 0 || equityHWM <= 0) return 1.0;
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   return (eq <= equityHWM * (1.0 - InpDDRiskAtPct / 100.0)) ? InpDDRiskFactor : 1.0;
}

// Risk % for a new trade on this tier. With InpRiskScale = 1 and the
// drawdown cut off this is the live band, bit for bit.
double LevelRiskPct(int lvl)
{
   return BandRiskPct(lvl) * InpRiskScale * DrawdownFactor();
}

// The distance the risk % is measured against. Live: ATR(level TF) x
// InpRiskATRMult. #2: the distance from the entry side of the market to the
// tier TF's cloud edge (where the kumo-touch exit fires) when that is
// further, capped at the disaster-stop distance (never below the ATR base).
// Returns 0 when the ATR is unreadable.
double SizingDist(int s, int lvl, int dir)
{
   double a[1];
   if(CopyBuffer(atr[s][lvl], 0, 1, 1, a) <= 0 || a[0] <= 0) return 0.0;
   double base = a[0] * InpRiskATRMult;
   if(!InpSizeOnCloudDist) return base;

   double dist = base;
   double senA[1], senB[1];
   if(CopyBuffer(ich[s][lvl + 1], 2, 1, 1, senA) > 0 &&
      CopyBuffer(ich[s][lvl + 1], 3, 1, 1, senB) > 0)
   {
      double toCloud = (dir == 1)
         ? SymbolInfoDouble(syms[s], SYMBOL_ASK) - MathMax(senA[0], senB[0])
         : MathMin(senA[0], senB[0]) - SymbolInfoDouble(syms[s], SYMBOL_BID);
      if(toCloud > dist) dist = toCloud;
   }
   if(InpDisasterStopEnabled)
      dist = MathMax(base, MathMin(dist, a[0] * InpDisasterATRMult));
   return dist;
}

// Money lost if every position of this EA on the symbol that would stay
// open beside a new trade on tier 'lvl' hit its stop right now. Tiers below
// 'lvl' are left out: a new bigger tier closes them. A position with no
// stop counts at its tier's disaster distance.
double OpenRiskMoney(int s, int lvl)
{
   string sym = syms[s];
   double total = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != sym) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MAGIC) continue;

      int l = LevelFromComment(PositionGetString(POSITION_COMMENT));
      if(l >= 0 && l <= lvl) continue;

      double sl  = PositionGetDouble(POSITION_SL);
      double cur = PositionGetDouble(POSITION_PRICE_CURRENT);
      double vol = PositionGetDouble(POSITION_VOLUME);
      int    dir = ((int)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;

      double dist = 0.0;
      if(sl > 0)
         dist = MathMax(0.0, (cur - sl) * dir);
      else if(l >= 0)
      {
         double a[1];
         if(CopyBuffer(atr[s][l], 0, 1, 1, a) > 0 && a[0] > 0) dist = a[0] * InpDisasterATRMult;
      }
      total += MoneyPerLot(sym, dist) * vol;
   }
   return total;
}

// Lots for a new entry on this tier. Returns 0 — "do not open this tier",
// the scan then walks down to the next one — with the reason in 'why':
//   #9  sizing data missing, or the tier's risk % is 0 (a tier is switched
//       off by setting its risk to 0; live opens InpFixedLots instead)
//   #10 the minimum lot would have to be rounded UP past InpMaxMinLotRiskPct
//   cap the open-risk cap leaves no room for even the minimum lot
double RiskLots(int s, int lvl, int dir, string &why)
{
   why = "";
   string sym      = syms[s];
   double fallback = InpSkipOnNoSizing ? 0.0 : InpFixedLots;   // #9

   double riskPct = LevelRiskPct(lvl);
   if(riskPct <= 0) { why = "risk % for this tier is 0"; return fallback; }

   double stopDist = SizingDist(s, lvl, dir);
   if(stopDist <= 0) { why = "ATR unreadable"; return fallback; }

   double moneyPerLot = MoneyPerLot(sym, stopDist);
   if(moneyPerLot <= 0) { why = "tick value unreadable"; return fallback; }

   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * (riskPct / 100.0);
   double lots      = riskMoney / moneyPerLot;

   double lotStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double lotMin  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double lotMax  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   if(lotStep > 0) lots = MathFloor(lots / lotStep) * lotStep;

   // #10: skip rather than round up to the broker minimum when that
   // minimum alone risks more than the ceiling at the sizing distance.
   if(InpMaxMinLotRiskPct > 0 && lots < lotMin)
   {
      double minLotRiskPct = (equity > 0) ? lotMin * moneyPerLot / equity * 100.0 : 1000.0;
      if(minLotRiskPct > InpMaxMinLotRiskPct)
      {
         why = "minimum lot would risk " + DoubleToString(minLotRiskPct, 1) + "% (limit " +
               DoubleToString(InpMaxMinLotRiskPct, 1) + "%)";
         return 0.0;
      }
   }

   lots = MathMax(lotMin, MathMin(lotMax, lots));

   // Open-risk cap: the loss at every hard stop on the symbol, this trade's
   // disaster stop included, must fit in InpMaxOpenRiskPct % of equity.
   if(InpMaxOpenRiskPct > 0)
   {
      double a[1];
      if(CopyBuffer(atr[s][lvl], 0, 1, 1, a) <= 0 || a[0] <= 0) { why = "ATR unreadable"; return 0.0; }
      double perLotAtStop = MoneyPerLot(sym, a[0] * InpDisasterATRMult);
      double room         = equity * InpMaxOpenRiskPct / 100.0 - OpenRiskMoney(s, lvl);
      double maxLots      = (perLotAtStop > 0) ? room / perLotAtStop : 0.0;
      if(lotStep > 0) maxLots = MathFloor(maxLots / lotStep) * lotStep;
      if(maxLots < lotMin)
      {
         why = "open-risk cap " + DoubleToString(InpMaxOpenRiskPct, 0) + "% leaves no room for the minimum lot";
         return 0.0;
      }
      if(lots > maxLots) lots = maxLots;
   }

   if(lots <= 0) { why = "lot size is 0"; return fallback; }
   return lots;
}

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

//==================================================================
// 7. ACCOUNT GUARDS
// Reasons not to ADD exposure: spread, an unmanageable position, Friday
// and quiet-window rules, the daily and weekly loss limits, the loss-streak
// pause. None of them touches exits or stop management.
//==================================================================

bool SpreadOK(string sym)
{
   if(InpMaxSpreadPoints <= 0) return true;
   return SymbolInfoInteger(sym, SYMBOL_SPREAD) <= InpMaxSpreadPoints;
}

// Read a start-of-period equity from a terminal global variable, or store
// the current equity there if this is the first look at the period.
double PeriodStartEquity(string gv, double equityNow)
{
   if(GlobalVariableCheck(gv)) return GlobalVariableGet(gv);
   GlobalVariableSet(gv, equityNow);
   GlobalVariablesFlush();
   return equityNow;
}

// Losing closes in a row, newest first, read from the deal history of this
// magic (so a restart rebuilds it). A close with profit + swap + commission
// below zero is a loss; anything else ends the run.
void RefreshLossStreak()
{
   lossStreak   = 0;
   lastLossTime = 0;
   datetime now = TimeCurrent();
   if(!HistorySelect(now - 30 * 86400, now + 60)) return;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      if((int)HistoryDealGetInteger(deal, DEAL_MAGIC) != MAGIC) continue;
      if((int)HistoryDealGetInteger(deal, DEAL_ENTRY) == DEAL_ENTRY_IN) continue;
      double pl = HistoryDealGetDouble(deal, DEAL_PROFIT) + HistoryDealGetDouble(deal, DEAL_SWAP) +
                  HistoryDealGetDouble(deal, DEAL_COMMISSION);
      if(pl >= 0) break;
      if(lossStreak == 0) lastLossTime = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
      lossStreak++;
   }
}

// Once per processed minute: roll the day and week, keep the high-water
// mark, refresh the loss streak when a trade has closed. Each part runs
// only while its switch is on, so with them off nothing is read or stored.
void RefreshAccountGuards()
{
   double eq    = AccountInfoDouble(ACCOUNT_EQUITY);
   int    today = (int)(TimeCurrent() / 86400);
   int    week  = (today + 3) / 7;               // 1970-01-01 was a Thursday: weeks start on Monday

   if(InpDailyLossPct > 0 && today != dayKey)
   {
      dayStartEq = PeriodStartEquity(GVName("DAY_" + IntegerToString(today)), eq);
      dayKey     = today;
   }
   if(InpWeeklyLossPct > 0 && week != weekKey)
   {
      weekStartEq = PeriodStartEquity(GVName("WEEK_" + IntegerToString(week)), eq);
      weekKey     = week;
   }
   if(InpDDRiskAtPct > 0)
   {
      string gv = GVName("HWM");
      if(equityHWM <= 0)
      {
         equityHWM = (GlobalVariableCheck(gv) && !InpDDResetHWM) ? GlobalVariableGet(gv) : eq;
         GlobalVariableSet(gv, equityHWM);
      }
      if(eq > equityHWM)
      {
         equityHWM = eq;
         GlobalVariableSet(gv, equityHWM);
      }
   }
   if(InpMaxConsecLosses > 0 && streakDirty)
   {
      RefreshLossStreak();
      streakDirty = false;
   }
}

// Minutes into the server day and the server weekday (5 = Friday).
void ServerClock(int &minuteOfDay, int &dayOfWeek)
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   minuteOfDay = dt.hour * 60 + dt.min;
   dayOfWeek   = dt.day_of_week;
}

// True from InpFriFlatHour on Friday: every position is closed and no
// entry is taken until the market reopens.
bool FridayFlatNow()
{
   if(InpFriFlatHour < 0) return false;
   int mod, dow;
   ServerClock(mod, dow);
   return dow == 5 && mod >= InpFriFlatHour * 60;
}

// Push a guard event once: 'key' names the event (the day, the week, the
// losing close), so the same one is never pushed twice.
void NotifyGuardOnce(string key, string text)
{
   if(!InpNotifyGuards || key == guardPushed) return;
   guardPushed = key;
   string msg = PCTime() + " | " + text;
   Print(msg); SendNotification(msg);
}

// Why no entry may be opened on this symbol right now, or "" when one may.
// Exits and stop management never depend on this.
string EntryBlockReason(int s)
{
   if(symBlockedUnknown[s]) return "an unmanageable position of this EA is open on the symbol";
   if(!SpreadOK(syms[s]))   return "spread above InpMaxSpreadPoints";

   int mod, dow;
   ServerClock(mod, dow);
   if(dow == 5 && InpFriFlatHour    >= 0 && mod >= InpFriFlatHour * 60)    return "Friday flat hour passed";
   if(dow == 5 && InpFriNoEntryHour >= 0 && mod >= InpFriNoEntryHour * 60) return "Friday no-entry hour passed";

   if(InpQuietFromHHMM != InpQuietToHHMM)
   {
      int from = (InpQuietFromHHMM / 100) * 60 + InpQuietFromHHMM % 100;
      int to   = (InpQuietToHHMM   / 100) * 60 + InpQuietToHHMM   % 100;
      bool inside = (from < to) ? (mod >= from && mod < to) : (mod >= from || mod < to);
      if(inside) return "inside the quiet window";
   }

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(InpDailyLossPct > 0 && dayStartEq > 0 && eq <= dayStartEq * (1.0 - InpDailyLossPct / 100.0))
   {
      NotifyGuardOnce("D" + IntegerToString(dayKey), "Daily loss limit " + DoubleToString(InpDailyLossPct, 1) +
                      "% reached — no new entries until the next server day");
      return "daily loss limit reached";
   }
   if(InpWeeklyLossPct > 0 && weekStartEq > 0 && eq <= weekStartEq * (1.0 - InpWeeklyLossPct / 100.0))
   {
      NotifyGuardOnce("W" + IntegerToString(weekKey), "Weekly loss limit " + DoubleToString(InpWeeklyLossPct, 1) +
                      "% reached — no new entries until next week");
      return "weekly loss limit reached";
   }
   if(InpMaxConsecLosses > 0 && lossStreak >= InpMaxConsecLosses &&
      TimeCurrent() < lastLossTime + (datetime)(InpLossPauseHours * 3600.0))
   {
      NotifyGuardOnce("S" + IntegerToString((long)lastLossTime), IntegerToString(lossStreak) +
                      " losing trades in a row — entries paused for " + DoubleToString(InpLossPauseHours, 0) + " h");
      return "loss-streak pause";
   }
   return "";
}

//==================================================================
// 8. ORDERS
// Open, close and find a tier's position.
//==================================================================

// Send the order with its disaster stop (R3) and record the tier's state.
// 'via' is the bias that authorised it, logged with the entry.
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
      // #11: the fill price, when the server reports one, is the true entry.
      double fill = trade.ResultPrice();
      if(InpUseFillPrice && fill > 0) price = fill;
      state[s][lvl] = dir;
      entryPrice[s][lvl] = price;   // BE + spike-lock trail references
      peakHigh[s][lvl]   = price;
      peakLow[s][lvl]    = price;
      beMoved[s][lvl]    = false;
      datetime now = TimeCurrent();
      peakFrom[s][lvl]     = (datetime)(((long)now / 60) * 60);   // #3: the entry minute's M1 bar
      needRealign[s][lvl]  = 0;
      exitNotified[s][lvl] = false;
      string action = (dir == 1) ? "Buy" : "Sell";
      string msg = PCTime() + " | " + action + " " + sym + " " + tfName[lvl + 1] +
                   " @ " + DoubleToString(lots, 2) + " (bottom-up, bias " + via + ")";
      Print(msg); SendNotification(msg);
   }
   return ok;
}

// Close all positions of the level; true only when none remain, so a failed
// close (requote, halt) is retried instead of freeing the level.
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

// Close a tier with a notification; true only when nothing remains open, so
// a failed close is retried next minute. #14: the retries are journal-only.
bool ExitLevel(int s, int l, string reason)
{
   string side = (state[s][l] == 1) ? "Long" : "Short";
   string msg  = PCTime() + " | Close " + syms[s] + " " + side + " " +
                 tfName[l + 1] + " (" + reason + ")";
   Print(msg);
   if(!InpQuietRetries || !exitNotified[s][l]) SendNotification(msg);
   exitNotified[s][l] = true;

   if(CloseLevelPositions(s, l))
   {
      state[s][l] = 0;
      exitNotified[s][l] = false;
      streakDirty = true;
      msg = PCTime() + " | " + syms[s] + " " + tfName[l + 1] + " level closed";
      Print(msg); SendNotification(msg);
      return true;
   }
   Print(PCTime() + " | " + syms[s] + " " + tfName[l + 1] + " exit signal but positions still open — will retry");
   return false;
}

// Close every tier below topTier (the bigger tier replaces them). True when
// none of them is left open.
bool SupersedeLower(int s, int topTier)
{
   bool allClosed = true;
   for(int l = 0; l < topTier; l++)
   {
      if(state[s][l] == 0) continue;

      string msg = PCTime() + " | Close " + syms[s] + " " + tfName[l + 1] +
                   " (superseded by " + tfName[topTier + 1] + ")";
      Print(msg);
      if(!InpQuietRetries || !exitNotified[s][l]) SendNotification(msg);
      exitNotified[s][l] = true;

      if(CloseLevelPositions(s, l))
      {
         state[s][l] = 0;
         exitNotified[s][l] = false;
         streakDirty = true;
      }
      else
      {
         allClosed = false;
         Print(PCTime() + " | " + syms[s] + " " + tfName[l + 1] + " superseded but positions still open — will retry");
      }
   }
   return allClosed;
}

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

//==================================================================
// 9. TRADE PROTECTION
// Per open tier, once a minute: chandelier peak, the disaster stop
// (self-healing), break-even, the chandelier trail. Stops only tighten.
//==================================================================

// Carry the chandelier reference forward. False = the bar data could not be
// read and (live behaviour) stop management is skipped this minute.
//   Live: the extreme of the level-TF bar still forming — which on H4 holds
//         up to four hours of prices from BEFORE the entry.
//   #3:   every M1 bar from the entry minute on, nothing earlier. After a
//         restart peakFrom is the entry minute, so the whole trade is
//         re-read once. If the M1 bars cannot be read the peak simply stays
//         where it was and the stops below are still managed.
bool UpdatePeak(int s, int lvl, bool isLong)
{
   if(InpPeakSinceEntry && peakFrom[s][lvl] > 0)
   {
      MqlRates m1x[];
      int nb = CopyRates(syms[s], PERIOD_M1, peakFrom[s][lvl], TimeCurrent(), m1x);
      if(nb > 0)
      {
         for(int b = 0; b < nb; b++)
         {
            if(isLong) { if(m1x[b].high > peakHigh[s][lvl]) peakHigh[s][lvl] = m1x[b].high; }
            else       { if(m1x[b].low  < peakLow[s][lvl])  peakLow[s][lvl]  = m1x[b].low;  }
         }
         peakFrom[s][lvl] = m1x[nb - 1].time;   // oldest first: the forming bar, re-read next minute
      }
      return true;
   }

   MqlRates tfx[];
   if(CopyRates(syms[s], tfs[lvl + 1], 0, 1, tfx) <= 0) return false;
   ArraySetAsSeries(tfx, true);
   if(isLong)
   {
      if(tfx[0].high > peakHigh[s][lvl]) peakHigh[s][lvl] = tfx[0].high;
   }
   else
   {
      if(tfx[0].low < peakLow[s][lvl]) peakLow[s][lvl] = tfx[0].low;
   }
   return true;
}

// May the stop of this position move to slNew? It must tighten by more
// than a point (and by minStep), and stay outside the broker's minimum
// distance from the side of the market that would trip it.
// #16: a short with no stop has POSITION_SL = 0, and "below the current
// stop" can then never be true — the live build gives such a short neither
// break-even nor the trail. With the fix, no stop means any valid stop
// tightens.
bool StopMayMove(bool isLong, double slNew, double slCur, double bid, double ask,
                 double point, double minDist, double minStep)
{
   if(isLong)
      return slNew > slCur + point && slNew < bid - minDist && slNew - slCur >= minStep;
   if(InpShortStopFix && slCur == 0.0)
      return slNew > ask + minDist;
   return slNew < slCur - point && slNew > ask + minDist && slCur - slNew >= minStep;
}

void ManageLevelProtection(int s, int lvl)
{
   int dir = state[s][lvl];
   if(dir == 0) return;

   double a[1];
   if(CopyBuffer(atr[s][lvl], 0, 1, 1, a) <= 0 || a[0] <= 0) return;
   double atrVal = a[0];

   bool isLong = (dir == 1);
   if(!UpdatePeak(s, lvl, isLong)) return;

   double point   = SymbolInfoDouble(syms[s], SYMBOL_POINT);
   double minDist = SymbolInfoInteger(syms[s], SYMBOL_TRADE_STOPS_LEVEL) * point;
   int    digits  = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);

   ulong ticket;
   if(!LevelTicket(s, lvl, ticket)) return;
   double slCur = PositionGetDouble(POSITION_SL);

   double bid = SymbolInfoDouble(syms[s], SYMBOL_BID);
   double ask = SymbolInfoDouble(syms[s], SYMBOL_ASK);

   // --- Disaster stop, self-healing (R3). Anchored at the ENTRY price so
   // the tail definition never drifts; attached only while no stop exists.
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
      else if(InpDisasterBreachClose && dSl > 0 &&
              (isLong ? bid <= dSl : ask >= dSl))
      {
         // #8: price is already through the disaster level, so no stop can
         // be placed there — the live build leaves the trade with no stop
         // at all. Take the loss the stop was meant to cap.
         ExitLevel(s, lvl, "disaster level breached, no SL");
         return;
      }
   }

   // --- Break-even: one-shot, tighter arming threshold on H1/H4.
   double beATR = (lvl >= 3) ? InpBEProfitH1H4 : InpBEProfitATR;
   if(!beMoved[s][lvl])
   {
      bool beArmed = isLong ? (bid >= entryPrice[s][lvl] + beATR * atrVal)
                            : (ask <= entryPrice[s][lvl] - beATR * atrVal);
      if(beArmed)
      {
         double slNew = isLong ? entryPrice[s][lvl] + InpBECoverPoints * point
                               : entryPrice[s][lvl] - InpBECoverPoints * point;
         slNew = NormalizeDouble(slNew, digits);

         if(StopMayMove(isLong, slNew, slCur, bid, ask, point, minDist, 0.0))
         {
            if(!trade.PositionModify(ticket, slNew, 0))
               Print(PCTime() + " | " + syms[s] + " " + tfName[lvl + 1] + " BE SL modify failed, retcode " +
                     IntegerToString(trade.ResultRetcode()));
            else
               beMoved[s][lvl] = true;
         }
      }
   }

   // --- Chandelier trail behind the peak. H1/H4 arm it at
   // InpTrailActivateATR x ATR, the lower tiers only on a spike
   // (InpSpikeLockATR x ATR). It only tightens, and skips steps under
   // 0.3 x ATR. The stop is re-read first: break-even may just have moved it.
   if(!LevelTicket(s, lvl, ticket)) return;
   slCur = PositionGetDouble(POSITION_SL);

   double armATR = (lvl >= 3) ? InpTrailActivateATR : InpSpikeLockATR;
   // #4: arm on the peak the trade actually reached, so a spike that came
   // and went inside the minute still arms the lock. The peak is a bid-side
   // price (bar high/low), so the short's threshold is checked on the bid low.
   bool armed;
   if(InpArmOnPeak)
      armed = isLong ? (peakHigh[s][lvl] >= entryPrice[s][lvl] + armATR * atrVal)
                     : (peakLow[s][lvl] > 0 && peakLow[s][lvl] <= entryPrice[s][lvl] - armATR * atrVal);
   else
      armed = isLong ? (bid >= entryPrice[s][lvl] + armATR * atrVal)
                     : (ask <= entryPrice[s][lvl] - armATR * atrVal);
   if(armed)
   {
      double slNew = isLong ? peakHigh[s][lvl] - InpTrailATR * atrVal
                            : peakLow[s][lvl] + InpTrailATR * atrVal;
      slNew = NormalizeDouble(slNew, digits);

      if(StopMayMove(isLong, slNew, slCur, bid, ask, point, minDist, 0.3 * atrVal))
      {
         if(!trade.PositionModify(ticket, slNew, 0))
            Print(PCTime() + " | " + syms[s] + " " + tfName[lvl + 1] + " trail SL modify failed, retcode " +
                  IntegerToString(trade.ResultRetcode()));
      }
   }
}

//==================================================================
// 10. STATE SYNC
// Rebuild what the EA believes from the positions on the account, so a
// restart mid-trade resumes the right tiers with the right references.
//==================================================================

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

// Called once per processed minute and at start-up. The position comment
// carries the tier ("Exp Buy M15"). For a tier the EA did not know about
// (a restart mid-trade) the entry and chandelier references are rebuilt:
//   #3 on : peakFrom = the entry minute, and ManageLevelProtection folds in
//           every M1 bar since then on its next pass;
//   #3 off: the live R4 rebuild from the level-TF bars since the open.
// A tier with no position has its memory cleared.
void SyncStateFromPositions()
{
   bool hasPos[MAX_SYMS][LEVELS];
   int  prevState[MAX_SYMS][LEVELS];             // what the EA believed before this sync
   for(int s = 0; s < symsCount; s++)
   {
      symBlockedUnknown[s] = false;              // R2: re-evaluated every sync
      for(int l = 0; l < LEVELS; l++)
      {
         prevState[s][l] = state[s][l];
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

         // R2: an unmatched comment on a magic position means the identity
         // is lost (broker rewrite, manual tampering) — block the symbol.
         int lvlMatch = LevelFromComment(comm);
         if(lvlMatch < 0)
         {
            symBlockedUnknown[s] = true;
            LogUnknownOnce(ticket, sym, comm);
            continue;
         }

         state[s][lvlMatch] = dir;
         hasPos[s][lvlMatch] = true;

         // EA (re)started mid-trade — rebuild the protection references.
         if(entryPrice[s][lvlMatch] == 0.0)
         {
            entryPrice[s][lvlMatch] = PositionGetDouble(POSITION_PRICE_OPEN);
            double hi = entryPrice[s][lvlMatch];
            double lo = entryPrice[s][lvlMatch];
            datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
            if(InpPeakSinceEntry)
            {
               // #3: M1 bars from the entry minute on — no pre-entry prices.
               peakFrom[s][lvlMatch] = (datetime)(((long)opened / 60) * 60);
            }
            else
            {
               MqlRates hist[];
               int nb = CopyRates(sym, tfs[lvlMatch + 1], opened, TimeCurrent(), hist);
               for(int b = 0; b < nb; b++)
               {
                  if(hist[b].high > hi) hi = hist[b].high;
                  if(hist[b].low  < lo) lo = hist[b].low;
               }
            }
            peakHigh[s][lvlMatch] = hi;
            peakLow[s][lvlMatch]  = lo;
         }
         break;
      }
   }

   // Tiers with no open position get their protection memory cleared
   for(int s = 0; s < symsCount; s++)
   {
      for(int l = 0; l < LEVELS; l++)
      {
         if(!hasPos[s][l])
         {
            // The EA still held this tier and nothing of ours closed it
            // (ExitLevel and SupersedeLower zero the state themselves), so a
            // broker-side stop did: BE, chandelier or disaster.
            if(prevState[s][l] != 0)
            {
               streakDirty = true;
               if(InpRealignAfterStop) needRealign[s][l] = prevState[s][l];   // #5
            }
            entryPrice[s][l]   = 0.0;
            peakHigh[s][l]     = 0.0;
            peakLow[s][l]      = 0.0;
            beMoved[s][l]      = false;
            peakFrom[s][l]     = 0;
            exitNotified[s][l] = false;
         }
      }
   }
}

//==================================================================
// 11. LIFECYCLE
// Init, deinit, and the once-a-minute loop.
//==================================================================

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
         entryPrice[s][l]   = 0.0;
         peakHigh[s][l]     = 0.0;
         peakLow[s][l]      = 0.0;
         beMoved[s][l]      = false;
         peakFrom[s][l]     = 0;
         needRealign[s][l]  = 0;
         exitNotified[s][l] = false;
         lastLogBar[s][l]   = 0;
         lastLogMsg[s][l]   = "";
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
   }

   dayKey = -1; weekKey = -1; equityHWM = 0.0;
   lossStreak = 0; lastLossTime = 0; streakDirty = true; guardPushed = "";

   trade.SetDeviationInPoints(Slippage);
   trade.SetExpertMagicNumber(MAGIC);
   SyncStateFromPositions();
   RefreshAccountGuards();
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

// Exits and stop management for every open tier of one symbol.
void ProcessExits(int s)
{
   bool flatNow = FridayFlatNow();
   // #6: while the spread is abnormal (rollover, news) the cloud touch is
   // ignored — a short exits on the ask and would otherwise be closed by
   // the spread alone. The broker-side stops still protect the trade.
   bool exitSpreadOK = (InpExitMaxSpread <= 0 ||
                        SymbolInfoInteger(syms[s], SYMBOL_SPREAD) <= InpExitMaxSpread);

   for(int l = 0; l < LEVELS; l++)
   {
      // Weekend guard: flat from InpFriFlatHour on Friday
      if(state[s][l] != 0 && flatNow)
         ExitLevel(s, l, "weekend flat");

      // Main exit: price touched the level TF's cloud edge
      if(state[s][l] != 0 && exitSpreadOK && InCloudTouch(s, l + 1, state[s][l]))
         ExitLevel(s, l, "kumo touch");

      // Rejection exit: a very strong rejection candle on the tier TF
      // against the trade (bearish kills a long, bullish kills a short)
      if(InpRejectionExit && state[s][l] != 0)
      {
         int rj = RejectionCandle(s, l + 1);
         if(rj != 0 && rj == -state[s][l])
            ExitLevel(s, l, "rejection");
      }

      // Profit protection: disaster stop, break-even, chandelier trail
      if(state[s][l] != 0) ManageLevelProtection(s, l);
   }
}

// Tier selection: scan H4 -> M5 and return the LARGEST free tier whose
// whole chain, cloud gate and bias agree and that can be sized. -1 = none.
int SelectTier(int s, int &dir, string &via, double &lots)
{
   for(int l = LEVELS - 1; l >= 0; l--)
   {
      // #1: a running tier blocks itself AND every smaller tier, so the
      // symbol really holds one position. Live: 'continue', which lets
      // M30/M15 open under a running H1/H4.
      if(state[s][l] != 0)
      {
         if(InpOnePosition) break;
         continue;
      }
      // M5 tier dropped (2026-09-23): no new M5 entries. An M5 position
      // already open keeps its exits and protection until it closes.
      if(l == 0 && !InpM5Tier) continue;

      int st = ChainAligned(s, l + 1);

      // #5: after a broker-side stop this tier must first fall out of
      // alignment on that side; until then it does not re-enter.
      if(needRealign[s][l] != 0)
      {
         if(st == needRealign[s][l]) continue;
         needRealign[s][l] = 0;
      }
      if(st == 0) continue;
      if(InpCloudBiasEnabled && !LevelCloudBiasOK(s, l, st)) continue;

      // Directional bias: H4, or the H1 stand-in for the lower tiers
      string v = "--";
      if(!EntryBiasOK(s, l, st, v)) continue;

      // H4 tier: D1 must carry the same bias (D1 in the cloud = no H4 trades)
      if(l == LEVELS - 1 && InpD1Filter && DailyAlign(s) != st) continue;

      // Sizing is part of selection: a tier that cannot be sized (#9), that
      // the minimum lot would oversize (#10) or that the open-risk cap has
      // no room for is skipped, and the scan walks down.
      string why = "";
      double lt  = RiskLots(s, l, st, why);
      if(lt <= 0)
      {
         LogOncePerBar(s, l, why);
         continue;
      }

      dir  = st;
      via  = v;
      lots = lt;
      return l;
   }
   return -1;
}

// Entry for one symbol: pick the tier, check the guards, close the smaller
// tiers into it, open it.
void ProcessEntry(int s)
{
   int    topDir  = 0;
   string topVia  = "--";
   double lots    = 0.0;
   int    topTier = SelectTier(s, topDir, topVia, lots);
   if(topTier < 0) return;

   // R2, the spread gate and the capital-protection guards: never ADD
   // exposure while one of them holds. Logged once per tier bar.
   string block = EntryBlockReason(s);
   if(block != "")
   {
      LogOncePerBar(s, topTier, block);
      return;
   }

   // Consolidation: only the largest tier runs. Smaller ones close first.
   bool cleared = SupersedeLower(s, topTier);
   if(InpSupersedeGuard && !cleared)
   {
      // #17 (review R1): the smaller tier is still open, so opening the
      // bigger one now would stack them. Wait for the close to go through.
      LogOncePerBar(s, topTier, "a superseded smaller tier could not be closed yet");
      return;
   }

   CapLotsToMargin(syms[s], (topDir == 1), lots);

   if(!OpenLevel(s, topTier, topDir, lots, topVia))
      Print(PCTime() + " | " + syms[s] + " " + tfName[topTier + 1] +
            " entry signal but order failed, retcode " + IntegerToString(trade.ResultRetcode()));
}

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

      // Position state and account guards: once per minute, on the first
      // symbol with a new bar
      if(!synced)
      {
         SyncStateFromPositions();
         RefreshAccountGuards();
         synced = true;
      }

      ProcessExits(s);
      ProcessEntry(s);
   }
}
//Fear God and Live
