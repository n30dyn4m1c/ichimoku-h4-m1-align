//+------------------------------------------------------------------+
//| Ichimoku Kumo Breakout EA — experimental                         |
//| Entry: price close above/below tenkan, kijun AND the cloud (VPS- |
//|        style alignment), the chikou span clear of tenkan, kijun  |
//|        and the cloud at its plotted position, and the kumo twist |
//|        (Senkou Span A vs Span B) agrees with the breakout         |
//|        direction                                                  |
//| Flat filter: at the point of breakout, before opening, the kijun |
//|        must be sloping — a flat kijun (move over InpFlatBars <=  |
//|        InpFlatATRMult * ATR(M1)) skips the trade and waits; the  |
//|        trade only opens once the kijun is angled in the breakout |
//|        direction, the cloud is thick (Span A - Span B >=          |
//|        InpMinCloudATR * ATR(M1)), and the future cloud (the       |
//|        Senkou spans drawn Kijun bars ahead) is angled in the      |
//|        breakout direction too                                     |
//| Momentum: ADX(51) with key levels 9, 17 and 26 — at the breakout |
//|        the DI in the trade direction must sit in the window       |
//|        (17, 26] (below 17 = too weak, above 26 = overextended,    |
//|        no trade) and dominate the other DI (+DI > -DI for a buy,  |
//|        -DI > +DI for a sell); the +DI/-DI lines must have crossed |
//|        exactly once over the last 9 periods — no crossover = no   |
//|        setup, more than one = consolidation, no trade             |
//| Exit:  close when the trade-direction DI crosses back over the    |
//|        other DI line (+DI/-DI cross back); ATR(M1) stop loss as   |
//|        the only other way out                                     |
//| Risk:  one fixed position (InpFixedLots, default 0.10) instead of |
//|        the equity-tiered ladder by default — flip InpUseFixedLots |
//|        for the VPS ladder sizing; ATR(M1) stop loss on every      |
//|        order, spread filter, re-entry cooldown; exits are         |
//|        verified so failed closes retry                            |
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

input group  "Cloud Thickness"
input double InpMinCloudATR = 0.5;   // Cloud width |Span A - Span B| must be >= this * ATR(M1) to open

input group  "Position Sizing"
input bool   InpUseFixedLots  = true;   // Trade one fixed position instead of the equity-tiered ladder
input double InpFixedLots     = 0.10;   // Fixed lot size for the single position

input group  "ADX Filter (key levels 9, 17, 26)"
input int    InpADXPeriod   = 51;   // ADX period (M1)
input int    InpADXWindow9  = 9;    // Key level 9: +DI/-DI crossover-count window (periods)
input double InpADXLevel17  = 17.0; // Key level 17: +DI (buy) / -DI (sell) must exceed this at the breakout
input int    InpADXLevel26  = 26;   // Key level 26: +DI (buy) / -DI (sell) above this = overextended — no trade

input group  "Logging"
input bool   InpLogSkips     = true;  // Log skipped entries (flat detected / kijun not angled)

//--- Constants and Global Variables ---
#define MAX_SYMS  60
#define TF_M1     PERIOD_M1   // single-timeframe build — everything reads M1

