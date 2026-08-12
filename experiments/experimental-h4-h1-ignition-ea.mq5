//+------------------------------------------------------------------+
//| Ichimoku H4-H1 Ignition EA (experimental)                        |
//| Concept: equivalence-aware multi-timeframe breakout alignment.   |
//|   H4  = trend gate: the full price+chikou breakout (classic       |
//|         alignment condition on the trend TF); optional looser     |
//|         bias modes via InpRequireH4Breakout/InpBiasMode           |
//|   H1  = pullback zone (price pulled back to the H1 cloud and/or   |
//|         tenkan; H1 Kijun = M30 cloud by the 26/52 bar law, so     |
//|         M30 is redundant and omitted)                             |
//|   M15 = ignition timing (micro-breakout above M15 tenkan/cloud    |
//|         with optional chikou confirm)                             |
//| Entry fires once per closed M15 bar when ALL of:                  |
//|   1. H4 breakout/bias agrees with the trade direction             |
//|   2. H1 price is pulled back to the zone (not extended)           |
//|   3. optional compression: |H4 Kijun - H1 Span B| < threshold     |
//|      (sister-level coincidence = pre-breakout energy)             |
//|   4. M15 ignition breakout (tenkan + cloud + momentum)            |
//|   5. freshness: bars since last H1 Kijun touch <= InpFreshness    |
//|      (the move must be young — the anti-"too late" gate)          |
//| Exit:  swing-scale machinery — ATR(H1) chandelier trail once      |
//|        profitable, spike profit lock (SL slams behind sudden      |
//|        impulse moves within a minute), H1 close crossing H1 kijun |
//|        as final fallback, or ATR(H1)-based protective stop loss.  |
//|        Exit management runs on every closed M1 bar; entries on    |
//|        closed M15 bars. BE30 off by default (its 30-min M1-scalper |
//|        window traps swing trades).                                |
//| Risk:  identical to the H4-M1 VPS build — equity-tiered ladder     |
//|        (GetEquityRisk) with fixed lots up to $8k and               |
//|        RiskBasedLots at InpHighEquityRiskPct above; caps by        |
//|        InpMaxRiskPct and free margin                               |
//| VPS: no Alert popups or equity alerts; exit management once per   |
//|        closed M1 bar, swing checks once per closed M15 bar         |
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

input group  "Risk Protection"
input bool   InpUseStopLoss       = true;   // Attach ATR-based stop loss to every entry
input int    InpATRPeriod         = 14;     // ATR period (H1)
input double InpATRMultiplier     = 3.0;    // SL distance = ATR * multiplier
input int    InpMaxSpreadPoints   = 60;     // Max spread in points to allow entry (0 = no limit)
input double InpHighEquityRiskPct = 1.0;    // % of equity risked per trade once equity > $8000
input int    InpReentryCooldownSec = 0;     // Min seconds after an exit before re-entering same symbol (0 = none)
input double InpMaxRiskPct         = 0.0;   // Cap total initial-stop risk per ladder as % of equity (0 = no cap)

//--- Trail mode: off, always on, or choppy-only (ADX regime filter)
enum ENUM_TRAIL_MODE { TRAIL_OFF = 0, TRAIL_ALWAYS = 1, TRAIL_CHOPPY = 2 };

input group  "Exit Management"
input ENUM_TRAIL_MODE InpTrailMode        = TRAIL_CHOPPY;  // 0=off, 1=always, 2=choppy-only (ADX)
input double          InpTrailATR         = 3.0;   // Trail distance = ATR(H1) * multiplier
input double          InpTrailActivateATR = 2.0;   // Arm the trail once profit >= ATR(H1) * multiplier
input int             InpADXPeriod        = 14;    // ADX period for choppy-market detection (H1)
input double          InpChopADXLevel     = 22.0;  // ADX below this = choppy -> trail on in auto mode

input group  "Break-Even (BE30) Management"
input bool   InpBE30Enabled        = false;  // Move SL to break even when profitable in time (off by default: M1-tuned window traps swing trades)
input int    InpBE30Minutes        = 30;     // Profit window after entry (minutes)
input double InpBE30ActivateATR    = 0.5;    // Min profit to arm BE (x ATR H1)
input int    InpBE30CoverPoints    = 15;     // Points beyond break even (covers spread)

input group  "Spike Profit Protection"
input bool   InpSpikeLockEnabled    = true;   // Slam SL to just behind sudden spike moves (checked every M1 bar)
input double InpSpikeATR            = 3.0;    // Spike = an M15 bar moved >= this x ATR(M15) in the trade direction
input double InpSpikeProfitATR      = 1.0;    // Min locked profit before the spike lock arms (x ATR H1)
input double InpSpikeBufferATR      = 0.5;    // Spike-lock distance behind the spike extreme (x ATR H1)

input group  "Ignition Entry"
input int    InpFreshnessBars      = 17;     // Max bars since last H1 Kijun touch for entry (young-move gate)
input double InpZoneToleranceATR   = 1.0;    // H1 pullback zone tolerance (x ATR H1)
input int    InpBiasMode           = 1;      // H4 bias (used when InpRequireH4Breakout=false): 0=price vs kijun+cloud, 1=kijun+tenkan structure, 2=kijun only
input bool   InpRequireH4Breakout  = true;   // Require the full H4 price+chikou breakout (classic alignment condition on the trend TF)
input int    InpZoneMode           = 1;      // H1 zone: 0=cloud pullback only, 1=cloud OR tenkan pullback
input bool   InpRequireCompression = false;  // Require |H4 Kijun - H1 Span B| < threshold (compression)
input double InpCompressionATR     = 0.35;   // Compression threshold (x ATR H1)
input bool   InpRequireChikou      = false;  // Require M15 chikou confirmation on the ignition bar

