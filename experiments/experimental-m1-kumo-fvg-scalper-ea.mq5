//+------------------------------------------------------------------+
//| EXPERIMENT — M1 KUMO-BREAKOUT FVG SCALPER (notes §64, magic      |
//| 20260886). A standalone M1 scalper, not a fork of the bias stack: |
//|   * BREAKOUT: on a closed M1 bar, price AND chikou are both       |
//|     beyond the M1 kumo (above it for a long, below for a short)   |
//|     where the bar before was not. That arms a setup in that       |
//|     direction; it is dropped the moment a closed bar fails the    |
//|     test (price or chikou back in or through the cloud).          |
//|   * FVG: the fair value gaps are the po3-levels indicator's       |
//|     (§60, v1.54) — three candles, the third's low above the       |
//|     first's high (bullish) or its high below the first's low      |
//|     (bearish), confirmed when the third closes, and mitigated by  |
//|     the same ENUM_FVG_MIT rules (default: a CLOSE beyond the far     |
//|     edge). The setup waits for a gap in its direction whose       |
//|     middle candle is the breakout bar or later.                   |
//|   * ENTRY: a limit order inside that gap (the middle by default), |
//|     SL at the nearest confirmed Williams fractal beyond the entry |
//|     — the newest fractal low below it for a buy, high above it    |
//|     for a sell. No TP. Unfilled orders expire.                    |
//|   * EXIT: the trade runs until an OPPOSING fair value gap forms   |
//|     after the fill and stays unmitigated for more than            |
//|     InpHoldSeconds (120 = 2 minutes) — or the fractal SL is hit.  |
//|   * SIZE: the §58 regime — 1% of equity below $7000, 0.5% to      |
//|     $13000, 0.1% above — against the entry-to-SL distance,        |
//|     capped to 80% of free margin.                                 |
//|   * One trade per breakout, one position or order per symbol.     |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

//--- What ends a fair value gap — the po3-levels indicator's enum, same
//--- values and the same default (a close beyond the far edge).
enum ENUM_FVG_MIT
  {
   FVG_MIT_FULL  = 0,   // Price trades through the whole gap
   FVG_MIT_HALF  = 1,   // Price reaches the middle of the gap
   FVG_MIT_TOUCH = 2,   // Price trades into the gap at all
   FVG_MIT_CLOSE = 3    // A candle closes beyond the gap (wicks ignored)
  };

//--- Where in the gap the limit order sits.
enum ENUM_FVG_ENTRY
  {
   FVG_ENTRY_NEAR = 0,  // Near edge (first touch — fills most often)
   FVG_ENTRY_MID  = 1,  // Middle (consequent encroachment)
   FVG_ENTRY_FAR  = 2   // Far edge (deepest, fills least often)
  };

//--- Input Parameters ---
input string Symbols  = "GOLDm#";
input int    Tenkan   = 9;
input int    Kijun    = 26;
input int    SenkouB  = 52;
input int    Slippage = 30;

input group  "Trade"
input int    InpMaxSpreadPoints  = 60;    // Max spread in points to place an order (0 = no limit)
input int    InpSetupMaxBars     = 30;    // M1 bars after the breakout an FVG may still form in (0 = no limit)
input int    InpLimitExpiryBars  = 15;    // Cancel an unfilled limit after this many M1 bars (0 = never)
input ENUM_FVG_ENTRY InpEntryIn  = FVG_ENTRY_MID; // Where in the gap the limit sits

input group  "Fair value gaps (po3-levels rules, §60)"
input ENUM_FVG_MIT InpFvgMit     = FVG_MIT_CLOSE; // What counts as mitigated
input int    InpFvgMinPts        = 0;     // Smallest gap used, in points (0 = all)
input int    InpFvgLookback      = 300;   // M1 candles searched at most

input group  "Exit — opposing FVG"
input int    InpHoldSeconds      = 120;   // Opposing gap must stand MORE than this long after it forms

input group  "Risk Management (the §58 regime, % of actual equity)"
input double InpFixedLots       = 0.10;   // Fixed lots fallback (sizing data unavailable)
input double InpRiskTier2At     = 7000.0; // Equity where risk drops to tier 2 (half regime)
input double InpRiskTier3At     = 13000.0;// Equity where risk drops to tier 3 (tiny regime)
input double InpRiskPct         = 1.0;    // Tier 1 (equity < Tier2At)
input double InpRiskPct_T2      = 0.5;    // Tier 2 (half regime)
input double InpRiskPct_T3      = 0.1;    // Tier 3 (equity >= Tier3At)
input double InpMarginUsePct    = 80.0;   // Max % of FREE margin one order may commit

