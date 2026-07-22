//+------------------------------------------------------------------+
//| Ichimoku H1-M1 Reversion EA                                      |
//| Idea:  Ichimoku time theory — after price has stayed off the H1  |
//|        Kijun for ~26 candles and the Kijun is flat, an extended   |
//|        move is "due" to revert back to the Kijun.                 |
//| Entry: price far from a flat H1 Kijun (no touch ~26 bars), then   |
//|        a reversion trigger fires — either a fresh M5 Kijun cross   |
//|        back toward the Kijun, or a turtle-soup rejection candle.   |
//| Exit:  hard SL at the current H1 swing (high if selling, low if   |
//|        buying); TP at the H1 Kijun. Broker-managed via order SL/TP.|
//| Risk:  same equity-scaled sizing as the H1-M1 breakout EA.        |
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

input group  "Reversion Setup"
input string InpTimeCycles    = "9,17,26,33"; // Ichimoku time cycles: bars since last H1 Kijun touch
input int    InpTimeTol       = 2;     // +/- tolerance applied to each time cycle
input double InpFarATRMult    = 2.0;   // Price must be >= this * ATR(H1) from the Kijun
input int    InpFlatBars      = 5;     // Bars over which the Kijun slope is measured
input double InpFlatATRMult   = 0.25;  // Kijun is "flat" if its move over InpFlatBars <= this * ATR(H1)
input bool   InpUseTrendFilter = true; // Only fade an established H1 Ichimoku trend (sell in an uptrend)
input double InpSLBufferATR   = 0.10;  // Extra SL padding beyond the stop level = this * ATR(H1)

input group  "Reversion Stop Management"
input int    InpM15TrailFractal = 2;   // Trail SL to the Nth M15 fractal high/low beyond price
input int    InpM15SwingWing    = 2;   // M15 fractal half-width (bars each side)
input int    InpM15FractalBars  = 100; // M15 bars scanned for fractals when trailing
input double InpM15ClearATR     = 0.1; // "Clearly beyond the M15 Kijun" buffer = this * ATR(M15)

input group  "Reversion Triggers"
input bool   InpUseM5Cross      = true; // Trigger on a fresh M5 close cross of the M5 Kijun
input bool   InpUseRejection    = true; // Trigger on a rejection candle raiding swing liquidity
input double InpRejWickFrac     = 0.55; // Rejection wick >= this fraction of the H1 candle range
input double InpRejBodyFrac     = 0.35; // Rejection body <= this fraction of the H1 candle range
input int    InpRaidBarsD1      = 50;   // D1 bars scanned for a swing high/low to raid (0 = off)
input int    InpRaidBarsH4      = 300;  // H4 bars scanned for a swing high/low to raid (0 = off)
input int    InpRaidBarsH1      = 500;  // H1 bars scanned for a swing high/low to raid (0 = off)
input int    InpSwingWing       = 2;    // Fractal half-width for a swing point (bars each side)
input bool   InpRequireUnraided = true; // Only count swings whose liquidity is not yet raided

input group  "Risk Protection"
input int    InpATRPeriod         = 14;   // ATR period (H1) for the distance / flatness measures
input int    InpMaxSpreadPoints   = 60;   // Max spread in points to allow entry (0 = no limit)
input double InpHighEquityRiskPct = 1.0;  // % of equity risked per trade once equity > $8000

input group             "Equity Alert Settings"
input double            InpMinProfitTrigger  = 5.0;        // Min Profit over Baseline to trigger alert
input double            InpWithdrawProfitPct = 50.0;       // Percentage of the PROFIT to withdraw
input ENUM_DAY_OF_WEEK  InpCheckDay          = FRIDAY;     // Day of the week to check
input bool              InpResetBaseline     = false;      // Set to true to reset baseline to current equity
input bool              InpSendPush          = true;       // Send push notification

//--- Constants and Global Variables ---
#define MAX_SYMS  60

