//+------------------------------------------------------------------+
//| Ichimoku H4-M1 Alignment EA (PO3)                                |
//| Entry: H4→M1 price+chikou all above/below tenkan,kijun,cloud,   |
//|        location-filtered by PO3 dealing ranges (room + bias)     |
//| Exit:  tiered TPs on PO3 levels for half the batch; remainder    |
//|        closes on M15 kijun cross or ATR-based protective stop    |
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

input group  "PO3 Dealing Ranges"
input bool   InpUsePO3         = true;   // Use PO3 dealing-range levels for TPs and entry filters
input double InpPO3Unit        = 1.0;    // Price per PO3 unit (1.0 = whole dollars on gold)
input int    InpPO3BasePower   = 4;      // Base rung: 3^4 = 81 units
input int    InpPO3StrongPower = 5;      // Strong level: 3^5 = 243 units
input double InpPO3MinRR       = 1.5;    // Min reward:risk for a level to qualify as a TP
input double InpPO3MaxRR       = 8.0;    // Levels beyond this R are ignored (runner instead)
input double InpPO3BufferATR   = 0.25;   // Front-run TP buffer = ATR(M15) * this
input bool   InpPO3RoomFilter  = true;   // Skip entries without MinRR room to next strong level
input bool   InpPO3BiasFilter  = true;   // Block entries against a recent major-level rejection
input int    InpPO3BiasPower   = 6;      // Major level for the bias filter: 3^6 = 729 units
input int    InpPO3BiasBars    = 180;    // H4 bars scanned for a major-level rejection
input double InpPO3BiasTolFrac = 0.4;    // Rejection tag tolerance, fraction of the base rung

input group             "Equity Alert Settings"
input double            InpMinProfitTrigger  = 5.0;        // Min Profit over Baseline to trigger alert
input double            InpWithdrawProfitPct = 50.0;       // Percentage of the PROFIT to withdraw
input ENUM_DAY_OF_WEEK  InpCheckDay          = FRIDAY;     // Day of the week to check
input bool              InpResetBaseline     = false;      // Set to true to reset baseline to current equity
input bool              InpSendPush          = true;       // Send push notification

//--- Constants and Global Variables ---
#define MAX_SYMS  60
#define TF_COUNT  6
#define IDX_M15   3   // index of M15 in tfs[] — used for exit check

ENUM_TIMEFRAMES tfs[TF_COUNT] = {
   PERIOD_H4, PERIOD_H1, PERIOD_M30, PERIOD_M15, PERIOD_M5, PERIOD_M1
};

int      ich[MAX_SYMS][TF_COUNT];
int      atr[MAX_SYMS];
string   syms[MAX_SYMS];
int      symsCount = 0;
datetime lastM1bar[MAX_SYMS];
datetime lastH4bar = 0;
int      state[MAX_SYMS];   // 0=no position, 1=long, -1=short
string   lastBlock[MAX_SYMS];   // last PO3 block reason printed, per symbol (anti-spam)

int MAGIC = 20260502;   // distinct from the pre-PO3 H4-M1 EA so both can run on one account

#define GV_BASE_EQUITY    "EA_EquityAlert_Base_"    + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))
#define GV_LAST_ALERT_DAY "EA_EquityAlert_Day_"     + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))

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

int OnInit()
{
   symsCount = ParseSymbols(Symbols);
   if(symsCount <= 0) return(INIT_FAILED);

   for(int s = 0; s < symsCount; s++)
   {
      state[s] = 0;
      lastM1bar[s] = 0;
      lastBlock[s] = "";
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
      for(int t = 0; t < TF_COUNT; t++)
         IndicatorRelease(ich[s][t]);
      if(atr[s] != INVALID_HANDLE) IndicatorRelease(atr[s]);
   }
}

//==============================================================
// Position State Sync (recover after restart)
//==============================================================

