//+------------------------------------------------------------------+
//| Ichimoku M1+M2 KIHON / PO3 RANGE SCALPER                         |
//| EXPERIMENTAL BUILD — not deployed. Magic 20260876.               |
//|                                                                  |
//| THE IDEA: a scalper that trades INSIDE a PO3 range and takes     |
//| profit at a PO3 number, only at kihon suchi times of the day.    |
//| Three gates, cheapest first, any one of them can veto:           |
//|                                                                  |
//|   1. TIME      — is the day's H1, M30 or M15 count on a kihon    |
//|                  suchi number right now?                         |
//|   2. STRUCTURE — are M1 AND M2 clear on price and chikou, and do |
//|                  the higher timeframes (M5..H4) agree?           |
//|   3. PRICE     — is there room inside the PO3 range to the next  |
//|                  level, at an acceptable reward:risk?            |
//|                                                                  |
//| GATE 1 — KIHON TIME. Candles are counted from the DAY open on    |
//| H1, M30 and M15, inclusive (the candle at the open is candle 1,  |
//| the convention ported verbatim from po3-levels.mq5). The gate is |
//| open while ANY enabled timeframe's count sits within InpKihonTol |
//| of a kihon number (9, 17, 26, 33, 42, 51, 65, 76, 129, ...) that |
//| a trading day can actually reach on that timeframe:              |
//|   H1  (~24 a day)  — 9, 17                                       |
//|   M30 (~48 a day)  — 9, 17, 26, 33, 42                           |
//|   M15 (~96 a day)  — 9, 17, 26, 33, 42, 51, 65, 76               |
//| The reach cap is §38's "26 trap" solved in general: a nearest-   |
//| number test would otherwise open the gate on a number the day    |
//| never gets to once a tolerance is set. With the default          |
//| InpKihonTol = 0 the gate is open for the WHOLE candle carrying   |
//| the number — one hour on H1, 30 minutes on M30, 15 on M15 — and  |
//| a trade can come at any minute inside it, not only at the open.  |
//| CONFLUENCE: the strongest times are when all three counts sit on |
//| a number at once (08:00-08:15 and 16:00-16:15 on a midnight     |
//| rollover). InpKihonMinTFs (1-3) sets how many must agree.        |
//| BREAKOUT: with InpBreakoutOnly the M1+M2 pair must TURN aligned  |
//| inside the window (it was not aligned that way on the bar        |
//| before), and each breakout is traded once. Off, any minute the   |
//| chain is aligned inside the window will do.                      |
//| Outside the windows the EA does not open trades. Running         |
//| trades are never gated; their SL and TP are on the order.        |
//|                                                                  |
//| GATE 2 — STRUCTURE (top-down). The family's CheckAlign on every  |
//| timeframe from M1 up to InpAlignTop (default H4), all the same   |
//| way: the last closed close beyond tenkan, kijun and the whole    |
//| cloud, and the chikou (that close, Kijun bars back) beyond that  |
//| bar's high/low and beyond tenkan, kijun and cloud as they stood  |
//| there. M1 and M2 are the scalp trigger and are always checked;   |
//| InpAlignTop = M2 drops the higher-timeframe confirmation.        |
//| GATE 2b — ICHIMOKU STRUCTURE TARGET (InpStructTarget). When the  |
//| chain holds from M1 only part of the way — at least up to        |
//| InpStructMinTop (M5) — the first timeframe that fails is read    |
//| for where price is HEADING instead of being a veto. Its nearest  |
//| line ahead of price — tenkan, kijun, SSA or SSB — is the target  |
//| (price is expected to bounce there). The road must be free: no   |
//| tenkan, kijun, SSA or SSB of any timeframe above it (up to       |
//| InpAlignTop) between entry and that line, and each of their      |
//| chikous — and its own — able to travel the same distance without |
//| a past candle or line in the way (InpStructChikou,               |
//| InpChikouPathBars). When the line sits within                    |
//| InpStructPO3TolPips of a PO3 number the PO3 number is the target |
//| instead — the higher-probability case — and InpStructNeedPO3     |
//| trades only those. Fully aligned chains keep the PO3 target.     |
//| Both use the PO3 stop.                                           |
//|                                                                  |
//| M2 is REQUIRED here (unlike §39, which skipped it): the build is |
//| defined by the M1+M2 trigger, so a broker that refuses an M2     |
//| handle fails init loudly rather than trading a different build.  |
//|                                                                  |
//| GATE 3 — PO3 RANGE. The range is the cell between two adjacent   |
//| multiples of 3^InpPO3Power (scaled as in po3-levels.mq5 — at     |
//| scale 1 and power 2 that is a 9-dollar cell on gold). A long     |
//| targets the level ABOVE price and is stopped beyond the level    |
//| BELOW it; a short the reverse. So every trade lives inside one   |
//| cell:                                                            |
//|   TP = the level ahead,  InpTPBufferPips in front of it          |
//|   SL = the level behind, InpSLBufferPips beyond it               |
//|        (widened to InpMinSLPips when price hugs that level)      |
//| The entry is skipped when the reward is under InpMinTPPips or    |
//| the reward:risk under InpMinRR — price is too close to the level |
//| it is heading into. Structure gives the direction; PO3 gives the |
//| exit and the room veto. It does not fade levels.                 |
//|                                                                  |
//| ONE POSITION PER SYMBOL. Both levels ride on the order, so the   |
//| broker closes the trade; the EA never trails, never moves a stop |
//| and has no break-even. Its only upkeep is re-attaching a stop    |
//| that has gone missing.                                           |
//|                                                                  |
//| RISK: InpRiskPct of equity against the ACTUAL stop distance of   |
//| each trade, which varies with where price sits in the cell.      |
//|                                                                  |
//| WHAT THIS BUILD DELIBERATELY DOES NOT HAVE: the robustness pack, |
//| the bias ladder, the cloud-bias gate, kumo-touch exits, trailing |
//| and a margin cap. It is a clean test of one question, not a      |
//| hardened build. Do not deploy it to the VPS as it stands.        |
//|                                                                  |
//| Author: Neo Malesa                                               |
//+------------------------------------------------------------------+
#property strict
#property version  "1.00"