int      ichH1[MAX_SYMS];   // H1 Ichimoku (Kijun, cloud) handle per symbol
int      ichM15[MAX_SYMS];  // M15 Ichimoku (Kijun) handle per symbol — trail confirmation
int      ichM5[MAX_SYMS];   // M5 Ichimoku (Kijun) handle per symbol
int      atrH1[MAX_SYMS];   // ATR(H1) handle per symbol
int      atrM15[MAX_SYMS];  // ATR(M15) handle per symbol — "clearly beyond Kijun" buffer
string   syms[MAX_SYMS];
int      symsCount = 0;
datetime lastM1bar[MAX_SYMS];
datetime lastM15bar[MAX_SYMS];
datetime lastH1bar = 0;
int      state[MAX_SYMS];   // 0=no position, 1=long, -1=short

int      g_cycles[];        // parsed Ichimoku time cycles (bars since last Kijun touch)
int      g_cycleCount = 0;
int      g_maxCycle   = 0;

int MAGIC = 20260722;

#define GV_BASE_EQUITY    "EA_RevAlert_Base_"    + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))
#define GV_LAST_ALERT_DAY "EA_RevAlert_Day_"     + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))

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
      if(SymbolSelect(sym, true)) syms[cnt++] = sym;
   }
   return cnt;
}

// Parse the "9,17,26,33" cycle list into g_cycles[] and record the largest.
void ParseCycles(string list)
{
   string parts[];
   int n = StringSplit(list, ',', parts);
   ArrayResize(g_cycles, 0);
   g_cycleCount = 0;
   g_maxCycle   = 0;
   for(int i = 0; i < n; i++)
   {
      string p = parts[i];
      StringTrimLeft(p);
      StringTrimRight(p);
      int v = (int)StringToInteger(p);
      if(v > 0)
      {
         ArrayResize(g_cycles, g_cycleCount + 1);
         g_cycles[g_cycleCount++] = v;
         if(v > g_maxCycle) g_maxCycle = v;
      }
   }
}

// True when the bars-since-last-touch count sits within any cycle +/- tolerance.
bool InTimeWindow(int count)
{
   for(int i = 0; i < g_cycleCount; i++)
      if(count >= g_cycles[i] - InpTimeTol && count <= g_cycles[i] + InpTimeTol) return true;
   return false;
}

int OnInit()
{
   symsCount = ParseSymbols(Symbols);
   if(symsCount <= 0) return(INIT_FAILED);

   ParseCycles(InpTimeCycles);
   if(g_cycleCount <= 0) return(INIT_FAILED);

   for(int s = 0; s < symsCount; s++)
   {
      state[s]      = 0;
      lastM1bar[s]  = 0;
      lastM15bar[s] = 0;

      ichH1[s]  = iIchimoku(syms[s], PERIOD_H1,  Tenkan, Kijun, SenkouB);
      ichM15[s] = iIchimoku(syms[s], PERIOD_M15, Tenkan, Kijun, SenkouB);
      ichM5[s]  = iIchimoku(syms[s], PERIOD_M5,  Tenkan, Kijun, SenkouB);
      atrH1[s]  = iATR(syms[s], PERIOD_H1,  InpATRPeriod);
      atrM15[s] = iATR(syms[s], PERIOD_M15, InpATRPeriod);
      if(ichH1[s]  == INVALID_HANDLE || ichM15[s] == INVALID_HANDLE ||
         ichM5[s]  == INVALID_HANDLE || atrH1[s]  == INVALID_HANDLE ||
         atrM15[s] == INVALID_HANDLE)
         return(INIT_FAILED);
   }

   trade.SetDeviationInPoints(Slippage);
   SyncStateFromPositions();
   InitEquityAlert();
   return(INIT_SUCCEEDED);
}

//==============================================================
// Equity Alert: weekly profit-withdrawal reminder
//==============================================================

