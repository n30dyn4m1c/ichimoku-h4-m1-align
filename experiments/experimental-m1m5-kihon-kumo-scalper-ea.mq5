//+------------------------------------------------------------------+
//| Ichimoku M1/M5 Kihon-Time Kumo Scalper EA — experimental          |
//| The intraday kihon study (notes §68), built as tested:           |
//| Time:  the signal M1 bar sits in a kihon candle of the day — the  |
//|        day's M15 candle 9, 17, 26, 33, 42, 51, 65 or 76, M30      |
//|        candle 9, 17, 26, 33 or 42, or H1 candle 9 or 17, counted  |
//|        from the D1 open (candle at the open = 1)                  |
//| Setup: price AND chikou clear of the kumo on M1 and M5 — the      |
//|        close beyond tenkan, kijun and the cloud, and beyond the   |
//|        high/low, tenkan, kijun and cloud 26 bars back. Trigger:   |
//|        TRIG_M5_BREAK (default) — the M5 bar that just closed made |
//|          M5 clear, M1 already clear (study T2)                    |
//|        TRIG_M1_BREAK — the M1 bar made M1 clear, M5 already clear |
//|          (study T1)                                               |
//|        TRIG_CANDLE_OPEN — the first M1 bar of an M15 candle with  |
//|          M1 and M5 both clear (study T3)                          |
//| Entry: at market on the next M1 bar, first tick inside the spread |
//|        cap; one trade per side per M15 candle, one per symbol     |
//| Stop:  beyond the kijun or the cloud edge, whichever is further,  |
//|        + 0.2 ATR — M5 lines for TRIG_M5_BREAK, M1 lines otherwise |
//| Exit:  EXIT_TARGET (default) — take profit at 1.5R. EXIT_KIJUN —  |
//|        close on an M1 close back beyond the M1 kijun. Both close  |
//|        after 90 M1 bars                                           |
//| Study (HistData M1, 8 markets, 2023 - Sep 2026): NO EDGE. Every   |
//|        trigger is ~0R before costs and -0.11 to -0.16R after;     |
//|        kihon windows are no better than other hours or than 200   |
//|        shifted placebo timetables. Built for an MT5 check only    |
//| Author: Neo Malesa                                               |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

enum TriggerMode
{
   TRIG_M5_BREAK    = 0,   // M5 turns clear of the kumo (price + chikou), M1 clear
   TRIG_M1_BREAK    = 1,   // M1 turns clear of the kumo (price + chikou), M5 clear
   TRIG_CANDLE_OPEN = 2    // M1 and M5 clear at the first minute of an M15 candle
};

enum ExitMode
{
   EXIT_TARGET = 0,   // Take profit at InpTargetR x risk
   EXIT_KIJUN  = 1    // Close on an M1 close back beyond the M1 kijun
};

//--- Input Parameters ---
input string      Symbols    = "GOLDm#";
input TriggerMode InpTrigger = TRIG_M5_BREAK;
input int         Tenkan     = 9;
input int         Kijun      = 26;
input int         SenkouB    = 52;
input int         Slippage   = 30;

input group  "Kihon Time (day candles counted from the D1 open)"
input bool   InpKihonGate = true;   // Only trade inside kihon candles (off = every hour, the control run)
input bool   InpKihonM15  = true;   // M15 candles 9, 17, 26, 33, 42, 51, 65, 76
input bool   InpKihonM30  = true;   // M30 candles 9, 17, 26, 33, 42
input bool   InpKihonH1   = true;   // H1 candles 9, 17
input int    InpKihonTol  = 0;      // Candles either side of the number (0 = on it, as tested)

input group  "Stop Loss"
input int    InpATRPeriod      = 14;    // ATR period (M1 and M5)
input double InpStopBufferATR  = 0.2;   // Stop sits this x ATR beyond the kijun / cloud edge
input double InpMinRiskATR     = 0.25;  // Skip when entry-to-stop is under this x ATR(M5)
input double InpMaxRiskATR     = 3.0;   // Skip when entry-to-stop is over this x ATR(M5)
input double InpMinRiskSpreads = 3.0;   // ...or under this many spreads

input group  "Exit"
input ExitMode InpExitMode    = EXIT_TARGET;
input double   InpTargetR     = 1.5;   // EXIT_TARGET: take profit at this multiple of the risk
input int      InpMaxHoldBars = 90;    // Close after this many M1 bars (0 = off)

