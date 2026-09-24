//+------------------------------------------------------------------+
//| EXPERIMENT — M1/M5 LIQUIDITY SCALPER (notes §58, magic 20260883) |
//| A standalone scalper, not a fork of the bias stack. Two tiers:    |
//|   * M5 TIER:  M1 + M5 aligned        -> TP at unraided M5 liq.    |
//|   * M15 TIER: M1 + M5 + M15 aligned  -> TP at unraided M15 liq.   |
//|   * ALIGNED = the live build's CheckAlign (price and chikou       |
//|     beyond tenkan, kijun and cloud) on the last closed bar. NO    |
//|     higher timeframe bias, no cloud-twist gate, no D1/H4/H1.      |
//|   * TP: the nearest UNRAIDED liquidity level on the tier's TF     |
//|     beyond the entry — a swing high above price for a buy, a      |
//|     swing low below it for a sell — found with the po3-levels     |
//|     rules (§52, the same scan as the liquidity-target build §53). |
//|   * SL: TWO FRACTALS back — the second Williams fractal low below |
//|     the entry for a buy (the second fractal high above it for a   |
//|     sell), counted from the newest confirmed fractal on the       |
//|     tier's fractal TF (M1 by default for both tiers).             |
//|   * No target or no stop = that tier does not trade.              |
//|   * FIXED LOTS (InpLots, 0.10) on every trade; no risk sizing.    |
//|   * TIERS_LARGEST (default): one position per symbol, the largest |
//|     aligned tier opens, and an M15 signal closes a running M5     |
//|     scalp and replaces it (the live build's supersede).           |
//|     TIERS_INDEPENDENT: each tier keeps its own position (needs a  |
//|     hedging account).                                             |
//|   * Positions exit only at their SL or TP (or a supersede).       |
//| Runs once per closed M1 bar.                                      |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

enum ENUM_TIER_MODE { TIERS_LARGEST = 0, TIERS_INDEPENDENT = 1 };

//--- Input Parameters ---
input string Symbols  = "GOLDm#";
input int    Tenkan   = 9;
input int    Kijun    = 26;
input int    SenkouB  = 52;
input int    Slippage = 30;

input group  "Trade"
input double         InpLots            = 0.10;          // Fixed lot size on every trade
input int            InpMaxSpreadPoints = 60;            // Max spread in points to allow entry (0 = no limit)
input bool           InpM5Tier          = true;          // M5 tier: M1+M5 aligned, TP at M5 liquidity
input bool           InpM15Tier         = true;          // M15 tier: M1+M5+M15 aligned, TP at M15 liquidity
input ENUM_TIER_MODE InpTierMode        = TIERS_LARGEST; // 0 = one position per symbol, M15 supersedes M5; 1 = each tier its own position (hedging)

input group  "Take Profit — unraided liquidity on the tier TF (po3-levels rules)"
input int    InpLiqLeft           = 6;    // Swing: candles to the left (po3-levels default)
input int    InpLiqRight          = 6;    // Swing: candles to the right (po3-levels default)
input int    InpLiqLookback       = 100;  // Candles of the tier TF searched
input int    InpLiqTPOffsetPoints = 0;    // Pull the TP this many points in front of the level

input group  "Stop Loss — two fractals back"
input ENUM_TIMEFRAMES InpFractalTF        = PERIOD_M1; // M5 tier: timeframe of the Williams fractals
input ENUM_TIMEFRAMES InpM15FractalTF     = PERIOD_M1; // M15 tier: timeframe of the Williams fractals
input int             InpFractalCount     = 2;         // Which fractal beyond the entry (2 = the second one)
input int             InpFractalLookback  = 200;       // Candles searched for fractals
input int             InpSLBufferPoints   = 0;         // Push the SL this many points beyond the fractal

//--- Constants and Global Variables ---
#define MAX_SYMS 60
#define TIERS    2      // 0 = M5 tier, 1 = M15 tier
#define TFS      3      // alignment stack: M1, M5, M15

ENUM_TIMEFRAMES tfs[TFS]      = { PERIOD_M1, PERIOD_M5, PERIOD_M15 };
string          tierName[TIERS] = { "M5", "M15" };

