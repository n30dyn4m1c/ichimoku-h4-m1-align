//+------------------------------------------------------------------+
//| EXPERIMENT — M1/M5 LIQUIDITY SCALPER (notes §58, magic 20260883) |
//| A standalone scalper, not a fork of the bias stack:               |
//|   * ENTRY: M1 and M5 Ichimoku-aligned the same way — the live     |
//|     build's CheckAlign (price and chikou beyond tenkan, kijun     |
//|     and cloud) on the last closed bar of each. NO higher          |
//|     timeframe bias, no cloud-twist gate, no D1/H4/H1 filter.      |
//|   * TP: the nearest UNRAIDED M5 liquidity level beyond the entry  |
//|     — a swing high above price for a buy, a swing low below it    |
//|     for a sell — found with the po3-levels rules (§52, the same   |
//|     scan as the liquidity-target build §53).                      |
//|   * SL: TWO FRACTALS back — the second Williams fractal low       |
//|     below the entry for a buy (the second fractal high above it   |
//|     for a sell), counted from the newest confirmed fractal on     |
//|     InpFractalTF (M1 by default).                                 |
//|   * No target or no stop = no trade.                              |
//|   * SIZE: the live VPS build's M5-tier risk regime — 1% of equity |
//|     below $7000, 0.5% to $13000, 0.1% above — measured against    |
//|     the distance from the entry to the fractal stop, so a trade   |
//|     stopped out loses that % (the stop is never moved for it).    |
//|     Capped to 80% of free margin; 0.10 lots if sizing data fails. |
//|   * One position per symbol; it exits only at its SL or TP.       |
//| Runs once per closed M1 bar.                                      |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

//--- Input Parameters ---
input string Symbols  = "GOLDm#";
input int    Tenkan   = 9;
input int    Kijun    = 26;
input int    SenkouB  = 52;
input int    Slippage = 30;

input group  "Trade"
input int    InpMaxSpreadPoints  = 60;    // Max spread in points to allow entry (0 = no limit)

input group  "Risk Management (the live VPS build's M5-tier regime, % of actual equity)"
input double InpFixedLots       = 0.10;   // Fixed lots fallback (sizing data unavailable)
input double InpRiskTier2At     = 7000.0; // Equity where risk drops to tier 2 (half regime)
input double InpRiskTier3At     = 13000.0;// Equity where risk drops to tier 3 (tiny regime)
input double InpRiskPctM5       = 1.0;    // M5 — tier 1 (equity < Tier2At)
input double InpRiskPctM5_T2    = 0.5;    // M5 — tier 2 (half regime)
input double InpRiskPctM5_T3    = 0.1;    // M5 — tier 3 (equity >= Tier3At)
input double InpMarginUsePct    = 80.0;   // Max % of FREE margin one order may commit

input group  "Take Profit — unraided M5 liquidity (po3-levels rules)"
input int    InpLiqLeft           = 6;    // Swing: candles to the left (po3-levels default)
input int    InpLiqRight          = 6;    // Swing: candles to the right (po3-levels default)
input int    InpLiqLookback       = 100;  // M5 candles of history searched
input int    InpLiqTPOffsetPoints = 0;    // Pull the TP this many points in front of the level

input group  "Stop Loss — two fractals back"
input ENUM_TIMEFRAMES InpFractalTF        = PERIOD_M1; // Timeframe of the Williams fractals
input int             InpFractalCount     = 2;         // Which fractal beyond the entry (2 = the second one)
input int             InpFractalLookback  = 200;       // Candles searched for fractals
input int             InpSLBufferPoints   = 0;         // Push the SL this many points beyond the fractal

//--- Constants and Global Variables ---
#define MAX_SYMS 60

string   syms[MAX_SYMS];
int      symsCount = 0;
int      ichM1[MAX_SYMS];
int      ichM5[MAX_SYMS];
int      frac[MAX_SYMS];
datetime lastM1bar[MAX_SYMS];
string   lastSkip[MAX_SYMS];     // last skip reason printed (logged on change only)