//--- Constants and Global Variables ---
#define MAX_SYMS  60
#define TF_COUNT  3
#define IDX_H1    1   // index of H1 in tfs[] — entry zone + freshness checks
#define IDX_M15   2   // index of M15 in tfs[] — ignition timing + exit checks
#define FRESH_LOOKBACK 60   // max bars scanned for the last H1 Kijun touch

ENUM_TIMEFRAMES tfs[TF_COUNT] = {
   PERIOD_H4, PERIOD_H1, PERIOD_M15
};

int      ich[MAX_SYMS][TF_COUNT];
int      atr[MAX_SYMS];     // ATR(H1) — SL distance, trail, BE, zone tolerance + compression (swing scale)
int      atrM15[MAX_SYMS];  // ATR(M15) — spike detection unit (single M15 bar ranges)
int      adx[MAX_SYMS];     // ADX(H1) handle for choppy-market regime detection
string   syms[MAX_SYMS];
int      symsCount = 0;
datetime lastM15bar[MAX_SYMS];
datetime lastM1bar[MAX_SYMS];   // exit-management cadence (spike peak lock-in)
datetime noReentryUntil[MAX_SYMS];
int      state[MAX_SYMS];   // 0=no position, 1=long, -1=short

double   entryPrice[MAX_SYMS];  // reference entry price per symbol (trail arming)
double   trailHigh[MAX_SYMS];   // highest high since entry (long chandelier reference)
double   trailLow[MAX_SYMS];    // lowest low since entry (short chandelier reference)

datetime entryTime[MAX_SYMS];   // entry time per symbol (BE30 profit window)
bool     beMoved[MAX_SYMS];     // BE30 stop already moved to break even (one-shot)

int MAGIC = 20260821;   // fresh number — distinct from all other builds

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
      state[s] = 0;
      lastM15bar[s] = 0;
      lastM1bar[s] = 0;
      noReentryUntil[s] = 0;
      entryTime[s] = 0;
      beMoved[s] = false;
      for(int t = 0; t < TF_COUNT; t++)
      {
         ich[s][t] = iIchimoku(syms[s], tfs[t], Tenkan, Kijun, SenkouB);
         if(ich[s][t] == INVALID_HANDLE) return(INIT_FAILED);
      }

      atr[s] = iATR(syms[s], PERIOD_H1, InpATRPeriod);
      if(atr[s] == INVALID_HANDLE) return(INIT_FAILED);

      atrM15[s] = INVALID_HANDLE;
      if(InpSpikeLockEnabled)
      {
         atrM15[s] = iATR(syms[s], PERIOD_M15, InpATRPeriod);
         if(atrM15[s] == INVALID_HANDLE) return(INIT_FAILED);
      }

      adx[s] = INVALID_HANDLE;
      if(InpTrailMode == TRAIL_CHOPPY)
      {
         adx[s] = iADX(syms[s], PERIOD_H1, InpADXPeriod);
         if(adx[s] == INVALID_HANDLE) return(INIT_FAILED);
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
      for(int t = 0; t < TF_COUNT; t++)
         if(ich[s][t] != INVALID_HANDLE) IndicatorRelease(ich[s][t]);
      if(atr[s] != INVALID_HANDLE) IndicatorRelease(atr[s]);
      if(atrM15[s] != INVALID_HANDLE) IndicatorRelease(atrM15[s]);
      if(adx[s] != INVALID_HANDLE) IndicatorRelease(adx[s]);
   }
}

//==============================================================
// Position State Sync (recover after restart)
//==============================================================

void SyncStateFromPositions()
{
   // Rebuild from scratch so positions closed by SL or manually free the
   // symbol for re-entry instead of leaving stale state behind.
   int prevState[MAX_SYMS];
   bool hasPos[MAX_SYMS];
   for(int s = 0; s < symsCount; s++) { prevState[s] = state[s]; state[s] = 0; hasPos[s] = false; }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      string sym   = PositionGetString(POSITION_SYMBOL);
      int    magic = (int)PositionGetInteger(POSITION_MAGIC);
      int    type  = (int)PositionGetInteger(POSITION_TYPE);
      int    dir   = (type == POSITION_TYPE_BUY) ? 1 : -1;

      if(magic != MAGIC) continue;

      for(int s = 0; s < symsCount; s++)
      {
         if(syms[s] == sym)
         {
            state[s] = dir;
            hasPos[s] = true;
            // EA (re)started mid-trade — rebuild the trail from the open price
            // and let it accumulate fresh extremes from here.
            if(entryPrice[s] == 0.0)
            {
               entryPrice[s] = PositionGetDouble(POSITION_PRICE_OPEN);
               trailHigh[s]  = entryPrice[s];
               trailLow[s]   = entryPrice[s];
            }
            // Restart mid-trade: restart the BE30 clock from the earliest
            // open position so the profit window keeps real entry semantics.
            if(entryTime[s] == 0)
               entryTime[s] = (datetime)PositionGetInteger(POSITION_TIME);
            break;
         }
      }
   }

   // Symbols with no open position get their trail memory cleared
   for(int s = 0; s < symsCount; s++)
   {
      if(!hasPos[s])
      {
         entryPrice[s] = 0.0;
         trailHigh[s]  = 0.0;
         trailLow[s]   = 0.0;
         entryTime[s]  = 0;
         beMoved[s]    = false;
      }
   }

   // A position that vanished since the last sync (SL hit, manual close) frees
   // the symbol; arm the optional re-entry cooldown so it can't flip instantly.
   for(int s = 0; s < symsCount; s++)
   {
      if(prevState[s] != 0 && state[s] == 0)
         noReentryUntil[s] = TimeCurrent() + InpReentryCooldownSec;
   }
}