string   syms[MAX_SYMS];
int      symsCount = 0;
int      ich[MAX_SYMS][TFS];
int      frac[MAX_SYMS][TIERS];
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
      for(int t = 0; t < TFS; t++)
      {
         ich[s][t] = iIchimoku(syms[s], tfs[t], Tenkan, Kijun, SenkouB);
         if(ich[s][t] == INVALID_HANDLE) return(INIT_FAILED);
      }
      frac[s][0] = iFractals(syms[s], InpFractalTF);
      frac[s][1] = iFractals(syms[s], InpM15FractalTF);
      if(frac[s][0] == INVALID_HANDLE || frac[s][1] == INVALID_HANDLE) return(INIT_FAILED);
   }

   trade.SetDeviationInPoints(Slippage);
   trade.SetExpertMagicNumber(MAGIC);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   for(int s = 0; s < symsCount; s++)
   {
      for(int t = 0; t < TFS; t++) IndicatorRelease(ich[s][t]);
      for(int k = 0; k < TIERS; k++) IndicatorRelease(frac[s][k]);
   }
}

//==============================================================
// Alignment Check — the live build's CheckAlign: on the last
// closed bar, price above (below) tenkan, kijun and the cloud,
// and chikou (that close, plotted Kijun bars back) above (below)
// the high (low), tenkan, kijun and cloud there. 1 = long,
// -1 = short, 0 = not aligned.
//==============================================================

int CheckAlign(int s, int tfIdx)
{
   string          sym    = syms[s];
   ENUM_TIMEFRAMES tf     = tfs[tfIdx];
   int             handle = ich[s][tfIdx];

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
// Stop Loss — two fractals back. Walks the Williams fractals of
// 'handle' from the newest confirmed one (bar 3: a fractal on
// bar 2 still depends on the live candle) back in time, counting
// only the fractals beyond the entry by at least minDist — lows
// below it for a buy, highs above it for a sell — and returns the
// InpFractalCount-th (the second by default). 0.0 = not found.
//==============================================================

double FractalStop(int handle, int dir, double price, double minDist)
{
   int n = (int)MathMax(10, InpFractalLookback);
   double f[];
   ArraySetAsSeries(f, true);
   int got = CopyBuffer(handle, (dir == 1) ? 1 : 0, 0, n, f);   // 0 = up, 1 = down
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

string TierComment(int tier) { return "LiqScalp " + tierName[tier]; }

// The tier a position belongs to, from its comment. Anything without the
// M15 tag is the M5 tier (the first version's "M1M5 scalp" included).
int PositionTier()
{
   return (StringFind(PositionGetString(POSITION_COMMENT), "M15") >= 0) ? 1 : 0;
}

// Tickets of this symbol's positions per tier (0 = none).
void TierTickets(string sym, ulong &tk[])
{
   for(int k = 0; k < TIERS; k++) tk[k] = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MAGIC) continue;
      if(PositionGetString(POSITION_SYMBOL) != sym) continue;
      tk[PositionTier()] = ticket;
   }
}

double FixedLots(string sym)
{
   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double lots = InpLots;
   if(step > 0) lots = MathRound(lots / step) * step;
   return MathMin(vmax, MathMax(vmin, lots));
}

// Journal a skipped signal once, not every minute it persists.
void Skip(int s, string why)
{
   if(why == lastSkip[s]) return;
   lastSkip[s] = why;
   Print(syms[s] + " skip: " + why);
}

//==============================================================
// Orders
//==============================================================

// SL and TP for a tier's entry. TP: the nearest unraided level on the
// tier's TF beyond the entry. SL: the second fractal beyond it. Both are
// measured from the side that trips them (a long's on the BID, a short's
// on the ASK) and must clear the broker's minimum stop distance. 'why'
// names what was missing when it returns false.
bool BuildOrder(int s, int tier, int dir, double &sl, double &tp, double &level, string &why)
{
   string sym     = syms[s];
   double point   = SymbolInfoDouble(sym, SYMBOL_POINT);
   int    digits  = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double minDist = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * point;
   double trip    = (dir == 1) ? SymbolInfoDouble(sym, SYMBOL_BID)
                               : SymbolInfoDouble(sym, SYMBOL_ASK);
   string side    = (dir == 1) ? "buy" : "sell";

   double offset = InpLiqTPOffsetPoints * point;
   level = LiqNearest(sym, tfs[tier + 1], dir, trip, minDist + offset + point);
   if(level == 0.0) { why = tierName[tier] + " " + side + ": no unraided " + tierName[tier] + " liquidity"; return false; }
   tp = NormalizeDouble((dir == 1) ? level - offset : level + offset, digits);

   double buffer = InpSLBufferPoints * point;
   double frc    = FractalStop(frac[s][tier], dir, trip, minDist + buffer + point);
   if(frc == 0.0) { why = tierName[tier] + " " + side + ": no fractal stop"; return false; }
   sl = NormalizeDouble((dir == 1) ? frc - buffer : frc + buffer, digits);
   return true;
}

