//+------------------------------------------------------------------+
//| EXPERIMENT — M1 CHIKOU BREAKOUT TO LIQUIDITY (notes §70,          |
//| magic 20260891). One timeframe, M1, nothing above it:             |
//|   * ENTRY: a CHIKOU SPAN BREAKOUT on the last closed M1 bar, the  |
//|     live VPS build's chikou test — the chikou (that close,        |
//|     plotted Kijun bars back) above the cloud there, the candle's  |
//|     high there, and the tenkan and kijun there (below the cloud,  |
//|     the low, tenkan and kijun for a sell) — newly true: on the    |
//|     bar before it was not.                                        |
//|   * TARGET: the nearest UNRAIDED M1 liquidity level beyond the    |
//|     entry — a swing high for a buy, a swing low for a sell —      |
//|     found with the po3-levels rules (§52), the indicator on your  |
//|     chart. It is the broker-side TP. No level = no trade.         |
//|   * FREE TO MOVE: the road from the entry to that level is clear. |
//|     PRICE: the M1 tenkan, kijun and both cloud edges at the       |
//|     closed bar do not lie between the entry and the target.       |
//|     CHIKOU: across the next InpChikouFreeBars bars ahead of the   |
//|     chikou, no candle (high for a buy, low for a sell), tenkan,   |
//|     kijun or cloud edge lies between the chikou and the target.   |
//|     A line beyond the target does not block — the TP comes first.|
//|   * SL: behind the M1 kijun (default) or the far edge of the M1   |
//|     cloud, or the further of the two (InpSLMode). The level must  |
//|     be behind the entry, or there is no trade.                    |
//|   * SIZE: the §58 scalper's regime — 1% of equity below $7000,    |
//|     0.5% to $13000, 0.1% above — on the distance to the stop,     |
//|     capped to 80% of free margin.                                 |
//|   * One position per symbol; it exits only at its SL or TP.       |
//| Runs once per closed M1 bar.                                      |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

enum ENUM_SL_MODE
{
   SL_KIJUN   = 0,   // Behind the M1 kijun
   SL_CLOUD   = 1,   // Behind the far edge of the M1 cloud
   SL_FURTHER = 2    // The further of the two behind the entry
};

//--- Input Parameters ---
input string Symbols  = "GOLDm#";
input int    Tenkan   = 9;
input int    Kijun    = 26;
input int    SenkouB  = 52;
input int    Slippage = 30;

input group  "Trade"
input int    InpMaxSpreadPoints  = 60;    // Max spread in points to allow entry (0 = no limit)

input group  "Free to move"
input int    InpChikouFreeBars   = 9;     // Bars ahead of the chikou that must be clear to the target (0 = off)
input bool   InpPriceFree        = true;  // Tenkan, kijun and cloud must not lie between entry and target

input group  "Chikou breakout"
input bool   InpChikouBothLines  = true;  // Chikou beyond tenkan AND kijun 26 back (live); false = either one

input group  "Risk Management (the §58 regime, % of actual equity)"
input double InpFixedLots       = 0.10;   // Fixed lots fallback (sizing data unavailable)
input double InpRiskTier2At     = 7000.0; // Equity where risk drops to tier 2 (half regime)
input double InpRiskTier3At     = 13000.0;// Equity where risk drops to tier 3 (tiny regime)
input double InpRiskPct         = 1.0;    // Tier 1 (equity < Tier2At)
input double InpRiskPct_T2      = 0.5;    // Tier 2 (half regime)
input double InpRiskPct_T3      = 0.1;    // Tier 3 (equity >= Tier3At)
input double InpMarginUsePct    = 80.0;   // Max % of FREE margin one order may commit

input group  "Take Profit — unraided M1 liquidity (po3-levels rules)"
input int    InpLiqLeft           = 6;    // Swing: candles to the left (po3-levels default)
input int    InpLiqRight          = 6;    // Swing: candles to the right (po3-levels default)
input int    InpLiqLookback       = 100;  // M1 candles of history searched
input int    InpLiqTPOffsetPoints = 0;    // Pull the TP this many points in front of the level

input group  "Stop Loss — M1 kijun / cloud"
input ENUM_SL_MODE InpSLMode         = SL_KIJUN; // Which line the stop sits behind
input int          InpSLBufferPoints = 0;        // Push the SL this many points beyond the line

//--- Constants and Global Variables ---
#define MAX_SYMS 60

string   syms[MAX_SYMS];
int      symsCount = 0;
int      ichM1[MAX_SYMS];
datetime lastM1bar[MAX_SYMS];
string   lastSkip[MAX_SYMS];     // last skip reason printed (logged on change only)