void SyncStateFromPositions()
{
   // Rebuild from scratch so positions closed by SL or manually free the
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
// Alignment Check: price and chikou both above/below tenkan,
// kijun, and cloud. Returns 1 (bullish), -1 (bearish), 0 (none)
//==============================================================

int CheckAlign(int s, int tfIdx)
{
   ENUM_TIMEFRAMES tf = tfs[tfIdx];

   MqlRates rt[];
   if(CopyRates(syms[s], tf, 0, 120, rt) <= 0) return 0;
   ArraySetAsSeries(rt, true);

   int sh      = 1;              // last closed bar
   int chShift = sh + Kijun;     // chikou's chart position for bar sh (Kijun bars back)
   int chCloud = chShift + Kijun;// senkou buffer offset for the cloud at chikou's position

   if(ArraySize(rt) <= chCloud) return 0;

   double tenkan[1], kijun[1], senA[1], senB[1];
   double tenkan_ch[1], kijun_ch[1], senA_ch[1], senB_ch[1];

   // price bar sh: tenkan, kijun, cloud
   if(CopyBuffer(ich[s][tfIdx], 0, sh,         1, tenkan)    <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 1, sh,         1, kijun)     <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 2, sh + Kijun, 1, senA)      <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 3, sh + Kijun, 1, senB)      <= 0) return 0;
   // tenkan, kijun, cloud at chikou's chart position
   if(CopyBuffer(ich[s][tfIdx], 0, chShift,    1, tenkan_ch) <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 1, chShift,    1, kijun_ch)  <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 2, chCloud,    1, senA_ch)   <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 3, chCloud,    1, senB_ch)   <= 0) return 0;

   double closeP = rt[sh].close;
   // The chikou span for bar sh IS its close, plotted Kijun bars back.
   // Compare it against the candle and Ichimoku levels at that chart position.
   double chik   = closeP;
   double cHi    = MathMax(senA[0], senB[0]);
   double cLo    = MathMin(senA[0], senB[0]);
   double cHiC   = MathMax(senA_ch[0], senB_ch[0]);
   double cLoC   = MathMin(senA_ch[0], senB_ch[0]);

   // bullish: price above tenkan, kijun, and cloud; chikou clear above price,
   // tenkan, kijun, and cloud at its plotted position
   if(closeP > tenkan[0] && closeP > kijun[0] && closeP > cHi &&
      chik > rt[chShift].high &&
      chik > tenkan_ch[0] && chik > kijun_ch[0] && chik > cHiC) return  1;

   // bearish: price below tenkan, kijun, and cloud; chikou clear below price,
   // tenkan, kijun, and cloud at its plotted position
   if(closeP < tenkan[0] && closeP < kijun[0] && closeP < cLo &&
      chik < rt[chShift].low &&
      chik < tenkan_ch[0] && chik < kijun_ch[0] && chik < cLoC) return -1;

   return 0;
}

//==============================================================
// Entry Check: all timeframes (H4→M1) aligned same direction
//==============================================================

