//+------------------------------------------------------------------+
//| EXPERIMENT — M1/M5 LIQUIDITY SWEEP, THEN CHIKOU BREAKOUT (notes   |
//| §71, magic 20260892). Two TIERS, M1 and M5, each trading its own  |
//| timeframe alone — no timeframe looks at another:                  |
//|   * SWEEP: a wick trades beyond an UNRAIDED swing — the           |
//|     po3-levels rules (§52): strictly beyond the InpLiqLeft candles|
//|     before it, at least as far as the InpLiqRight after it, all   |
//|     its right-hand candles closed, within InpLiqLookback candles. |
//|     A swept LOW arms a LONG, a swept HIGH arms a SHORT — the stop |
//|     hunt is taken against the side it ran.                        |
//|   * TRIGGER: within the tier's sweep window (90 bars, the sweep   |
//|     bar included), a CHIKOU BREAKOUT in the armed direction — the |
//|     live VPS build's chikou test (above the cloud, the high, the  |
//|     tenkan and kijun 26 bars back; the mirror for a sell), newly  |
//|     true on the closed bar. Entry at the next bar's open.         |
//|   * SL: the sweep's extreme — the furthest wick from the sweep    |
//|     bar to the trigger bar (a sell's stop is lifted by the spread,|
//|     since it trips on the ask). A stop closer than the tier's     |
//|     minimum ($2 on gold) is skipped: the spread eats small stops. |
//|   * TP: the tier's target, 3 times the stop distance (3R).        |
//|   * TIERS: M1 (InpM1Tier) and M5 (InpM5Tier) run the same rules   |
//|     on their own bars, with their own window, minimum stop and    |
//|     target, and hold one position each — tagged by comment, so an |
//|     M1 and an M5 trade can run side by side. Bars, windows and    |
//|     lookbacks are counted in the tier's own candles.              |
//|   * SIZE: the live VPS build's M5 regime — 1% of equity below     |
//|     $7000, 0.5% to $13000, 0.1% above — on each tier. M1 measures |
//|     it on the ACTUAL stop (InpM1SizeBasis = SIZE_STOP), so a stop- |
//|     out loses that %. M5 sizes it exactly as the live VPS M5 tier |
//|     does (InpM5SizeBasis = SIZE_VPS_ATR), against ATR(M5, 14) x   |
//|     InpRiskATRMult (2); the sweep stop is a median 2.6x that, so  |
//|     an M5 stop-out loses ~2.6x the %. Capped to 80% of free       |
//|     margin. One position per tier per symbol, exits at SL or TP   |
//|     only. A sweep seen while the tier's position is open does not |
//|     arm. Each tier runs once per closed bar of its timeframe.     |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

enum ENUM_SIZE_BASIS
{
   SIZE_STOP    = 0,   // The actual stop distance (a stop-out loses the %)
   SIZE_VPS_ATR = 1    // The VPS build's basis: ATR(tier) x InpRiskATRMult
};

//--- Input Parameters ---
input string Symbols  = "GOLDm#";
input int    Tenkan   = 9;
input int    Kijun    = 26;
input int    SenkouB  = 52;
input int    Slippage = 30;

input group  "Trade"
input int    InpMaxSpreadPoints  = 60;    // Max spread in points to allow entry (0 = no limit)

input group  "Sweep — unraided liquidity (po3-levels rules, in the tier's own candles)"
input int    InpLiqLeft          = 6;     // Swing: candles to the left (po3-levels default)
input int    InpLiqRight         = 6;     // Swing: candles to the right (po3-levels default)
input int    InpLiqLookback      = 100;   // Candles of history searched

input group  "M1 tier"
input bool   InpM1Tier           = true;  // Trade the M1 tier
input int    InpM1SweepWindow    = 90;    // M1 bars after the sweep the chikou breakout may come
input double InpM1MinStop        = 2.0;   // Minimum stop distance in PRICE (gold: $2); 0 = off
input double InpM1TargetR        = 3.0;   // Take profit at this multiple of the stop distance