//==============================================================
// Entry Engine — equivalence-aware roles per timeframe
//==============================================================

// H4 trend gate — the filter not the trigger, but it must be a REAL
// breakout. InpRequireH4Breakout = true (default): the full H4
// price+chikou breakout — price above/below tenkan, kijun and cloud
// AND the chikou span clear above/below price and levels at its
// plotted position 26 bars back (the classic alignment condition on
// the trend TF). = false: sticky bias only, per InpBiasMode:
//   0 = price vs kijun + cloud (strict), 1 = kijun + tenkan structure,
//   2 = kijun only (loosest — high-frequency variant for A/B tests).
int CheckH4Bias(int s)
{
   double tenkan[1], kijun[1], senA[1], senB[1];
   if(CopyBuffer(ich[s][0], 0, 1, 1, tenkan) <= 0) return 0;
   if(CopyBuffer(ich[s][0], 1, 1, 1, kijun)  <= 0) return 0;
   if(CopyBuffer(ich[s][0], 2, 1, 1, senA)   <= 0) return 0;
   if(CopyBuffer(ich[s][0], 3, 1, 1, senB)   <= 0) return 0;

   MqlRates rt[];
   if(CopyRates(syms[s], PERIOD_H4, 0, 1 + Kijun + 1, rt) <= 0) return 0;
   ArraySetAsSeries(rt, true);
   if(ArraySize(rt) <= 1 + Kijun) return 0;

   int sh = 1;   // last closed bar
   double closeP = rt[sh].close;
   double cHi = MathMax(senA[0], senB[0]);
   double cLo = MathMin(senA[0], senB[0]);

   if(InpRequireH4Breakout)
   {
      bool above = closeP > tenkan[0] && closeP > kijun[0] && closeP > cHi;
      bool below = closeP < tenkan[0] && closeP < kijun[0] && closeP < cLo;
      if(!above && !below) return 0;

      // tenkan, kijun, cloud at chikou's chart position
      int chShift = sh + Kijun;
      double tenkan_ch[1], kijun_ch[1], senA_ch[1], senB_ch[1];
      if(CopyBuffer(ich[s][0], 0, chShift, 1, tenkan_ch) <= 0) return 0;
      if(CopyBuffer(ich[s][0], 1, chShift, 1, kijun_ch)  <= 0) return 0;
      if(CopyBuffer(ich[s][0], 2, chShift, 1, senA_ch)   <= 0) return 0;
      if(CopyBuffer(ich[s][0], 3, chShift, 1, senB_ch)   <= 0) return 0;

      double cHiC = MathMax(senA_ch[0], senB_ch[0]);
      double cLoC = MathMin(senA_ch[0], senB_ch[0]);

      if(above && closeP > rt[chShift].high &&
         closeP > tenkan_ch[0] && closeP > kijun_ch[0] && closeP > cHiC) return  1;
      if(below && closeP < rt[chShift].low &&
         closeP < tenkan_ch[0] && closeP < kijun_ch[0] && closeP < cLoC) return -1;
      return 0;
   }

   if(InpBiasMode == 0)
   {
      if(closeP > kijun[0] && closeP > cHi) return  1;
      if(closeP < kijun[0] && closeP < cLo) return -1;
      return 0;
   }
   if(InpBiasMode == 1)
   {
      if(closeP > kijun[0] && tenkan[0] > kijun[0]) return  1;
      if(closeP < kijun[0] && tenkan[0] < kijun[0]) return -1;
      return 0;
   }
   if(closeP > kijun[0]) return  1;
   if(closeP < kijun[0]) return -1;
   return 0;
}

// H1 pullback zone: H1 trend intact (price on the right side of the H1
// Kijun) while price is close to a pullback target. InpZoneMode:
//   0 = cloud pullback only (price retraced into/near the H1 cloud)
//   1 = cloud OR tenkan pullback (default — also catches the shallow
//       pullbacks strong trends make to the H1 tenkan, which never
//       reach the cloud)
// A price far from both levels is an extended move — the "too late" case.
bool CheckH1Zone(int s, int dir)
{
   double tenkan[1], kijun[1], senA[1], senB[1];
   if(CopyBuffer(ich[s][IDX_H1], 0, 1, 1, tenkan) <= 0) return false;
   if(CopyBuffer(ich[s][IDX_H1], 1, 1, 1, kijun)  <= 0) return false;
   if(CopyBuffer(ich[s][IDX_H1], 2, 1, 1, senA)   <= 0) return false;
   if(CopyBuffer(ich[s][IDX_H1], 3, 1, 1, senB)   <= 0) return false;

   MqlRates rt[];
   if(CopyRates(syms[s], PERIOD_H1, 1, 1, rt) <= 0) return false;
   double closeP = rt[0].close;

   double cHi = MathMax(senA[0], senB[0]);
   double cLo = MathMin(senA[0], senB[0]);

   double tol = 0.0;
   if(atr[s] != INVALID_HANDLE)
   {
      double a[1];
      if(CopyBuffer(atr[s], 0, 1, 1, a) <= 0 || a[0] <= 0) return false;
      tol = InpZoneToleranceATR * a[0];
   }

   if(dir == 1)
   {
      if(closeP <= kijun[0]) return false;
      if(closeP <= cHi + tol) return true;
      if(InpZoneMode >= 1 && closeP <= tenkan[0] + tol) return true;
      return false;
   }
   if(dir == -1)
   {
      if(closeP >= kijun[0]) return false;
      if(closeP >= cLo - tol) return true;
      if(InpZoneMode >= 1 && closeP >= tenkan[0] - tol) return true;
      return false;
   }
   return false;
}

