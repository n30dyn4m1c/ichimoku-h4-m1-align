//+------------------------------------------------------------------+
//| PO3 SWEEP REJECTION EA                                           |
//| EXPERIMENTAL BUILD — not deployed. Magic 20260877.               |
//|                                                                  |
//| THE IDEA (Hopi's PO3 dealing ranges, the user's reading of gold):|
//| price breaks a PO3 level, overshoots into the next range, but    |
//| usually does NOT reach that range's midpoint — it is rejected    |
//| and trades back through the level. A close beyond the level      |
//| decides nothing; only the midpoint does.                         |
//|                                                                  |
//| On a 27 range (InpLevelPower = 3), level 4077, next range        |
//| 4077-4104:                                                       |
//|   4090.5  ACCEPTANCE LINE (InpAcceptPct = 50 of the next range)  |
//|           a close beyond it = a real break, the level flips      |
//|   4077    LEVEL — a close back through it WITH a rejection       |
//|           pattern = a rejection, traded the other way            |
//| Between the two is the SWEEP ZONE, where nothing is decided yet. |
//|                                                                  |
//| Every sweep ends one of three ways, read on closed InpSignalTF   |
//| bars (M5 default, M1 optional):                                  |
//|   ACCEPTED — a close beyond the acceptance line                  |
//|   REJECTED — a close back through the level on a bar that shows  |
//|              a turtle soup (the sweep took out the prior         |
//|              InpTSLookback-bar extreme) or an engulfing candle   |
//|   EXPIRED  — neither within InpSweepMaxBars                      |
//| The mirror (a sweep BELOW a level, rejected upward) is a long.   |
//|                                                                  |
//| A REJECTED sweep opens one trade against the sweep:              |
//|   stop  — beyond the acceptance line + InpStopBufferPts (if      |
//|           price gets there the break was real, the idea is wrong)|
//|   target— InpTPPct of a range back through the level (100 = the  |
//|           far side of the range the sweep came from)             |
//| optionally only with the Ichimoku cloud bias of H1/H4 (the fade  |
//| is taken only against a counter-trend pop, §7) and inside a      |
//| session window. One trade at a time.                             |
//|                                                                  |
//| MEASUREMENT: every sweep is written to a CSV in the COMMON Files |
//| folder (po3-sweep-<symbol>.csv) with its grade, overshoot and    |
//| outcome, and a per-grade summary is printed at the end of a run. |
//| InpTrade = false runs it as a pure measurement.                  |
//+------------------------------------------------------------------+
#property copyright "Neo Malesa"
#property version   "1.00"

#include <Trade/Trade.mqh>

enum PatternMode
{
   PAT_TURTLE = 0,   // turtle soup only
   PAT_ENGULF = 1,   // engulfing only
   PAT_EITHER = 2    // either one
};

enum BiasMode
{
   BIAS_NONE = 0,    // no bias filter
   BIAS_H1   = 1,    // H1 close beyond the cloud
   BIAS_H4   = 2     // H4 close beyond the cloud
};

input group  "PO3 Levels"
input double InpPO3Scale   = 1.0;   // Scale divisor (1 = whole numbers, 100 = workbook 2dp) — as the indicator
input int    InpLevelPower = 3;     // Levels = multiples of 3^power (2 = 9, 3 = 27, 4 = 81)
input double InpAcceptPct  = 50.0;  // Acceptance line, % into the next range (50 = midpoint, 66.7 = upper third)

input group  "Rejection"
input ENUM_TIMEFRAMES InpSignalTF = PERIOD_M5; // Timeframe the sweep and pattern are read on
input PatternMode     InpPattern  = PAT_ENGULF; // Rejection pattern required (engulfing: best in the §51 backtests)
input int    InpTSLookback   = 20;  // Turtle soup: the sweep must take out this many bars' extreme
input int    InpSweepMaxBars = 24;  // Sweep expires after this many signal bars undecided