input group  "M5 tier"
input bool   InpM5Tier           = true;  // Trade the M5 tier
input int    InpM5SweepWindow    = 90;    // M5 bars after the sweep the chikou breakout may come
input double InpM5MinStop        = 2.0;   // Minimum stop distance in PRICE (gold: $2); 0 = off
input double InpM5TargetR        = 3.0;   // Take profit at this multiple of the stop distance

input group  "Risk Management (the live VPS build's M5/M15 regime, % of actual equity)"
input double InpFixedLots       = 0.10;   // Fixed lots fallback (sizing data unavailable)
input ENUM_SIZE_BASIS InpM1SizeBasis = SIZE_STOP;    // M1: distance the % is measured against
input ENUM_SIZE_BASIS InpM5SizeBasis = SIZE_VPS_ATR; // M5: distance the % is measured against (the live VPS M5 tier's)
input double InpRiskATRMult     = 2.0;    // SIZE_VPS_ATR: reference stop = ATR(tier, InpATRPeriod) x this (the VPS value)
input int    InpATRPeriod       = 14;     // ATR period (the VPS value)
input double InpRiskTier2At     = 7000.0; // Equity where risk drops to tier 2 (half regime)
input double InpRiskTier3At     = 13000.0;// Equity where risk drops to tier 3 (tiny regime)
input double InpRiskPct         = 1.0;    // Tier 1 (equity < Tier2At), each of M1 and M5
input double InpRiskPct_T2      = 0.5;    // Tier 2 (half regime)
input double InpRiskPct_T3      = 0.1;    // Tier 3 (equity >= Tier3At)
input double InpMarginUsePct    = 80.0;   // Max % of FREE margin one order may commit

//--- Constants and Global Variables ---
#define MAX_SYMS 60
#define NT       2               // tiers: 0 = M1, 1 = M5

const ENUM_TIMEFRAMES TF[NT]   = {PERIOD_M1, PERIOD_M5};
const string          TFN[NT]  = {"M1", "M5"};

string   syms[MAX_SYMS];
int      symsCount = 0;
int      ich[MAX_SYMS][NT];
int      atrH[MAX_SYMS][NT];
datetime lastBar[MAX_SYMS][NT];
string   lastSkip[MAX_SYMS][NT];   // last skip reason printed (logged on change only)
datetime armLong[MAX_SYMS][NT];    // open time of the oldest live sweep of a low (0 = none)
datetime armShort[MAX_SYMS][NT];   // open time of the oldest live sweep of a high (0 = none)
datetime lastLong[MAX_SYMS][NT];   // the newest sweep of a low, taken over when the oldest expires
datetime lastShort[MAX_SYMS][NT];  // the newest sweep of a high

int MAGIC = 20260892;   // M1/M5 liquidity sweep, then chikou breakout

// Per-tier settings, read from the inputs.
bool   TierOn(int t)     { return (t == 0) ? InpM1Tier        : InpM5Tier;        }
int    TierWindow(int t) { return (t == 0) ? InpM1SweepWindow : InpM5SweepWindow; }
double TierMinStop(int t){ return (t == 0) ? InpM1MinStop     : InpM5MinStop;     }
double TierTargetR(int t){ return (t == 0) ? InpM1TargetR     : InpM5TargetR;     }
string TierComment(int t){ return TFN[t] + " sweep chikou"; }
ENUM_SIZE_BASIS TierBasis(int t) { return (t == 0) ? InpM1SizeBasis : InpM5SizeBasis; }

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
      for(int t = 0; t < NT; t++)
      {
         lastBar[s][t]   = 0;
         lastSkip[s][t]  = "";
         armLong[s][t]   = 0;
         armShort[s][t]  = 0;
         lastLong[s][t]  = 0;
         lastShort[s][t] = 0;
         ich[s][t]  = iIchimoku(syms[s], TF[t], Tenkan, Kijun, SenkouB);
         atrH[s][t] = iATR(syms[s], TF[t], InpATRPeriod);
         if(ich[s][t] == INVALID_HANDLE || atrH[s][t] == INVALID_HANDLE) return(INIT_FAILED);
      }

   trade.SetDeviationInPoints(Slippage);
   trade.SetExpertMagicNumber(MAGIC);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   for(int s = 0; s < symsCount; s++)
      for(int t = 0; t < NT; t++)
      {
         IndicatorRelease(ich[s][t]);
         IndicatorRelease(atrH[s][t]);
      }
}