#include <Trade/Trade.mqh>

//--- Input Parameters ---
input string Symbols  = "GOLDm#";
input int    Tenkan   = 9;
input int    Kijun    = 26;
input int    SenkouB  = 52;
input int    Slippage = 30;

input group  "Gate 1 - Kihon Suchi Time (counted from the day open)"
input bool   InpKihonGateEnabled = true; // Only open trades at kihon times (off = any hour)
input bool   InpKihonH1  = true;         // H1 count on a kihon number opens the gate
input bool   InpKihonM30 = true;         // M30 count on a kihon number opens the gate
input bool   InpKihonM15 = true;         // M15 count on a kihon number opens the gate
input int    InpKihonTol = 0;            // Candles either side of the number (0 = on it exactly)
input int    InpKihonMinTFs = 1;         // How many of H1/M30/M15 must be on a number at once (1-3)
input bool   InpBreakoutOnly = true;     // M1+M2 must TURN aligned inside the kihon window (one trade per breakout)

input group  "Gate 2 - Alignment"
input ENUM_TIMEFRAMES InpAlignTop = PERIOD_H4; // Highest timeframe that must agree (M2 = M1+M2 only)

input group  "Gate 2b - Ichimoku Structure Target"
input bool   InpStructTarget   = true;        // Trade a partial breakout toward the next TF's nearest line
input ENUM_TIMEFRAMES InpStructMinTop = PERIOD_M5; // The breakout must reach at least this TF (M1+M2+..+this aligned)
input bool   InpStructChikou   = true;        // The chikou of the target TF and every TF above must be free too
input int    InpChikouPathBars = 3;           // Chikou path checked over this many bars (from its position toward now)
input double InpStructPO3TolPips = 10.0;      // Target line within this of a PO3 number -> the PO3 number is the target
input bool   InpStructNeedPO3  = false;       // Only trade structure targets whose line sits on a PO3 number

input group  "Gate 3 - PO3 Range"
input double InpPO3Scale     = 1.0;   // Scale divisor (1 = whole numbers, 100 = workbook 2dp) — as the indicator
input int    InpPO3Power     = 2;     // Range size = 3^power (2 = 9, 3 = 27, 4 = 81)
input double InpPipPoints    = 10.0;  // Points per pip (2-decimal gold = 10; 3-decimal gold = 100)
input double InpTPBufferPips = 5.0;   // TP sits this far IN FRONT of the target level
input double InpSLBufferPips = 10.0;  // SL sits this far BEYOND the level behind price
input double InpMinSLPips    = 20.0;  // Stop never closer than this
input double InpMinTPPips    = 20.0;  // Skip when the target is closer than this
input double InpMinRR        = 1.0;   // Skip when reward:risk is below this

input group  "Risk & Filters"
input double InpRiskPct         = 1.0;  // % of equity lost if the stop is hit
input double InpFixedLots       = 0.10; // Fallback lots (sizing data unavailable)
input int    InpMaxSpreadPoints = 60;   // Max spread in points to allow entry (0 = no limit)

//--- Constants and Global Variables ---
#define MAX_SYMS 60
#define TFS      7      // M1, M2, M5, M15, M30, H1, H4 — the alignment stack

ENUM_TIMEFRAMES tfs[TFS]    = { PERIOD_M1, PERIOD_M2, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4 };
string          tfName[TFS] = { "M1", "M2", "M5", "M15", "M30", "H1", "H4" };

int      ich[MAX_SYMS][TFS];
string   syms[MAX_SYMS];
int      symsCount = 0;
datetime lastM1bar[MAX_SYMS];
int      state[MAX_SYMS];        // 0 = flat, 1 = long, -1 = short
int      pairPrev[MAX_SYMS];     // M1+M2 direction on the previous bar (-99 = not read yet)
datetime brkTime[MAX_SYMS];      // open time of the bar the last M1+M2 breakout closed on
int      brkDir[MAX_SYMS];
bool     brkUsed[MAX_SYMS];      // that breakout has been traded
double   slPrice[MAX_SYMS];      // the stop placed at entry — the self-heal target
double   tpPrice[MAX_SYMS];
int      lastMinuteKey = -1;
int      alignTopIdx   = TFS - 1;
int      structMinIdx  = 2;

int MAGIC = 20260876;   // experimental kihon/PO3 range scalper (nothing else uses this)

CTrade trade;

//==============================================================
// Pips — InpPipPoints * SYMBOL_POINT, resolved per symbol.
//==============================================================

double PipPrice(const int s)
{
   return InpPipPoints * SymbolInfoDouble(syms[s], SYMBOL_POINT);
}