input group  "Risk"
input double InpRiskPct         = 0.5;   // % of equity lost if the stop is hit
input bool   InpUseFixedLots    = false; // Trade InpFixedLots instead of risk sizing
input double InpFixedLots       = 0.01;
input double InpMaxMarginPct    = 80.0;  // Use at most this % of free margin
input int    InpMaxSpreadPoints = 40;    // Wait for a spread at or below this (0 = no limit)

input group  "Logging"
input bool   InpLogSkips = false;   // Log signals outside a kihon candle and risk skips

//--- Constants and Global Variables ---
#define MAX_SYMS 60

int      ich1[MAX_SYMS], ich5[MAX_SYMS];
int      atr1[MAX_SYMS], atr5[MAX_SYMS];
string   syms[MAX_SYMS];
int      symsCount = 0;
datetime lastBar[MAX_SYMS];
datetime lastBlock[MAX_SYMS][2];   // M15 candle of the last signal, [0] buy / [1] sell

// A signal read on a closed M1 bar waits here until it fills or its entry bar ends
int      pendDir[MAX_SYMS];
datetime pendBar[MAX_SYMS];
double   pendStop[MAX_SYMS];
double   pendATR[MAX_SYMS];        // ATR(M5), the unit of the risk filter
string   pendInfo[MAX_SYMS];       // the kihon candles the signal sat in
int      pendTries[MAX_SYMS];

const int KihonNums[8] = { 9, 17, 26, 33, 42, 51, 65, 76 };