int      ich[MAX_SYMS];   // iIchimoku(M1) handle per symbol
int      atr[MAX_SYMS];   // iATR(M1) handle per symbol
int      adx[MAX_SYMS];   // iADX(M1) handle per symbol — tier filter that picks the exit
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

      adx[s] = iADX(syms[s], TF_M1, InpADXPeriod);
      if(adx[s] == INVALID_HANDLE) return(INIT_FAILED);
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
      if(adx[s] != INVALID_HANDLE) IndicatorRelease(adx[s]);
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
// Kumo Breakout Check (VPS-style alignment): price close above/
// below tenkan, kijun AND the cloud, and the chikou span clear of
// tenkan, kijun AND the cloud at its plotted position, with the
// kumo twist agreeing. Returns 1 (bullish), -1 (bearish), 0 (none).
// Read on the last closed M1 bar.
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

   double tenkan[1], kijun[1], senA[1], senB[1];
   double tenkan_ch[1], kijun_ch[1], senA_ch[1], senB_ch[1];
   if(CopyBuffer(ich[s], 0, sh,      1, tenkan)    <= 0) return 0;
   if(CopyBuffer(ich[s], 1, sh,      1, kijun)     <= 0) return 0;
   if(CopyBuffer(ich[s], 2, sh,      1, senA)      <= 0) return 0;
   if(CopyBuffer(ich[s], 3, sh,      1, senB)      <= 0) return 0;
   if(CopyBuffer(ich[s], 0, chShift, 1, tenkan_ch) <= 0) return 0;
   if(CopyBuffer(ich[s], 1, chShift, 1, kijun_ch)  <= 0) return 0;
   if(CopyBuffer(ich[s], 2, chShift, 1, senA_ch)   <= 0) return 0;
   if(CopyBuffer(ich[s], 3, chShift, 1, senB_ch)   <= 0) return 0;

   double closeP = rt[sh].close;
   double cHi    = MathMax(senA[0], senB[0]);
   double cLo    = MathMin(senA[0], senB[0]);
   double cHiC   = MathMax(senA_ch[0], senB_ch[0]);
   double cLoC   = MathMin(senA_ch[0], senB_ch[0]);

   // bullish: price above tenkan, kijun and cloud; chikou (the close
   // plotted Kijun bars back) clear above tenkan, kijun and cloud at
   // its plotted position; the kumo twist agrees (Span A above Span B)
   if(closeP > tenkan[0]    && closeP > kijun[0]    && closeP > cHi &&
      closeP > tenkan_ch[0] && closeP > kijun_ch[0] && closeP > cHiC &&
      senA[0] > senB[0]) return  1;

   // bearish: mirror of the above
   if(closeP < tenkan[0]    && closeP < kijun[0]    && closeP < cLo &&
      closeP < tenkan_ch[0] && closeP < kijun_ch[0] && closeP < cLoC &&
      senA[0] < senB[0]) return -1;

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

// The cloud is "thin" when the Senkou spans are closer together than
// InpMinCloudATR * ATR(M1) — a narrow cloud is consolidation, so a
// breakout through it is skipped and waited out. Unreadable values
// count as thin (conservative) so no trade ever opens unfiltered.
bool CloudThin(int s, double atrVal)
{
   double senA[1], senB[1];
   if(CopyBuffer(ich[s], 2, 1, 1, senA) <= 0) return true;
   if(CopyBuffer(ich[s], 3, 1, 1, senB) <= 0) return true;
   return MathAbs(senA[0] - senB[0]) < InpMinCloudATR * atrVal;
}