//==============================================================
// KIHON SUCHI CORE
//
// KihonCount is ported verbatim from experiments/po3-levels.mq5
// (via §38), so the EA and the chart agree on where a count stands:
// inclusive counting, Bars() over [anchor, now] so a candle before
// the anchor is never in the window.
//==============================================================

#define KIHON_COUNT     12
#define KIHON_SPAN_CAP  20000
const int Kihon[KIHON_COUNT] = { 9, 17, 26, 33, 42, 51, 65, 76, 129, 172, 226, 257 };

int KihonCount(const string sym, const ENUM_TIMEFRAMES tf, const datetime anchor)
{
   if(anchor <= 0)
      return(0);

   datetime cur = iTime(sym, tf, 0);
   if(cur == 0)
      return(0);                       // history not ready on this timeframe
   if(anchor >= cur)
      return(1);                       // anchor falls inside the developing candle

   int secs = PeriodSeconds(tf);
   if(secs > 0 && ((long)TimeCurrent() - (long)anchor) / secs > KIHON_SPAN_CAP)
      return(-1);

   int n = Bars(sym, tf, anchor, TimeCurrent());
   return(n > 0 ? n : 0);
}

//--- The kihon number the count n is on (within tol), or 0. Only numbers a
//--- trading day can reach on this timeframe are considered — see the header
//--- for why: a tolerance would otherwise open the gate on a number past the
//--- end of the day (§38's "26 trap" on H1).
int KihonHit(const int n, const ENUM_TIMEFRAMES tf, const int tol)
{
   int perDay = 86400 / PeriodSeconds(tf);
   for(int i = 0; i < KIHON_COUNT; i++)
   {
      if(Kihon[i] > perDay) break;
      if(MathAbs(n - Kihon[i]) <= tol) return(Kihon[i]);
   }
   return(0);
}

//--- One timeframe's reading, appended to info: "M15:33*" on the number,
//--- "M15:34(33)*" off it by the tolerance, "M15:28" when not on one. On a
//--- hit, 'start' is the open of the first candle of that timeframe's window
//--- (candle K - tol), so a trade anywhere inside the window can be dated
//--- against it — the gate covers the whole candle, not just its open.
bool KihonTfOK(const string sym, const ENUM_TIMEFRAMES tf, const string name,
               const datetime dayOpen, string &info, datetime &start)
{
   start = 0;
   int c = KihonCount(sym, tf, dayOpen);
   if(c <= 0)
   {
      info += " " + name + ":--";
      return(false);                   // unknown count does not open the gate
   }
   int tol = (int)MathMax(0, MathMin(8, InpKihonTol));
   int k   = KihonHit(c, tf, tol);
   info += " " + name + ":" + IntegerToString(c) +
           ((k > 0 && k != c) ? "(" + IntegerToString(k) + ")" : "") +
           (k > 0 ? "*" : "");
   if(k <= 0) return(false);

   int first = (int)MathMax(1, k - tol);
   start = iTime(sym, tf, 0) - (datetime)((c - first) * PeriodSeconds(tf));
   return(true);
}

//+------------------------------------------------------------------+
//| Gate 1. How many of H1, M30 and M15 are on a kihon number right  |
//| now (the CONFLUENCE, 0-3), and since when. The gate is open when |
//| that count reaches InpKihonMinTFs. 'winStart' is the latest of   |
//| the hit timeframes' window starts — the moment the current       |
//| confluence began — which is what a breakout is dated against.    |
//| 'info' records every reading, starred where it hit, with the     |
//| count: "H1:9* M30:17* M15:33* x3".                               |
//+------------------------------------------------------------------+
int KihonConfluence(const int s, string &info, datetime &winStart)
{
   info = ""; winStart = 0;
   if(!InpKihonGateEnabled) { info = "off"; return(3); }

   datetime dayOpen = iTime(syms[s], PERIOD_D1, 0);
   if(dayOpen <= 0) { info = "no D1 bar"; return(0); }

   int n = 0;
   datetime st;
   if(InpKihonH1  && KihonTfOK(syms[s], PERIOD_H1,  "H1",  dayOpen, info, st)) { n++; winStart = MathMax(winStart, st); }
   if(InpKihonM30 && KihonTfOK(syms[s], PERIOD_M30, "M30", dayOpen, info, st)) { n++; winStart = MathMax(winStart, st); }
   if(InpKihonM15 && KihonTfOK(syms[s], PERIOD_M15, "M15", dayOpen, info, st)) { n++; winStart = MathMax(winStart, st); }
   info += " x" + IntegerToString(n);
   StringTrimLeft(info);
   return(n);
}

//==============================================================
// Breakout tracking — the moment M1 and M2 TURN aligned.
//
// Read on every closed M1 bar, in or out of a kihon window and in or
// out of a trade, so the EA always knows when the current M1+M2
// alignment began. A breakout is the bar on which the pair goes from
// anything else to aligned one way (flat -> long, or short -> long).
// With InpBreakoutOnly the entry needs that bar to fall INSIDE the
// current kihon window, and each breakout is traded at most once.
//==============================================================

void TrackBreakout(const int s, const datetime barTime)
{
   int a1   = CheckAlign(s, 0);
   int pair = (a1 != 0 && CheckAlign(s, 1) == a1) ? a1 : 0;

   if(pairPrev[s] != -99 && pair != 0 && pair != pairPrev[s])
   {
      brkTime[s] = barTime;
      brkDir[s]  = pair;
      brkUsed[s] = false;
   }
   pairPrev[s] = pair;
}