int MAGIC = 20260890;   // fresh — no other EA uses this

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
      lastBar[s] = 0;
      lastBlock[s][0] = 0;
      lastBlock[s][1] = 0;
      pendDir[s] = 0;

      ich1[s] = iIchimoku(syms[s], PERIOD_M1, Tenkan, Kijun, SenkouB);
      ich5[s] = iIchimoku(syms[s], PERIOD_M5, Tenkan, Kijun, SenkouB);
      atr1[s] = iATR(syms[s], PERIOD_M1, InpATRPeriod);
      atr5[s] = iATR(syms[s], PERIOD_M5, InpATRPeriod);
      if(ich1[s] == INVALID_HANDLE || ich5[s] == INVALID_HANDLE ||
         atr1[s] == INVALID_HANDLE || atr5[s] == INVALID_HANDLE) return(INIT_FAILED);
   }

   trade.SetDeviationInPoints(Slippage);
   trade.SetExpertMagicNumber(MAGIC);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   for(int s = 0; s < symsCount; s++)
   {
      if(ich1[s] != INVALID_HANDLE) IndicatorRelease(ich1[s]);
      if(ich5[s] != INVALID_HANDLE) IndicatorRelease(ich5[s]);
      if(atr1[s] != INVALID_HANDLE) IndicatorRelease(atr1[s]);
      if(atr5[s] != INVALID_HANDLE) IndicatorRelease(atr5[s]);
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
// Kihon time. A candle of 'tf' is on a kihon number when its count
// from the D1 open is within InpKihonTol of one a day can reach
// (M15 up to 76, M30 up to 42, H1 up to 17). Counting is §49's:
// inclusive, Bars() over [day open, t], so the candle at the open
// is candle 1. 't' is the signal bar's open time.
//==============================================================

bool KihonTf(string sym, ENUM_TIMEFRAMES tf, string name, datetime dayOpen, datetime t, string &info)
{
   int n = Bars(sym, tf, dayOpen, t);
   if(n <= 0) return false;                    // history not ready: no window
   int reach = 86400 / PeriodSeconds(tf);
   for(int i = 0; i < 8; i++)
   {
      if(KihonNums[i] > reach) break;
      if(MathAbs(n - KihonNums[i]) <= InpKihonTol)
      {
         info += (info == "" ? "" : " ") + name + ":" + IntegerToString(n);
         return true;
      }
   }
   return false;
}

bool InKihon(string sym, datetime t, string &info)
{
   info = "";
   if(!InpKihonGate) { info = "gate off"; return true; }
   int dshift = iBarShift(sym, PERIOD_D1, t);
   datetime dayOpen = (dshift >= 0) ? iTime(sym, PERIOD_D1, dshift) : 0;
   if(dayOpen <= 0) return false;
   bool hit = false;
   if(InpKihonM15 && KihonTf(sym, PERIOD_M15, "M15", dayOpen, t, info)) hit = true;
   if(InpKihonM30 && KihonTf(sym, PERIOD_M30, "M30", dayOpen, t, info)) hit = true;
   if(InpKihonH1  && KihonTf(sym, PERIOD_H1,  "H1",  dayOpen, t, info)) hit = true;
   return hit;
}

//==============================================================
// Kumo clearance on one timeframe at closed bar p: 1 when the close
// is above tenkan, kijun and the cloud under it AND above the high,
// tenkan, kijun and cloud of the bar Kijun back (the chikou is
// free); -1 for the mirror; 0 otherwise. Fills kijun and the cloud
// edges at p for the stop. MT5's Senkou buffers are pre-shifted:
// the value at shift p is the cloud drawn under bar p.
//==============================================================

int ClearDir(string sym, ENUM_TIMEFRAMES tf, int h, int p, double &kjP, double &topP, double &botP)
{
   int q = p + Kijun;
   int need = q + 1;
   double cl[], hi[], lo[], tk[], kj[], sa[], sb[];
   if(CopyClose(sym, tf, 0, need, cl) < need) return 0;
   if(CopyHigh(sym, tf, 0, need, hi) < need) return 0;
   if(CopyLow(sym, tf, 0, need, lo) < need) return 0;
   if(CopyBuffer(h, 0, 0, need, tk) < need) return 0;
   if(CopyBuffer(h, 1, 0, need, kj) < need) return 0;
   if(CopyBuffer(h, 2, 0, need, sa) < need) return 0;
   if(CopyBuffer(h, 3, 0, need, sb) < need) return 0;
   ArraySetAsSeries(cl, true); ArraySetAsSeries(hi, true); ArraySetAsSeries(lo, true);
   ArraySetAsSeries(tk, true); ArraySetAsSeries(kj, true);
   ArraySetAsSeries(sa, true); ArraySetAsSeries(sb, true);

   double c = cl[p];
   topP = MathMax(sa[p], sb[p]);
   botP = MathMin(sa[p], sb[p]);
   kjP  = kj[p];
   double topQ = MathMax(sa[q], sb[q]), botQ = MathMin(sa[q], sb[q]);

   bool pxL = c > MathMax(tk[p], MathMax(kj[p], topP));
   bool pxS = c < MathMin(tk[p], MathMin(kj[p], botP));
   bool chL = c > MathMax(MathMax(hi[q], tk[q]), MathMax(kj[q], topQ));
   bool chS = c < MathMin(MathMin(lo[q], tk[q]), MathMin(kj[q], botQ));
   if(pxL && chL) return 1;
   if(pxS && chS) return -1;
   return 0;
}

//==============================================================
// Signal on the M1 bar that just closed (shift 1). Returns 1 / -1
// and fills the stop and ATR(M5); 0 otherwise.
//==============================================================

int CheckSignal(int s, double &stop, double &atrVal, string &info)
{
   string sym = syms[s];
   datetime t1 = iTime(sym, PERIOD_M1, 1);
   if(t1 == 0) return 0;

   double k1 = 0, top1 = 0, bot1 = 0, k5 = 0, top5 = 0, bot5 = 0, d1 = 0, d2 = 0, d3 = 0;
   int dir = 0;
   bool useM5Stop = false;

   if(InpTrigger == TRIG_M5_BREAK)
   {
      // only on the M1 bar that closed an M5 bar
      if(iTime(sym, PERIOD_M5, 0) != iTime(sym, PERIOD_M1, 0)) return 0;
      int c5 = ClearDir(sym, PERIOD_M5, ich5[s], 1, k5, top5, bot5);
      if(c5 == 0 || ClearDir(sym, PERIOD_M5, ich5[s], 2, d1, d2, d3) == c5) return 0;
      if(ClearDir(sym, PERIOD_M1, ich1[s], 1, k1, top1, bot1) != c5) return 0;
      dir = c5;
      useM5Stop = true;
   }
   else
   {
      int c1 = ClearDir(sym, PERIOD_M1, ich1[s], 1, k1, top1, bot1);
      if(c1 == 0) return 0;
      if(InpTrigger == TRIG_M1_BREAK)
      {
         if(ClearDir(sym, PERIOD_M1, ich1[s], 2, d1, d2, d3) == c1) return 0;
      }
      else if(t1 % (15 * 60) != 0) return 0;          // TRIG_CANDLE_OPEN
      if(ClearDir(sym, PERIOD_M5, ich5[s], 1, k5, top5, bot5) != c1) return 0;
      dir = c1;
   }

   // one signal per side per M15 candle
   datetime blk = (datetime)(t1 - t1 % (15 * 60));
   int side = (dir == 1) ? 0 : 1;
   if(lastBlock[s][side] == blk) return 0;

   if(!InKihon(sym, t1, info))
   {
      if(InpLogSkips) Print(PCTime() + " | " + sym + (dir == 1 ? " buy" : " sell") + " signal outside a kihon candle — no trade");
      return 0;
   }
   lastBlock[s][side] = blk;

   double a5[1], a1[1];
   if(CopyBuffer(atr5[s], 0, 1, 1, a5) <= 0 || a5[0] <= 0) return 0;
   atrVal = a5[0];
   double a = 0, kj = 0, top = 0, bot = 0;
   if(useM5Stop) { a = a5[0]; kj = k5; top = top5; bot = bot5; }
   else
   {
      if(CopyBuffer(atr1[s], 0, 1, 1, a1) <= 0 || a1[0] <= 0) return 0;
      a = a1[0]; kj = k1; top = top1; bot = bot1;
   }
   stop = (dir == 1) ? MathMin(kj, bot) - InpStopBufferATR * a
                     : MathMax(kj, top) + InpStopBufferATR * a;
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

   double price  = isBuy ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID);
   double spread = SymbolInfoDouble(sym, SYMBOL_ASK) - SymbolInfoDouble(sym, SYMBOL_BID);
   double risk   = (price - pendStop[s]) * dir;
   double minRisk = MathMax(InpMinRiskATR * pendATR[s], InpMinRiskSpreads * spread);
   if(risk < minRisk || risk > InpMaxRiskATR * pendATR[s])
   {
      if(InpLogSkips) Print(PCTime() + " | " + sym + " kihon scalp skipped — entry-to-stop " + DoubleToString(risk / pendATR[s], 2) + " x ATR(M5) is out of range");
      return true;
   }

   int    digits  = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double point   = SymbolInfoDouble(sym, SYMBOL_POINT);
   double minDist = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * point;
   if(risk < minDist)
   {
      if(InpLogSkips) Print(PCTime() + " | " + sym + " kihon scalp skipped — stop inside the broker minimum");
      return true;
   }
   double sl = NormalizeDouble(pendStop[s], digits);
   double tp = (InpExitMode == EXIT_TARGET) ? NormalizeDouble(price + dir * InpTargetR * risk, digits) : 0.0;
   double lots = SizeLots(sym, isBuy, price, risk);

   trade.SetTypeFillingBySymbol(sym);
   string cmt = "Kihon " + pendInfo[s];
   bool ok = isBuy ? trade.Buy(lots, sym, price, sl, tp, cmt)
                   : trade.Sell(lots, sym, price, sl, tp, cmt);
   if(!ok)
   {
      pendTries[s]++;
      bool giveUp = pendTries[s] >= 3;
      Print(PCTime() + " | " + sym + " kihon scalp order failed, retcode " + IntegerToString(trade.ResultRetcode()) +
            (giveUp ? " — giving up on this signal" : " — will retry"));
      return giveUp;
   }

   string msg = PCTime() + " | " + (isBuy ? "Buy " : "Sell ") + sym + " @ " + DoubleToString(lots, 2) +
                " (" + EnumToString(InpTrigger) + " in " + pendInfo[s] + ", risk " +
                DoubleToString(risk / pendATR[s], 2) + " x ATR M5)";
   Print(msg); SendNotification(msg);
   return true;
}