// The future cloud (the Senkou spans drawn Kijun bars ahead of price)
// must be angled in the trade direction: from the last closed bar out
// to the far end of the drawn cloud (shift 1 - Kijun), every span's
// move must exceed InpFlatATRMult * ATR(M1) in the breakout direction.
// Unreadable values count as not angled (conservative).
bool FutureCloudAngled(int s, int dir, double atrVal)
{
   double aNow[1], bNow[1], aFar[1], bFar[1];
   if(CopyBuffer(ich[s], 2, 1,        1, aNow) <= 0) return false;
   if(CopyBuffer(ich[s], 3, 1,        1, bNow) <= 0) return false;
   if(CopyBuffer(ich[s], 2, 1 - Kijun, 1, aFar) <= 0) return false;
   if(CopyBuffer(ich[s], 3, 1 - Kijun, 1, bFar) <= 0) return false;

   double minMove = InpFlatATRMult * atrVal;
   if(dir == 1)
      return aFar[0] - aNow[0] > minMove && bFar[0] - bNow[0] > minMove;
   return aNow[0] - aFar[0] > minMove && bNow[0] - bFar[0] > minMove;
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
// ADX (period 51) filters. Key levels: 9 (crossover-count window),
// 17 (+DI/-DI strength gate), 26 (overextension cap). The trade is
// only opened when, at the breakout, the DI in the trade direction
// sits in (17, 26] and dominates the other DI, and the +DI/-DI
// lines crossed exactly once over the last 9 periods (no cross =
// no setup; more than one cross = consolidation). The exit closes
// when the DI lines cross back over again.
//==============================================================

// +DI (buy, buffer 1) or -DI (sell, buffer 2) on the last closed bar
double GetDIDir(int s, int dir)
{
   int buffer = (dir == 1) ? 1 : 2;
   double d[1];
   if(CopyBuffer(adx[s], buffer, 1, 1, d) <= 0 || d[0] <= 0) return 0.0;
   return d[0];
}

// Key level 17: at the breakout the DI in the trade direction must
// exceed 17 — a buy with +DI <= 17 or a sell with -DI <= 17 is not
// taken. Unreadable values count as 0 (block the entry).
bool DIStrong(int s, int dir)
{
   return GetDIDir(s, dir) > InpADXLevel17;
}

// Key level 26: at the breakout the DI in the trade direction must not
// be overextended — a buy with +DI > 26 or a sell with -DI > 26 is not
// taken (the move has run too far to chase).
bool DIOverextended(int s, int dir)
{
   return GetDIDir(s, dir) > InpADXLevel26;
}

// Count +DI/-DI crossovers over the last InpADXWindow9 periods.
// Returns -1 when the values can't be read.
int DICrossCount(int s)
{
   int n = MathMax(InpADXWindow9, 2);
   double dPlus[], dMinus[];
   if(CopyBuffer(adx[s], 1, 1, n, dPlus)  <= 0) return -1;
   if(CopyBuffer(adx[s], 2, 1, n, dMinus) <= 0) return -1;
   ArraySetAsSeries(dPlus, true);
   ArraySetAsSeries(dMinus, true);

   int crosses = 0;
   for(int i = 0; i < n - 1; i++)
   {
      double now  = dPlus[i]   - dMinus[i];
      double prev = dPlus[i+1] - dMinus[i+1];
      if((now >= 0 && prev < 0) || (now < 0 && prev >= 0)) crosses++;
   }
   return crosses;
}

// The trade-direction DI must dominate the other DI at entry so the
// cross-back exit is well defined — a buy needs +DI > -DI, a sell
// needs -DI > +DI. Unreadable values block the entry (conservative).
bool DIDominates(int s, int dir)
{
   double plus[1], minus[1];
   if(CopyBuffer(adx[s], 1, 1, 1, plus)  <= 0) return false;
   if(CopyBuffer(adx[s], 2, 1, 1, minus) <= 0) return false;
   return (dir == 1) ? plus[0] > minus[0] : minus[0] > plus[0];
}

// Exit: close when the trade-direction DI crosses back below the other
// DI line — a long exits on the closed bar where +DI crossed below -DI,
// a short where -DI crossed below +DI. A trade entered with the DI
// dominating is guaranteed to have this event still ahead of it.
bool CheckDICrossExit(int s, int dir)
{
   int bufMine  = (dir == 1) ? 1 : 2;
   int bufOther = (dir == 1) ? 2 : 1;
   double mine[2], other[2];
   if(CopyBuffer(adx[s], bufMine,  1, 2, mine)  <= 0) return false;
   if(CopyBuffer(adx[s], bufOther, 1, 2, other) <= 0) return false;
   // non-series copy: index 0 = previous closed bar, index 1 = last closed bar
   return mine[1] < other[1] && mine[0] >= other[0];
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

      // Exit check: close when the trade-direction DI crosses back
      // below the other DI line (a long exits when +DI crossed below
      // -DI; a short when -DI crossed below +DI)
      if(state[s] != 0)
      {
         if(CheckDICrossExit(s, state[s]))
         {
            string side = (state[s] == 1) ? "Long" : "Short";
            string di   = (state[s] == 1) ? "+DI" : "-DI";
            string msg  = PCTime() + " | Close " + syms[s] + " " + side + " (" + di + "/DI cross back)";
            Print(msg); SendNotification(msg);

            if(ClosePositions(syms[s]))
            {
               state[s] = 0;
               noReentryUntil[s] = TimeCurrent() + InpReentryCooldownSec;
            }
            else
               Print(PCTime() + " | " + syms[s] + " exit signal but positions still open — will retry");
         }
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

            if(CloudThin(s, atrVal))
            {
               if(InpLogSkips)
                  Print(PCTime() + " | " + syms[s] + " kumo breakout but cloud too thin — waiting");
               continue;
            }

            if(!FutureCloudAngled(s, dir, atrVal))
            {
               if(InpLogSkips)
               {
                  string way = (dir == 1) ? "up" : "down";
                  Print(PCTime() + " | " + syms[s] + " kumo breakout but future cloud not angled " + way + " — waiting");
               }
               continue;
            }

            if(!KijunAngled(s, dir, atrVal))
            {
               if(InpLogSkips)
               {
                  string way = (dir == 1) ? "up" : "down";
                  Print(PCTime() + " | " + syms[s] + " kumo breakout, kijun not flat but not angled " + way + " — waiting");
               }
               continue;
            }

            if(!DIStrong(s, dir))
            {
               if(InpLogSkips)
               {
                  string di = (dir == 1) ? "+DI" : "-DI";
                  Print(PCTime() + " | " + syms[s] + " kumo breakout but " + di + " at/below " + DoubleToString(InpADXLevel17, 0) + " — no trade");
               }
               continue;
            }

            if(!DIDominates(s, dir))
            {
               if(InpLogSkips)
               {
                  string di = (dir == 1) ? "+DI" : "-DI";
                  Print(PCTime() + " | " + syms[s] + " kumo breakout but " + di + " not above the other DI — no trade");
               }
               continue;
            }

            int crosses = DICrossCount(s);
            if(crosses < 0)
            {
               if(InpLogSkips)
                  Print(PCTime() + " | " + syms[s] + " ADX values unreadable — entry skipped");
               continue;
            }
            if(crosses == 0)
            {
               if(InpLogSkips)
                  Print(PCTime() + " | " + syms[s] + " kumo breakout but no +DI/-DI crossover in last " + IntegerToString(InpADXWindow9) + " periods — no trade");
               continue;
            }
            if(crosses > 1)
            {
               if(InpLogSkips)
                  Print(PCTime() + " | " + syms[s] + " kumo breakout but +DI/-DI crossed " + IntegerToString(crosses) + " times in last " + IntegerToString(InpADXWindow9) + " periods (consolidation) — no trade");
               continue;
            }

            if(DIOverextended(s, dir))
            {
               if(InpLogSkips)
               {
                  string di = (dir == 1) ? "+DI" : "-DI";
                  Print(PCTime() + " | " + syms[s] + " kumo breakout but " + di + " above " + DoubleToString(InpADXLevel26, 0) + " (overextended) — no trade");
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
            if(InpUseFixedLots)
            {
               count = 1;
               lots = InpFixedLots;
               double lotStep = SymbolInfoDouble(syms[s], SYMBOL_VOLUME_STEP);
               double lotMin  = SymbolInfoDouble(syms[s], SYMBOL_VOLUME_MIN);
               double lotMax  = SymbolInfoDouble(syms[s], SYMBOL_VOLUME_MAX);
               if(lotStep > 0) lots = MathFloor(lots / lotStep) * lotStep;
               lots = MathMax(lotMin, MathMin(lotMax, lots));
            }
            else
            {
               GetEquityRisk(syms[s], dist, count, lots);
               CapToRisk(syms[s], dist, count, lots);
               CapToMargin(syms[s], isBuy, count, lots);
            }

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
