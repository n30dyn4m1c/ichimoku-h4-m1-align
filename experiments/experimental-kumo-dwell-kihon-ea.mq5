//+------------------------------------------------------------------+
//| Ichimoku Kumo-Dwell Kihon Breakout EA — experimental              |
//| Strategy 4 of the kihon suchi study (notes §67), built as tested: |
//| Setup: price has closed inside (or on the wrong side of) the     |
//|        cloud for a kihon suchi count of consecutive bars — 9, 17, |
//|        26, 33, 42, 51, 65 or 76, within +-InpKihonTol — and the   |
//|        last closed bar is the first close beyond the cloud        |
//| Entry: breakout close above the cloud (below for a sell), Tenkan  |
//|        above Kijun (below), and the close above the close Kijun   |
//|        bars back (below) — the chikou is free. Entered at the     |
//|        open of the next bar; if the spread is too wide the signal |
//|        waits for the first acceptable tick of that same bar       |
//| Stop:  beyond the Kijun or the cloud edge, whichever is further,  |
//|        plus InpStopBufferATR x ATR; capped at InpMaxStopATR x ATR |
//|        from the breakout close. Entries risking less than         |
//|        InpMinRiskATR or more than InpMaxRiskATR x ATR are skipped |
//| Exit:  EXIT_TARGET (default) — take profit at InpTargetR x the    |
//|        risk (2R tested). EXIT_KIJUN — close on a bar that closes  |
//|        back beyond the Kijun. Both modes also close after         |
//|        InpMaxHoldBars bars (60 tested)                            |
//| Risk:  InpRiskPct % of equity per trade, sized on the real stop   |
//|        distance, capped by free margin; one position per symbol   |
//| Study (Yahoo D1 data, 9 markets, 2000-2026): 166 trades, 59% win  |
//|        at 1R, +0.34R at 2R, against +0.06R for non-kihon dwells   |
//|        of 7+ bars. Failed on 2 years of H4 — D1 is the default    |
//| Author: Neo Malesa                                               |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

enum ExitMode
{
   EXIT_TARGET = 0,   // Take profit at InpTargetR x risk
   EXIT_KIJUN  = 1    // Close on a close back beyond the Kijun
};

//--- Input Parameters ---
input string          Symbols  = "GOLDm#";
input ENUM_TIMEFRAMES InpTF    = PERIOD_D1;   // Timeframe the setup is read on (tested on D1)
input int             Tenkan   = 9;
input int             Kijun    = 26;
input int             SenkouB  = 52;
input int             Slippage = 30;

input group  "Kihon Dwell"
input string InpKihonNumbers = "9,17,26,33,42,51,65,76";  // Dwell counts that qualify (comma-separated)
input int    InpKihonTol     = 1;      // A dwell within +- this many bars of a number qualifies
input int    InpMaxDwell     = 200;    // Longest dwell counted (bars)
input bool   InpTKFilter     = true;   // Require Tenkan above Kijun (below for a sell)
input bool   InpChikouFilter = true;   // Require the close beyond the close Kijun bars back

input group  "Stop Loss"
input int    InpATRPeriod      = 14;   // ATR period (on InpTF)
input double InpStopBufferATR  = 0.2;  // Stop sits this x ATR beyond the Kijun / cloud edge
input double InpMaxStopATR     = 3.0;  // Stop never further than this x ATR from the breakout close
input double InpMinRiskATR     = 0.2;  // Skip when entry-to-stop is under this x ATR
input double InpMaxRiskATR     = 6.0;  // Skip when entry-to-stop is over this x ATR (gap)

input group  "Exit"
input ExitMode InpExitMode    = EXIT_TARGET;
input double   InpTargetR     = 2.0;   // EXIT_TARGET: take profit at this multiple of the risk
input int      InpMaxHoldBars = 60;    // Close after this many bars on InpTF (0 = off)

input group  "Risk"
input double InpRiskPct         = 1.0;   // % of equity lost if the stop is hit
input bool   InpUseFixedLots    = false; // Trade InpFixedLots instead of risk sizing
input double InpFixedLots       = 0.10;
input double InpMaxMarginPct    = 80.0;  // Use at most this % of free margin
input int    InpMaxSpreadPoints = 60;    // Wait for a spread at or below this (0 = no limit)

input group  "Logging"
input bool   InpLogSkips = true;   // Log breakouts that do not qualify, with their dwell count