// Kijun-close exit (EXIT_KIJUN) and the time stop, read on the last closed M1 bar
void CheckExit(int s, ulong ticket)
{
   string sym = syms[s];
   if(!PositionSelectByTicket(ticket)) return;
   int dir = ((int)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
   int held = iBarShift(sym, PERIOD_M1, (datetime)PositionGetInteger(POSITION_TIME));
   string reason = "";

   if(InpMaxHoldBars > 0 && held >= InpMaxHoldBars)
      reason = "held " + IntegerToString(held) + " M1 bars";
   // the entry bar itself is not judged, as in the study
   if(reason == "" && InpExitMode == EXIT_KIJUN && held >= 2)
   {
      double kj[1];
      double c1 = iClose(sym, PERIOD_M1, 1);
      if(CopyBuffer(ich1[s], 1, 1, 1, kj) > 0 && c1 > 0 &&
         ((dir == 1 && c1 < kj[0]) || (dir == -1 && c1 > kj[0])))
         reason = "M1 close back beyond the kijun";
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
      datetime bar0 = iTime(sym, PERIOD_M1, 0);
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
            double stop = 0, atrVal = 0;
            string info;
            int dir = CheckSignal(s, stop, atrVal, info);
            if(dir != 0)
            {
               pendDir[s]   = dir;
               pendBar[s]   = bar0;
               pendStop[s]  = stop;
               pendATR[s]   = atrVal;
               pendInfo[s]  = info;
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
//Fear God and Live