//==============================================================
// PO3 CORE — levels are m x 3^n in a scaled integer space
// (price = raw / scale), as in po3-levels.mq5 and §38. A level's
// strength is 3^v3(raw); the levels of power >= k are exactly the
// multiples of 3^k, so the range around price is one division.
//==============================================================

long PO3Step(const int power)
{
   long v = 1;
   int  n = (power < 0) ? 0 : (power > 20 ? 20 : power);
   for(int i = 0; i < n; i++)
      v *= 3;
   return(v);
}

//--- How many times raw divides by 3 — the exponent of the strongest PO3
//--- level that lands on it, capped at 9 (19683) like the indicator's top grid.
int PO3Power(long raw)
{
   if(raw <= 0)
      return(0);
   int n = 0;
   while(n < 9 && (raw % 3) == 0)
   {
      raw /= 3;
      n++;
   }
   return(n);
}

string PO3Tag(const int s, const double lvl, const int power)
{
   return(DoubleToString(lvl, (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS)) +
          " (" + IntegerToString((int)PO3Step(power)) + ")");
}

struct RangePlan
{
   double target;   // the PO3 level ahead of price
   double behind;   // the PO3 level behind price
   int    tgtPow;   // the target level's real power
   string tgtName;  // "4491.00 (9)" for a PO3 target, "M15 SSB 4488.20" for a structure one
   double tp;
   double sl;
   double rr;
   string why;      // reason for a veto, empty when the plan is good
};

//--- The PO3 levels either side of entry: the next multiple of the step
//--- STRICTLY beyond entry in the trade's direction (so a price sitting on a
//--- level looks to the next one), and the level one step behind it.
bool PO3Levels(const int dir, const double entry, double &ahead, double &behind, int &power)
{
   long   step   = PO3Step(InpPO3Power);
   double scaled = entry * InpPO3Scale;
   long   m      = (dir == 1) ? (long)MathFloor(scaled / (double)step + 1e-9) + 1
                              : (long)MathCeil (scaled / (double)step - 1e-9) - 1;
   long   raw    = m * step;
   if(raw <= 0 || raw - dir * step <= 0) return(false);

   ahead  = (double)raw / InpPO3Scale;
   behind = (double)(raw - dir * step) / InpPO3Scale;
   power  = PO3Power(raw);
   return(true);
}

//+------------------------------------------------------------------+
//| Gate 3. Turn a target into an order, and veto it when there is   |
//| no room. The TP sits InpTPBufferPips in front of p.target; the   |
//| stop is always the PO3 range stop — InpSLBufferPips beyond the   |
//| PO3 level behind price, widened to InpMinSLPips — whichever kind |
//| of target the trade has. 'entry' is the price the order would    |
//| fill at (ask for a long, bid for a short).                       |
//+------------------------------------------------------------------+
bool FinishPlan(const int s, const int dir, const double entry, RangePlan &p)
{
   int    d   = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);
   double pip = PipPrice(s);

   p.tp = NormalizeDouble(p.target - dir * InpTPBufferPips * pip, d);
   p.sl = p.behind - dir * InpSLBufferPips * pip;
   if(dir * (entry - p.sl) < InpMinSLPips * pip)
      p.sl = entry - dir * InpMinSLPips * pip;
   p.sl = NormalizeDouble(p.sl, d);

   double reward = dir * (p.tp - entry);
   double risk   = dir * (entry - p.sl);
   if(risk <= 0) { p.why = "stop on the wrong side"; return(false); }
   p.rr = reward / risk;

   if(reward < InpMinTPPips * pip)
   {
      p.why = StringFormat("no room — %.1f pips to %s", reward / pip, p.tgtName);
      return(false);
   }
   if(p.rr < InpMinRR)
   {
      p.why = StringFormat("rr %.2f < %.2f to %s", p.rr, InpMinRR, p.tgtName);
      return(false);
   }

   double minDist = SymbolInfoInteger(syms[s], SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(syms[s], SYMBOL_POINT);
   double bid     = SymbolInfoDouble(syms[s], SYMBOL_BID);
   double ask     = SymbolInfoDouble(syms[s], SYMBOL_ASK);
   bool okSL = (dir == 1) ? (p.sl < bid - minDist) : (p.sl > ask + minDist);
   bool okTP = (dir == 1) ? (p.tp > ask + minDist) : (p.tp < bid - minDist);
   if(!okSL || !okTP) { p.why = "inside the broker's minimum stop distance"; return(false); }
   return(true);
}