int MAGIC = 20260883;   // M1/M5 liquidity scalper

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
      ichM5[s] = iIchimoku(syms[s], PERIOD_M5, Tenkan, Kijun, SenkouB);
      frac[s]  = iFractals(syms[s], InpFractalTF);
      if(ichM1[s] == INVALID_HANDLE || ichM5[s] == INVALID_HANDLE ||
         frac[s] == INVALID_HANDLE) return(INIT_FAILED);
   }

   trade.SetDeviationInPoints(Slippage);
   trade.SetExpertMagicNumber(MAGIC);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   for(int s = 0; s < symsCount; s++)
   {
      IndicatorRelease(ichM1[s]);
      IndicatorRelease(ichM5[s]);
      IndicatorRelease(frac[s]);
   }
}

//==============================================================
// Alignment Check — the live build's CheckAlign: on the last
// closed bar, price above (below) tenkan, kijun and the cloud,
// and chikou (that close, plotted Kijun bars back) above (below)
// the high (low), tenkan, kijun and cloud there. 1 = long,
// -1 = short, 0 = not aligned.
//==============================================================

int CheckAlign(string sym, ENUM_TIMEFRAMES tf, int handle)
{
   int sh      = 1;              // last closed bar
   int chShift = sh + Kijun;     // chikou's chart position for bar sh (Kijun bars back)

   MqlRates rt[];
   if(CopyRates(sym, tf, 0, chShift + 1, rt) <= 0) return 0;
   ArraySetAsSeries(rt, true);

   if(ArraySize(rt) <= chShift) return 0;

   double tenkan[1], kijun[1], senA[1], senB[1];
   if(CopyBuffer(handle, 0, sh, 1, tenkan) <= 0) return 0;
   if(CopyBuffer(handle, 1, sh, 1, kijun)  <= 0) return 0;
   if(CopyBuffer(handle, 2, sh, 1, senA)   <= 0) return 0;
   if(CopyBuffer(handle, 3, sh, 1, senB)   <= 0) return 0;

   double closeP = rt[sh].close;
   double cHi    = MathMax(senA[0], senB[0]);
   double cLo    = MathMin(senA[0], senB[0]);

   bool above = closeP > tenkan[0] && closeP > kijun[0] && closeP > cHi;
   bool below = closeP < tenkan[0] && closeP < kijun[0] && closeP < cLo;
   if(!above && !below) return 0;

   double tenkan_ch[1], kijun_ch[1], senA_ch[1], senB_ch[1];
   if(CopyBuffer(handle, 0, chShift, 1, tenkan_ch) <= 0) return 0;
   if(CopyBuffer(handle, 1, chShift, 1, kijun_ch)  <= 0) return 0;
   if(CopyBuffer(handle, 2, chShift, 1, senA_ch)   <= 0) return 0;
   if(CopyBuffer(handle, 3, chShift, 1, senB_ch)   <= 0) return 0;

   double chik = closeP;
   double cHiC = MathMax(senA_ch[0], senB_ch[0]);
   double cLoC = MathMin(senA_ch[0], senB_ch[0]);

   if(above && chik > rt[chShift].high &&
      chik > tenkan_ch[0] && chik > kijun_ch[0] && chik > cHiC) return  1;

   if(below && chik < rt[chShift].low &&
      chik < tenkan_ch[0] && chik < kijun_ch[0] && chik < cLoC) return -1;

   return 0;
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
// Stop Loss — two fractals back. Walks the Williams fractals on
// InpFractalTF from the newest confirmed one (bar 3: a fractal on
// bar 2 still depends on the live candle) back in time, counting
// only the fractals beyond the entry by at least minDist — lows
// below it for a buy, highs above it for a sell — and returns the
// InpFractalCount-th (the second by default). 0.0 = not found.
//==============================================================

double FractalStop(int s, int dir, double price, double minDist)
{
   int n = (int)MathMax(10, InpFractalLookback);
   double f[];
   ArraySetAsSeries(f, true);
   int got = CopyBuffer(frac[s], (dir == 1) ? 1 : 0, 0, n, f);   // 0 = up, 1 = down
   if(got <= 3) return 0.0;

   int want  = (int)MathMax(1, InpFractalCount);
   int found = 0;
   for(int i = 3; i < got; i++)
   {
      double v = f[i];
      if(v == EMPTY_VALUE || v <= 0.0) continue;
      bool beyond = (dir == 1) ? (v <= price - minDist) : (v >= price + minDist);
      if(!beyond) continue;
      if(++found == want) return v;
   }
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
// Risk Management — the live VPS build's regime for the M5 tier:
// risk a fixed % of the ACTUAL equity at entry, de-risking as the
// account grows (1% below InpRiskTier2At, 0.5% between the tiers,
// 0.1% at InpRiskTier3At and above). The % is measured against
// the distance from the entry to the fractal stop, so a stopped-
// out trade loses that % (live, having no stop, used ATR x 2);
// the stop is placed first and never moved to suit the size.
// Falls back to InpFixedLots when the sizing data is unavailable;
// every order is capped to the free margin.
//==============================================================

double RiskPct()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq >= InpRiskTier3At) return InpRiskPctM5_T3;
   if(eq >= InpRiskTier2At) return InpRiskPctM5_T2;
   return InpRiskPctM5;
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

   int d1 = CheckAlign(sym, PERIOD_M1, ichM1[s]);
   if(d1 == 0) { lastSkip[s] = ""; return; }
   int d5 = CheckAlign(sym, PERIOD_M5, ichM5[s]);
   if(d5 != d1) { lastSkip[s] = ""; return; }
   int dir = d1;

   if(!SpreadOK(sym)) { Skip(s, "spread"); return; }

   double point   = SymbolInfoDouble(sym, SYMBOL_POINT);
   int    digits  = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double minDist = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * point;
   double ask     = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid     = SymbolInfoDouble(sym, SYMBOL_BID);
   double price   = (dir == 1) ? ask : bid;
   string side    = (dir == 1) ? "buy" : "sell";

   // TP: the nearest unraided M5 level beyond the entry. A long's TP
   // trips on the BID and a short's on the ASK, so the distance is
   // measured from that side.
   double offset = InpLiqTPOffsetPoints * point;
   double trip   = (dir == 1) ? bid : ask;
   double level  = LiqNearest(sym, PERIOD_M5, dir, trip, minDist + offset + point);
   if(level == 0.0) { Skip(s, side + " aligned, no unraided M5 liquidity"); return; }
   double tp = NormalizeDouble((dir == 1) ? level - offset : level + offset, digits);

   // SL: the second fractal beyond the entry, pushed out by the buffer.
   double buffer = InpSLBufferPoints * point;
   double frc    = FractalStop(s, dir, trip, minDist + buffer + point);
   if(frc == 0.0) { Skip(s, side + " aligned, no fractal stop"); return; }
   double sl = NormalizeDouble((dir == 1) ? frc - buffer : frc + buffer, digits);

   double lots = RiskLots(s, MathAbs(price - sl));
   CapLotsToMargin(sym, (dir == 1), lots);
   trade.SetTypeFillingBySymbol(sym);
   bool ok = (dir == 1) ? trade.Buy(lots, sym, price, sl, tp, "M1M5 scalp")
                        : trade.Sell(lots, sym, price, sl, tp, "M1M5 scalp");
   lastSkip[s] = "";
   if(ok)
      Print(sym + " " + side + " @ " + DoubleToString(price, digits) + " lots " +
            DoubleToString(lots, 2) + " | SL " + DoubleToString(sl, digits) +
            " (fractal " + IntegerToString(InpFractalCount) + ") | TP " +
            DoubleToString(tp, digits) + " (M5 liquidity " + DoubleToString(level, digits) + ")");
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
//This work is my worship unto GOD
