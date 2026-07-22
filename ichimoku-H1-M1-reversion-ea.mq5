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
input int    InpSwingLookback = 10;    // H1 bars used for the stop-loss swing high/low
input double InpSLBufferATR   = 0.10;  // Extra SL padding beyond the swing = this * ATR(H1)

input group  "Reversion Triggers"
input bool   InpUseM5Cross      = true; // Trigger on a fresh M5 close cross of the M5 Kijun
input bool   InpUseRejection    = true; // Trigger on a rejection candle raiding swing liquidity
input double InpRejWickFrac     = 0.55; // Rejection wick >= this fraction of the H1 candle range
input double InpRejBodyFrac     = 0.35; // Rejection body <= this fraction of the H1 candle range
input int    InpRejLookback     = 500;  // H1 bars scanned for prior swing highs/lows to raid
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
int      ichM5[MAX_SYMS];   // M5 Ichimoku (Kijun) handle per symbol
int      atrH1[MAX_SYMS];   // ATR(H1) handle per symbol
string   syms[MAX_SYMS];
int      symsCount = 0;
datetime lastM1bar[MAX_SYMS];
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
      state[s]     = 0;
      lastM1bar[s] = 0;

      ichH1[s] = iIchimoku(syms[s], PERIOD_H1, Tenkan, Kijun, SenkouB);
      ichM5[s] = iIchimoku(syms[s], PERIOD_M5, Tenkan, Kijun, SenkouB);
      atrH1[s] = iATR(syms[s], PERIOD_H1, InpATRPeriod);
      if(ichH1[s] == INVALID_HANDLE || ichM5[s] == INVALID_HANDLE || atrH1[s] == INVALID_HANDLE)
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
      if(ichH1[s] != INVALID_HANDLE) IndicatorRelease(ichH1[s]);
      if(ichM5[s] != INVALID_HANDLE) IndicatorRelease(ichM5[s]);
      if(atrH1[s] != INVALID_HANDLE) IndicatorRelease(atrH1[s]);
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

double SwingHigh(int s)
{
   MqlRates rt[];
   if(CopyRates(syms[s], PERIOD_H1, 1, InpSwingLookback, rt) <= 0) return 0.0;
   double hi = rt[0].high;
   for(int i = 1; i < ArraySize(rt); i++) if(rt[i].high > hi) hi = rt[i].high;
   return hi;
}

double SwingLow(int s)
{
   MqlRates rt[];
   if(CopyRates(syms[s], PERIOD_H1, 1, InpSwingLookback, rt) <= 0) return 0.0;
   double lo = rt[0].low;
   for(int i = 1; i < ArraySize(rt); i++) if(rt[i].low < lo) lo = rt[i].low;
   return lo;
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

// Proper rejection candle: the last closed H1 bar is a long-wicked, small-body
// candle whose wick raids beyond a prior fractal swing high/low from the last
// InpRejLookback bars, then closes back inside it. With InpRequireUnraided the
// raided swing must still hold resting liquidity (nothing exceeded it since it
// formed). dir = -1 wants an upper-wick raid above a swing high (doji to the
// upside); dir = +1 wants a lower-wick raid below a swing low.
bool RejectionTrigger(int s, int dir)
{
   int wing = MathMax(1, InpSwingWing);
   int need = InpRejLookback + wing + 2;

   MqlRates rt[];
   if(CopyRates(syms[s], PERIOD_H1, 1, need, rt) < need) return false;
   ArraySetAsSeries(rt, true);   // rt[0] = rejection candle (last closed H1 bar)

   double o = rt[0].open, h = rt[0].high, l = rt[0].low, c = rt[0].close;
   double range = h - l;
   if(range <= 0) return false;

   double body   = MathAbs(c - o);
   double upWick = h - MathMax(o, c);
   double loWick = MathMin(o, c) - l;
   if(body > InpRejBodyFrac * range) return false;

   int n    = ArraySize(rt);
   int last = n - 1 - wing;      // furthest index that can still be a fractal centre

   if(dir == -1)
   {
      if(upWick < InpRejWickFrac * range) return false;

      // Walk from the most recent past swing outward; j > wing keeps the
      // fractal test off the rejection candle itself (index 0).
      for(int j = wing + 1; j <= last; j++)
      {
         double sh = rt[j].high;
         bool isSwing = true;
         for(int k = 1; k <= wing && isSwing; k++)
            if(rt[j - k].high >= sh || rt[j + k].high >= sh) isSwing = false;
         if(!isSwing) continue;

         if(!(h > sh && c < sh)) continue;   // wick raids above, close rejects back below

         if(InpRequireUnraided)
         {
            bool raided = false;
            for(int i = 1; i < j && !raided; i++) if(rt[i].high >= sh) raided = true;
            if(raided) continue;
         }
         return true;
      }
      return false;
   }

   if(loWick < InpRejWickFrac * range) return false;

   for(int j = wing + 1; j <= last; j++)
   {
      double sl = rt[j].low;
      bool isSwing = true;
      for(int k = 1; k <= wing && isSwing; k++)
         if(rt[j - k].low <= sl || rt[j + k].low <= sl) isSwing = false;
      if(!isSwing) continue;

      if(!(l < sl && c > sl)) continue;      // wick raids below, close rejects back above

      if(InpRequireUnraided)
      {
         bool raided = false;
         for(int i = 1; i < j && !raided; i++) if(rt[i].low <= sl) raided = true;
         if(raided) continue;
      }
      return true;
   }
   return false;
}

//==============================================================
// Reversion Setup Check
//==============================================================
// Returns +1 (buy back up to the Kijun), -1 (sell back down to the Kijun),
// or 0 (no setup). On a valid setup, fills sl (swing stop), tp (H1 Kijun),
// stopDist (|entry - sl|) and a short trigger label.
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

   // Time theory: bars since the last Kijun touch must land on an Ichimoku
   // cycle (9 / 17 / 26 / 33 by default) within +/- InpTimeTol.
   barsSince = CountNoTouch(s);
   if(!InTimeWindow(barsSince)) return 0;

   // The Kijun must be flat so it acts as a magnet, not a trending line.
   if(!KijunFlat(s, atr)) return 0;

   // At least one reversion trigger must fire.
   bool triggered = false;
   if(InpUseM5Cross && M5CrossTrigger(s, dir))                { triggered = true; trig = "M5 cross"; }
   if(!triggered && InpUseRejection && RejectionTrigger(s, dir)) { triggered = true; trig = "rejection"; }
   if(!triggered) return 0;

   // Stop loss at the H1 swing, take profit at the H1 Kijun.
   int    digits  = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);
   double point   = SymbolInfoDouble(syms[s], SYMBOL_POINT);
   double buf     = InpSLBufferATR * atr;
   double swing   = (dir == -1) ? SwingHigh(s) : SwingLow(s);
   if(swing <= 0) return 0;

   sl = (dir == -1) ? swing + buf : swing - buf;
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