//--- The full-alignment target: the PO3 level ahead of price.
bool PlanRange(const int s, const int dir, const double entry, RangePlan &p)
{
   p.target = 0; p.behind = 0; p.tgtPow = 0; p.tgtName = ""; p.tp = 0; p.sl = 0; p.rr = 0; p.why = "";
   if(!PO3Levels(dir, entry, p.target, p.behind, p.tgtPow)) { p.why = "no PO3 level ahead"; return(false); }
   p.tgtName = PO3Tag(s, p.target, p.tgtPow);
   return(FinishPlan(s, dir, entry, p));
}

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

   alignTopIdx = -1;
   for(int t = 1; t < TFS; t++)
      if(tfs[t] == InpAlignTop) alignTopIdx = t;
   if(alignTopIdx < 1)
   {
      Print("Alignment: InpAlignTop must be one of M2, M5, M15, M30, H1, H4. Aborting.");
      return(INIT_FAILED);
   }
   structMinIdx = -1;
   for(int t = 1; t < TFS; t++)
      if(tfs[t] == InpStructMinTop) structMinIdx = t;
   if(InpStructTarget && structMinIdx < 1)
   {
      Print("Structure target: InpStructMinTop must be one of M2, M5, M15, M30, H1, H4. Aborting.");
      return(INIT_FAILED);
   }
   if(InpKihonMinTFs < 1 || InpKihonMinTFs > 3)
   {
      Print("Kihon gate: InpKihonMinTFs must be 1-3. Aborting.");
      return(INIT_FAILED);
   }
   if(InpPipPoints <= 0 || InpPO3Scale <= 0 || InpPO3Power < 0 || InpPO3Power > 9)
   {
      Print("PO3: InpPipPoints and InpPO3Scale must be positive and InpPO3Power 0-9. Aborting.");
      return(INIT_FAILED);
   }

   for(int s = 0; s < symsCount; s++)
   {
      lastM1bar[s] = 0;
      pairPrev[s]  = -99;
      brkTime[s]   = 0;
      brkDir[s]    = 0;
      brkUsed[s]   = true;
      state[s]     = 0;
      slPrice[s]   = 0.0;
      tpPrice[s]   = 0.0;

      for(int t = 0; t < TFS; t++)
      {
         ich[s][t] = iIchimoku(syms[s], tfs[t], Tenkan, Kijun, SenkouB);
         if(ich[s][t] == INVALID_HANDLE)
         {
            Print(syms[s] + " refused an " + tfName[t] + " Ichimoku handle" +
                  (t == 1 ? " — this broker does not serve M2, which the scalp trigger needs" : "") +
                  ". Aborting.");
            return(INIT_FAILED);
         }
      }

      double pip  = PipPrice(s);
      int    d    = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);
      double step = (double)PO3Step(InpPO3Power) / InpPO3Scale;
      PrintFormat("PO3 range: %s — cell %s (3^%d), 1 pip = %s | TP buffer %.1f, SL buffer %.1f, "
                  "min SL %.1f, min TP %.1f pips, min rr %.2f",
                  syms[s], DoubleToString(step, d), InpPO3Power, DoubleToString(pip, d),
                  InpTPBufferPips, InpSLBufferPips, InpMinSLPips, InpMinTPPips, InpMinRR);
   }

   string chain = "M1";
   for(int t = 1; t <= alignTopIdx; t++) chain += "+" + tfName[t];
   Print("Alignment: " + chain + " all agreeing -> PO3 target.");
   if(InpStructTarget)
      Print("Structure target: ON — M1.." + tfName[structMinIdx] + " (at least) aligned with the next TF "
            "heading for its nearest line (tenkan/kijun/SSA/SSB) -> line target, road free up to " + tfName[alignTopIdx] +
            (InpStructChikou ? " (price and chikou)." : " (price only)."));

   if(InpKihonGateEnabled)
      PrintFormat("Kihon gate: ON — entries anywhere inside a candle where at least %d of the day's%s%s%s "
                  "counts are within %d of a reachable kihon number.", InpKihonMinTFs,
                  InpKihonH1 ? " H1" : "", InpKihonM30 ? " M30" : "", InpKihonM15 ? " M15" : "", InpKihonTol);
   else
      Print("Kihon gate: OFF — entries run at any hour.");
   Print(InpBreakoutOnly ? "Entry: BREAKOUT — M1+M2 must turn aligned inside the kihon window, one trade per breakout."
                         : "Entry: STATE — any minute the chain is aligned inside the kihon window.");

   trade.SetDeviationInPoints(Slippage);
   trade.SetExpertMagicNumber(MAGIC);
   SyncStateFromPositions();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   for(int s = 0; s < symsCount; s++)
      for(int t = 0; t < TFS; t++)
         if(ich[s][t] != INVALID_HANDLE) IndicatorRelease(ich[s][t]);
}

//==============================================================
// Position State — one position per symbol, found by magic.
// A restart recovers the direction from the position; the stop
// to heal to is the position's own, or, if that is already gone,
// the range stop rebuilt from the open price.
//==============================================================

bool SymbolTicket(const int s, ulong &ticket)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != syms[s]) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MAGIC) continue;
      return(true);
   }
   return(false);
}

