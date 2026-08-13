//+------------------------------------------------------------------+
//| Ichimoku Kumo Breakout EA — experimental                         |
//| Entry: price close breaks out of the cloud AND the chikou span   |
//|        breaks out of the cloud at its plotted position, and the  |
//|        kumo twist (Senkou Span A vs Span B) agrees with the      |
//|        breakout direction                                         |
//| Flat filter: at the point of breakout, before opening, the kijun |
//|        must be sloping — a flat kijun (move over InpFlatBars <=  |
//|        InpFlatATRMult * ATR(M1)) skips the trade and waits; the  |
//|        trade only opens once the kijun is angled in the breakout |
//|        direction                                                  |
//| Exit:  all positions close when price closes back inside the     |
//|        cloud                                                      |
//| Risk:  VPS-style ladder sizing (20% risk up to $8k, 10% to       |
//|        $13k, 5% above), ATR(M1) stop loss on every order, caps   |
//|        by InpMaxRiskPct and free margin, spread filter, re-entry |
//|        cooldown; exits are verified so failed closes retry       |
//| VPS:   no Alert popups; all logic runs only on closed M1 bars    |
//|        (once per minute) to cut CPU usage                        |
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
input int    InpATRPeriod         = 14;     // ATR period (M1)
input double InpATRMultiplier     = 3.0;    // SL distance = ATR * multiplier
input int    InpMaxSpreadPoints   = 60;     // Max spread in points to allow entry (0 = no limit)
input double InpHighEquityRiskPct = 1.0;    // % of equity risked per trade once equity > $8000
input int    InpReentryCooldownSec = 0;     // Min seconds after an exit before re-entering same symbol (0 = none)
input double InpMaxRiskPct         = 0.0;   // Cap total initial-stop risk per ladder as % of equity (0 = no cap)

input group  "Flat-Kijun Filter"
input int    InpFlatBars     = 10;    // Bars over which each line's move is measured
input double InpFlatATRMult  = 0.15;  // A line is "flat" if its move over InpFlatBars <= this * ATR(M1)

input group  "Logging"
input bool   InpLogSkips     = true;  // Log skipped entries (flat detected / kijun not angled)

//--- Constants and Global Variables ---
#define MAX_SYMS  60
#define TF_M1     PERIOD_M1   // single-timeframe build — everything reads M1

int      ich[MAX_SYMS];   // iIchimoku(M1) handle per symbol
int      atr[MAX_SYMS];   // iATR(M1) handle per symbol
string   syms[MAX_SYMS];
int      symsCount = 0;
datetime lastM1bar[MAX_SYMS];
datetime noReentryUntil[MAX_SYMS];
int      lastMinuteKey = -1;
int      state[MAX_SYMS];   // 0=no position, 1=long, -1=short

int MAGIC = 20260845;   // fresh — no other EA uses this

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
      lastM1bar[s] = 0;
      noReentryUntil[s] = 0;

      ich[s] = iIchimoku(syms[s], TF_M1, Tenkan, Kijun, SenkouB);
      if(ich[s] == INVALID_HANDLE) return(INIT_FAILED);

      // ATR always needed — flat detection measures every line vs ATR(M1)
      atr[s] = iATR(syms[s], TF_M1, InpATRPeriod);
      if(atr[s] == INVALID_HANDLE) return(INIT_FAILED);
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
      if(ich[s] != INVALID_HANDLE) IndicatorRelease(ich[s]);
      if(atr[s] != INVALID_HANDLE) IndicatorRelease(atr[s]);
   }
}

//==============================================================
// Position State Sync (recover after restart)
//==============================================================

void SyncStateFromPositions()
{
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
            break;
         }
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
// Kumo Breakout Check: price close and chikou both outside the
// cloud, with the kumo twist agreeing. Returns 1 (bullish),
// -1 (bearish), 0 (none). Read on the last closed M1 bar.
//==============================================================