//--- Constants and Global Variables ---
#define MAX_SYMS  60
#define MAX_KIHON 32

int      ich[MAX_SYMS];
int      atr[MAX_SYMS];
string   syms[MAX_SYMS];
int      symsCount = 0;
datetime lastBar[MAX_SYMS];

// A signal read on a closed bar waits here until it fills or its entry bar ends
int      pendDir[MAX_SYMS];     // 0 = none, 1 = buy, -1 = sell
datetime pendBar[MAX_SYMS];     // open time of the bar the entry belongs to
double   pendStop[MAX_SYMS];
double   pendATR[MAX_SYMS];
int      pendDwell[MAX_SYMS];
int      pendTries[MAX_SYMS];   // failed order attempts on the entry bar

int kihon[MAX_KIHON];
int kihonCount = 0;

int MAGIC = 20260889;   // fresh — no other EA uses this

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

int ParseKihon(string list)
{
   string parts[];
   int n = StringSplit(list, ',', parts);
   int cnt = 0;
   for(int i = 0; i < n && cnt < MAX_KIHON; i++)
   {
      string p = parts[i];
      StringTrimLeft(p);
      StringTrimRight(p);
      int v = (int)StringToInteger(p);
      if(v > 0) kihon[cnt++] = v;
   }
   return cnt;
}

int OnInit()
{
   symsCount = ParseSymbols(Symbols);
   if(symsCount <= 0) return(INIT_FAILED);
   kihonCount = ParseKihon(InpKihonNumbers);
   if(kihonCount <= 0) return(INIT_FAILED);

   for(int s = 0; s < symsCount; s++)
   {
      lastBar[s] = 0;
      pendDir[s] = 0;

      ich[s] = iIchimoku(syms[s], InpTF, Tenkan, Kijun, SenkouB);
      if(ich[s] == INVALID_HANDLE) return(INIT_FAILED);
      atr[s] = iATR(syms[s], InpTF, InpATRPeriod);
      if(atr[s] == INVALID_HANDLE) return(INIT_FAILED);
   }

   trade.SetDeviationInPoints(Slippage);
   trade.SetExpertMagicNumber(MAGIC);
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

bool OnKihon(int dwell)
{
   for(int i = 0; i < kihonCount; i++)
      if(MathAbs(dwell - kihon[i]) <= InpKihonTol) return true;
   return false;
}

bool SpreadOK(string sym)
{
   if(InpMaxSpreadPoints <= 0) return true;
   return SymbolInfoInteger(sym, SYMBOL_SPREAD) <= InpMaxSpreadPoints;
}

// Ticket of this EA's position on the symbol, or 0 when there is none
ulong FindPosition(string sym)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) == sym &&
         (int)PositionGetInteger(POSITION_MAGIC) == MAGIC) return ticket;
   }
   return 0;
}

//==============================================================
// Signal: read on the last closed bar (shift 1). Returns 1 / -1
// when the bar is a qualifying kihon-dwell breakout and fills the
// stop level, ATR and dwell count; 0 otherwise.
//==============================================================