input group  "Filters"
input BiasMode InpBias          = BIAS_H4; // Trade only with the cloud bias (a sell needs price below the cloud)
input int    InpSessionStart    = 15;   // Server hour trades may open from (0-23; 15-20 = New York on GOLDm#)
input int    InpSessionEnd      = 20;   // Server hour trades stop opening (24 = end of day; start > end wraps midnight)
input int    InpMaxSpreadPoints = 60;   // Max spread in points to allow entry (0 = no limit)

input group  "Trade"
input bool   InpTrade          = true;  // Open trades (false = measure and log only)
input int    InpStopBufferPts  = 50;    // Stop this many points beyond the acceptance line
input double InpTPPct          = 100.0; // Target, % of a range back through the level
input double InpMinRR          = 1.0;   // Skip when reward:risk is below this
input double InpRiskPct        = 1.0;   // % of equity lost if the stop is hit (0 = fixed lots)
input double InpFixedLots      = 0.01;  // Fallback lots
input bool   InpCsvLog         = true;  // Write every sweep to the CSV

const int Tenkan  = 9;
const int Kijun   = 26;
const int SenkouB = 52;

int MAGIC = 20260877;   // experimental PO3 sweep rejection (nothing else uses this)

enum Outcome { OUT_ACCEPTED = 0, OUT_REJECTED = 1, OUT_EXPIRED = 2 };

struct Sweep
{
   bool     active;
   int      side;      // +1 = sweep ABOVE a level (short setup), -1 = BELOW (long setup)
   double   level;
   double   accept;
   int      grade;     // the level's real power (3 = 27, 4 = 81, ...)
   double   priorExt;  // the prior InpTSLookback-bar extreme when the sweep began
   double   extreme;   // furthest price reached beyond the level
   datetime start;
   int      bars;
};

Sweep    sw[2];               // [0] above a level, [1] below a level
datetime resolvedBar[2];      // the bar each side last resolved on (no restart on that bar)
CTrade   trade;
int      ichH = INVALID_HANDLE;
int      csv  = INVALID_HANDLE;
datetime lastBar = 0;
double   stepPx  = 0.0;

//--- per grade (index = power, 0-9): outcomes, and the overshoot of rejected sweeps
int      nSweep[10], nAcc[10], nRej[10], nExp[10], nTraded[10];
double   rejOverPct[10];

//+------------------------------------------------------------------+
//| PO3 arithmetic — the same as po3-levels.mq5 and the kihon-po3 EAs |
//+------------------------------------------------------------------+
long PO3Step(const int power)
{
   long v = 1;
   int  n = (power < 0) ? 0 : (power > 20 ? 20 : power);
   for(int i = 0; i < n; i++)
      v *= 3;
   return(v);
}

//--- How many times raw divides by 3, capped at 9 (19683) like the indicator.
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

//--- The level at or below px (dir = -1) or at or above px (dir = +1).
double LevelNear(const double px, const int dir, int &grade)
{
   long step = PO3Step(InpLevelPower);
   double q  = px * InpPO3Scale / (double)step;
   long raw  = ((dir > 0) ? (long)MathCeil(q) : (long)MathFloor(q)) * step;
   grade = PO3Power(raw);
   return((double)raw / InpPO3Scale);
}