int CheckAllAlign(int s)
{
   int dir = CheckAlign(s, 0);
   if(dir == 0) return 0;

   for(int t = 1; t < TF_COUNT; t++)
   {
      if(CheckAlign(s, t) != dir) return 0;
   }
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
// Risk Management
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
// PO3 Dealing Ranges (Hopiplaka)
// Levels are fixed multiples of 3^n price units — on gold the 81
// grid is ...3888, 3969, 4050... with every level whose multiple
// carries a higher power of 3 outranking its neighbours (3888 =
// 16*3^5 is a 243-grade level, 4374 = 2*3^7 a 2187-grade one).
// floor(price/step)*step bounds the current dealing range; its
// midpoint is equilibrium, the lower half discount, the upper
// half premium. Ichimoku alignment decides WHEN to trade; PO3
// decides WHERE it's worth trading and HOW FAR to hold.
//==============================================================

double PO3Step(int power)
{
   return MathPow(3.0, power) * InpPO3Unit;
}

// First multiple of `step` strictly beyond `price` in direction `dir`
double PO3NextLevel(double price, int dir, double step)
{
   double k = MathFloor(price / step + 1e-9);
   if(dir > 0) return (k + 1.0) * step;
   return (k * step < price - 1e-9) ? k * step : (k - 1.0) * step;
}

// Walk levels of size 3^sigPower beyond `from` in direction `dir` and
// return the first whose buffered reward lands in [MinRR, MaxRR] * the
// stop distance — past `beyond`, when given, so TP2 clears TP1's level.
// Returns 0 when nothing qualifies: that order stays a kijun-trailed runner.
double PO3PickTarget(double from, int dir, int sigPower, double stopDist,
                     double buffer, double beyond)
{
   double step = PO3Step(sigPower);
   double lvl  = PO3NextLevel(from, dir, step);
   for(int i = 0; i < 64; i++, lvl += dir * step)
   {
      if(beyond > 0 && ((dir > 0) ? (lvl <= beyond + 1e-9)
                                  : (lvl >= beyond - 1e-9))) continue;
      double reward = MathAbs(lvl - from) - buffer;
      if(reward > InpPO3MaxRR * stopDist) return 0.0;
      if(reward < InpPO3MinRR * stopDist) continue;
      return lvl;
   }
   return 0.0;
}

// Premium/discount position inside the strong-grade dealing range
string PO3RangeInfo(double price)
{
   double step = PO3Step(InpPO3StrongPower);
   double lo   = MathFloor(price / step + 1e-9) * step;
   double pct  = (price - lo) / step * 100.0;
   string zone = (pct > 55.0) ? "premium" : ((pct < 45.0) ? "discount" : "equilibrium");
   return StringFormat("PO3 %g[%g-%g] %.0f%% %s", step, lo, lo + step, pct, zone);
}

// The first strong-grade level ahead is where the move is most likely to
// stall — entering with less than MinRR of room to it is a poor-geometry
// trade regardless of how clean the Ichimoku alignment looks.
bool PO3RoomOK(double entry, int dir, double stopDist, double buffer)
{
   double lvl  = PO3NextLevel(entry, dir, PO3Step(InpPO3StrongPower));
   double room = MathAbs(lvl - entry) - buffer;
   return room >= InpPO3MinRR * stopDist;
}

// Detects price "acting off" a major PO3 level: when the H4 lookback
// extreme tagged (or raided) a 3^BiasPower-grade level and price has since
// been rejected back away from it, only trades away from that level are
// allowed. Returns -1 (shorts only), +1 (longs only), or 0 (no bias).
// A rejection stops binding as soon as price reclaims the level, and a
// newer opposite-side tag supersedes an older one.
int PO3Bias(int s)
{
   double step = PO3Step(InpPO3BiasPower);
   double tol  = InpPO3BiasTolFrac * PO3Step(InpPO3BasePower);

   MqlRates rt[];
   int n = CopyRates(syms[s], PERIOD_H4, 1, InpPO3BiasBars, rt);
   if(n <= 0) return 0;
   ArraySetAsSeries(rt, true);

   int hhI = 0, llI = 0;
   for(int i = 1; i < n; i++)
   {
      if(rt[i].high > rt[hhI].high) hhI = i;
      if(rt[i].low  < rt[llI].low)  llI = i;
   }
   double close0 = rt[0].close;

   double hLvl = MathRound(rt[hhI].high / step) * step;
   bool   hTag = (MathAbs(rt[hhI].high - hLvl) <= tol) && (close0 < hLvl - tol);

   double lLvl = MathRound(rt[llI].low / step) * step;
   bool   lTag = (MathAbs(rt[llI].low - lLvl) <= tol) && (close0 > lLvl + tol);

   if(hTag && lTag) return (hhI < llI) ? -1 : 1;   // series order: lower index = newer
   if(hTag) return -1;
   if(lTag) return  1;
   return 0;
}

// Print a block reason once per streak instead of once per M1 bar
void BlockNote(int s, string reason)
{
   string msg = syms[s] + ": entry blocked (" + reason + ")";
   if(msg == lastBlock[s]) return;
   lastBlock[s] = msg;
   Print(msg);
}

//==============================================================
// Trading Functions
//==============================================================

bool SpreadOK(string sym)
{
   if(InpMaxSpreadPoints <= 0) return true;
   return SymbolInfoInteger(sym, SYMBOL_SPREAD) <= InpMaxSpreadPoints;
}

bool GetATRValue(int s, double &val)
{
   val = 0.0;
   if(atr[s] == INVALID_HANDLE) return false;
   double a[1];
   if(CopyBuffer(atr[s], 0, 1, 1, a) <= 0 || a[0] <= 0) return false;
   val = a[0];
   return true;
}

// ATR(M15) * multiplier, widened to the broker's minimum stop distance if
// needed. Returns false when the ATR value is unavailable so the caller
// skips the entry instead of trading unprotected.
bool GetStopDistance(int s, double &dist)
{
   dist = 0.0;
   double a = 0.0;
   if(!GetATRValue(s, a)) return false;

   dist = a * InpATRMultiplier;
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

// Drop a TP that sits on the wrong side of price or inside the broker's
// minimum stop distance — such a level failed the RR gate anyway.
double NormalizeTP(int s, bool isBuy, double price, double tp)
{
   if(tp <= 0) return 0.0;
   if((isBuy && tp <= price) || (!isBuy && tp >= price)) return 0.0;

   double point   = SymbolInfoDouble(syms[s], SYMBOL_POINT);
   double minDist = SymbolInfoInteger(syms[s], SYMBOL_TRADE_STOPS_LEVEL) * point;
   if(MathAbs(tp - price) < minDist) return 0.0;

   int digits = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);
   return NormalizeDouble(tp, digits);
}

// Alternate the batch between the two PO3 target tiers: even-indexed
// orders bank at TP1 (nearest qualifying base rung), odd-indexed at TP2
// (nearest qualifying strong level beyond it). A zero TP leaves that
// order as a runner managed by the M15 kijun exit.
int OpenPositions(int s, bool isBuy, double dist, int count, double lots,
                  double tp1, double tp2)
{
   string sym = syms[s];

   trade.SetExpertMagicNumber(MAGIC);

   int filled = 0;
   for(int i = 0; i < count; i++)
   {
      double price = isBuy ? SymbolInfoDouble(sym, SYMBOL_ASK)
                           : SymbolInfoDouble(sym, SYMBOL_BID);
      double sl = InpUseStopLoss ? BuildStopLoss(s, isBuy, price, dist) : 0.0;
      double tp = NormalizeTP(s, isBuy, price, (i % 2 == 0) ? tp1 : tp2);

      bool ok = isBuy ? trade.Buy(lots,  sym, price, sl, tp, "Buy H4-M1")
                      : trade.Sell(lots, sym, price, sl, tp, "Sell H4-M1");
      if(!ok) break;   // out of margin or rejected — don't hammer the server
      filled++;
   }
   return filled;
}

// Ichimoku said "go" — PO3 now decides whether the location is worth it
// (bias + room filters) and supplies the tiered targets before the batch
// is opened.
void TryEnter(int s, int st)
{
   bool   isBuy = (st == 1);
   string sym   = syms[s];

   double dist = 0.0;
   if(InpUseStopLoss && !GetStopDistance(s, dist)) return;   // ATR unavailable — skip entry

   // PO3 RR gating needs a stop distance to measure reward against; without
   // one (InpUseStopLoss off) only the bias filter stays active.
   double atrVal = 0.0, buffer = 0.0;
   bool po3 = InpUsePO3 && dist > 0 && GetATRValue(s, atrVal);
   if(po3) buffer = atrVal * InpPO3BufferATR;

   double entry = isBuy ? SymbolInfoDouble(sym, SYMBOL_ASK)
                        : SymbolInfoDouble(sym, SYMBOL_BID);

   if(InpUsePO3 && InpPO3BiasFilter)
   {
      int bias = PO3Bias(s);
      if(bias != 0 && bias != st)
      {
         BlockNote(s, "against major PO3 level rejection");
         return;
      }
   }
   if(po3 && InpPO3RoomFilter && !PO3RoomOK(entry, st, dist, buffer))
   {
      BlockNote(s, "no room to next strong PO3 level");
      return;
   }
   lastBlock[s] = "";

   double tp1 = 0.0, tp2 = 0.0;
   if(po3)
   {
      double lvl1 = PO3PickTarget(entry, st, InpPO3BasePower,   dist, buffer, 0.0);
      double lvl2 = PO3PickTarget(entry, st, InpPO3StrongPower, dist, buffer, lvl1);
      if(lvl1 > 0) tp1 = lvl1 - st * buffer;   // front-run the level
      if(lvl2 > 0) tp2 = lvl2 - st * buffer;
   }

   int count; double lots;
   GetEquityRisk(sym, dist, count, lots);

   string action = isBuy ? "Buy" : "Sell";
   string msg = PCTime() + " | " + action + " " + sym +
                " x" + IntegerToString(count) +
                " @ " + DoubleToString(lots, 2) + " (H4-M1)";
   if(InpUsePO3)
   {
      msg += " | " + PO3RangeInfo(entry) +
             " | TP1 " + (tp1 > 0 ? DoubleToString(tp1, 2) : "runner") +
             " TP2 "   + (tp2 > 0 ? DoubleToString(tp2, 2) : "runner");
   }
   Print(msg); Alert(msg); SendNotification(msg);

   // Track state if any order filled — keeps exit logic and re-entry
   // guard correct even when only some of the orders go through.
   if(OpenPositions(s, isBuy, dist, count, lots, tp1, tp2) > 0)
      state[s] = st;
}

void ClosePositions(string sym)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) == sym &&
         (int)PositionGetInteger(POSITION_MAGIC) == MAGIC)
      {
         trade.PositionClose(ticket);
      }
   }
}

