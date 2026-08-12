//+------------------------------------------------------------------+
//| Ichimoku H4-H1 Ignition EA (experimental)                        |
//| Concept: equivalence-aware multi-timeframe breakout alignment.   |
//|   H4  = trend bias filter (price vs Kijun + cloud side only —    |
//|         no chikou, deliberately sticky)                          |
//|   H1  = pullback zone (price retraced into/near the H1 cloud;    |
//|         H1 Kijun = M30 cloud by the 26/52 bar law, so M30 is     |
//|         redundant and omitted)                                   |
//|   M15 = ignition timing (micro-breakout above M15 tenkan/cloud   |
//|         with optional chikou confirm — the only chikou in the    |
//|         engine, so it is cheap and rarely late)                  |
//| Entry fires once per closed M15 bar when ALL of:                 |
//|   1. H4 bias agrees with the trade direction                     |
//|   2. H1 price is pulled back to the cloud zone (not extended)    |
//|   3. optional compression: |H4 Kijun - H1 Span B| < threshold    |
//|      (the sister-level coincidence = pre-breakout energy)        |
//|   4. M15 ignition breakout (tenkan + cloud + momentum)           |
//|   5. freshness: bars since last H1 Kijun touch <= InpFreshness   |
//|      (the move must be young — the anti-"too late" gate)         |
//| Exit:  M15 chandelier trail (locks in the peak) once profitable, |
//|        M15 close crossing M15 kijun as final fallback, or ATR-   |
//|        based protective stop loss (all verbatim from the H4-M1   |
//|        VPS build)                                                |
//| Risk:  identical ladder/caps/margin logic as the H4-M1 VPS build |
//|        (equity tiers + InpMaxRiskPct cap + free-margin cap)      |
//| VPS: no Alert popups or equity alerts; all logic runs only on    |
//|        closed M15 bars (once per 15 min) to cut CPU usage        |
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
input int    InpATRPeriod         = 14;     // ATR period (M15)
input double InpATRMultiplier     = 3.0;    // SL distance = ATR * multiplier
input int    InpMaxSpreadPoints   = 60;     // Max spread in points to allow entry (0 = no limit)
input double InpHighEquityRiskPct = 1.0;    // % of equity risked per trade once equity > $8000
input int    InpReentryCooldownSec = 0;     // Min seconds after an exit before re-entering same symbol (0 = none)
input double InpMaxRiskPct         = 0.0;   // Cap total initial-stop risk per ladder as % of equity (0 = no cap)

//--- Trail mode: off, always on, or choppy-only (ADX regime filter)
enum ENUM_TRAIL_MODE { TRAIL_OFF = 0, TRAIL_ALWAYS = 1, TRAIL_CHOPPY = 2 };

input group  "Exit Management"
input ENUM_TRAIL_MODE InpTrailMode        = TRAIL_CHOPPY;  // 0=off, 1=always, 2=choppy-only (ADX)
input double          InpTrailATR         = 2.0;   // Trail distance = ATR(M15) * multiplier
input double          InpTrailActivateATR = 1.0;   // Arm the trail once profit >= ATR(M15) * multiplier
input int             InpADXPeriod        = 14;    // ADX period for choppy-market detection (M15)
input double          InpChopADXLevel     = 22.0;  // ADX below this = choppy -> trail on in auto mode

input group  "Break-Even (BE30) Management"
input bool   InpBE30Enabled        = true;   // Move SL to break even when profitable in time
input int    InpBE30Minutes        = 30;     // Profit window after entry (minutes)
input double InpBE30ActivateATR    = 0.5;    // Min profit to arm BE (x ATR M15)
input int    InpBE30CoverPoints    = 15;     // Points beyond break even (covers spread)