int MAGIC = 20260891;   // M1 chikou breakout to liquidity

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
      lastM1bar[s] = 0;
      lastSkip[s]  = "";
      ichM1[s] = iIchimoku(syms[s], PERIOD_M1, Tenkan, Kijun, SenkouB);
      if(ichM1[s] == INVALID_HANDLE) return(INIT_FAILED);
   }

   trade.SetDeviationInPoints(Slippage);
   trade.SetExpertMagicNumber(MAGIC);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   for(int s = 0; s < symsCount; s++)
      IndicatorRelease(ichM1[s]);
}

//==============================================================
// The M1 picture. Series arrays, index = bar shift, read once per
// closed bar: rates, tenkan, kijun and the cloud as it is plotted
// on each bar (MT5's senkou buffers are already shifted forward).
//==============================================================

struct M1Pic
{
   MqlRates r[];
   double   tk[];
   double   kj[];
   double   sa[];
   double   sb[];
};

bool LoadPic(int s, M1Pic &p, int bars)
{
   ArraySetAsSeries(p.r,  true);
   ArraySetAsSeries(p.tk, true);
   ArraySetAsSeries(p.kj, true);
   ArraySetAsSeries(p.sa, true);
   ArraySetAsSeries(p.sb, true);
   if(CopyRates(syms[s], PERIOD_M1, 0, bars, p.r) < bars) return false;
   if(CopyBuffer(ichM1[s], 0, 0, bars, p.tk) < bars) return false;
   if(CopyBuffer(ichM1[s], 1, 0, bars, p.kj) < bars) return false;
   if(CopyBuffer(ichM1[s], 2, 0, bars, p.sa) < bars) return false;
   if(CopyBuffer(ichM1[s], 3, 0, bars, p.sb) < bars) return false;
   return true;
}

//==============================================================
// Chikou clear — the live VPS build's chikou test (CheckAlign).
// For bar sh the chikou is that bar's close, plotted Kijun bars
// back. +1 when it is above the cloud there, above the candle's
// high there, and above the tenkan and kijun there; -1 the mirror
// (below the cloud, the low, tenkan and kijun); 0 otherwise.
// InpChikouBothLines=false accepts the tenkan OR the kijun.
//==============================================================

int ChikouClear(const M1Pic &p, int sh)
{
   int    c    = sh + Kijun;
   double chik = p.r[sh].close;
   double cHi  = MathMax(p.sa[c], p.sb[c]);
   double cLo  = MathMin(p.sa[c], p.sb[c]);

   bool upTk = chik > p.tk[c], upKj = chik > p.kj[c];
   bool dnTk = chik < p.tk[c], dnKj = chik < p.kj[c];
   bool upLines = InpChikouBothLines ? (upTk && upKj) : (upTk || upKj);
   bool dnLines = InpChikouBothLines ? (dnTk && dnKj) : (dnTk || dnKj);

   if(chik > cHi && chik > p.r[c].high && upLines) return  1;
   if(chik < cLo && chik < p.r[c].low  && dnLines) return -1;
   return 0;
}

// The breakout: clear on the last closed bar, not on the one before.
int ChikouBreakout(const M1Pic &p)
{
   int now = ChikouClear(p, 1);
   if(now == 0) return 0;
   return (ChikouClear(p, 2) == now) ? 0 : now;
}

//==============================================================
// Free to move. 'v' blocks a move from 'from' to 'target' when it
// lies strictly between them — anything beyond the target is never
// reached, because the TP is.
//==============================================================

bool Blocks(double v, double from, double target)
{
   if(v == EMPTY_VALUE || v <= 0.0) return false;
   return (target > from) ? (v > from && v < target)
                          : (v < from && v > target);
}

// Price: the tenkan, kijun and both cloud edges at the closed bar.
bool PriceFree(const M1Pic &p, double entry, double target, string &why)
{
   if(!InpPriceFree) return true;
   if(Blocks(p.tk[1], entry, target)) { why = "tenkan in the way";     return false; }
   if(Blocks(p.kj[1], entry, target)) { why = "kijun in the way";      return false; }
   if(Blocks(p.sa[1], entry, target) ||
      Blocks(p.sb[1], entry, target)) { why = "cloud in the way";      return false; }
   return true;
}

// Chikou: the InpChikouFreeBars bars it will walk into next, at
// shifts Kijun, Kijun-1, ... (it sits at Kijun+1 for the closed bar).
// For a buy a candle blocks with its high, for a sell with its low.
bool ChikouFree(const M1Pic &p, int dir, double target, string &why)
{
   int n = (int)MathMin(InpChikouFreeBars, Kijun);
   if(n <= 0) return true;
   double chik = p.r[1].close;
   for(int k = 0; k < n; k++)
   {
      int c = Kijun - k;
      double candle = (dir == 1) ? p.r[c].high : p.r[c].low;
      if(Blocks(candle,  chik, target)) { why = "chikou: candle in the way"; return false; }
      if(Blocks(p.tk[c], chik, target)) { why = "chikou: tenkan in the way"; return false; }
      if(Blocks(p.kj[c], chik, target)) { why = "chikou: kijun in the way";  return false; }
      if(Blocks(p.sa[c], chik, target) ||
         Blocks(p.sb[c], chik, target)) { why = "chikou: cloud in the way";  return false; }
   }
   return true;
}