//==============================================================
// Main Loop
//==============================================================

void OnTick()
{
   // Equity alert: fire only on a new H4 bar (CheckEquityAlert self-guards on day-of-week)
   MqlRates h4[];
   if(symsCount > 0 && CopyRates(syms[0], PERIOD_H4, 0, 1, h4) > 0 && h4[0].time != lastH4bar)
   {
      lastH4bar = h4[0].time;
      CheckEquityAlert();
   }

   SyncStateFromPositions();

   for(int s = 0; s < symsCount; s++)
   {
      // Per-symbol M1 bar gating — only act on a new closed M1 bar for this symbol
      MqlRates m1[];
      if(CopyRates(syms[s], PERIOD_M1, 0, 2, m1) <= 0) continue;
      ArraySetAsSeries(m1, true);
      if(m1[1].time == lastM1bar[s]) continue;
      lastM1bar[s] = m1[1].time;

      // Exit check: close all when M15 closes against direction across M15 kijun
      if(state[s] != 0 && CheckM15Exit(s, state[s]))
      {
         string side = (state[s] == 1) ? "Long" : "Short";
         string msg  = PCTime() + " | Close " + syms[s] + " " + side + " (M15 kijun crossed)";
         Print(msg); Alert(msg); SendNotification(msg);

         ClosePositions(syms[s]);
         state[s] = 0;
      }

      // Entry check: all timeframes H4→M1 must align, spread must be sane,
      // and the PO3 location filters must approve before orders go out.
      if(state[s] == 0 && SpreadOK(syms[s]))
      {
         int st = CheckAllAlign(s);
         if(st != 0) TryEnter(s, st);
      }
   }
}
//This work is my worship unto GOD