void InitEquityAlert()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(!GlobalVariableCheck(GV_BASE_EQUITY) || InpResetBaseline)
   {
      GlobalVariableSet(GV_BASE_EQUITY, currentEquity);
   }
   if(!GlobalVariableCheck(GV_LAST_ALERT_DAY))
   {
      GlobalVariableSet(GV_LAST_ALERT_DAY, 0);
   }
}

void CheckEquityAlert()
{
   MqlDateTime dt;
   TimeCurrent(dt);

   if(dt.day_of_week != InpCheckDay) return;
   if((int)GlobalVariableGet(GV_LAST_ALERT_DAY) == dt.day) return;

   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double baseEquity    = GlobalVariableGet(GV_BASE_EQUITY);
   double profit        = currentEquity - baseEquity;

   if(profit >= InpMinProfitTrigger)
   {
      double withdrawAmount = profit * (InpWithdrawProfitPct / 100.0);
      string msg = StringFormat("Profit: %.2f. Suggest withdrawing: %.2f", profit, withdrawAmount);

      Alert(msg);
      if(InpSendPush) SendNotification(msg);

      GlobalVariableSet(GV_LAST_ALERT_DAY, (double)dt.day);
      GlobalVariablesFlush();
   }
}

void OnDeinit(const int reason)
{
   for(int s = 0; s < symsCount; s++)
   {
      if(ichH1[s]  != INVALID_HANDLE) IndicatorRelease(ichH1[s]);
      if(ichM15[s] != INVALID_HANDLE) IndicatorRelease(ichM15[s]);
      if(ichM5[s]  != INVALID_HANDLE) IndicatorRelease(ichM5[s]);
      if(atrH1[s]  != INVALID_HANDLE) IndicatorRelease(atrH1[s]);
      if(atrM15[s] != INVALID_HANDLE) IndicatorRelease(atrM15[s]);
   }
}

//==============================================================
// Position State Sync (recover after restart)
//==============================================================

void SyncStateFromPositions()
{
   // Rebuild from scratch so positions closed by SL/TP or manually free the
   // symbol for re-entry instead of leaving stale state behind.
   for(int s = 0; s < symsCount; s++) state[s] = 0;

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
         if(syms[s] == sym) { state[s] = dir; break; }
      }
   }
}

//==============================================================
// Ichimoku / ATR helpers
//==============================================================

double ATRval(int s)
{
   double a[1];
   if(CopyBuffer(atrH1[s], 0, 1, 1, a) <= 0 || a[0] <= 0) return -1.0;
   return a[0];
}

bool GetH1Kijun(int s, int shift, double &v)
{
   double k[1];
   if(CopyBuffer(ichH1[s], 1, shift, 1, k) <= 0) return false;
   v = k[0];
   return true;
}

// Consecutive most-recent closed H1 bars whose range does NOT contain the
// Kijun (i.e. the candle never touched the Kijun). Stops at the first touch.
int CountNoTouch(int s)
{
   // Copy comfortably past the largest cycle window so a streak longer than
   // every window returns a value outside them all (no false positive).
   int want = g_maxCycle + InpTimeTol + 10;
   double kij[];
   MqlRates rt[];
   if(CopyBuffer(ichH1[s], 1, 1, want, kij) <= 0) return 0;
   if(CopyRates(syms[s], PERIOD_H1, 1, want, rt) <= 0) return 0;
   ArraySetAsSeries(kij, true);
   ArraySetAsSeries(rt, true);

   int n = MathMin(ArraySize(kij), ArraySize(rt));
   int count = 0;
   for(int i = 0; i < n; i++)
   {
      double k = kij[i];
      if(rt[i].low <= k && rt[i].high >= k) break;   // candle straddles the Kijun -> touched
      count++;
   }
   return count;
}

// The Kijun is flat when its move over InpFlatBars H1 bars is small vs ATR.
bool KijunFlat(int s, double atr)
{
   double kNow, kPast;
   if(!GetH1Kijun(s, 1, kNow))                 return false;
   if(!GetH1Kijun(s, 1 + InpFlatBars, kPast))  return false;
   return MathAbs(kNow - kPast) <= InpFlatATRMult * atr;
}