// Compression flag: the H4 Kijun and the H1 cloud's Span B sit at nearly
// the same level (|diff| < threshold x ATR H1). Sister-level coincidence —
// all midpoints converge, i.e. pre-breakout energy.
bool IsCompressed(int s)
{
   double k4[1], sb1[1];
   if(CopyBuffer(ich[s][0],       1, 1, 1, k4)  <= 0) return false;
   if(CopyBuffer(ich[s][IDX_H1],  3, 1, 1, sb1) <= 0) return false;

   if(atr[s] == INVALID_HANDLE) return false;
   double a[1];
   if(CopyBuffer(atr[s], 0, 1, 1, a) <= 0 || a[0] <= 0) return false;

   return MathAbs(k4[0] - sb1[0]) < InpCompressionATR * a[0];
}

// M15 ignition: micro-breakout in the trade direction — close through the
// M15 tenkan AND the M15 cloud, with momentum (close above prior closed
// bar). Optional chikou confirmation: the ignition bar's close is also
// clear above/below price and levels at its plotted position (26 bars back).
bool CheckM15Ignition(int s, int dir)
{
   int sh      = 1;
   int chShift = sh + Kijun;

   MqlRates rt[];
   if(CopyRates(syms[s], PERIOD_M15, 0, chShift + 1, rt) <= 0) return false;
   ArraySetAsSeries(rt, true);
   if(ArraySize(rt) <= chShift) return false;

   double tenkan[1], senA[1], senB[1];
   if(CopyBuffer(ich[s][IDX_M15], 0, sh, 1, tenkan) <= 0) return false;
   if(CopyBuffer(ich[s][IDX_M15], 2, sh, 1, senA)   <= 0) return false;
   if(CopyBuffer(ich[s][IDX_M15], 3, sh, 1, senB)   <= 0) return false;

   double closeP = rt[sh].close;
   double cHi    = MathMax(senA[0], senB[0]);
   double cLo    = MathMin(senA[0], senB[0]);

   bool above = closeP > tenkan[0] && closeP > cHi && closeP > rt[sh + 1].close;
   bool below = closeP < tenkan[0] && closeP < cLo && closeP < rt[sh + 1].close;
   if(!above && !below) return false;

   if(InpRequireChikou)
   {
      double tenkan_ch[1], kijun_ch[1], senA_ch[1], senB_ch[1];
      if(CopyBuffer(ich[s][IDX_M15], 0, chShift, 1, tenkan_ch) <= 0) return false;
      if(CopyBuffer(ich[s][IDX_M15], 1, chShift, 1, kijun_ch)  <= 0) return false;
      if(CopyBuffer(ich[s][IDX_M15], 2, chShift, 1, senA_ch)   <= 0) return false;
      if(CopyBuffer(ich[s][IDX_M15], 3, chShift, 1, senB_ch)   <= 0) return false;

      double cHiC = MathMax(senA_ch[0], senB_ch[0]);
      double cLoC = MathMin(senA_ch[0], senB_ch[0]);

      if(above && closeP > rt[chShift].high &&
         closeP > tenkan_ch[0] && closeP > kijun_ch[0] && closeP > cHiC) return true;
      if(below && closeP < rt[chShift].low &&
         closeP < tenkan_ch[0] && closeP < kijun_ch[0] && closeP < cLoC) return true;
      return false;
   }

   return (dir == 1) ? above : below;
}

// Bars since the last H1 Kijun touch (long: a low <= Kijun; short: a high
// >= Kijun). Count starts at the last closed bar (0 = touched on the
// current bar). Capped at FRESH_LOOKBACK.
int BarsSinceKijunTouch(int s, int dir)
{
   double kij[];
   MqlRates rt[];
   if(CopyBuffer(ich[s][IDX_H1], 1, 1, FRESH_LOOKBACK, kij) <= 0) return FRESH_LOOKBACK;
   if(CopyRates(syms[s], PERIOD_H1, 1, FRESH_LOOKBACK, rt) <= 0) return FRESH_LOOKBACK;
   ArraySetAsSeries(kij, true);
   ArraySetAsSeries(rt, true);

   int n = MathMin(ArraySize(kij), ArraySize(rt));
   for(int i = 0; i < n; i++)
   {
      if(dir ==  1 && rt[i].low  <= kij[i]) return i;
      if(dir == -1 && rt[i].high >= kij[i]) return i;
   }
   return FRESH_LOOKBACK;
}

//==============================================================
// Entry Check: H4 bias + H1 zone + compression + M15 ignition
// + freshness all agree. Returns 1 (bullish), -1 (bearish), 0 (none)
//==============================================================