bool OpenTier(int s, int tier, int dir, double sl, double tp, double level)
{
   string sym    = syms[s];
   int    digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double price  = (dir == 1) ? SymbolInfoDouble(sym, SYMBOL_ASK)
                              : SymbolInfoDouble(sym, SYMBOL_BID);
   string side   = (dir == 1) ? "buy" : "sell";
   double lots   = FixedLots(sym);

   trade.SetTypeFillingBySymbol(sym);
   bool ok = (dir == 1) ? trade.Buy(lots, sym, price, sl, tp, TierComment(tier))
                        : trade.Sell(lots, sym, price, sl, tp, TierComment(tier));
   if(ok)
      Print(sym + " " + tierName[tier] + " " + side + " @ " + DoubleToString(price, digits) +
            " lots " + DoubleToString(lots, 2) + " | SL " + DoubleToString(sl, digits) +
            " (fractal " + IntegerToString(InpFractalCount) + ") | TP " +
            DoubleToString(tp, digits) + " (" + tierName[tier] + " liquidity " +
            DoubleToString(level, digits) + ")");
   else
      Print(sym + " " + tierName[tier] + " " + side + " failed, retcode " +
            IntegerToString(trade.ResultRetcode()));
   return ok;
}

// Try one tier: build its SL/TP and open it. Returns true when it opened.
bool TryTier(int s, int tier, int dir, string &why)
{
   double sl, tp, level;
   if(!BuildOrder(s, tier, dir, sl, tp, level, why)) return false;
   return OpenTier(s, tier, dir, sl, tp, level);
}

//==============================================================
// Entry
//==============================================================

void TryEntry(int s)
{
   string sym = syms[s];

   // Alignment, bottom-up: M1 and M5 must agree for either tier; M15
   // must agree as well for the M15 tier.
   int dir = CheckAlign(s, 0);
   if(dir == 0 || CheckAlign(s, 1) != dir) { lastSkip[s] = ""; return; }
   bool m15 = InpM15Tier && CheckAlign(s, 2) == dir;
   bool m5  = InpM5Tier;
   if(!m15 && !m5) { lastSkip[s] = ""; return; }

   if(!SpreadOK(sym)) { Skip(s, "spread"); return; }

   ulong tk[TIERS];
   TierTickets(sym, tk);
   string why = "";

   if(InpTierMode == TIERS_INDEPENDENT)
   {
      // Each tier keeps its own position.
      if(m15 && tk[1] == 0 && !TryTier(s, 1, dir, why) && why != "") Skip(s, why);
      if(m5  && tk[0] == 0 && !TryTier(s, 0, dir, why) && why != "") Skip(s, why);
      return;
   }

   // TIERS_LARGEST: one position per symbol. A running M15 trade blocks
   // everything; a running M5 trade blocks everything except an M15
   // signal, which closes it and takes its place.
   if(tk[1] != 0) return;

   if(m15)
   {
      double sl, tp, level;
      if(BuildOrder(s, 1, dir, sl, tp, level, why))
      {
         if(tk[0] != 0)
         {
            Print(sym + " close M5 (superseded by M15)");
            if(!trade.PositionClose(tk[0], Slippage))
            {
               Print(sym + " M5 supersede close failed, retcode " +
                     IntegerToString(trade.ResultRetcode()) + " — will retry");
               return;
            }
         }
         lastSkip[s] = "";
         OpenTier(s, 1, dir, sl, tp, level);
         return;
      }
      // No M15 target or stop: fall back to the M5 tier.
   }

   if(tk[0] != 0) return;
   string why5 = "";
   if(m5 && !TryTier(s, 0, dir, why5)) why = (why == "") ? why5 : why + "; " + why5;
   else if(m5) why = "";
   if(why != "") Skip(s, why);
   else lastSkip[s] = "";
}

void OnTick()
{
   for(int s = 0; s < symsCount; s++)
   {
      // Act once per closed M1 bar.
      datetime t = iTime(syms[s], PERIOD_M1, 1);
      if(t == 0 || t == lastM1bar[s]) continue;
      lastM1bar[s] = t;

      TryEntry(s);
   }
}
//This work is my worship unto GOD