// Usual Ichimoku trend on the last closed H1 bar: +1 bullish (close above the
// cloud and Tenkan above Kijun), -1 bearish (mirror), 0 neither. The cloud that
// sits under the current bar is read Kijun bars into the Senkou buffers, since
// the spans are plotted Kijun periods ahead (same offset the alignment EA uses).
int CheckH1Trend(int s)
{
   int sh = 1;
   double tenkan[1], kijun[1], senA[1], senB[1];
   if(CopyBuffer(ichH1[s], 0, sh,         1, tenkan) <= 0) return 0;
   if(CopyBuffer(ichH1[s], 1, sh,         1, kijun)  <= 0) return 0;
   if(CopyBuffer(ichH1[s], 2, sh + Kijun, 1, senA)   <= 0) return 0;
   if(CopyBuffer(ichH1[s], 3, sh + Kijun, 1, senB)   <= 0) return 0;

   MqlRates rt[];
   if(CopyRates(syms[s], PERIOD_H1, sh, 1, rt) <= 0) return 0;
   double close    = rt[0].close;
   double cloudTop = MathMax(senA[0], senB[0]);
   double cloudBot = MathMin(senA[0], senB[0]);

   if(close > cloudTop && tenkan[0] > kijun[0]) return  1;
   if(close < cloudBot && tenkan[0] < kijun[0]) return -1;
   return 0;
}

// A closed M15 candle has confirmed the reversion when its close is clearly
// beyond the M15 Kijun in the trade direction (below for a sell, above for a
// buy), "clearly" = at least InpM15ClearATR * ATR(M15) past the Kijun.
bool M15Confirmed(int s, int dir)
{
   double kij[1];
   if(CopyBuffer(ichM15[s], 1, 1, 1, kij) <= 0) return false;

   MqlRates rt[];
   if(CopyRates(syms[s], PERIOD_M15, 1, 1, rt) <= 0) return false;
   double close = rt[0].close;

   double a[1], buf = 0.0;
   if(CopyBuffer(atrM15[s], 0, 1, 1, a) > 0 && a[0] > 0) buf = InpM15ClearATR * a[0];

   if(dir == -1) return close < kij[0] - buf;
   return close > kij[0] + buf;
}

// Nth M15 fractal on the protective side of `price` (highs above it for a sell,
// lows below it for a buy), ordered nearest-first. Returns false if fewer than
// `nth` exist. Used to trail the stop up/down behind M15 structure.
bool NthM15Fractal(int s, int dir, double price, int nth, double &level)
{
   if(nth < 1) return false;

   int wing = MathMax(1, InpM15SwingWing);
   int need = InpM15FractalBars + wing + 2;

   MqlRates rt[];
   if(CopyRates(syms[s], PERIOD_M15, 1, need, rt) < need) return false;
   ArraySetAsSeries(rt, true);

   int n    = ArraySize(rt);
   int last = n - 1 - wing;

   double found[];
   int cnt = 0;
   for(int j = wing; j <= last; j++)
   {
      double lvl = (dir == -1) ? rt[j].high : rt[j].low;

      bool isSwing = true;
      for(int k = 1; k <= wing && isSwing; k++)
      {
         if(dir == -1) { if(rt[j-k].high >= lvl || rt[j+k].high >= lvl) isSwing = false; }
         else          { if(rt[j-k].low  <= lvl || rt[j+k].low  <= lvl) isSwing = false; }
      }
      if(!isSwing) continue;

      if(dir == -1 && lvl <= price) continue;   // keep only fractals on the stop side
      if(dir ==  1 && lvl >= price) continue;

      ArrayResize(found, cnt + 1);
      found[cnt++] = lvl;
   }
   if(cnt < nth) return false;

   ArraySort(found);   // ascending
   // sell: nearest above price = smallest -> nth smallest; buy: nth largest.
   level = (dir == -1) ? found[nth - 1] : found[cnt - nth];
   return true;
}