//+------------------------------------------------------------------+
int OnInit()
{
   if(InpPO3Scale <= 0 || InpLevelPower < 1 || InpLevelPower > 9 ||
      InpAcceptPct <= 0 || InpAcceptPct >= 100 || InpTSLookback < 1 || InpSweepMaxBars < 1)
   {
      Print("PO3 sweep: bad inputs (scale > 0, power 1-9, accept 0-100, lookback and max bars >= 1). Aborting.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   stepPx = (double)PO3Step(InpLevelPower) / InpPO3Scale;
   trade.SetExpertMagicNumber(MAGIC);
   trade.SetTypeFillingBySymbol(_Symbol);

   if(InpBias != BIAS_NONE)
   {
      ichH = iIchimoku(_Symbol, (InpBias == BIAS_H1) ? PERIOD_H1 : PERIOD_H4, Tenkan, Kijun, SenkouB);
      if(ichH == INVALID_HANDLE)
      {
         Print("PO3 sweep: Ichimoku handle failed. Aborting.");
         return(INIT_FAILED);
      }
   }

   for(int k = 0; k < 2; k++) { sw[k].active = false; resolvedBar[k] = 0; }
   ArrayInitialize(nSweep, 0); ArrayInitialize(nAcc, 0); ArrayInitialize(nRej, 0);
   ArrayInitialize(nExp, 0);   ArrayInitialize(nTraded, 0); ArrayInitialize(rejOverPct, 0.0);

   if(InpCsvLog)
   {
      csv = FileOpen("po3-sweep-" + _Symbol + ".csv", FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
      if(csv != INVALID_HANDLE)
         FileWrite(csv, "start", "end", "side", "level", "grade", "accept", "extreme",
                   "overshoot_pct", "bars", "outcome", "pattern", "start_hour", "traded");
      else
         Print("PO3 sweep: CSV open failed, error ", GetLastError(), " — continuing without it.");
   }

   PrintFormat("PO3 sweep: %s levels every %s (3^%d), acceptance at %.1f%% of the next range, read on %s.",
               _Symbol, DoubleToString(stepPx, _Digits), InpLevelPower, InpAcceptPct,
               EnumToString(InpSignalTF));
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("PO3 sweep summary — grade: sweeps / accepted / rejected / expired / traded | avg rejected overshoot");
   for(int g = 0; g < 10; g++)
   {
      if(nSweep[g] == 0) continue;
      PrintFormat("  %5d: %d / %d (%.0f%%) / %d (%.0f%%) / %d / %d | %.0f%% of a range",
                  (int)PO3Step(g), nSweep[g],
                  nAcc[g], 100.0 * nAcc[g] / nSweep[g],
                  nRej[g], 100.0 * nRej[g] / nSweep[g],
                  nExp[g], nTraded[g],
                  (nRej[g] > 0) ? rejOverPct[g] / nRej[g] : 0.0);
   }
   if(csv != INVALID_HANDLE) FileClose(csv);
   if(ichH != INVALID_HANDLE) IndicatorRelease(ichH);
}

//+------------------------------------------------------------------+
//| Filters                                                          |
//+------------------------------------------------------------------+
bool HasPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MAGIC)
         return(true);
   }
   return(false);
}

bool SessionOK()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(InpSessionStart <= InpSessionEnd)
      return(dt.hour >= InpSessionStart && dt.hour < InpSessionEnd);
   return(dt.hour >= InpSessionStart || dt.hour < InpSessionEnd);   // wraps midnight
}

bool SpreadOK()
{
   if(InpMaxSpreadPoints <= 0) return(true);
   return(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) <= InpMaxSpreadPoints);
}

//--- The bias timeframe's last closed close beyond its cloud in direction dir.
bool BiasOK(const int dir, string &why)
{
   if(InpBias == BIAS_NONE) return(true);
   ENUM_TIMEFRAMES tf = (InpBias == BIAS_H1) ? PERIOD_H1 : PERIOD_H4;
   double senA[1], senB[1];
   if(CopyBuffer(ichH, 2, 1, 1, senA) <= 0 || CopyBuffer(ichH, 3, 1, 1, senB) <= 0)
   {
      why = "bias cloud unreadable";
      return(false);
   }
   double c = iClose(_Symbol, tf, 1);
   bool ok = (dir == 1) ? (c > MathMax(senA[0], senB[0])) : (c < MathMin(senA[0], senB[0]));
   if(!ok) why = EnumToString(tf) + " close not " + ((dir == 1) ? "above" : "below") + " the cloud";
   return(ok);
}

//--- Lots such that a stop-out loses InpRiskPct of equity.
double RiskLots(const double stopDist)
{
   if(InpRiskPct <= 0 || stopDist <= 0) return(InpFixedLots);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0 || tickSize <= 0) return(InpFixedLots);

   double moneyPerLot = (stopDist / tickSize) * tickValue;
   if(moneyPerLot <= 0) return(InpFixedLots);
   double lots = AccountInfoDouble(ACCOUNT_EQUITY) * (InpRiskPct / 100.0) / moneyPerLot;

   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double lotMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotMax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(lotStep > 0) lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(lotMin, MathMin(lotMax, lots));
   return((lots > 0) ? lots : InpFixedLots);
}