int CheckSignal(int s, double &stop, double &atrVal, int &dwell)
{
   string sym = syms[s];
   int need = MathMax(InpMaxDwell + 3, Kijun + 2);

   // MT5's iIchimoku Senkou buffers are pre-shifted: the value at shift p
   // is the cloud as drawn under bar p, which is the cloud price is read against.
   double cl[], senA[], senB[], tk[1], kj[1], a[1];
   if(CopyClose(sym, InpTF, 0, need, cl) < need) return 0;
   if(CopyBuffer(ich[s], 2, 0, need, senA) < need) return 0;
   if(CopyBuffer(ich[s], 3, 0, need, senB) < need) return 0;
   if(CopyBuffer(ich[s], 0, 1, 1, tk) <= 0) return 0;
   if(CopyBuffer(ich[s], 1, 1, 1, kj) <= 0) return 0;
   if(CopyBuffer(atr[s], 0, 1, 1, a) <= 0 || a[0] <= 0) return 0;
   ArraySetAsSeries(cl, true);
   ArraySetAsSeries(senA, true);
   ArraySetAsSeries(senB, true);

   double close1 = cl[1];
   double top1 = MathMax(senA[1], senB[1]), bot1 = MathMin(senA[1], senB[1]);
   double top2 = MathMax(senA[2], senB[2]), bot2 = MathMin(senA[2], senB[2]);
   atrVal = a[0];

   int dir = 0;
   if(close1 > top1 && cl[2] <= top2) dir = 1;          // first close above the cloud
   else if(close1 < bot1 && cl[2] >= bot2) dir = -1;    // first close below the cloud
   if(dir == 0) return 0;

   // Dwell: consecutive closes before the breakout bar that sat inside or
   // on the wrong side of the cloud (at or below its top for a buy).
   dwell = 0;
   for(int j = 2; j < need && dwell < InpMaxDwell; j++)
   {
      double top = MathMax(senA[j], senB[j]), bot = MathMin(senA[j], senB[j]);
      bool inside = (dir == 1) ? cl[j] <= top : cl[j] >= bot;
      if(!inside) break;
      dwell++;
   }

   string side = (dir == 1) ? "up" : "down";
   if(InpTKFilter && ((dir == 1 && tk[0] <= kj[0]) || (dir == -1 && tk[0] >= kj[0])))
   {
      if(InpLogSkips) Print(PCTime() + " | " + sym + " cloud break " + side + " after " + IntegerToString(dwell) + " bars, tenkan not past kijun — no trade");
      return 0;
   }
   double chikouRef = cl[1 + Kijun];
   if(InpChikouFilter && ((dir == 1 && close1 <= chikouRef) || (dir == -1 && close1 >= chikouRef)))
   {
      if(InpLogSkips) Print(PCTime() + " | " + sym + " cloud break " + side + " after " + IntegerToString(dwell) + " bars, chikou not free — no trade");
      return 0;
   }
   if(!OnKihon(dwell))
   {
      if(InpLogSkips) Print(PCTime() + " | " + sym + " cloud break " + side + " after " + IntegerToString(dwell) + " bars — not a kihon count, no trade");
      return 0;
   }

   // Stop beyond the Kijun or the cloud edge, whichever is further, capped
   if(dir == 1)
   {
      stop = MathMin(kj[0], bot1) - InpStopBufferATR * atrVal;
      if(close1 - stop > InpMaxStopATR * atrVal) stop = close1 - InpMaxStopATR * atrVal;
   }
   else
   {
      stop = MathMax(kj[0], top1) + InpStopBufferATR * atrVal;
      if(stop - close1 > InpMaxStopATR * atrVal) stop = close1 + InpMaxStopATR * atrVal;
   }
   return dir;
}

//==============================================================
// Sizing
//==============================================================

double NormalizeLots(string sym, double lots)
{
   double lotStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double lotMin  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double lotMax  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   if(lotStep > 0) lots = MathFloor(lots / lotStep) * lotStep;
   return MathMax(lotMin, MathMin(lotMax, lots));
}

double SizeLots(string sym, bool isBuy, double price, double stopDist)
{
   double lots = InpFixedLots;
   if(!InpUseFixedLots)
   {
      double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
      if(tickValue > 0 && tickSize > 0 && stopDist > 0)
      {
         double moneyPerLot = (stopDist / tickSize) * tickValue;
         lots = AccountInfoDouble(ACCOUNT_EQUITY) * (InpRiskPct / 100.0) / moneyPerLot;
      }
   }
   lots = NormalizeLots(sym, lots);

   // Cap to the free-margin budget so the order is not rejected outright
   double marginOne = 0.0;
   if(InpMaxMarginPct > 0 &&
      OrderCalcMargin(isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, sym, 1.0, price, marginOne) && marginOne > 0)
   {
      double maxLots = AccountInfoDouble(ACCOUNT_MARGIN_FREE) * (InpMaxMarginPct / 100.0) / marginOne;
      if(lots > maxLots) lots = NormalizeLots(sym, maxLots);
   }
   return lots;
}

//==============================================================
// Entry and Exit
//==============================================================