//==============================================================
// Take Profit — unraided liquidity, the po3-levels rules (§52)
// as ported in the liquidity-target build (§53). A swing high
// stands strictly above the InpLiqLeft candles before it and at
// least as high as the InpLiqRight candles after it (so of a run
// of equal highs the oldest is the swing); lows mirror it. It is
// unraided while no later wick has traded BEYOND it — the live
// candle counts, so a level taken out this minute is gone.
//==============================================================

bool LiqIsSwing(const MqlRates &r[], const int i, const bool isHigh,
                const int left, const int right)
{
   double v = isHigh ? r[i].high : r[i].low;
   for(int j = 1; j <= left; j++)                 // older: strictly beyond
   {
      double o = isHigh ? r[i + j].high : r[i + j].low;
      if(isHigh ? (v <= o) : (v >= o)) return false;
   }
   for(int j = 1; j <= right; j++)                // newer: at least as far
   {
      double o = isHigh ? r[i - j].high : r[i - j].low;
      if(isHigh ? (v < o) : (v > o)) return false;
   }
   return true;
}

// The nearest unraided level on tf in the trade's direction that lies at
// least minDist beyond 'price' — a high above for a long, a low below for a
// short. One newest-to-oldest pass carries the furthest wick since each
// candle. Returns 0.0 when there is none.
double LiqNearest(string sym, ENUM_TIMEFRAMES tf, int dir, double price, double minDist)
{
   int left  = (int)MathMax(1, InpLiqLeft);
   int right = (int)MathMax(1, InpLiqRight);
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int n = CopyRates(sym, tf, 0, (int)MathMax(left + right + 2, InpLiqLookback), r);
   if(n < left + right + 2) return 0.0;

   bool   isHigh = (dir == 1);
   double reach  = isHigh ? -DBL_MAX : DBL_MAX;
   double best   = 0.0;
   for(int i = 0; i < n; i++)
   {
      if(i > right && i + left < n && LiqIsSwing(r, i, isHigh, left, right))
      {
         double level  = isHigh ? r[i].high : r[i].low;
         bool   raided = isHigh ? (reach > level) : (reach < level);
         bool   clear  = isHigh ? (level >= price + minDist) : (level <= price - minDist);
         if(!raided && clear &&
            (best == 0.0 || (isHigh ? level < best : level > best)))
            best = level;
      }
      reach = isHigh ? MathMax(reach, r[i].high) : MathMin(reach, r[i].low);
   }
   return best;
}

//==============================================================
// Stop Loss — behind the M1 kijun or the far edge of the M1 cloud
// at the closed bar. The line must be behind the entry by at least
// minDist (below it for a buy, above it for a sell); with
// SL_FURTHER the further of the two that qualify is taken.
// 0.0 = no line behind the entry.
//==============================================================

double LineStop(const M1Pic &p, int dir, double price, double minDist)
{
   double kij = p.kj[1];
   double far = (dir == 1) ? MathMin(p.sa[1], p.sb[1]) : MathMax(p.sa[1], p.sb[1]);
   bool kOk = (dir == 1) ? (kij <= price - minDist) : (kij >= price + minDist);
   bool cOk = (dir == 1) ? (far <= price - minDist) : (far >= price + minDist);

   if(InpSLMode == SL_KIJUN) return kOk ? kij : 0.0;
   if(InpSLMode == SL_CLOUD) return cOk ? far : 0.0;
   if(kOk && cOk) return (dir == 1) ? MathMin(kij, far) : MathMax(kij, far);
   if(kOk) return kij;
   if(cOk) return far;
   return 0.0;
}

//==============================================================
// Utility Functions
//==============================================================

bool SpreadOK(string sym)
{
   if(InpMaxSpreadPoints <= 0) return true;
   return SymbolInfoInteger(sym, SYMBOL_SPREAD) <= InpMaxSpreadPoints;
}

bool HasPosition(string sym)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MAGIC) continue;
      if(PositionGetString(POSITION_SYMBOL) == sym) return true;
   }
   return false;
}

//==============================================================
// Risk Management — the §58 regime: risk a fixed % of the ACTUAL
// equity at entry, de-risking as the account grows (1% below
// InpRiskTier2At, 0.5% between the tiers, 0.1% at InpRiskTier3At
// and above), measured against the distance from the entry to the
// stop, so a stopped-out trade loses that %. The stop is placed
// first and never moved to suit the size. Falls back to
// InpFixedLots when the sizing data is unavailable; every order is
// capped to the free margin.
//==============================================================