void SyncStateFromPositions()
{
   for(int s = 0; s < symsCount; s++)
   {
      ulong ticket;
      if(!SymbolTicket(s, ticket))
      {
         state[s] = 0; slPrice[s] = 0.0; tpPrice[s] = 0.0;
         continue;
      }
      int dir = ((int)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      state[s] = dir;
      if(slPrice[s] == 0.0)
      {
         double curSL = PositionGetDouble(POSITION_SL);
         tpPrice[s]   = PositionGetDouble(POSITION_TP);
         if(curSL > 0.0)
            slPrice[s] = curSL;
         else
         {
            RangePlan p;
            PlanRange(s, dir, PositionGetDouble(POSITION_PRICE_OPEN), p);
            slPrice[s] = p.sl;
         }
      }
   }
}

//==============================================================
// Alignment Check — identical to the family's CheckAlign: price
// and chikou both above/below tenkan, kijun, and cloud on one
// timeframe. Returns 1 (bullish), -1 (bearish), 0 (none).
//==============================================================

int CheckAlign(const int s, const int tfIdx)
{
   ENUM_TIMEFRAMES tf = tfs[tfIdx];

   int sh      = 1;              // last closed bar
   int chShift = sh + Kijun;     // chikou's chart position for bar sh (Kijun bars back)

   MqlRates rt[];
   if(CopyRates(syms[s], tf, 0, chShift + 1, rt) <= 0) return 0;
   ArraySetAsSeries(rt, true);
   if(ArraySize(rt) <= chShift) return 0;

   double tenkan[1], kijun[1], senA[1], senB[1];
   if(CopyBuffer(ich[s][tfIdx], 0, sh, 1, tenkan) <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 1, sh, 1, kijun)  <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 2, sh, 1, senA)   <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 3, sh, 1, senB)   <= 0) return 0;

   double closeP = rt[sh].close;
   double cHi    = MathMax(senA[0], senB[0]);
   double cLo    = MathMin(senA[0], senB[0]);

   bool above = closeP > tenkan[0] && closeP > kijun[0] && closeP > cHi;
   bool below = closeP < tenkan[0] && closeP < kijun[0] && closeP < cLo;
   if(!above && !below) return 0;

   double tenkan_ch[1], kijun_ch[1], senA_ch[1], senB_ch[1];
   if(CopyBuffer(ich[s][tfIdx], 0, chShift, 1, tenkan_ch) <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 1, chShift, 1, kijun_ch)  <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 2, chShift, 1, senA_ch)   <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 3, chShift, 1, senB_ch)   <= 0) return 0;

   double chik = closeP;
   double cHiC = MathMax(senA_ch[0], senB_ch[0]);
   double cLoC = MathMin(senA_ch[0], senB_ch[0]);

   if(above && chik > rt[chShift].high &&
      chik > tenkan_ch[0] && chik > kijun_ch[0] && chik > cHiC) return  1;

   if(below && chik < rt[chShift].low &&
      chik < tenkan_ch[0] && chik < kijun_ch[0] && chik < cLoC) return -1;

   return 0;
}

//--- Gate 2. Walk the chain from M1 up to InpAlignTop and report how far it
//--- holds: 'top' is the highest timeframe index aligned the same way as M1
//--- with every timeframe below it aligned too. M1 first (the cheapest to
//--- fail). Returns the direction, or 0 when M1 and M2 do not both agree.
int ChainWalk(const int s, int &top)
{
   top = -1;
   int dir = CheckAlign(s, 0);
   if(dir == 0) return 0;
   top = 0;
   for(int t = 1; t <= alignTopIdx; t++)
   {
      if(CheckAlign(s, t) != dir) break;
      top = t;
   }
   return (top >= 1) ? dir : 0;
}

//==============================================================
// Ichimoku structure target (gate 2b)
//
// A partial breakout: M1 up to some timeframe is aligned, and the
// next timeframe up is not. Its nearest line ahead of price — tenkan,
// kijun, SSA or SSB — is where price is heading and where it is
// expected to bounce, so it becomes the target. The trade is only
// taken when the road to it is clear: no tenkan, kijun or cloud edge
// of any timeframe above it lies between entry and that line, and
// (InpStructChikou) each of those timeframes' chikou can travel the
// same distance without meeting a past candle or line.
//==============================================================

//--- True when 'lvl' lies strictly between entry and the target, on the
//--- trade's side — an obstacle on the road.
bool OnRoad(const double lvl, const int dir, const double from, const double to)
{
   return (dir * (lvl - from) > 0 && dir * (lvl - to) < 0);
}

//--- Price side: this timeframe's current tenkan, kijun, Span A and Span B.
bool PriceFree(const int s, const int t, const int dir, const double from, const double to, string &why)
{
   double v[1];
   string nm[4] = { "tenkan", "kijun", "SSA", "SSB" };
   for(int b = 0; b < 4; b++)
   {
      if(CopyBuffer(ich[s][t], b, 1, 1, v) <= 0) { why = tfName[t] + " unreadable"; return(false); }
      if(OnRoad(v[0], dir, from, to)) { why = tfName[t] + " " + nm[b] + " in the way"; return(false); }
   }
   return(true);
}

//--- Chikou side: the last closed close, plotted Kijun bars back, must be
//--- able to move 'dist' in the trade's direction. Its path is the columns
//--- from its own position toward now (InpChikouPathBars of them): the
//--- candle extreme it would run into and the four lines as they stood.
bool ChikouFree(const int s, const int t, const int dir, const double dist, string &why)
{
   int n       = (int)MathMax(1, MathMin(Kijun - 1, InpChikouPathBars));
   int chShift = 1 + Kijun;

   MqlRates rt[];
   if(CopyRates(syms[s], tfs[t], 0, chShift + 1, rt) <= chShift) { why = tfName[t] + " chikou unreadable"; return(false); }
   ArraySetAsSeries(rt, true);

   double from = rt[1].close;
   double to   = from + dir * dist;
   for(int k = 0; k < n; k++)
   {
      int sh = chShift - k;
      double ext = (dir == 1) ? rt[sh].high : rt[sh].low;
      if(OnRoad(ext, dir, from, to)) { why = tfName[t] + " chikou blocked by price"; return(false); }

      double v[1];
      for(int b = 0; b < 4; b++)
      {
         if(CopyBuffer(ich[s][t], b, sh, 1, v) <= 0) { why = tfName[t] + " chikou unreadable"; return(false); }
         if(OnRoad(v[0], dir, from, to)) { why = tfName[t] + " chikou blocked by a line"; return(false); }
      }
   }
   return(true);
}