// Try to fill the pending signal. Returns true when the signal is used up
// (filled or rejected for good), false to keep waiting for the spread.
bool TryEntry(int s)
{
   string sym = syms[s];
   int    dir = pendDir[s];
   bool   isBuy = (dir == 1);
   if(!SpreadOK(sym)) return false;

   double price = isBuy ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID);
   double risk  = (price - pendStop[s]) * dir;
   if(risk < InpMinRiskATR * pendATR[s] || risk > InpMaxRiskATR * pendATR[s])
   {
      if(InpLogSkips) Print(PCTime() + " | " + sym + " kihon breakout skipped — entry-to-stop " + DoubleToString(risk / pendATR[s], 2) + " x ATR is out of range");
      return true;
   }

   int    digits  = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double point   = SymbolInfoDouble(sym, SYMBOL_POINT);
   double minDist = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * point;
   if(risk < minDist)
   {
      if(InpLogSkips) Print(PCTime() + " | " + sym + " kihon breakout skipped — stop inside the broker minimum");
      return true;
   }
   double sl = NormalizeDouble(pendStop[s], digits);
   double tp = (InpExitMode == EXIT_TARGET) ? NormalizeDouble(price + dir * InpTargetR * risk, digits) : 0.0;
   double lots = SizeLots(sym, isBuy, price, risk);

   trade.SetTypeFillingBySymbol(sym);
   string cmt = "Kihon Dwell " + IntegerToString(pendDwell[s]);
   bool ok = isBuy ? trade.Buy(lots, sym, price, sl, tp, cmt)
                   : trade.Sell(lots, sym, price, sl, tp, cmt);
   if(!ok)
   {
      pendTries[s]++;
      bool giveUp = pendTries[s] >= 3;
      Print(PCTime() + " | " + sym + " kihon breakout order failed, retcode " + IntegerToString(trade.ResultRetcode()) +
            (giveUp ? " — giving up on this signal" : " — will retry"));
      return giveUp;
   }

   string msg = PCTime() + " | " + (isBuy ? "Buy " : "Sell ") + sym + " @ " + DoubleToString(lots, 2) +
                " (kumo break after " + IntegerToString(pendDwell[s]) + "-bar dwell, risk " +
                DoubleToString(risk / pendATR[s], 2) + " x ATR)";
   Print(msg); SendNotification(msg);
   return true;
}

// Kijun-close exit (EXIT_KIJUN) and the time stop, read on the last closed bar
void CheckExit(int s, ulong ticket)
{
   string sym = syms[s];
   if(!PositionSelectByTicket(ticket)) return;
   int dir = ((int)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
   string reason = "";

   if(InpMaxHoldBars > 0)
   {
      int held = iBarShift(sym, InpTF, (datetime)PositionGetInteger(POSITION_TIME));
      if(held >= InpMaxHoldBars) reason = "held " + IntegerToString(held) + " bars";
   }
   if(reason == "" && InpExitMode == EXIT_KIJUN)
   {
      double kj[1];
      double c1 = iClose(sym, InpTF, 1);
      if(CopyBuffer(ich[s], 1, 1, 1, kj) > 0 && c1 > 0 &&
         ((dir == 1 && c1 < kj[0]) || (dir == -1 && c1 > kj[0])))
         reason = "close back beyond the kijun";
   }
   if(reason == "") return;

   if(trade.PositionClose(ticket))
   {
      string msg = PCTime() + " | Close " + sym + (dir == 1 ? " Long" : " Short") + " (" + reason + ")";
      Print(msg); SendNotification(msg);
   }
   else
      Print(PCTime() + " | " + sym + " close failed, retcode " + IntegerToString(trade.ResultRetcode()) + " — will retry");
}

//==============================================================
// Main Loop
//==============================================================

void OnTick()
{
   for(int s = 0; s < symsCount; s++)
   {
      string   sym = syms[s];
      datetime bar0 = iTime(sym, InpTF, 0);
      if(bar0 == 0) continue;
      ulong ticket = FindPosition(sym);

      if(bar0 != lastBar[s])
      {
         lastBar[s] = bar0;
         pendDir[s] = 0;   // an unfilled signal expires with its entry bar

         if(ticket != 0)
            CheckExit(s, ticket);
         else
         {
            double stop, atrVal;
            int dwell;
            int dir = CheckSignal(s, stop, atrVal, dwell);
            if(dir != 0)
            {
               pendDir[s]   = dir;
               pendBar[s]   = bar0;
               pendStop[s]  = stop;
               pendATR[s]   = atrVal;
               pendDwell[s] = dwell;
               pendTries[s] = 0;
            }
         }
      }

      // Fill a pending signal on any tick of its entry bar once the spread allows
      if(pendDir[s] != 0 && pendBar[s] == bar0 && ticket == 0)
      {
         if(TryEntry(s)) pendDir[s] = 0;
      }
   }
}
//This work is my worship unto GOD