double RiskPct()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq >= InpRiskTier3At) return InpRiskPct_T3;
   if(eq >= InpRiskTier2At) return InpRiskPct_T2;
   return InpRiskPct;
}

double RiskLots(int s, double stopDist)
{
   double riskPct = RiskPct();
   if(riskPct <= 0 || stopDist <= 0) return InpFixedLots;

   double tickValue = SymbolInfoDouble(syms[s], SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(syms[s], SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0 || tickSize <= 0) return InpFixedLots;

   double moneyPerLot = (stopDist / tickSize) * tickValue;
   if(moneyPerLot <= 0) return InpFixedLots;

   double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * (riskPct / 100.0);
   double lots      = riskMoney / moneyPerLot;

   double lotStep = SymbolInfoDouble(syms[s], SYMBOL_VOLUME_STEP);
   double lotMin  = SymbolInfoDouble(syms[s], SYMBOL_VOLUME_MIN);
   double lotMax  = SymbolInfoDouble(syms[s], SYMBOL_VOLUME_MAX);
   if(lotStep > 0) lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(lotMin, MathMin(lotMax, lots));

   return (lots > 0) ? lots : InpFixedLots;
}

// Scale a single order down so it commits at most InpMarginUsePct % of the
// free margin. lots never drops below the broker minimum.
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

// Journal a skipped signal once, not every minute it persists.
void Skip(int s, string why)
{
   if(why == lastSkip[s]) return;
   lastSkip[s] = why;
   Print(syms[s] + " skip: " + why);
}

//==============================================================
// Entry
//==============================================================

void TryEntry(int s)
{
   string sym = syms[s];

   M1Pic p;
   if(!LoadPic(s, p, Kijun + 4)) return;

   int dir = ChikouBreakout(p);
   if(dir == 0) { lastSkip[s] = ""; return; }

   string side = (dir == 1) ? "buy" : "sell";
   if(!SpreadOK(sym)) { Skip(s, side + " breakout, spread"); return; }

   double point   = SymbolInfoDouble(sym, SYMBOL_POINT);
   int    digits  = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double minDist = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * point;
   double ask     = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid     = SymbolInfoDouble(sym, SYMBOL_BID);
   double price   = (dir == 1) ? ask : bid;

   // TP: the nearest unraided M1 level beyond the entry. A long's TP
   // trips on the BID and a short's on the ASK, so the distance is
   // measured from that side.
   double offset = InpLiqTPOffsetPoints * point;
   double trip   = (dir == 1) ? bid : ask;
   double level  = LiqNearest(sym, PERIOD_M1, dir, trip, minDist + offset + point);
   if(level == 0.0) { Skip(s, side + " breakout, no unraided M1 liquidity"); return; }

   // Free to move: nothing between the entry (and the chikou) and the level.
   string why = "";
   if(!PriceFree(p, price, level, why) || !ChikouFree(p, dir, level, why))
   {
      Skip(s, side + " breakout, not free to move (" + why + ")");
      return;
   }
   double tp = NormalizeDouble((dir == 1) ? level - offset : level + offset, digits);

   // SL: behind the M1 kijun / cloud, pushed out by the buffer.
   double buffer = InpSLBufferPoints * point;
   double line   = LineStop(p, dir, trip, minDist + buffer + point);
   if(line == 0.0) { Skip(s, side + " breakout, no kijun/cloud behind the entry"); return; }
   double sl = NormalizeDouble((dir == 1) ? line - buffer : line + buffer, digits);

   double lots = RiskLots(s, MathAbs(price - sl));
   CapLotsToMargin(sym, (dir == 1), lots);
   trade.SetTypeFillingBySymbol(sym);
   bool ok = (dir == 1) ? trade.Buy(lots, sym, price, sl, tp, "M1 chikou liq")
                        : trade.Sell(lots, sym, price, sl, tp, "M1 chikou liq");
   lastSkip[s] = "";
   if(ok)
      Print(sym + " " + side + " @ " + DoubleToString(price, digits) + " lots " +
            DoubleToString(lots, 2) + " | SL " + DoubleToString(sl, digits) +
            " | TP " + DoubleToString(tp, digits) +
            " (M1 liquidity " + DoubleToString(level, digits) + ")");
   else
      Print(sym + " " + side + " failed, retcode " + IntegerToString(trade.ResultRetcode()));
}

void OnTick()
{
   for(int s = 0; s < symsCount; s++)
   {
      // Act once per closed M1 bar.
      datetime t = iTime(syms[s], PERIOD_M1, 1);
      if(t == 0 || t == lastM1bar[s]) continue;
      lastM1bar[s] = t;

      if(HasPosition(syms[s])) continue;
      TryEntry(s);
   }
}
//Fear God and Live