int CheckKumoBreakout(int s)
{
   int sh      = 1;              // last closed bar
   int chShift = sh + Kijun;     // chikou's chart position for bar sh (Kijun bars back)
   // MT5's iIchimoku Senkou buffers are pre-shifted: the value at shift p
   // is the cloud as drawn at chart position p — no extra offset needed.

   MqlRates rt[];
   if(CopyRates(syms[s], TF_M1, 0, chShift + 1, rt) <= 0) return 0;
   ArraySetAsSeries(rt, true);
   if(ArraySize(rt) <= chShift) return 0;

   double senA[1], senB[1], senA_ch[1], senB_ch[1];
   if(CopyBuffer(ich[s], 2, sh,      1, senA)    <= 0) return 0;
   if(CopyBuffer(ich[s], 3, sh,      1, senB)    <= 0) return 0;
   if(CopyBuffer(ich[s], 2, chShift, 1, senA_ch) <= 0) return 0;
   if(CopyBuffer(ich[s], 3, chShift, 1, senB_ch) <= 0) return 0;

   double closeP = rt[sh].close;
   double cHi    = MathMax(senA[0], senB[0]);
   double cLo    = MathMin(senA[0], senB[0]);
   double cHiC   = MathMax(senA_ch[0], senB_ch[0]);
   double cLoC   = MathMin(senA_ch[0], senB_ch[0]);

   // bullish: price closed above the cloud, chikou (the close plotted Kijun
   // bars back) clear above the cloud at its plotted position, and the
   // kumo twist agrees (Span A above Span B)
   if(closeP > cHi && closeP > cHiC && senA[0] > senB[0]) return  1;

   // bearish: mirror of the above
   if(closeP < cLo && closeP < cLoC && senA[0] < senB[0]) return -1;

   return 0;
}

//==============================================================
// Flat-Kijun Filter: the kijun is "flat" when its move over
// InpFlatBars M1 bars is small vs ATR(M1). Unreadable values count
// as flat (conservative) so no trade ever opens unfiltered.
//==============================================================

bool KijunFlat(int s, double atrVal)
{
   double now[1], past[1];
   if(CopyBuffer(ich[s], 1, 1,              1, now)  <= 0) return true;
   if(CopyBuffer(ich[s], 1, 1 + InpFlatBars, 1, past) <= 0) return true;
   return MathAbs(now[0] - past[0]) <= InpFlatATRMult * atrVal;
}

// The kijun must be angled in the trade direction: a rising kijun for a
// long breakout, a falling one for a short breakout. A kijun that is still
// flat (or sloped against the breakout) blocks the entry.
bool KijunAngled(int s, int dir, double atrVal)
{
   double now[1], past[1];
   if(CopyBuffer(ich[s], 1, 1,              1, now)  <= 0) return false;
   if(CopyBuffer(ich[s], 1, 1 + InpFlatBars, 1, past) <= 0) return false;
   double move = now[0] - past[0];
   if(MathAbs(move) <= InpFlatATRMult * atrVal) return false;
   return (dir == 1) ? move > 0 : move < 0;
}

//==============================================================
// Exit Check: price closed back inside the cloud (between the
// two Senkou spans) on the last closed M1 bar
//==============================================================