//==============================================================
// Chikou breakout — the live VPS build's chikou test (CheckAlign).
// For bar sh the chikou is that bar's close, plotted Kijun bars
// back: +1 above the cloud, the high, the tenkan and the kijun
// there; -1 below the cloud, the low, the tenkan and the kijun;
// 0 otherwise. A breakout is clear on bar 1 and not on bar 2.
//==============================================================

int ChikouClear(int s, int t, const MqlRates &r[], int sh)
{
   int c = sh + Kijun;
   if(c >= ArraySize(r)) return 0;
   double tk[1], kj[1], sa[1], sb[1];
   if(CopyBuffer(ich[s][t], 0, c, 1, tk) <= 0) return 0;
   if(CopyBuffer(ich[s][t], 1, c, 1, kj) <= 0) return 0;
   if(CopyBuffer(ich[s][t], 2, c, 1, sa) <= 0) return 0;
   if(CopyBuffer(ich[s][t], 3, c, 1, sb) <= 0) return 0;
   double chik = r[sh].close;
   double cHi  = MathMax(sa[0], sb[0]);
   double cLo  = MathMin(sa[0], sb[0]);
   if(chik > cHi && chik > r[c].high && chik > tk[0] && chik > kj[0]) return  1;
   if(chik < cLo && chik < r[c].low  && chik < tk[0] && chik < kj[0]) return -1;
   return 0;
}

int ChikouBreakout(int s, int t, const MqlRates &r[])
{
   int now = ChikouClear(s, t, r, 1);
   if(now == 0) return 0;
   return (ChikouClear(s, t, r, 2) == now) ? 0 : now;
}

//==============================================================
// Sweeps — the po3-levels swing rules (§52). A swing high stands
// strictly above the InpLiqLeft candles before it and at least as
// high as the InpLiqRight candles after it; lows mirror it. The
// closed bar 1 SWEEPS a swing when its wick goes beyond it and no
// candle between them did — the level was unraided until bar 1.
// Only swings whose right-hand candles closed before bar 1, and
// that lie within InpLiqLookback bars of it, count.
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

// True when closed bar 1 swept an unraided swing high (isHigh) or low.
bool SweptBy1(const MqlRates &r[], const bool isHigh)
{
   int left  = (int)MathMax(1, InpLiqLeft);
   int right = (int)MathMax(1, InpLiqRight);
   int n     = ArraySize(r);
   double w1 = isHigh ? r[1].high : r[1].low;
   double reach = isHigh ? -DBL_MAX : DBL_MAX;    // furthest wick on bars 2 .. i-1
   for(int i = 2; i <= InpLiqLookback && i + left < n; i++)
   {
      if(i >= right + 2 && LiqIsSwing(r, i, isHigh, left, right))
      {
         double v = isHigh ? r[i].high : r[i].low;
         bool unraided = isHigh ? (reach <= v) : (reach >= v);
         bool swept    = isHigh ? (w1 > v)     : (w1 < v);
         if(unraided && swept) return true;
      }
      reach = isHigh ? MathMax(reach, r[i].high) : MathMin(reach, r[i].low);
   }
   return false;
}

//==============================================================
// Utility Functions
//==============================================================