int CheckIgnitionEntry(int s)
{
   int dir = CheckH4Bias(s);
   if(dir == 0) return 0;

   if(!CheckH1Zone(s, dir)) return 0;
   if(InpRequireCompression && !IsCompressed(s)) return 0;
   if(!CheckM15Ignition(s, dir)) return 0;

   // Mature-move gate: the H1 move must be young — the last Kijun touch
   // must be within InpFreshnessBars bars, otherwise the move is already
   // developed and the breakout is late.
   if(BarsSinceKijunTouch(s, dir) > InpFreshnessBars) return 0;

   return dir;
}

//==============================================================
// Exit Check: H1 price closed on wrong side of H1 kijun
// (swing-scale fallback — the M15 kijun exit of the M1 scalper
// builds stops out normal swing pullbacks)
//==============================================================

bool CheckH1Exit(int s, int dir)
{
   double kij[1];
   if(CopyBuffer(ich[s][IDX_H1], 1, 1, 1, kij) <= 0) return false;

   MqlRates rt[];
   if(CopyRates(syms[s], PERIOD_H1, 1, 1, rt) <= 0) return false;
   double closeP = rt[0].close;

   if(dir ==  1 && closeP < kij[0]) return true;
   if(dir == -1 && closeP > kij[0]) return true;
   return false;
}

//==============================================================
// Choppy-market detection: ADX(H1) below InpChopADXLevel means no
// trend, so the trail is allowed. An unready/unknown ADX value is
// treated as choppy (trail on) to match the always-on default.
//==============================================================

bool IsChoppy(int s)
{
   double d[1];
   if(CopyBuffer(adx[s], 0, 1, 1, d) <= 0 || d[0] <= 0) return true;
   return d[0] < InpChopADXLevel;
}

//==============================================================
// Exit Trail: ATR chandelier stop once the trade is in profit.
// The reference point is the extreme (high/low) of the M15 bar
// that is still forming, so a peak is locked in before it
// retraces; the distance and arm threshold use ATR(H1) (swing
// scale). Re-evaluated on every new M15 bar; only ever
// tightens and never sits inside the broker minimum stop.
//==============================================================

void ManageTrail(int s)
{
   if(state[s] == 0 || InpTrailMode == TRAIL_OFF || !InpUseStopLoss) return;
   if(InpTrailMode == TRAIL_CHOPPY && !IsChoppy(s)) return;

   double atrVal;
   if(atr[s] == INVALID_HANDLE) return;
   double a[1];
   if(CopyBuffer(atr[s], 0, 1, 1, a) <= 0 || a[0] <= 0) return;
   atrVal = a[0];

   MqlRates m15[];
   if(CopyRates(syms[s], PERIOD_M15, 0, 1, m15) <= 0) return;
   ArraySetAsSeries(m15, true);

   bool isLong = (state[s] == 1);
   if(isLong)
   {
      if(m15[0].high > trailHigh[s]) trailHigh[s] = m15[0].high;
   }
   else
   {
      if(m15[0].low < trailLow[s]) trailLow[s] = m15[0].low;
   }

   double point   = SymbolInfoDouble(syms[s], SYMBOL_POINT);
   double minDist = SymbolInfoInteger(syms[s], SYMBOL_TRADE_STOPS_LEVEL) * point;
   int    digits  = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);

   // Not profitable enough yet to arm the trail
   if(isLong && SymbolInfoDouble(syms[s], SYMBOL_BID) < entryPrice[s] + InpTrailActivateATR * atrVal) return;
   if(!isLong && SymbolInfoDouble(syms[s], SYMBOL_ASK) > entryPrice[s] - InpTrailActivateATR * atrVal) return;

   double price = isLong ? SymbolInfoDouble(syms[s], SYMBOL_BID)
                         : SymbolInfoDouble(syms[s], SYMBOL_ASK);
   double slNew = isLong ? trailHigh[s] - InpTrailATR * atrVal
                         : trailLow[s] + InpTrailATR * atrVal;
   slNew = NormalizeDouble(slNew, digits);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != syms[s]) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MAGIC) continue;

      double slCur = PositionGetDouble(POSITION_SL);

      // Only ever tighten, keep out of the broker's minimum stop distance,
      // and skip microscopic improvements (0.3x ATR) to cut request volume.
      if(isLong && slNew > slCur + point && slNew < price - minDist &&
         slNew - slCur >= 0.3 * atrVal)
      {
         if(!trade.PositionModify(ticket, slNew, 0))
            Print(PCTime() + " | " + syms[s] + " trail SL modify failed, retcode " + IntegerToString(trade.ResultRetcode()));
      }
      if(!isLong && slNew < slCur - point && slNew > price + minDist &&
         slCur - slNew >= 0.3 * atrVal)
      {
         if(!trade.PositionModify(ticket, slNew, 0))
            Print(PCTime() + " | " + syms[s] + " trail SL modify failed, retcode " + IntegerToString(trade.ResultRetcode()));
      }
   }
}

//==============================================================
// Spike Profit Protection: checked on every new M1 bar. When an M15
// bar (forming or last closed) has moved InpSpikeATR x ATR(M15) in
// the trade direction while the trade is already locked in
// InpSpikeProfitATR x ATR(H1) of profit, the stop is slammed up to
// just behind the spike extreme (InpSpikeBufferATR x ATR(H1)) — the
// sudden peak is banked before the reversal that typically follows a
// spike. Tighten-only, respects the broker minimum stop, and never
// lowers an existing stop.
//==============================================================