//+------------------------------------------------------------------+
//| Gate 2b. 'tt' is the first timeframe above the aligned chain.    |
//| Its nearest line ahead is the target, and the road to it must be |
//| free on tt and every timeframe above it up to InpAlignTop.       |
//+------------------------------------------------------------------+
bool PlanStructure(const int s, const int dir, const int tt, const double entry, RangePlan &p)
{
   p.target = 0; p.behind = 0; p.tgtPow = 0; p.tgtName = ""; p.tp = 0; p.sl = 0; p.rr = 0; p.why = "";

   //--- The target is the NEAREST of tt's four lines ahead of entry —
   //--- tenkan, kijun, SSA or SSB, whichever price reaches first.
   string nm[4] = { "tenkan", "kijun", "SSA", "SSB" };
   double line  = 0.0;
   int    which = -1;
   for(int b = 0; b < 4; b++)
   {
      double v[1];
      if(CopyBuffer(ich[s][tt], b, 1, 1, v) <= 0) { p.why = tfName[tt] + " unreadable"; return(false); }
      if(dir * (v[0] - entry) <= 0) continue;                  // behind price
      if(which < 0 || dir * (v[0] - line) < 0) { line = v[0]; which = b; }
   }
   if(which < 0) { p.why = tfName[tt] + " has no line ahead"; return(false); }

   int d = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);
   p.target  = line;
   p.tgtName = tfName[tt] + " " + nm[which] + " " + DoubleToString(line, d);

   //--- A line that coincides with a PO3 number is the higher-probability
   //--- target, and the PO3 number is what the trade aims at. The nearest
   //--- multiple of the range step counts when it is within the tolerance
   //--- and still ahead of entry.
   long   step = PO3Step(InpPO3Power);
   long   raw  = (long)MathRound(line * InpPO3Scale / (double)step) * step;
   double lvl  = (double)raw / InpPO3Scale;
   bool   onPO3 = (raw > 0 && MathAbs(lvl - line) <= InpStructPO3TolPips * PipPrice(s) &&
                   dir * (lvl - entry) > 0);
   if(!onPO3 && InpStructNeedPO3) { p.why = p.tgtName + " not on a PO3 number"; return(false); }

   //--- The road is checked to whichever of the line and the PO3 number comes
   //--- first: a PO3 number just past the line must not count the line itself
   //--- as an obstacle, and one just short of it is where the trade ends.
   double roadTo = line;
   if(onPO3 && dir * (lvl - line) < 0) roadTo = lvl;

   double dist = dir * (roadTo - entry);
   for(int t = tt; t <= alignTopIdx; t++)
   {
      if(!PriceFree(s, t, dir, entry, roadTo, p.why)) return(false);
      if(InpStructChikou && !ChikouFree(s, t, dir, dist, p.why)) return(false);
   }

   double ahead;
   int    pw;
   if(!PO3Levels(dir, entry, ahead, p.behind, pw)) { p.why = "no PO3 level behind"; return(false); }

   if(onPO3)
   {
      p.target  = lvl;
      p.tgtPow  = PO3Power(raw);
      p.tgtName += " = PO3 " + PO3Tag(s, lvl, p.tgtPow);
   }
   return(FinishPlan(s, dir, entry, p));
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

bool SpreadOK(const string sym)
{
   if(InpMaxSpreadPoints <= 0) return true;
   return SymbolInfoInteger(sym, SYMBOL_SPREAD) <= InpMaxSpreadPoints;
}