bool SpreadOK(string sym)
{
   if(InpMaxSpreadPoints <= 0) return true;
   return SymbolInfoInteger(sym, SYMBOL_SPREAD) <= InpMaxSpreadPoints;
}

// The tier's own position, found by its comment. A position of this magic
// whose comment names neither tier (edited by hand, or by the broker)
// blocks both tiers rather than letting a second trade stack on it.
bool HasPosition(string sym, int t)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MAGIC) continue;
      if(PositionGetString(POSITION_SYMBOL) != sym) continue;
      string cm = PositionGetString(POSITION_COMMENT);
      if(StringFind(cm, TierComment(t)) == 0) return true;
      bool known = false;
      for(int u = 0; u < NT; u++)
         if(StringFind(cm, TierComment(u)) == 0) known = true;
      if(!known) return true;
   }
   return false;
}

//==============================================================
// Risk Management — the live VPS build's regime for its lowest
// tiers (M5/M15): risk a fixed % of the ACTUAL equity at entry,
// de-risking as the account grows (1% below InpRiskTier2At, 0.5%
// between the tiers, 0.1% at InpRiskTier3At and above). SIZE_STOP
// measures it against the distance to the stop, so a stopped-out
// trade loses that %. SIZE_VPS_ATR measures it against ATR(tier) x
// InpRiskATRMult as the VPS build does — it has no entry stop, this
// EA does, and the sweep stop is usually 2.5-3x that reference. The
// basis is set per tier: M1 on the stop, M5 the VPS way.
// Falls back to InpFixedLots when the sizing data is unavailable;
// every order is capped to the free margin. Each tier risks the %
// on its own, so with an M1 and an M5 trade open together the
// account carries twice it.
//==============================================================

double RiskPct()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq >= InpRiskTier3At) return InpRiskPct_T3;
   if(eq >= InpRiskTier2At) return InpRiskPct_T2;
   return InpRiskPct;
}