//==============================================================
// Reversion Triggers
//==============================================================

// Fresh M5 close cross of the M5 Kijun back toward the H1 Kijun.
// dir = -1 (sell reversion) wants a downward cross; dir = +1 an upward cross.
bool M5CrossTrigger(int s, int dir)
{
   double k[];
   MqlRates rt[];
   if(CopyBuffer(ichM5[s], 1, 1, 2, k) < 2)          return false;
   if(CopyRates(syms[s], PERIOD_M5, 1, 2, rt) < 2)   return false;
   ArraySetAsSeries(k, true);
   ArraySetAsSeries(rt, true);

   double c1 = rt[0].close, c2 = rt[1].close;   // bar 1 (recent), bar 2 (older)
   double k1 = k[0],        k2 = k[1];

   if(dir == -1) return (c2 >= k2 && c1 < k1);   // crossed down toward the Kijun
   return (c2 <= k2 && c1 > k1);                 // crossed up toward the Kijun
}

// Does the H1 rejection candle (rejH / rejL / rejC) raid an UNLIQUIDATED
// fractal swing on timeframe tf, within the last `lookback` closed bars?
//   - fractal: strictly beyond `wing` neighbours on each side (a swing point).
//   - unraided: no more-recent closed bar on tf has exceeded the level since it
//     formed (its resting liquidity is still there). Judged at tf's resolution.
//   - raid: the rejection candle's wick pokes beyond the level and the close
//     rejects back inside it.
// tfIsRejection = true when tf is the rejection candle's own timeframe (H1):
// its index 0 IS the rejection candle, so it is excluded from swing detection
// and from the prior-raid scan. On higher timeframes index 0 is an ordinary
// past bar and counts toward both.
bool RaidsSwing(int s, ENUM_TIMEFRAMES tf, int lookback, int dir,
                double rejH, double rejL, double rejC, bool tfIsRejection)
{
   if(lookback <= 0) return false;

   int wing = MathMax(1, InpSwingWing);
   int need = lookback + wing + 2;

   MqlRates rt[];
   if(CopyRates(syms[s], tf, 1, need, rt) < need) return false;
   ArraySetAsSeries(rt, true);   // rt[0] = last closed bar on tf

   int n       = ArraySize(rt);
   int last    = n - 1 - wing;                 // furthest index that can be a fractal centre
   int startJ  = tfIsRejection ? wing + 1 : wing;
   int firstRd = tfIsRejection ? 1 : 0;        // first index to test for a prior raid

   for(int j = startJ; j <= last; j++)
   {
      double lvl   = (dir == -1) ? rt[j].high : rt[j].low;

      // fractal test against the `wing` neighbours on each side
      bool isSwing = true;
      for(int k = 1; k <= wing && isSwing; k++)
      {
         if(dir == -1) { if(rt[j-k].high >= lvl || rt[j+k].high >= lvl) isSwing = false; }
         else          { if(rt[j-k].low  <= lvl || rt[j+k].low  <= lvl) isSwing = false; }
      }
      if(!isSwing) continue;

      // the rejection candle must raid the level and close back inside it
      if(dir == -1) { if(!(rejH > lvl && rejC < lvl)) continue; }
      else          { if(!(rejL < lvl && rejC > lvl)) continue; }

      // level must not already be liquidated by a more-recent closed bar on tf
      if(InpRequireUnraided)
      {
         bool raided = false;
         for(int i = firstRd; i < j && !raided; i++)
         {
            if(dir == -1) { if(rt[i].high >= lvl) raided = true; }
            else          { if(rt[i].low  <= lvl) raided = true; }
         }
         if(raided) continue;
      }
      return true;
   }
   return false;
}