//+------------------------------------------------------------------+
//| Sweeps                                                           |
//+------------------------------------------------------------------+
//--- Rejection pattern on closed bar r[1] for a sweep on 'side'.
//--- Returns "TS", "ENG", "TS+ENG" or "" (none that InpPattern accepts).
string Pattern(const Sweep &s, const MqlRates &r[])
{
   bool ts  = s.side * (s.extreme - s.priorExt) > 0;   // the sweep ran the prior extreme's stops
   bool eng;
   if(s.side == 1)   // bearish engulfing
      eng = r[1].close < r[1].open && r[2].close > r[2].open &&
            r[1].open >= r[2].close && r[1].close <= r[2].open;
   else              // bullish engulfing
      eng = r[1].close > r[1].open && r[2].close < r[2].open &&
            r[1].open <= r[2].close && r[1].close >= r[2].open;

   if(InpPattern == PAT_TURTLE) eng = false;
   if(InpPattern == PAT_ENGULF) ts  = false;
   if(ts && eng) return("TS+ENG");
   if(ts)        return("TS");
   if(eng)       return("ENG");
   return("");
}

void Resolve(const int k, const Outcome out, const string pat, const bool traded, const datetime end)
{
   Sweep s = sw[k];
   int g = s.grade;
   double overPct = 100.0 * s.side * (s.extreme - s.level) / stepPx;

   nSweep[g]++;
   if(out == OUT_ACCEPTED) nAcc[g]++;
   if(out == OUT_EXPIRED)  nExp[g]++;
   if(out == OUT_REJECTED) { nRej[g]++; rejOverPct[g] += overPct; }
   if(traded) nTraded[g]++;

   string outName = (out == OUT_ACCEPTED) ? "accepted" : (out == OUT_REJECTED ? "rejected" : "expired");
   if(csv != INVALID_HANDLE)
   {
      MqlDateTime dt;
      TimeToStruct(s.start, dt);
      FileWrite(csv, TimeToString(s.start), TimeToString(end), (s.side == 1) ? "above" : "below",
                DoubleToString(s.level, _Digits), (int)PO3Step(g), DoubleToString(s.accept, _Digits),
                DoubleToString(s.extreme, _Digits), DoubleToString(overPct, 1), s.bars, outName,
                pat, dt.hour, traded ? 1 : 0);
   }
   sw[k].active   = false;
   resolvedBar[k] = end;
}

//--- Trade a rejected sweep against its side. True when an order was placed.
bool TradeRejection(const Sweep &s, const string pat)
{
   if(!InpTrade || HasPosition()) return(false);
   string why = "";
   if(!SessionOK())              why = "outside session";
   else if(!SpreadOK())          why = "spread too wide";
   else if(!BiasOK(-s.side, why)) { }
   if(why != "")
   {
      PrintFormat("PO3 sweep: %s rejection at %s skipped — %s.", (s.side == 1) ? "sell" : "buy",
                  DoubleToString(s.level, _Digits), why);
      return(false);
   }

   int    dir   = -s.side;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double entry = (dir == 1) ? ask : bid;
   double sl    = NormalizeDouble(s.accept + s.side * InpStopBufferPts * point, _Digits);
   double tp    = NormalizeDouble(s.level - s.side * stepPx * InpTPPct / 100.0, _Digits);
   double risk  = dir * (entry - sl);
   double rew   = dir * (tp - entry);
   double minD  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;

   if(risk <= minD || rew <= minD)
   {
      PrintFormat("PO3 sweep: rejection at %s skipped — price already past the stop or target.",
                  DoubleToString(s.level, _Digits));
      return(false);
   }
   if(rew / risk < InpMinRR)
   {
      PrintFormat("PO3 sweep: rejection at %s skipped — R:R %.2f below %.2f.",
                  DoubleToString(s.level, _Digits), rew / risk, InpMinRR);
      return(false);
   }

   double lots = RiskLots(risk);
   string comment = StringFormat("PO3 %s %d %s", (dir == 1) ? "Buy" : "Sell", (int)PO3Step(s.grade), pat);
   bool ok = (dir == 1) ? trade.Buy(lots, _Symbol, entry, sl, tp, comment)
                        : trade.Sell(lots, _Symbol, entry, sl, tp, comment);
   if(ok)
      PrintFormat("PO3 sweep: %s %.2f @ %s | level %s (%d) swept to %s, %s | SL %s TP %s R:R %.2f",
                  (dir == 1) ? "BUY" : "SELL", lots, DoubleToString(entry, _Digits),
                  DoubleToString(s.level, _Digits), (int)PO3Step(s.grade),
                  DoubleToString(s.extreme, _Digits), pat,
                  DoubleToString(sl, _Digits), DoubleToString(tp, _Digits), rew / risk);
   else
      PrintFormat("PO3 sweep: order failed, retcode %d.", trade.ResultRetcode());
   return(ok);
}