void ManageSpikeLock(int s)
{
   if(state[s] == 0 || !InpSpikeLockEnabled || !InpUseStopLoss) return;
   if(atr[s] == INVALID_HANDLE || atrM15[s] == INVALID_HANDLE) return;

   double a1[1], a15[1];
   if(CopyBuffer(atr[s], 0, 1, 1, a1) <= 0 || a1[0] <= 0) return;
   if(CopyBuffer(atrM15[s], 0, 1, 1, a15) <= 0 || a15[0] <= 0) return;
   double atrH1v = a1[0];

   bool isLong = (state[s] == 1);
   double bid  = SymbolInfoDouble(syms[s], SYMBOL_BID);
   double ask  = SymbolInfoDouble(syms[s], SYMBOL_ASK);

   // Must already be locked in real profit before the spike lock arms
   if(isLong && bid < entryPrice[s] + InpSpikeProfitATR * atrH1v) return;
   if(!isLong && ask > entryPrice[s] - InpSpikeProfitATR * atrH1v) return;

   MqlRates m15[];
   if(CopyRates(syms[s], PERIOD_M15, 0, 2, m15) <= 0) return;
   ArraySetAsSeries(m15, true);

   double spikeExtreme = isLong ? 0.0 : DBL_MAX;
   bool spiked = false;
   for(int i = 0; i < 2; i++)   // forming bar + last closed bar
   {
      double range = m15[i].high - m15[i].low;
      if(range < InpSpikeATR * a15[0]) continue;
      if(isLong  && m15[i].high > spikeExtreme) spikeExtreme = m15[i].high;
      if(!isLong && m15[i].low  < spikeExtreme) spikeExtreme = m15[i].low;
      spiked = true;
   }
   if(!spiked) return;

   double point   = SymbolInfoDouble(syms[s], SYMBOL_POINT);
   double minDist = SymbolInfoInteger(syms[s], SYMBOL_TRADE_STOPS_LEVEL) * point;
   int    digits  = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);

   double price = isLong ? bid : ask;
   double slNew = isLong ? spikeExtreme - InpSpikeBufferATR * atrH1v
                         : spikeExtreme + InpSpikeBufferATR * atrH1v;
   slNew = NormalizeDouble(slNew, digits);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != syms[s]) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MAGIC) continue;

      double slCur = PositionGetDouble(POSITION_SL);

      if(isLong && slNew > slCur + point && slNew < price - minDist)
      {
         if(!trade.PositionModify(ticket, slNew, 0))
            Print(PCTime() + " | " + syms[s] + " spike-lock SL modify failed, retcode " + IntegerToString(trade.ResultRetcode()));
      }
      if(!isLong && slNew < slCur - point && slNew > price + minDist)
      {
         if(!trade.PositionModify(ticket, slNew, 0))
            Print(PCTime() + " | " + syms[s] + " spike-lock SL modify failed, retcode " + IntegerToString(trade.ResultRetcode()));
      }
   }
}

//==============================================================
// Break-Even Management (BE30): off by default — its 30-minute
// window was tuned for M1-cadence scalping and traps swing
// trades on noise. If enabled: when the trade reaches a
// profitable position within InpBE30Minutes of entry, the stop
// loss moves up to break even plus a few points to cover the
// spread. One-shot per trade (beMoved); the chandelier trail may
// tighten further afterwards but never lowers the stop back down.
//==============================================================

double AvgOpenPrice(int s)
{
   double sum = 0.0, vol = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != syms[s]) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MAGIC) continue;
      sum += PositionGetDouble(POSITION_PRICE_OPEN) * PositionGetDouble(POSITION_VOLUME);
      vol += PositionGetDouble(POSITION_VOLUME);
   }
   return (vol > 0) ? sum / vol : 0.0;
}

void ManageBE(int s)
{
   if(state[s] == 0 || !InpBE30Enabled) return;
   if(entryTime[s] == 0 || beMoved[s]) return;

   // The profit window: once InpBE30Minutes have passed without the trade
   // turning profitable, the stop stays where it is for this trade.
   if(TimeCurrent() - entryTime[s] > InpBE30Minutes * 60) return;

   double avg = AvgOpenPrice(s);
   if(avg <= 0) return;

   if(atr[s] == INVALID_HANDLE) return;
   double a[1];
   if(CopyBuffer(atr[s], 0, 1, 1, a) <= 0 || a[0] <= 0) return;
   double atrVal = a[0];

   bool   isLong = (state[s] == 1);
   double bid    = SymbolInfoDouble(syms[s], SYMBOL_BID);
   double ask    = SymbolInfoDouble(syms[s], SYMBOL_ASK);

   // Not yet profitable enough to arm the break-even move
   if(isLong && bid < avg + InpBE30ActivateATR * atrVal) return;
   if(!isLong && ask > avg - InpBE30ActivateATR * atrVal) return;

   double point   = SymbolInfoDouble(syms[s], SYMBOL_POINT);
   double minDist = SymbolInfoInteger(syms[s], SYMBOL_TRADE_STOPS_LEVEL) * point;
   int    digits  = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);

   // Break even plus a few points to cover the spread
   double slNew = isLong ? avg + InpBE30CoverPoints * point
                         : avg - InpBE30CoverPoints * point;
   slNew = NormalizeDouble(slNew, digits);

   double price = isLong ? bid : ask;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != syms[s]) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MAGIC) continue;

      double slCur = PositionGetDouble(POSITION_SL);

      // Only ever tighten, and keep out of the broker's minimum stop distance
      if(isLong && slNew > slCur + point && slNew < price - minDist)
      {
         if(!trade.PositionModify(ticket, slNew, 0))
            Print(PCTime() + " | " + syms[s] + " BE SL modify failed, retcode " + IntegerToString(trade.ResultRetcode()));
         else
            beMoved[s] = true;
      }
      if(!isLong && slNew < slCur - point && slNew > price + minDist)
      {
         if(!trade.PositionModify(ticket, slNew, 0))
            Print(PCTime() + " | " + syms[s] + " BE SL modify failed, retcode " + IntegerToString(trade.ResultRetcode()));
         else
            beMoved[s] = true;
      }
   }
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