bool PriceInsideCloud(int s)
{
   double senA[1], senB[1];
   if(CopyBuffer(ich[s], 2, 1, 1, senA) <= 0) return false;
   if(CopyBuffer(ich[s], 3, 1, 1, senB) <= 0) return false;

   MqlRates rt[];
   if(CopyRates(syms[s], TF_M1, 1, 1, rt) <= 0) return false;
   double closeP = rt[0].close;

   double cHi = MathMax(senA[0], senB[0]);
   double cLo = MathMin(senA[0], senB[0]);
   return closeP < cHi && closeP > cLo;
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

// Raw ATR(M1) value. Returns false when the ATR value is unavailable so the
// caller skips the entry instead of trading unfiltered and unprotected.
bool GetATR(int s, double &atrVal)
{
   atrVal = 0.0;
   if(atr[s] == INVALID_HANDLE) return false;
   double a[1];
   if(CopyBuffer(atr[s], 0, 1, 1, a) <= 0 || a[0] <= 0) return false;
   atrVal = a[0];
   return true;
}

// ATR(M1) * multiplier, widened to the broker's minimum stop distance if
// needed. Returns false when the ATR value is unavailable.
bool GetStopDistance(int s, double &dist)
{
   double atrVal;
   if(!GetATR(s, atrVal)) return false;

   dist = atrVal * InpATRMultiplier;
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

int OpenPositions(int s, bool isBuy, double dist, int count, double lots)
{
   string sym = syms[s];

   int filled = 0;
   for(int i = 0; i < count; i++)
   {
      double price = isBuy ? SymbolInfoDouble(sym, SYMBOL_ASK)
                           : SymbolInfoDouble(sym, SYMBOL_BID);
      double sl = InpUseStopLoss ? BuildStopLoss(s, isBuy, price, dist) : 0.0;

      bool ok = isBuy ? trade.Buy(lots,  sym, price, sl, 0, "Kumo Breakout")
                      : trade.Sell(lots, sym, price, sl, 0, "Kumo Breakout");
      if(!ok) break;   // out of margin or rejected — don't hammer the server
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
      if(CopyRates(syms[s], TF_M1, 0, 2, m1) < 2) continue;
      ArraySetAsSeries(m1, true);
      if(m1[1].time == lastM1bar[s]) continue;
      lastM1bar[s] = m1[1].time;

      // Sync position state once per tick on the first new M1 bar instead of
      // rebuilding it on every single tick.
      if(!synced) { SyncStateFromPositions(); synced = true; }

      // Exit check: price closed back inside the cloud
      if(state[s] != 0 && PriceInsideCloud(s))
      {
         string side = (state[s] == 1) ? "Long" : "Short";
         string msg  = PCTime() + " | Close " + syms[s] + " " + side + " (price back inside cloud)";
         Print(msg); SendNotification(msg);

         if(ClosePositions(syms[s]))
         {
            state[s] = 0;
            noReentryUntil[s] = TimeCurrent() + InpReentryCooldownSec;
         }
         else
            Print(PCTime() + " | " + syms[s] + " exit signal but positions still open — will retry");
      }

      // Entry check: kumo breakout signal, flat filter, angled kijun, spread
      if(state[s] == 0 && TimeCurrent() >= noReentryUntil[s])
      {
         int dir = CheckKumoBreakout(s);
         if(dir != 0)
         {
            double atrVal;
            if(!GetATR(s, atrVal))
            {
               if(InpLogSkips) Print(PCTime() + " | " + syms[s] + " ATR unavailable — entry skipped");
               continue;
            }

            if(KijunFlat(s, atrVal))
            {
               if(InpLogSkips)
                  Print(PCTime() + " | " + syms[s] + " kumo breakout but kijun flat — skipping and waiting");
               continue;
            }

            if(!KijunAngled(s, dir, atrVal))
            {
               if(InpLogSkips)
               {
                  string way = (dir == 1) ? "up" : "down";
                  Print(PCTime() + " | " + syms[s] + " kumo breakout, no flats, but kijun not angled " + way + " — waiting");
               }
               continue;
            }

            if(!SpreadOK(syms[s]))
            {
               if(InpLogSkips) Print(PCTime() + " | " + syms[s] + " spread too wide — entry skipped");
               continue;
            }

            bool   isBuy = (dir == 1);
            double dist  = 0.0;
            if(InpUseStopLoss && !GetStopDistance(s, dist)) continue;   // ATR unavailable — skip entry

            int count; double lots;
            GetEquityRisk(syms[s], dist, count, lots);
            CapToRisk(syms[s], dist, count, lots);
            CapToMargin(syms[s], isBuy, count, lots);

            // Track state if any order filled — keeps exit logic and re-entry
            // guard correct even when only some of the orders go through.
            // Alert reports the actual fill count, not the requested count.
            int filled = OpenPositions(s, isBuy, dist, count, lots);
            if(filled > 0)
            {
               state[s] = dir;
               string action = isBuy ? "Buy" : "Sell";
               string msg = PCTime() + " | " + action + " " + syms[s] +
                            " x" + IntegerToString(filled) +
                            " @ " + DoubleToString(lots, 2) + " (kumo breakout)";
               Print(msg); SendNotification(msg);
            }
            else
               Print(PCTime() + " | " + syms[s] + " entry signal but no order filled");
         }
      }
   }
}
//This work is my worship unto GOD