//--- Advance sweep k by closed bar r[1].
void UpdateSweep(const int k, const MqlRates &r[])
{
   sw[k].bars++;
   if(sw[k].side == 1) sw[k].extreme = MathMax(sw[k].extreme, r[1].high);
   else                sw[k].extreme = MathMin(sw[k].extreme, r[1].low);

   double c = r[1].close;
   if(sw[k].side * (c - sw[k].accept) > 0)
   {
      Resolve(k, OUT_ACCEPTED, "", false, r[1].time);
      return;
   }
   if(sw[k].side * (sw[k].level - c) > 0)
   {
      string pat = Pattern(sw[k], r);
      if(pat != "")
      {
         bool traded = TradeRejection(sw[k], pat);
         Resolve(k, OUT_REJECTED, pat, traded, r[1].time);
         return;
      }
   }
   if(sw[k].bars >= InpSweepMaxBars)
      Resolve(k, OUT_EXPIRED, "", false, r[1].time);
}

//--- A new sweep begins when bar r[1] trades through a level that bar r[2]
//--- closed on the other side of.
void StartSweeps(const MqlRates &r[])
{
   for(int k = 0; k < 2; k++)
   {
      if(sw[k].active || resolvedBar[k] == r[1].time) continue;
      int    side = (k == 0) ? 1 : -1;
      int    grade;
      //--- above: the highest level at or below the high; below: the lowest at or above the low
      double lvl = (side == 1) ? LevelNear(r[1].high, -1, grade) : LevelNear(r[1].low, 1, grade);
      bool crossed = (side == 1) ? (r[2].close < lvl && r[1].high > lvl)
                                 : (r[2].close > lvl && r[1].low  < lvl);
      if(!crossed) continue;

      double prior = r[2].high, lo = r[2].low;
      for(int i = 2; i <= InpTSLookback + 1; i++)
      {
         prior = MathMax(prior, r[i].high);
         lo    = MathMin(lo, r[i].low);
      }

      sw[k].active   = true;
      sw[k].side     = side;
      sw[k].level    = lvl;
      sw[k].accept   = lvl + side * stepPx * InpAcceptPct / 100.0;
      sw[k].grade    = grade;
      sw[k].priorExt = (side == 1) ? prior : lo;
      sw[k].extreme  = lvl;
      sw[k].start    = r[1].time;
      sw[k].bars     = 0;
      UpdateSweep(k, r);                   // the crossing bar itself can accept or reject
   }
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime bar = iTime(_Symbol, InpSignalTF, 0);
   if(bar == 0 || bar == lastBar) return;

   MqlRates r[];
   ArraySetAsSeries(r, true);
   int need = InpTSLookback + 2;
   if(CopyRates(_Symbol, InpSignalTF, 0, need, r) < need) return;   // retried next tick
   lastBar = bar;

   for(int k = 0; k < 2; k++)
      if(sw[k].active) UpdateSweep(k, r);
   StartSweeps(r);
}
//+------------------------------------------------------------------+