input group  "Ignition Entry"
input int    InpFreshnessBars      = 9;      // Max bars since last H1 Kijun touch for entry (young-move gate)
input double InpZoneToleranceATR   = 0.5;    // H1 pullback zone tolerance (x ATR H1)
input bool   InpRequireCompression = true;   // Require |H4 Kijun - H1 Span B| < threshold (compression)
input double InpCompressionATR     = 0.15;   // Compression threshold (x ATR H1)
input bool   InpRequireChikou      = true;   // Require M15 chikou confirmation on the ignition bar

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
int      atr[MAX_SYMS];     // ATR(M15) — VPS risk, trail and BE distances
int      atrH1[MAX_SYMS];   // ATR(H1) — entry zone tolerance + compression threshold
int      adx[MAX_SYMS];     // ADX(M15) handle for choppy-market regime detection
string   syms[MAX_SYMS];
int      symsCount = 0;
datetime lastM15bar[MAX_SYMS];
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
      noReentryUntil[s] = 0;
      entryTime[s] = 0;
      beMoved[s] = false;
      for(int t = 0; t < TF_COUNT; t++)
      {
         ich[s][t] = iIchimoku(syms[s], tfs[t], Tenkan, Kijun, SenkouB);
         if(ich[s][t] == INVALID_HANDLE) return(INIT_FAILED);
      }

      atr[s] = INVALID_HANDLE;
      if(InpUseStopLoss)
      {
         atr[s] = iATR(syms[s], PERIOD_M15, InpATRPeriod);
         if(atr[s] == INVALID_HANDLE) return(INIT_FAILED);
      }

      atrH1[s] = INVALID_HANDLE;
      if(InpRequireCompression || InpZoneToleranceATR > 0)
      {
         atrH1[s] = iATR(syms[s], PERIOD_H1, InpATRPeriod);
         if(atrH1[s] == INVALID_HANDLE) return(INIT_FAILED);
      }

      adx[s] = INVALID_HANDLE;
      if(InpTrailMode == TRAIL_CHOPPY)
      {
         adx[s] = iADX(syms[s], PERIOD_M15, InpADXPeriod);
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
      if(atrH1[s] != INVALID_HANDLE) IndicatorRelease(atrH1[s]);
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

// H4 trend bias: price vs Kijun and cloud side only (no chikou —
// deliberately sticky, this is the filter not the trigger).
int CheckH4Bias(int s)
{
   double kijun[1], senA[1], senB[1];
   if(CopyBuffer(ich[s][0], 1, 1, 1, kijun) <= 0) return 0;
   if(CopyBuffer(ich[s][0], 2, 1, 1, senA)  <= 0) return 0;
   if(CopyBuffer(ich[s][0], 3, 1, 1, senB)  <= 0) return 0;

   MqlRates rt[];
   if(CopyRates(syms[s], PERIOD_H4, 1, 1, rt) <= 0) return 0;
   double closeP = rt[0].close;

   double cHi = MathMax(senA[0], senB[0]);
   double cLo = MathMin(senA[0], senB[0]);

   if(closeP > kijun[0] && closeP > cHi) return  1;
   if(closeP < kijun[0] && closeP < cLo) return -1;
   return 0;
}

// H1 pullback zone: H1 trend intact (price above H1 Kijun) while price
// has retraced into or near the H1 cloud top (within tolerance). A price
// far above the cloud is an extended move — the "too late" case.
bool CheckH1Zone(int s, int dir)
{
   double kijun[1], senA[1], senB[1];
   if(CopyBuffer(ich[s][IDX_H1], 1, 1, 1, kijun) <= 0) return false;
   if(CopyBuffer(ich[s][IDX_H1], 2, 1, 1, senA)  <= 0) return false;
   if(CopyBuffer(ich[s][IDX_H1], 3, 1, 1, senB)  <= 0) return false;

   MqlRates rt[];
   if(CopyRates(syms[s], PERIOD_H1, 1, 1, rt) <= 0) return false;
   double closeP = rt[0].close;

   double cHi = MathMax(senA[0], senB[0]);
   double cLo = MathMin(senA[0], senB[0]);

   double tol = 0.0;
   if(atrH1[s] != INVALID_HANDLE)
   {
      double a[1];
      if(CopyBuffer(atrH1[s], 0, 1, 1, a) <= 0 || a[0] <= 0) return false;
      tol = InpZoneToleranceATR * a[0];
   }

   if(dir ==  1) return (closeP > kijun[0] && closeP <= cHi + tol);
   if(dir == -1) return (closeP < kijun[0] && closeP >= cLo - tol);
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

   if(atrH1[s] == INVALID_HANDLE) return false;
   double a[1];
   if(CopyBuffer(atrH1[s], 0, 1, 1, a) <= 0 || a[0] <= 0) return false;

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
// Exit Check: M15 price closed on wrong side of M15 kijun
//==============================================================

bool CheckM15Exit(int s, int dir)
{
   double kij[1];
   if(CopyBuffer(ich[s][IDX_M15], 1, 1, 1, kij) <= 0) return false;

   MqlRates rt[];
   if(CopyRates(syms[s], PERIOD_M15, 1, 1, rt) <= 0) return false;
   double closeP = rt[0].close;

   if(dir ==  1 && closeP < kij[0]) return true;
   if(dir == -1 && closeP > kij[0]) return true;
   return false;
}

//==============================================================
// Choppy-market detection: ADX(M15) below InpChopADXLevel means no
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
// retraces. Re-evaluated on every new M15 bar; only ever
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
// Break-Even Management (BE30): if the trade reaches a profitable
// position within InpBE30Minutes of entry, the stop loss moves up
// to break even plus a few points to cover the spread. One-shot
// per trade (beMoved); the chandelier trail may tighten further
// afterwards but never lowers the stop back down.
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

// ATR(M15) * multiplier, widened to the broker's minimum stop distance if
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
      // Cadence: all logic runs only on closed M15 bars, which change at
      // most once per 15 minutes. Skip every intermediate tick entirely.
      MqlRates m15[];
      if(CopyRates(syms[s], PERIOD_M15, 0, 2, m15) < 2) continue;
      ArraySetAsSeries(m15, true);
      if(m15[1].time == lastM15bar[s]) continue;
      lastM15bar[s] = m15[1].time;

      // Sync position state once per new M15 bar
      SyncStateFromPositions();

      // Exit check: close all when M15 closes against direction across M15 kijun
      if(state[s] != 0 && CheckM15Exit(s, state[s]))
      {
         string side = (state[s] == 1) ? "Long" : "Short";
         string msg  = PCTime() + " | Close " + syms[s] + " " + side + " (M15 kijun crossed)";
         Print(msg); SendNotification(msg);

         if(ClosePositions(syms[s]))
         {
            state[s] = 0;
            noReentryUntil[s] = TimeCurrent() + InpReentryCooldownSec;
         }
         else
            Print(PCTime() + " | " + syms[s] + " exit signal but positions still open — will retry");
      }

      // Chandelier trail: tighten stops behind the peak on each new M15 bar
      if(state[s] != 0) ManageTrail(s);

      // BE30: move the stop to break even + cover if profitable in time
      if(state[s] != 0) ManageBE(s);

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