double RiskLots(int s, int t, double stopDist)
{
   double riskPct = RiskPct();
   if(TierBasis(t) == SIZE_VPS_ATR)
   {
      double a[1];
      if(CopyBuffer(atrH[s][t], 0, 1, 1, a) <= 0 || a[0] <= 0) return InpFixedLots;
      stopDist = a[0] * InpRiskATRMult;
   }
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
void Skip(int s, int t, string why)
{
   if(why == lastSkip[s][t]) return;
   lastSkip[s][t] = why;
   Print(syms[s] + " " + TFN[t] + " skip: " + why);
}

//==============================================================
// Per closed bar: drop sweeps older than the window, arm new ones,
// then look for the chikou breakout of an armed side.
//==============================================================

// Tier bars from the sweep bar opening at tm to closed bar 1 (0 = bar 1 itself).
int BarsSince(string sym, int t, datetime tm)
{
   int sh = iBarShift(sym, TF[t], tm, false);
   return (sh < 0) ? INT_MAX : sh - 1;
}

void ClearArms(int s, int t)
{
   armLong[s][t] = 0; armShort[s][t] = 0; lastLong[s][t] = 0; lastShort[s][t] = 0;
}

void OnBar(int s, int t)
{
   string sym = syms[s];
   int win  = TierWindow(t);
   int bars = (int)MathMax(InpLiqLookback + InpLiqLeft + 2, win + Kijun + 4);
   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(sym, TF[t], 0, bars, r) < bars) return;

   // A swept low arms a long, a swept high a short. The oldest live
   // sweep is kept: its extreme is the furthest wick of the whole run.
   // When it ages out of the window the newest sweep takes over.
   if(SweptBy1(r, false)) { lastLong[s][t]  = r[1].time; if(armLong[s][t]  == 0) armLong[s][t]  = r[1].time; }
   if(SweptBy1(r, true))  { lastShort[s][t] = r[1].time; if(armShort[s][t] == 0) armShort[s][t] = r[1].time; }
   if(armLong[s][t] != 0 && BarsSince(sym, t, armLong[s][t]) > win)
      armLong[s][t] = (lastLong[s][t] != 0 && BarsSince(sym, t, lastLong[s][t]) <= win) ? lastLong[s][t] : 0;
   if(armShort[s][t] != 0 && BarsSince(sym, t, armShort[s][t]) > win)
      armShort[s][t] = (lastShort[s][t] != 0 && BarsSince(sym, t, lastShort[s][t]) <= win) ? lastShort[s][t] : 0;

   int dir = ChikouBreakout(s, t, r);
   if(dir == 0) return;
   datetime armed = (dir == 1) ? armLong[s][t] : armShort[s][t];
   if(armed == 0) return;

   string side = (dir == 1) ? "buy" : "sell";
   if(!SpreadOK(sym)) { Skip(s, t, side + " breakout after sweep, spread"); return; }

   // The sweep's extreme: the furthest wick from the sweep bar to bar 1.
   int from = BarsSince(sym, t, armed) + 1;
   if(from >= ArraySize(r)) return;
   double ext = (dir == 1) ? r[1].low : r[1].high;
   for(int i = 1; i <= from; i++)
      ext = (dir == 1) ? MathMin(ext, r[i].low) : MathMax(ext, r[i].high);

   double point   = SymbolInfoDouble(sym, SYMBOL_POINT);
   int    digits  = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double minDist = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * point;
   double ask     = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid     = SymbolInfoDouble(sym, SYMBOL_BID);
   double price   = (dir == 1) ? ask : bid;

   // A sell's stop trips on the ask, so it sits a spread above the wick.
   double sl   = NormalizeDouble((dir == 1) ? ext : ext + (ask - bid), digits);
   double risk = (dir == 1) ? (price - sl) : (sl - price);
   if(risk <= minDist) { Skip(s, t, side + " breakout after sweep, stop not behind the entry"); return; }
   double minStop = TierMinStop(t);
   if(minStop > 0 && risk < minStop)
   {
      Skip(s, t, side + " breakout after sweep, stop " + DoubleToString(risk, digits) + " under the minimum");
      return;
   }
   double tgtR = TierTargetR(t);
   double tp = NormalizeDouble((dir == 1) ? price + tgtR * risk : price - tgtR * risk, digits);

   double lots = RiskLots(s, t, risk);
   CapLotsToMargin(sym, (dir == 1), lots);
   trade.SetTypeFillingBySymbol(sym);
   bool ok = (dir == 1) ? trade.Buy(lots, sym, price, sl, tp, TierComment(t))
                        : trade.Sell(lots, sym, price, sl, tp, TierComment(t));
   lastSkip[s][t] = "";
   if(ok)
   {
      ClearArms(s, t);
      Print(sym + " " + TFN[t] + " " + side + " @ " + DoubleToString(price, digits) + " lots " +
            DoubleToString(lots, 2) + " | SL " + DoubleToString(sl, digits) +
            " (sweep extreme) | TP " + DoubleToString(tp, digits) +
            " (" + DoubleToString(tgtR, 1) + "R)");
   }
   else
      Print(sym + " " + TFN[t] + " " + side + " failed, retcode " + IntegerToString(trade.ResultRetcode()));
}

void OnTick()
{
   for(int s = 0; s < symsCount; s++)
      for(int t = 0; t < NT; t++)
      {
         if(!TierOn(t)) continue;

         // Act once per closed bar of the tier's timeframe.
         datetime tm = iTime(syms[s], TF[t], 1);
         if(tm == 0 || tm == lastBar[s][t]) continue;
         lastBar[s][t] = tm;

         // While the tier's position is open nothing arms; the next setup starts flat.
         if(HasPosition(syms[s], t)) { ClearArms(s, t); continue; }
         OnBar(s, t);
      }
}
//Fear God and Live