input group  "Stop Loss — nearest fractal"
input ENUM_TIMEFRAMES InpFractalTF        = PERIOD_M1; // Timeframe of the Williams fractals
input int             InpFractalLookback  = 200;       // Candles searched for fractals
input int             InpSLBufferPoints   = 0;         // Push the SL this many points beyond the fractal

//--- Constants and Global Variables ---
#define MAX_SYMS 60
#define MAX_GAPS 64

struct Gap
  {
   datetime mid;      // middle candle's open time (the gap's id, as in po3-levels)
   datetime formed;   // third candle's close — the moment the gap is confirmed
   double   bot;
   double   top;
   bool     bull;
  };

string   syms[MAX_SYMS];
int      symsCount = 0;
int      ich[MAX_SYMS];
int      frac[MAX_SYMS];
datetime lastM1bar[MAX_SYMS];
int      setupDir[MAX_SYMS];     // armed breakout: 1 long, -1 short, 0 none
datetime setupTime[MAX_SYMS];    // open time of the breakout bar
datetime lastGapUsed[MAX_SYMS];  // middle-candle time of the last gap an order was placed in
datetime exitDue[MAX_SYMS];      // earliest time a standing opposing gap passes the hold (0 = none)
string   lastSkip[MAX_SYMS];     // last skip reason printed (logged on change only)

int MAGIC = 20260886;   // M1 kumo-breakout FVG scalper

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
      lastM1bar[s]   = 0;
      setupDir[s]    = 0;
      setupTime[s]   = 0;
      lastGapUsed[s] = 0;
      exitDue[s]     = 0;
      lastSkip[s]    = "";
      ich[s]  = iIchimoku(syms[s], PERIOD_M1, Tenkan, Kijun, SenkouB);
      frac[s] = iFractals(syms[s], InpFractalTF);
      if(ich[s] == INVALID_HANDLE || frac[s] == INVALID_HANDLE) return(INIT_FAILED);
   }

   trade.SetDeviationInPoints(Slippage);
   trade.SetExpertMagicNumber(MAGIC);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   for(int s = 0; s < symsCount; s++)
   {
      IndicatorRelease(ich[s]);
      IndicatorRelease(frac[s]);
   }
}

//==============================================================
// Kumo side — on M1 bar sh, the close above (below) the cloud
// at that bar AND the chikou (that close, plotted Kijun bars
// back) above (below) the cloud there. Only the cloud is read;
// tenkan and kijun play no part. 1 = both above, -1 = both
// below, 0 = anything else.
//==============================================================

int KumoSide(int s, int sh)
{
   string sym     = syms[s];
   int    chShift = sh + Kijun;

   double c[1];
   if(CopyClose(sym, PERIOD_M1, sh, 1, c) <= 0) return 0;

   double senA[1], senB[1], senA_ch[1], senB_ch[1];
   if(CopyBuffer(ich[s], 2, sh, 1, senA)         <= 0) return 0;
   if(CopyBuffer(ich[s], 3, sh, 1, senB)         <= 0) return 0;
   if(CopyBuffer(ich[s], 2, chShift, 1, senA_ch) <= 0) return 0;
   if(CopyBuffer(ich[s], 3, chShift, 1, senB_ch) <= 0) return 0;

   double closeP = c[0];
   if(closeP > MathMax(senA[0], senB[0]) && closeP > MathMax(senA_ch[0], senB_ch[0])) return  1;
   if(closeP < MathMin(senA[0], senB[0]) && closeP < MathMin(senA_ch[0], senB_ch[0])) return -1;
   return 0;
}

//==============================================================
// Fair value gaps — the po3-levels scan (§60, v1.54) on M1.
// Three candles: bullish when the third's low is above the
// first's high, bearish when its high is below the first's low.
// A gap exists once its third candle has closed. Walking from
// the newest candle back, the lowest / highest price traded
// AFTER each gap's third candle is carried, so one pass settles
// every gap. FVG_MIT_CLOSE carries closes of closed candles only
// (index 1 up) and a gap stands while none closed beyond its far
// edge; the wick modes carry wicks, the live candle included.
//==============================================================