//==============================================================
// Risk Management (identical to the H4-M1 VPS build)
//==============================================================

// Lot size that risks InpHighEquityRiskPct% of equity, split evenly across
// 'count' concurrent orders, if the ATR stop loss is hit on all of them.
// Falls back to a conservative fixed lot when the stop distance or the
// symbol's tick value/size aren't available (e.g. InpUseStopLoss = false).
double RiskBasedLots(string sym, double eq, double stopDist, int count)
{
   double fallback = 0.10;
   if(stopDist <= 0 || count <= 0) return fallback;

   double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0 || tickSize <= 0) return fallback;

   double moneyPerLot = (stopDist / tickSize) * tickValue;
   if(moneyPerLot <= 0) return fallback;

   double riskMoney = eq * (InpHighEquityRiskPct / 100.0) / count;
   double lots      = riskMoney / moneyPerLot;

   double lotStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double lotMin  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double lotMax  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   if(lotStep > 0) lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(lotMin, MathMin(lotMax, lots));

   return (lots > 0) ? lots : fallback;
}

void GetEquityRisk(string sym, double stopDist, int &count, double &lots)
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq <= 30)        { count = 4;  lots = 0.10; }
   else if(eq <= 50)   { count = 4;  lots = 0.10; }
   else if(eq <= 70)   { count = 8;  lots = 0.10; }
   else if(eq <= 100)  { count = 8;  lots = 0.10; }
   else if(eq <= 130)  { count = 12;  lots = 0.10; }
   else if(eq <= 150)  { count = 16;  lots = 0.10; }
   else if(eq <= 170)  { count = 20; lots = 0.10; }
   else if(eq <= 200)  { count = 12;  lots = 0.20; }
   else if(eq <= 300)  { count = 8;  lots = 0.30; }
   else if(eq <= 400)  { count = 12;  lots = 0.30; }
   else if(eq <= 500)  { count = 12;  lots = 0.30; }
   else if(eq <= 600)  { count = 16;  lots = 0.30; }
   else if(eq <= 1000) { count = 8;  lots = 0.50; }
   else if(eq <= 3000) { count = 8;  lots = 0.30; }
   else if(eq <= 5000) { count = 8;  lots = 0.20; }
   else if(eq <= 8000) { count = 8;  lots = 0.10; }
   else                { count = 4;  lots = RiskBasedLots(sym, eq, stopDist, count); }
}

// Scale the ladder down so the initial stop on all orders risks at most
// InpMaxRiskPct% of equity. count never drops below 1.
void CapToRisk(string sym, double dist, int &count, double &lots)
{
   if(count <= 0 || lots <= 0 || dist <= 0 || InpMaxRiskPct <= 0) return;
   double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0 || tickSize <= 0) return;

   double lossPerOrder = (dist / tickSize) * tickValue * lots;
   if(lossPerOrder <= 0) return;

   double budget = AccountInfoDouble(ACCOUNT_EQUITY) * (InpMaxRiskPct / 100.0);
   int maxByRisk = (int)MathFloor(budget / lossPerOrder);
   if(maxByRisk < 1) maxByRisk = 1;
   if(count > maxByRisk) count = maxByRisk;
}

// Scale the ladder down to the free margin so the orders fill fully
// instead of silently breaking mid-way. count never drops below 1.
void CapToMargin(string sym, bool isBuy, int &count, double &lots)
{
   if(count <= 0 || lots <= 0) return;
   double price = isBuy ? SymbolInfoDouble(sym, SYMBOL_ASK)
                        : SymbolInfoDouble(sym, SYMBOL_BID);
   double marginOne = 0.0;
   if(!OrderCalcMargin(isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, sym, lots, price, marginOne))
      return;
   if(marginOne <= 0) return;
   int maxByMargin = (int)MathFloor(AccountInfoDouble(ACCOUNT_MARGIN_FREE) / marginOne);
   if(maxByMargin < 1) maxByMargin = 1;
   if(count > maxByMargin) count = maxByMargin;
}

//==============================================================
// Trading Functions
//==============================================================

bool SpreadOK(string sym)
{
   if(InpMaxSpreadPoints <= 0) return true;
   return SymbolInfoInteger(sym, SYMBOL_SPREAD) <= InpMaxSpreadPoints;
}

// ATR(H1) * multiplier, widened to the broker's minimum stop distance if
// needed. Returns false when the ATR value is unavailable so the caller
// skips the entry instead of trading unprotected.
bool GetStopDistance(int s, double &dist)
{
   dist = 0.0;
   double a[1];
   if(CopyBuffer(atr[s], 0, 1, 1, a) <= 0 || a[0] <= 0) return false;

   dist = a[0] * InpATRMultiplier;
   double point   = SymbolInfoDouble(syms[s], SYMBOL_POINT);
   double minDist = SymbolInfoInteger(syms[s], SYMBOL_TRADE_STOPS_LEVEL) * point;
   if(dist < minDist) dist = minDist;
   return true;
}