// Proper rejection candle: the last closed H1 bar is a long-wicked, small-body
// candle whose wick raids an unliquidated fractal swing on the daily, H4, or H1
// timeframe (see RaidsSwing) and closes back inside it. dir = -1 wants an
// upper-wick raid above a swing high (doji to the upside); dir = +1 a lower-wick
// raid below a swing low.
bool RejectionTrigger(int s, int dir)
{
   MqlRates h1[];
   if(CopyRates(syms[s], PERIOD_H1, 1, 1, h1) <= 0) return false;

   double o = h1[0].open, h = h1[0].high, l = h1[0].low, c = h1[0].close;
   double range = h - l;
   if(range <= 0) return false;

   double body   = MathAbs(c - o);
   double upWick = h - MathMax(o, c);
   double loWick = MathMin(o, c) - l;
   if(body > InpRejBodyFrac * range) return false;
   if(dir == -1 && upWick < InpRejWickFrac * range) return false;
   if(dir ==  1 && loWick < InpRejWickFrac * range) return false;

   // A raid on any configured timeframe qualifies (0 bars disables that TF).
   if(RaidsSwing(s, PERIOD_D1, InpRaidBarsD1, dir, h, l, c, false)) return true;
   if(RaidsSwing(s, PERIOD_H4, InpRaidBarsH4, dir, h, l, c, false)) return true;
   if(RaidsSwing(s, PERIOD_H1, InpRaidBarsH1, dir, h, l, c, true))  return true;
   return false;
}

//==============================================================
// Reversion Setup Check
//==============================================================
// Returns +1 (buy back up to the Kijun), -1 (sell back down to the Kijun),
// or 0 (no setup). On a valid setup, fills sl (initial stop at the H1 signal
// candle's extreme), tp (H1 Kijun), stopDist (|entry - sl|) and a trigger label.
//==============================================================

int CheckReversion(int s, double &sl, double &tp, double &stopDist, string &trig, int &barsSince)
{
   sl = 0.0; tp = 0.0; stopDist = 0.0; trig = ""; barsSince = 0;

   double atr = ATRval(s);
   if(atr <= 0) return 0;

   double kijNow;
   if(!GetH1Kijun(s, 1, kijNow)) return 0;

   MqlRates h1[];
   if(CopyRates(syms[s], PERIOD_H1, 1, 1, h1) <= 0) return 0;
   double priceNow = h1[0].close;

   // Price must be extended away from the Kijun to have room to revert.
   double dist = priceNow - kijNow;
   if(MathAbs(dist) < InpFarATRMult * atr) return 0;

   // Above the Kijun -> sell back down; below -> buy back up.
   int dir = (dist > 0) ? -1 : 1;

   // Only fade an established Ichimoku trend: a sell reversion (dir -1) needs a
   // bullish H1 trend to fade, a buy reversion (dir +1) needs a bearish one.
   if(InpUseTrendFilter && CheckH1Trend(s) != -dir) return 0;

   // Time theory: bars since the last Kijun touch (H1 break away from the Kijun)
   // must land on an Ichimoku cycle (9 / 17 / 26 / 33 by default) +/- InpTimeTol.
   barsSince = CountNoTouch(s);
   if(!InTimeWindow(barsSince)) return 0;

   // The Kijun must be flat so it acts as a magnet, not a trending line.
   if(!KijunFlat(s, atr)) return 0;

   // At least one reversion trigger must fire.
   bool triggered = false;
   if(InpUseM5Cross && M5CrossTrigger(s, dir))                { triggered = true; trig = "M5 cross"; }
   if(!triggered && InpUseRejection && RejectionTrigger(s, dir)) { triggered = true; trig = "rejection"; }
   if(!triggered) return 0;

   // Initial stop loss at the H1 signal candle's own extreme (tight, small
   // risk); it is trailed to M15 fractals once M15 confirms. TP at the H1 Kijun.
   int    digits  = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);
   double point   = SymbolInfoDouble(syms[s], SYMBOL_POINT);
   double buf     = InpSLBufferATR * atr;
   double signal  = (dir == -1) ? h1[0].high : h1[0].low;
   if(signal <= 0) return 0;

   sl = (dir == -1) ? signal + buf : signal - buf;
   tp = kijNow;

   // Respect the broker's minimum stop distance around the live entry price.
   double ref     = (dir == -1) ? SymbolInfoDouble(syms[s], SYMBOL_BID)
                                : SymbolInfoDouble(syms[s], SYMBOL_ASK);
   double minDist = SymbolInfoInteger(syms[s], SYMBOL_TRADE_STOPS_LEVEL) * point;

   if(dir == -1)
   {
      if(sl < ref + minDist) sl = ref + minDist;   // SL above, widen if too tight
      if(tp > ref - minDist) return 0;             // TP below must clear min distance
   }
   else
   {
      if(sl > ref - minDist) sl = ref - minDist;   // SL below, widen if too tight
      if(tp < ref + minDist) return 0;             // TP above must clear min distance
   }

   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);
   stopDist = MathAbs(ref - sl);
   if(stopDist <= 0) return 0;

   return dir;
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
// Risk Management (same equity-scaled sizing as the breakout EA)
//==============================================================