// The price a wick has to reach for the gap to count as mitigated.
double FvgTrigger(const double bot, const double top, const bool bull)
{
   if(InpFvgMit == FVG_MIT_HALF)  return (bot + top) / 2.0;
   if(InpFvgMit == FVG_MIT_TOUCH) return bull ? top : bot;
   return bull ? bot : top;
}

// Fills out[] with the standing gaps of the wanted side among the last
// 'count' M1 candles, newest first; returns how many.
int FvgStanding(string sym, int count, bool wantBull, Gap &out[])
{
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int n = CopyRates(sym, PERIOD_M1, 0, (int)MathMax(4, count), r);
   if(n < 4) return 0;

   bool   byClose = (InpFvgMit == FVG_MIT_CLOSE);
   double minGap  = MathMax(0, InpFvgMinPts) * SymbolInfoDouble(sym, SYMBOL_POINT);
   double lo = DBL_MAX, hi = -DBL_MAX;
   int    got = 0;
   int    secs = PeriodSeconds(PERIOD_M1);

   for(int m = 2; m + 1 < n && got < MAX_GAPS; m++)
   {
      if(!byClose)
      {
         lo = MathMin(lo, r[m - 2].low);
         hi = MathMax(hi, r[m - 2].high);
      }
      else if(m - 2 >= 1)
      {
         lo = MathMin(lo, r[m - 2].close);
         hi = MathMax(hi, r[m - 2].close);
      }

      double bot, top;
      bool   open;
      if(wantBull)
      {
         if(!(r[m - 1].low > r[m + 1].high)) continue;
         bot  = r[m + 1].high; top = r[m - 1].low;
         open = byClose ? (lo >= bot) : (lo > FvgTrigger(bot, top, true));
      }
      else
      {
         if(!(r[m - 1].high < r[m + 1].low)) continue;
         bot  = r[m - 1].high; top = r[m + 1].low;
         open = byClose ? (hi <= top) : (hi < FvgTrigger(bot, top, false));
      }
      if(top - bot < minGap || !open) continue;

      ArrayResize(out, got + 1, MAX_GAPS);
      out[got].mid    = r[m].time;
      out[got].formed = r[m - 1].time + secs;
      out[got].bot    = bot;
      out[got].top    = top;
      out[got].bull   = wantBull;
      got++;
   }
   return got;
}

// M1 candles from 'since' to now, plus the three a gap needs, capped.
int BarsSince(string sym, datetime since)
{
   int sh = iBarShift(sym, PERIOD_M1, since, false);
   if(sh < 0) sh = InpFvgLookback;
   return (int)MathMin(MathMax(4, InpFvgLookback), sh + 4);
}

//==============================================================
// Stop Loss — the nearest fractal. Walks the Williams fractals
// on InpFractalTF from the newest confirmed one (bar 3: a
// fractal on bar 2 still depends on the live candle) back in
// time and returns the first beyond the entry by at least
// minDist — a low below it for a buy, a high above it for a
// sell. 0.0 = not found.
//==============================================================

double FractalStop(int s, int dir, double price, double minDist)
{
   int n = (int)MathMax(10, InpFractalLookback);
   double f[];
   ArraySetAsSeries(f, true);
   int got = CopyBuffer(frac[s], (dir == 1) ? 1 : 0, 0, n, f);   // 0 = up, 1 = down
   if(got <= 3) return 0.0;

   for(int i = 3; i < got; i++)
   {
      double v = f[i];
      if(v == EMPTY_VALUE || v <= 0.0) continue;
      if((dir == 1) ? (v <= price - minDist) : (v >= price + minDist)) return v;
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

// This EA's position on sym: its ticket, direction and fill time. 0 = none.
ulong FindPosition(string sym, int &dir, datetime &opened)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MAGIC) continue;
      if(PositionGetString(POSITION_SYMBOL) != sym) continue;
      dir    = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      opened = (datetime)PositionGetInteger(POSITION_TIME);
      return ticket;
   }
   return 0;
}

// This EA's pending limit on sym: its ticket, direction and placement time.
ulong FindPending(string sym, int &dir, datetime &placed)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) != MAGIC) continue;
      if(OrderGetString(ORDER_SYMBOL) != sym) continue;
      ENUM_ORDER_TYPE t = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(t != ORDER_TYPE_BUY_LIMIT && t != ORDER_TYPE_SELL_LIMIT) continue;
      dir    = (t == ORDER_TYPE_BUY_LIMIT) ? 1 : -1;
      placed = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
      return ticket;
   }
   return 0;
}