double BuildStopLoss(int s, bool isBuy, double price, double dist)
{
   int digits = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);
   return NormalizeDouble(isBuy ? price - dist : price + dist, digits);
}

int OpenPositions(int s, bool isBuy, double dist, int count, double lots, double &firstFill)
{
   string sym = syms[s];

   int filled = 0;
   firstFill = 0.0;
   for(int i = 0; i < count; i++)
   {
      double price = isBuy ? SymbolInfoDouble(sym, SYMBOL_ASK)
                           : SymbolInfoDouble(sym, SYMBOL_BID);
      double sl = InpUseStopLoss ? BuildStopLoss(s, isBuy, price, dist) : 0.0;

      bool ok = isBuy ? trade.Buy(lots,  sym, price, sl, 0, "Buy Ignition")
                      : trade.Sell(lots, sym, price, sl, 0, "Sell Ignition");
      if(!ok) break;   // out of margin or rejected — don't hammer the server
      if(firstFill == 0.0) firstFill = price;
      filled++;
   }
   return filled;
}

// Close all positions for the symbol; returns true only when none remain
// open, so a failed close (requote, halt) is retried instead of freeing
// the symbol for a fresh entry.
bool ClosePositions(string sym)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) == sym &&
         (int)PositionGetInteger(POSITION_MAGIC) == MAGIC)
      {
         if(!trade.PositionClose(ticket))
            Print(PCTime() + " | " + sym + " close failed, retcode " + IntegerToString(trade.ResultRetcode()));
      }
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) == sym &&
         (int)PositionGetInteger(POSITION_MAGIC) == MAGIC) return false;
   }
   return true;
}

//==============================================================
// Main Loop
//==============================================================

void OnTick()
{
   for(int s = 0; s < symsCount; s++)
   {
      // Fast cadence: exit management (trail, spike lock, BE) runs on every
      // new closed M1 bar so a sudden spike's peak is banked within a
      // minute instead of up to 15.
      MqlRates m1[];
      if(CopyRates(syms[s], PERIOD_M1, 0, 2, m1) < 2) continue;
      ArraySetAsSeries(m1, true);
      if(m1[1].time == lastM1bar[s]) continue;
      lastM1bar[s] = m1[1].time;

      // Sync position state once per new M1 bar
      SyncStateFromPositions();

      // Exit management: chandelier trail + spike lock + BE on each new M1 bar
      if(state[s] != 0) ManageTrail(s);
      if(state[s] != 0) ManageSpikeLock(s);
      if(state[s] != 0) ManageBE(s);

      // Swing checks: entry and the H1 kijun fallback exit only on new M15 bars
      MqlRates m15[];
      if(CopyRates(syms[s], PERIOD_M15, 0, 2, m15) < 2) continue;
      ArraySetAsSeries(m15, true);
      if(m15[1].time == lastM15bar[s]) continue;
      lastM15bar[s] = m15[1].time;

      // Exit check: close all when H1 closes against direction across H1 kijun
      if(state[s] != 0 && CheckH1Exit(s, state[s]))
      {
         string side = (state[s] == 1) ? "Long" : "Short";
         string msg  = PCTime() + " | Close " + syms[s] + " " + side + " (H1 kijun crossed)";
         Print(msg); SendNotification(msg);

         if(ClosePositions(syms[s]))
         {
            state[s] = 0;
            noReentryUntil[s] = TimeCurrent() + InpReentryCooldownSec;
         }
         else
            Print(PCTime() + " | " + syms[s] + " exit signal but positions still open — will retry");
      }

      // Entry check: H4 bias + H1 zone + compression + M15 ignition +
      // freshness must all agree, spread must be sane
      if(state[s] == 0 && TimeCurrent() >= noReentryUntil[s] && SpreadOK(syms[s]))
      {
         int st = CheckIgnitionEntry(s);
         if(st != 0)
         {
            bool   isBuy = (st == 1);
            double dist  = 0.0;
            if(InpUseStopLoss && !GetStopDistance(s, dist)) continue;   // ATR unavailable — skip entry

            int count; double lots;
            GetEquityRisk(syms[s], dist, count, lots);
            CapToRisk(syms[s], dist, count, lots);
            CapToMargin(syms[s], isBuy, count, lots);

            // Track state if any order filled — keeps exit logic and re-entry
            // guard correct even when only some of the orders go through.
            // Alert reports the actual fill count, not the requested count.
            double firstFill = 0.0;
            int filled = OpenPositions(s, isBuy, dist, count, lots, firstFill);
            if(filled > 0)
            {
               state[s] = st;
               entryPrice[s] = firstFill;   // chandelier trail reference
               trailHigh[s]  = firstFill;
               trailLow[s]   = firstFill;
               entryTime[s]  = TimeCurrent();   // start the BE30 profit window
               beMoved[s]    = false;
               string action = isBuy ? "Buy" : "Sell";
               string msg = PCTime() + " | " + action + " " + syms[s] +
                            " x" + IntegerToString(filled) +
                            " @ " + DoubleToString(lots, 2) + " (H4-H1 Ignition)";
               Print(msg); SendNotification(msg);
            }
            else
               Print(PCTime() + " | " + syms[s] + " entry signal but no order filled");
         }
      }
   }
}
//This work is my worship unto GOD