// Lot size that risks InpHighEquityRiskPct% of equity, split evenly across
// 'count' concurrent orders, if the stop loss is hit on all of them. Falls
// back to a conservative fixed lot when the stop distance or the symbol's
// tick value/size aren't available.
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
   if(eq <= 30)        { count = 2;  lots = 0.10; }
   else if(eq <= 50)   { count = 2;  lots = 0.10; }
   else if(eq <= 70)   { count = 4;  lots = 0.10; }
   else if(eq <= 100)  { count = 4;  lots = 0.10; }
   else if(eq <= 130)  { count = 6;  lots = 0.10; }
   else if(eq <= 150)  { count = 8;  lots = 0.10; }
   else if(eq <= 170)  { count = 10; lots = 0.10; }
   else if(eq <= 200)  { count = 6;  lots = 0.20; }
   else if(eq <= 300)  { count = 4;  lots = 0.30; }
   else if(eq <= 400)  { count = 6;  lots = 0.30; }
   else if(eq <= 500)  { count = 6;  lots = 0.30; }
   else if(eq <= 600)  { count = 8;  lots = 0.30; }
   else if(eq <= 1000) { count = 4;  lots = 0.50; }
   else if(eq <= 3000) { count = 4;  lots = 0.30; }
   else if(eq <= 5000) { count = 4;  lots = 0.20; }
   else if(eq <= 8000) { count = 4;  lots = 0.10; }
   else                { count = 2;  lots = RiskBasedLots(sym, eq, stopDist, count); }
}

//==============================================================
// Trading Functions
//==============================================================

bool SpreadOK(string sym)
{
   if(InpMaxSpreadPoints <= 0) return true;
   return SymbolInfoInteger(sym, SYMBOL_SPREAD) <= InpMaxSpreadPoints;
}

int OpenReversion(int s, bool isBuy, double sl, double tp, int count, double lots)
{
   string sym = syms[s];
   trade.SetExpertMagicNumber(MAGIC);

   int filled = 0;
   for(int i = 0; i < count; i++)
   {
      double price = isBuy ? SymbolInfoDouble(sym, SYMBOL_ASK)
                           : SymbolInfoDouble(sym, SYMBOL_BID);

      bool ok = isBuy ? trade.Buy(lots,  sym, price, sl, tp, "Buy H1 Reversion")
                      : trade.Sell(lots, sym, price, sl, tp, "Sell H1 Reversion");
      if(!ok) break;   // out of margin or rejected — don't hammer the server
      filled++;
   }
   return filled;
}