//--- Lots such that a stop-out at this trade's own stop loses InpRiskPct.
double RiskLots(const int s, const double stopDist)
{
   if(InpRiskPct <= 0 || stopDist <= 0) return InpFixedLots;

   double tickValue = SymbolInfoDouble(syms[s], SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(syms[s], SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0 || tickSize <= 0) return InpFixedLots;

   double moneyPerLot = (stopDist / tickSize) * tickValue;
   if(moneyPerLot <= 0) return InpFixedLots;

   double lots = AccountInfoDouble(ACCOUNT_EQUITY) * (InpRiskPct / 100.0) / moneyPerLot;

   double lotStep = SymbolInfoDouble(syms[s], SYMBOL_VOLUME_STEP);
   double lotMin  = SymbolInfoDouble(syms[s], SYMBOL_VOLUME_MIN);
   double lotMax  = SymbolInfoDouble(syms[s], SYMBOL_VOLUME_MAX);
   if(lotStep > 0) lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(lotMin, MathMin(lotMax, lots));

   return (lots > 0) ? lots : InpFixedLots;
}

//==============================================================
// Trading
//==============================================================

bool OpenScalp(const int s, const int dir, const RangePlan &p, const double entry, const string kihonInfo)
{
   string sym  = syms[s];
   double lots = RiskLots(s, dir * (entry - p.sl));

   trade.SetTypeFillingBySymbol(sym);
   string comment = (dir == 1) ? "PO3 Scalp Buy" : "PO3 Scalp Sell";
   bool ok = (dir == 1) ? trade.Buy(lots, sym, entry, p.sl, p.tp, comment)
                        : trade.Sell(lots, sym, entry, p.sl, p.tp, comment);
   if(ok)
   {
      state[s]   = dir;
      slPrice[s] = p.sl;
      tpPrice[s] = p.tp;

      int    d   = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      double pip = PipPrice(s);
      string msg = PCTime() + " | " + ((dir == 1) ? "Buy " : "Sell ") + sym + " @ " +
                   DoubleToString(lots, 2) + " | TP " + DoubleToString(p.tp, d) + " -> " +
                   p.tgtName + ", SL " + DoubleToString(p.sl, d) +
                   " behind " + DoubleToString(p.behind, d) +
                   StringFormat(" | %.0f/%.0f pips, rr %.2f", dir * (p.tp - entry) / pip,
                                dir * (entry - p.sl) / pip, p.rr) +
                   " [" + kihonInfo + "]";
      Print(msg); SendNotification(msg);
   }
   return ok;
}

//--- Free the slot when the broker has closed the trade, and re-attach a
//--- stop that has gone missing. Nothing else moves.
void ManagePosition(const int s)
{
   ulong ticket;
   if(!SymbolTicket(s, ticket))
   {
      Print(PCTime() + " | " + syms[s] + " scalp closed at the broker (SL or TP).");
      state[s] = 0; slPrice[s] = 0.0; tpPrice[s] = 0.0;
      return;
   }

   if(PositionGetDouble(POSITION_SL) != 0.0 || slPrice[s] <= 0.0) return;

   string sym     = syms[s];
   double minDist = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(sym, SYMBOL_POINT);
   bool   okHeal  = (state[s] == 1) ? (slPrice[s] < SymbolInfoDouble(sym, SYMBOL_BID) - minDist)
                                    : (slPrice[s] > SymbolInfoDouble(sym, SYMBOL_ASK) + minDist);
   if(okHeal && trade.PositionModify(ticket, slPrice[s], PositionGetDouble(POSITION_TP)))
      Print(PCTime() + " | " + sym + " stop was missing — re-attached at " +
            DoubleToString(slPrice[s], (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)));
   else if(okHeal)
      Print(PCTime() + " | " + sym + " stop is missing and could not be re-attached, retcode " +
            IntegerToString(trade.ResultRetcode()));
}

//==============================================================
// Main Loop — runs once per closed M1 bar.
//==============================================================

void OnTick()
{
   int nowKey = (int)(TimeCurrent() / 60);
   if(nowKey == lastMinuteKey) return;
   lastMinuteKey = nowKey;

   bool synced = false;
   for(int s = 0; s < symsCount; s++)
   {
      MqlRates m1[];
      if(CopyRates(syms[s], PERIOD_M1, 0, 2, m1) < 2) continue;
      ArraySetAsSeries(m1, true);
      if(m1[1].time == lastM1bar[s]) continue;
      lastM1bar[s] = m1[1].time;

      if(!synced) { SyncStateFromPositions(); synced = true; }

      TrackBreakout(s, m1[1].time);

      if(state[s] != 0) { ManagePosition(s); continue; }

      // Gate 1 — time: enough of H1/M30/M15 on a kihon number, anywhere
      // inside the candle. Market-wide and the cheapest, so it goes first.
      string   kInfo;
      datetime winStart;
      if(KihonConfluence(s, kInfo, winStart) < InpKihonMinTFs) continue;
      if(!SpreadOK(syms[s])) continue;

      // The breakout must have happened inside this window and not been traded.
      if(InpBreakoutOnly && (brkUsed[s] || brkTime[s] < winStart)) continue;

      // Gate 2 — structure. Fully aligned to InpAlignTop: PO3 target.
      // Aligned only part of the way: the next TF's nearest line (or the PO3 number on it), if the road is free.
      int top;
      int dir = ChainWalk(s, top);
      if(dir == 0) continue;
      if(InpBreakoutOnly && dir != brkDir[s]) continue;

      bool full = (top >= alignTopIdx);
      if(!full && !(InpStructTarget && top >= structMinIdx)) continue;

      // Gate 3 — the target and the room to it.
      double entry = (dir == 1) ? SymbolInfoDouble(syms[s], SYMBOL_ASK)
                                : SymbolInfoDouble(syms[s], SYMBOL_BID);
      RangePlan p;
      bool planned = full ? PlanRange(s, dir, entry, p) : PlanStructure(s, dir, top + 1, entry, p);
      if(!planned)
      {
         // Structure vetoes are routine (most partial chains have no clear
         // road), so only a chain that reached a target is worth a line.
         if(full || StringFind(p.why, "rr ") == 0 || StringFind(p.why, "no room") == 0)
            Print(PCTime() + " | " + syms[s] + ((dir == 1) ? " long" : " short") +
                  " aligned to " + tfName[top] + " at kihon time [" + kInfo + "] but skipped — " + p.why);
         continue;
      }

      if(InpBreakoutOnly)
         kInfo += " | breakout " + TimeToString(brkTime[s], TIME_MINUTES);
      if(OpenScalp(s, dir, p, entry, kInfo))
         brkUsed[s] = true;
      else
         Print(PCTime() + " | " + syms[s] + " entry signal but order failed, retcode " +
               IntegerToString(trade.ResultRetcode()));
   }
}
//This work is my worship unto GOD