//==============================================================
// Risk Management — the §58 regime: a fixed % of the ACTUAL
// equity, de-risking as the account grows, measured against the
// distance from the limit price to the fractal stop. Falls back
// to InpFixedLots when the sizing data is unavailable; every
// order is capped to the free margin.
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
// free margin at the order's own price. lots never drops below the broker
// minimum.
void CapLotsToMargin(string sym, bool isBuy, double price, double &lots)
{
   if(lots <= 0) return;
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

void Disarm(int s, string why)
{
   if(setupDir[s] == 0) return;
   Print(syms[s] + " " + ((setupDir[s] == 1) ? "long" : "short") + " setup dropped: " + why);
   setupDir[s]  = 0;
   setupTime[s] = 0;
   lastSkip[s]  = "";
}

//==============================================================
// Entry — a limit inside the newest standing gap in the setup's
// direction whose middle candle is the breakout bar or later and
// that has not had an order yet.
//==============================================================

void TryEntry(int s)
{
   string sym = syms[s];
   int    dir = setupDir[s];
   string side = (dir == 1) ? "buy" : "sell";

   Gap g[];
   int n = FvgStanding(sym, BarsSince(sym, setupTime[s]), dir == 1, g);
   int k = -1;
   for(int i = 0; i < n; i++)
   {
      if(g[i].mid < setupTime[s]) break;          // newest first: the rest predate the breakout
      if(g[i].mid <= lastGapUsed[s]) break;       // already traded (or older than it)
      k = i;
      break;
   }
   if(k < 0) return;

   if(!SpreadOK(sym)) { Skip(s, "spread"); return; }

   double point   = SymbolInfoDouble(sym, SYMBOL_POINT);
   double tick    = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   int    digits  = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double minDist = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * point;
   double ask     = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid     = SymbolInfoDouble(sym, SYMBOL_BID);

   double nearEdge  = (dir == 1) ? g[k].top : g[k].bot;
   double farEdge   = (dir == 1) ? g[k].bot : g[k].top;
   double price = (InpEntryIn == FVG_ENTRY_NEAR) ? nearEdge :
                  (InpEntryIn == FVG_ENTRY_FAR)  ? farEdge  : (nearEdge + farEdge) / 2.0;
   if(tick > 0) price = MathRound(price / tick) * tick;
   price = NormalizeDouble(price, digits);

   // A limit must sit on the far side of the market; a gap price is
   // already back in cannot take one.
   if((dir == 1) ? (price > ask - minDist) : (price < bid + minDist))
   {
      lastGapUsed[s] = g[k].mid;
      Skip(s, side + " FVG " + DoubleToString(g[k].bot, digits) + "-" +
              DoubleToString(g[k].top, digits) + " already reached");
      return;
   }

   double buffer = InpSLBufferPoints * point;
   double frc    = FractalStop(s, dir, price, minDist + buffer + point);
   if(frc == 0.0) { Skip(s, side + " FVG found, no fractal beyond it"); return; }
   double sl = NormalizeDouble((dir == 1) ? frc - buffer : frc + buffer, digits);

   double lots = RiskLots(s, MathAbs(price - sl));
   CapLotsToMargin(sym, (dir == 1), price, lots);
   trade.SetTypeFillingBySymbol(sym);
   bool ok = (dir == 1)
             ? trade.BuyLimit(lots, price, sym, sl, 0.0, ORDER_TIME_GTC, 0, "M1 kumo FVG")
             : trade.SellLimit(lots, price, sym, sl, 0.0, ORDER_TIME_GTC, 0, "M1 kumo FVG");
   lastSkip[s] = "";
   if(ok)
   {
      lastGapUsed[s] = g[k].mid;
      Print(sym + " " + side + " limit @ " + DoubleToString(price, digits) + " lots " +
            DoubleToString(lots, 2) + " in FVG " + DoubleToString(g[k].bot, digits) + "-" +
            DoubleToString(g[k].top, digits) + " (" + TimeToString(g[k].mid, TIME_DATE | TIME_MINUTES) +
            ") | SL " + DoubleToString(sl, digits) + " (fractal)");
   }
   else
      Print(sym + " " + side + " limit failed, retcode " + IntegerToString(trade.ResultRetcode()));
}

//==============================================================
// Once per closed M1 bar — breakout state, pending orders,
// entries.
//==============================================================

void OnNewBar(int s)
{
   string sym = syms[s];
   int now  = KumoSide(s, 1);
   int prev = KumoSide(s, 2);

   // The setup lives only while price and chikou stay beyond the cloud.
   if(setupDir[s] != 0 && now != setupDir[s])
      Disarm(s, "price or chikou back in the cloud");

   // A fresh breakout arms a setup (it cannot re-arm an armed one: now
   // equals prev then).
   if(now != 0 && prev != now)
   {
      setupDir[s]  = now;
      setupTime[s] = iTime(sym, PERIOD_M1, 1);
      lastSkip[s]  = "";
      Print(sym + " " + ((now == 1) ? "bullish" : "bearish") +
            " kumo breakout (price + chikou) at " + TimeToString(setupTime[s], TIME_DATE | TIME_MINUTES));
   }

   // An unfilled limit goes when its side of the cloud is lost or it expires.
   int      odir;
   datetime placed;
   ulong    ord = FindPending(sym, odir, placed);
   if(ord != 0)
   {
      string why = "";
      if(now != odir) why = "price or chikou back in the cloud";
      else if(InpLimitExpiryBars > 0 &&
              iBarShift(sym, PERIOD_M1, placed, false) >= InpLimitExpiryBars)
         why = "expired after " + IntegerToString(InpLimitExpiryBars) + " bars";
      if(why == "") return;
      if(trade.OrderDelete(ord)) Print(sym + " limit cancelled: " + why);
      else { Print(sym + " limit cancel failed, retcode " + IntegerToString(trade.ResultRetcode())); return; }
   }

   int      pdir;
   datetime opened;
   if(FindPosition(sym, pdir, opened) != 0) return;
   if(setupDir[s] == 0) return;

   if(InpSetupMaxBars > 0 && iBarShift(sym, PERIOD_M1, setupTime[s], false) > InpSetupMaxBars)
   {
      Disarm(s, "no FVG taken within " + IntegerToString(InpSetupMaxBars) + " bars");
      return;
   }
   TryEntry(s);
}

//==============================================================
// Exit — the earliest time a standing OPPOSING gap confirmed
// after the fill has stood for more than InpHoldSeconds (0 =
// none yet). A bearish gap ends a long, a bullish gap a short.
//==============================================================

datetime OpposingDue(string sym, int dir, datetime opened)
{
   Gap g[];
   int n = FvgStanding(sym, BarsSince(sym, opened), dir != 1, g);
   datetime best = 0;
   for(int i = 0; i < n; i++)
   {
      if(g[i].formed <= opened) break;            // newest first: the rest formed before the fill
      datetime due = g[i].formed + InpHoldSeconds;
      if(best == 0 || due < best) best = due;
   }
   return best;
}

void ManagePosition(int s, bool newBar)
{
   string   sym = syms[s];
   int      dir;
   datetime opened;
   ulong    ticket = FindPosition(sym, dir, opened);
   if(ticket == 0) { exitDue[s] = 0; return; }

   // Filled: one trade per breakout.
   if(setupDir[s] != 0) Disarm(s, "limit filled");

   // Close mode only changes on a closed bar; the wick modes can end the
   // pending gap on any tick, so they rescan while one is counting down.
   if(newBar || (InpFvgMit != FVG_MIT_CLOSE && exitDue[s] != 0))
      exitDue[s] = OpposingDue(sym, dir, opened);

   if(exitDue[s] == 0 || TimeCurrent() <= exitDue[s]) return;

   if(trade.PositionClose(ticket))
   {
      Print(sym + " " + ((dir == 1) ? "long" : "short") + " closed: opposing FVG held over " +
            IntegerToString(InpHoldSeconds) + "s");
      exitDue[s] = 0;
   }
   else
      Print(sym + " close failed, retcode " + IntegerToString(trade.ResultRetcode()));
}

void OnTick()
{
   for(int s = 0; s < symsCount; s++)
   {
      datetime t = iTime(syms[s], PERIOD_M1, 1);
      bool newBar = (t != 0 && t != lastM1bar[s]);
      if(newBar)
      {
         lastM1bar[s] = t;
         OnNewBar(s);
      }
      ManagePosition(s, newBar);
   }
}
//This work is my worship unto GOD