// Trail the stop of every open position on this symbol to the Nth M15 fractal
// beyond price (InpM15TrailFractal). Only tightens — a short's stop only moves
// down, a long's only up — and never inside the broker's minimum stop distance.
void TrailSymbolStops(int s, int dir)
{
   string sym   = syms[s];
   double price = (dir == 1) ? SymbolInfoDouble(sym, SYMBOL_ASK)
                             : SymbolInfoDouble(sym, SYMBOL_BID);

   double lvl;
   if(!NthM15Fractal(s, dir, price, InpM15TrailFractal, lvl)) return;

   double atr   = ATRval(s);
   double buf   = (atr > 0) ? InpSLBufferATR * atr : 0.0;
   int    dg    = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   double minD  = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * point;

   double newSL = (dir == 1) ? lvl - buf : lvl + buf;
   newSL = NormalizeDouble(newSL, dg);

   if(dir == -1 && newSL < price + minD) return;   // too close to price to place
   if(dir ==  1 && newSL > price - minD) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != sym) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MAGIC) continue;

      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);

      bool tighten = (dir == -1) ? (curSL == 0.0 || newSL < curSL)
                                 : (curSL == 0.0 || newSL > curSL);
      if(!tighten) continue;

      trade.PositionModify(ticket, newSL, curTP);
   }
}

// Once per new M15 bar, for each symbol holding a reversion position that M15
// has confirmed, trail the stop behind M15 structure.
void ManageReversionStops()
{
   for(int s = 0; s < symsCount; s++)
   {
      if(state[s] == 0) continue;

      MqlRates m15[];
      if(CopyRates(syms[s], PERIOD_M15, 0, 2, m15) < 2) continue;
      ArraySetAsSeries(m15, true);
      if(m15[1].time == lastM15bar[s]) continue;
      lastM15bar[s] = m15[1].time;

      int dir = state[s];                 // reversion direction (+1 buy, -1 sell)
      if(!M15Confirmed(s, dir)) continue; // wait for a clear M15 close beyond the Kijun
      TrailSymbolStops(s, dir);
   }
}

//==============================================================
// Main Loop
//==============================================================

void OnTick()
{
   // Equity alert: fire only on a new H1 bar (CheckEquityAlert self-guards on day-of-week)
   MqlRates h1[];
   if(symsCount > 0 && CopyRates(syms[0], PERIOD_H1, 0, 1, h1) > 0 && h1[0].time != lastH1bar)
   {
      lastH1bar = h1[0].time;
      CheckEquityAlert();
   }

   SyncStateFromPositions();
   ManageReversionStops();   // trail stops of open positions on each new M15 bar

   for(int s = 0; s < symsCount; s++)
   {
      // Per-symbol M1 bar gating — only act on a new closed M1 bar for this symbol
      MqlRates m1[];
      if(CopyRates(syms[s], PERIOD_M1, 0, 2, m1) < 2) continue;
      ArraySetAsSeries(m1, true);
      if(m1[1].time == lastM1bar[s]) continue;
      lastM1bar[s] = m1[1].time;

      // Exits are broker-managed by each order's attached SL / TP; state[s] just
      // guards against re-entry until the current reversion trade has closed.
      if(state[s] != 0) continue;
      if(!SpreadOK(syms[s])) continue;

      double sl, tp, stopDist; string trig; int barsSince;
      int dir = CheckReversion(s, sl, tp, stopDist, trig, barsSince);
      if(dir == 0) continue;

      bool isBuy = (dir == 1);

      int count; double lots;
      GetEquityRisk(syms[s], stopDist, count, lots);

      // Track state if any order filled — keeps the re-entry guard correct even
      // when only some of the orders go through. Alert reports the actual fills.
      int filled = OpenReversion(s, isBuy, sl, tp, count, lots);
      if(filled > 0)
      {
         state[s] = dir;
         int    dg     = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);
         string action = isBuy ? "Buy" : "Sell";
         string msg = PCTime() + " | " + action + " " + syms[s] +
                      " x" + IntegerToString(filled) +
                      " @ " + DoubleToString(lots, 2) +
                      " (H1 Reversion: " + trig + " @" + IntegerToString(barsSince) + "c) SL " +
                      DoubleToString(sl, dg) + " TP " + DoubleToString(tp, dg);
         Print(msg); Alert(msg); SendNotification(msg);
      }
      else
         Print(PCTime() + " | " + syms[s] + " reversion signal but no order filled");
   }
}
//This work is my worship unto GOD
