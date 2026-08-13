//+------------------------------------------------------------------+
//| Ichimoku Structure-Map EA (experimental)                         |
//| Idea:  instead of a boolean "all timeframes aligned" breakout     |
//|        gate, the direction is anchored top-down: scan the         |
//|        timeframes from the highest down (H4 first, then H1) and   |
//|        take the FIRST one where price and the chikou are "free    |
//|        to move" (price past its kijun, chikou clear of the candle |
//|        Kijun bars back). That timeframe decides the direction.    |
//|        Being inside the cloud is acceptable — the cloud is read   |
//|        as an obstacle and a target, never as a veto.              |
//| Entry: the lower timeframes do NOT have to align — they only      |
//|        have to show potential movement in the Ichimoku structures:|
//|        price pulls back into a level (kijun, tenkan, cloud edge)  |
//|        on the anchor timeframes, reacts away from it on the       |
//|        trigger timeframe with a confirming candle, and the leg    |
//|        on the swing timeframe still reads as a pullback.          |
//| Trade: the setup is only taken when the numbers work — a          |
//|        structure-based stop behind the reaction level, the next   |
//|        structural obstacle as the target, and a minimum           |
//|        reward:risk. Size scales with the conviction score.        |
//| Exit:  swing-structure trail, break-even lock, kijun-cross        |
//|        fallback, ATR protective stop.                             |
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

//--- Timeframe slots run highest to lowest. Set a slot to PERIOD_CURRENT to
//--- switch it off; the stack can be anchored anywhere from MN1 downwards.
//--- Direction: the first of the top InpAnchorTFs slots with a "price and
//--- chikou free to move" read; the lower slots only add conviction.
//--- Monthly-anchored preset — MN1 / W1 / D1 / H4 / H1 / M15, weights
//--- 3 / 2.5 / 2 / 1.5 / 1 / 0.5, InpTrigIdx = 5 (time entries on M15),
//--- InpExitIdx = 3 (hold on the H4 scale), InpLegTFIdx = 2 (grade D1 legs),
//--- InpAnchorTFs = 3 (scan MN1/W1/D1 for the first free read),
//--- InpLevelTFs = 3 (bounce off MN1/W1/D1 structures), InpObstacleTFs = 4
//--- (measure room down to H4 — monthly obstacles alone are so far away that
//--- the reward:risk gate stops filtering anything).
input group  "Structure Map — timeframes and weights"
input ENUM_TIMEFRAMES InpTF1 = PERIOD_H4;      // Slot 1 (highest — trend anchor)
input ENUM_TIMEFRAMES InpTF2 = PERIOD_H1;      // Slot 2
input ENUM_TIMEFRAMES InpTF3 = PERIOD_M15;     // Slot 3
input ENUM_TIMEFRAMES InpTF4 = PERIOD_M5;      // Slot 4
input ENUM_TIMEFRAMES InpTF5 = PERIOD_CURRENT; // Slot 5 (PERIOD_CURRENT = off)
input ENUM_TIMEFRAMES InpTF6 = PERIOD_CURRENT; // Slot 6 (PERIOD_CURRENT = off)
input int    InpAnchorTFs    = 2;   // Top N slots scanned for the "free to move" read
input double InpW1 = 3.0;    // Weight of slot 1 in the conviction bonus (never a gate)
input double InpW2 = 2.0;    // Weight of slot 2 in the conviction bonus
input double InpW3 = 1.5;    // Weight of slot 3 in the conviction bonus
input double InpW4 = 0.5;    // Weight of slot 4 in the conviction bonus
input double InpW5 = 0.0;    // Weight of slot 5 in the conviction bonus
input double InpW6 = 0.0;    // Weight of slot 6 in the conviction bonus
input int    InpTrigIdx     = 2;  // Slot of the trigger TF — reaction, candles, entry cadence
input int    InpExitIdx     = 1;  // Slot of the exit/holding TF (1 = H1 — between H4 anchor and M15 trigger)
input int    InpLegTFIdx    = 1;  // Slot of the TF whose legs/retracement are graded
input int    InpLevelTFs    = 2;  // Bounce levels are taken from the top N slots
input int    InpObstacleTFs = 2;  // Target obstacles are scanned across the top N slots

input group  "Structure Map — measurement"
input int    InpSlopeBars     = 5;    // Bars used to measure kijun slope
input double InpFlatSlopeATR  = 0.15; // Kijun is "flat" when its move over InpSlopeBars <= this x ATR
input int    InpSwingWing     = 2;    // Fractal half-width for a swing point (bars each side)
input int    InpLegBars       = 120;  // Bars scanned per timeframe for swing legs
input int    InpATRPeriod     = 14;   // ATR period (computed per timeframe)

input group  "Reaction (bounce) detection"
input int    InpReactionBars     = 3;    // Trigger-TF bars back to search for the level touch
input double InpTouchATR         = 0.25; // Level counts as touched within this x ATR(trigger)
input double InpMaxEntryDistATR  = 1.25; // Max distance from the level at entry (x ATR trigger)
input bool   InpUseKijunLevels   = true; // Bounce off tenkan/kijun levels
input bool   InpUseCloudLevels   = true; // Bounce off cloud edges (span A/B boundaries)
input bool   InpUseTenkanLevels  = true; // Include the (weakest) tenkan level

input group  "Candle structure at the level"
input double InpMinCandleScore = 1.0;  // Minimum price-action score to accept the reaction
input double InpPinWickFrac    = 0.50; // Rejection wick >= this fraction of the candle range
input double InpPinBodyFrac    = 0.40; // Rejection body <= this fraction of the candle range
input bool   InpUseMomentumBar = true; // Score a close beyond the reaction bar's extreme

input group  "Leg / retracement quality"
input double InpMinRetrace  = 0.25; // Shallowest pullback accepted (fraction of prior leg)
input double InpMaxRetrace  = 0.90; // Deepest pullback accepted before it reads as reversal
input double InpLateLegATR  = 6.0;  // Move already this extended (x ATR) reads as late (0 = off)

input group  "Conviction scoring"
input double InpMinContext   = 25.0; // Min anchor "free to move" strength to trade (0..100)
input double InpMinScore     = 55.0; // Min conviction score to open a trade (0..100)
input double InpStrongScore  = 75.0; // Conviction at/above this uses the full order ladder
input bool   InpLogMap       = true; // Print the structure map on every evaluated setup

input group  "Trade construction"
input double InpSLBufferATR   = 0.30; // Stop padding beyond the reaction extreme (x ATR trigger)
input bool   InpSLBeyondSwing = true; // Push the stop beyond the last trigger-TF swing too
input double InpMaxRiskATR    = 4.0;  // Skip the setup if the structural stop exceeds this x ATR
input double InpMinRR         = 1.5;  // Min reward:risk to the next obstacle, else skip
input double InpMaxRR         = 8.0;  // Obstacles beyond this R are ignored (order runs free)
input double InpTPBufferATR   = 0.25; // Front-run the obstacle by this x ATR(trigger)
input double InpRunnerFrac    = 0.50; // Fraction of the ladder left without a take profit

input group  "Risk Protection"
input bool   InpUseStopLoss        = true;  // Attach the structural stop loss to every entry
input double InpATRMultiplier      = 3.0;   // Fallback stop = ATR(trigger) x this
input int    InpMaxSpreadPoints    = 60;    // Max spread in points to allow entry (0 = no limit)
input double InpHighEquityRiskPct  = 1.0;   // % of equity risked per trade once equity > $8000
input int    InpReentryCooldownSec = 900;   // Min seconds after an exit before re-entering
input double InpMaxRiskPct         = 0.0;   // Cap total initial-stop risk per ladder (0 = no cap)

input group  "Exit Management"
input bool   InpStructTrail      = true;  // Trail the stop behind each new confirmed swing
input double InpTrailActivateATR = 0.5;   // Arm the structure trail once profit >= this x ATR(exit TF)
input int    InpTrailWing        = 2;     // Fractal half-width for trail swings
input int    InpTrailSwingBars   = 60;    // Exit-TF bars scanned for the trail swing
input bool   InpKijunExit        = true;  // Close on an exit-TF close across its kijun
input bool   InpExitOnFlip       = false; // Close when the context score flips against the trade
input bool   InpBEEnabled        = true;  // Move the stop to break even once in profit
input double InpBEActivateATR    = 1.0;   // Profit needed to arm break even (x ATR exit TF)
input int    InpBECoverPoints    = 15;    // Points beyond break even (covers the spread)

//--- Constants and Global Variables ---
#define MAX_SYMS   60
#define TF_COUNT   6
#define MAX_LEVELS 32
#define SCORE_MAX  10.0   // maximum raw component sum in ScoreMap()

// One timeframe's complete reading of where price sits and what the legs did.
struct TFMap
{
   bool   ok;
   double atr;
   double open, high, low, close;
   double tenkan, kijun, spanA, spanB, cloudHi, cloudLo;
   double futA, futB;          // cloud projected Kijun bars ahead (twist read)
   int    cloudSide;           // +1 above cloud, 0 inside, -1 below
   double cloudThickATR;       // cloud thickness in ATR
   int    twist;               // +1 future span A above span B, -1 below
   int    tkState;             // +1 tenkan above kijun, -1 below
   double kijunSlopeATR;       // signed kijun move over InpSlopeBars, in ATR
   bool   kijunFlat;
   int    chikou;              // +1 chikou clear above the candle 26 back, -1 below, 0 tangled
   double dKijunATR;           // signed close-to-kijun distance in ATR
   double dTenkanATR;
   double dCloudATR;           // signed distance to the nearest cloud edge (0 when inside)
   int    structDir;           // +1 higher highs and higher lows, -1 lower, 0 mixed
   double swHi, swLo;          // most recent confirmed fractal high / low
   double pSwHi, pSwLo;        // the ones before those
   int    idxHi, idxLo;        // their bar indexes (0 = last closed bar)
   int    legDir;              // +1 price rising from the last pivot, -1 falling
   double legATR;              // size of the leg in progress, in ATR
   double impulseATR;          // size of the last completed leg, in ATR
   double retraceFrac;         // legATR / impulseATR
   double score;               // normalised directional read, -1..+1
};

// A price level price can react against.
struct Level
{
   double price;
   int    grade;   // higher = more structurally significant
   string name;
};

ENUM_TIMEFRAMES tfs[TF_COUNT];
double          wts[TF_COUNT];
bool            tfOn[TF_COUNT];   // slot enabled (not PERIOD_CURRENT)
int             g_exitIdx = 0;    // resolved exit/holding slot

int      ich[MAX_SYMS][TF_COUNT];
int      atrH[MAX_SYMS][TF_COUNT];
string   syms[MAX_SYMS];
int      symsCount = 0;

datetime lastTrigBar[MAX_SYMS];
datetime lastM1bar[MAX_SYMS];
datetime noReentryUntil[MAX_SYMS];
int      lastMinuteKey = -1;

int      state[MAX_SYMS];        // 0 = flat, 1 = long, -1 = short
double   entryPrice[MAX_SYMS];
datetime entryTime[MAX_SYMS];
bool     beMoved[MAX_SYMS];
double   entryConv[MAX_SYMS];    // conviction score the trade was opened on

TFMap    g_map[TF_COUNT];        // structure map of the symbol under evaluation

int MAGIC = 20260834;

CTrade trade;

//==============================================================
// Small helpers
//==============================================================

int Sgn(double v)
{
   if(v > 0.0) return  1;
   if(v < 0.0) return -1;
   return 0;
}

double Clamp(double v, double lo, double hi)
{
   if(v < lo) return lo;
   if(v > hi) return hi;
   return v;
}

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

// "PERIOD_H4" -> "H4" for compact log lines
string TFName(int t)
{
   string n = EnumToString(tfs[t]);
   if(StringSubstr(n, 0, 7) == "PERIOD_") n = StringSubstr(n, 7);
   return n;
}

// ATR of timeframe t on the last closed bar; 0 when unavailable.
double ATRv(int s, int t)
{
   double a[1];
   if(atrH[s][t] == INVALID_HANDLE) return 0.0;
   if(CopyBuffer(atrH[s][t], 0, 1, 1, a) <= 0) return 0.0;
   return (a[0] > 0.0) ? a[0] : 0.0;
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

// Bars of history a slot needs before its map can be built. A monthly slot
// asks for ~56 monthly candles (about 4.5 years), so this is worth checking
// up front rather than discovering it as a silent no-trade condition.
int BarsNeeded()
{
   return (int)MathMax(SenkouB, Kijun + InpSlopeBars) + 4;
}

int OnInit()
{
   tfs[0] = InpTF1; tfs[1] = InpTF2; tfs[2] = InpTF3;
   tfs[3] = InpTF4; tfs[4] = InpTF5; tfs[5] = InpTF6;
   wts[0] = InpW1;  wts[1] = InpW2;  wts[2] = InpW3;
   wts[3] = InpW4;  wts[4] = InpW5;  wts[5] = InpW6;

   // A slot left at PERIOD_CURRENT is switched off: it is never mapped, never
   // scored, supplies no levels, and allocates no indicator handles.
   for(int t = 0; t < TF_COUNT; t++) tfOn[t] = (tfs[t] != PERIOD_CURRENT);

   if(InpTrigIdx  < 0 || InpTrigIdx  >= TF_COUNT || !tfOn[InpTrigIdx])
      return(INIT_PARAMETERS_INCORRECT);
   if(InpLegTFIdx < 0 || InpLegTFIdx >= TF_COUNT || !tfOn[InpLegTFIdx])
      return(INIT_PARAMETERS_INCORRECT);
   if(InpLevelTFs    < 1 || InpLevelTFs    > TF_COUNT) return(INIT_PARAMETERS_INCORRECT);
   if(InpObstacleTFs < 1 || InpObstacleTFs > TF_COUNT) return(INIT_PARAMETERS_INCORRECT);
   if(InpAnchorTFs   < 1 || InpAnchorTFs   > TF_COUNT) return(INIT_PARAMETERS_INCORRECT);

   // The exit/holding slot defaults to the trigger slot, which keeps the
   // single-scale behaviour when no separate holding timeframe is wanted.
   g_exitIdx = (InpExitIdx < 0) ? InpTrigIdx : InpExitIdx;
   if(g_exitIdx >= TF_COUNT || !tfOn[g_exitIdx]) return(INIT_PARAMETERS_INCORRECT);

   // The exit timeframe must not be faster than the trigger timeframe — a
   // holding scale shorter than the timing scale is incoherent.
   if(PeriodSeconds(tfs[g_exitIdx]) < PeriodSeconds(tfs[InpTrigIdx]))
      return(INIT_PARAMETERS_INCORRECT);

   double wsum = 0.0;
   for(int t = 0; t < TF_COUNT; t++)
      if(tfOn[t]) wsum += MathMax(0.0, wts[t]);
   if(wsum <= 0.0) return(INIT_PARAMETERS_INCORRECT);

   symsCount = ParseSymbols(Symbols);
   if(symsCount <= 0) return(INIT_FAILED);

   int need = BarsNeeded();
   for(int s = 0; s < symsCount; s++)
   {
      state[s]          = 0;
      lastTrigBar[s]    = 0;
      lastM1bar[s]      = 0;
      noReentryUntil[s] = 0;
      entryPrice[s]     = 0.0;
      entryTime[s]      = 0;
      beMoved[s]        = false;
      entryConv[s]      = 0.0;

      for(int t = 0; t < TF_COUNT; t++)
      {
         ich[s][t]  = INVALID_HANDLE;
         atrH[s][t] = INVALID_HANDLE;
         if(!tfOn[t]) continue;

         ich[s][t] = iIchimoku(syms[s], tfs[t], Tenkan, Kijun, SenkouB);
         if(ich[s][t] == INVALID_HANDLE) return(INIT_FAILED);

         atrH[s][t] = iATR(syms[s], tfs[t], InpATRPeriod);
         if(atrH[s][t] == INVALID_HANDLE) return(INIT_FAILED);

         // Warn rather than fail: history often fills in after the terminal
         // finishes downloading, and a weighted slot that stays short simply
         // keeps the EA flat until it is ready.
         int have = Bars(syms[s], tfs[t]);
         if(have < need)
            Print(PCTime() + " | " + syms[s] + " " + TFName(t) + " has " +
                  IntegerToString(have) + " bars, needs " + IntegerToString(need) +
                  " — no signals on this symbol until the history fills in");
      }
   }

   trade.SetDeviationInPoints(Slippage);
   trade.SetExpertMagicNumber(MAGIC);
   SyncStateFromPositions();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   for(int s = 0; s < symsCount; s++)
      for(int t = 0; t < TF_COUNT; t++)
      {
         if(ich[s][t]  != INVALID_HANDLE) IndicatorRelease(ich[s][t]);
         if(atrH[s][t] != INVALID_HANDLE) IndicatorRelease(atrH[s][t]);
      }
}

//==============================================================
// Position State Sync (recover after restart)
//==============================================================

void SyncStateFromPositions()
{
   int  prevState[MAX_SYMS];
   bool hasPos[MAX_SYMS];
   for(int s = 0; s < symsCount; s++) { prevState[s] = state[s]; state[s] = 0; hasPos[s] = false; }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MAGIC) continue;

      string sym  = PositionGetString(POSITION_SYMBOL);
      int    type = (int)PositionGetInteger(POSITION_TYPE);
      int    dir  = (type == POSITION_TYPE_BUY) ? 1 : -1;

      for(int s = 0; s < symsCount; s++)
      {
         if(syms[s] != sym) continue;
         state[s]  = dir;
         hasPos[s] = true;
         // Restarted mid-trade: rebuild the references from the position itself.
         if(entryPrice[s] == 0.0) entryPrice[s] = PositionGetDouble(POSITION_PRICE_OPEN);
         if(entryTime[s]  == 0)   entryTime[s]  = (datetime)PositionGetInteger(POSITION_TIME);
         break;
      }
   }

   for(int s = 0; s < symsCount; s++)
   {
      if(!hasPos[s])
      {
         entryPrice[s] = 0.0;
         entryTime[s]  = 0;
         beMoved[s]    = false;
         entryConv[s]  = 0.0;
      }
      // A position that vanished since the last sync (stop hit, manual close)
      // frees the symbol; arm the cooldown so it can't flip straight back in.
      if(prevState[s] != 0 && state[s] == 0)
         noReentryUntil[s] = TimeCurrent() + InpReentryCooldownSec;
   }
}

//==============================================================
// Swing legs: the most recent two fractal highs and lows on a
// timeframe, with the bar index of each most-recent pivot.
// Index 0 = last closed bar. Returns false when the history is
// too short or fewer than two of either pivot exist.
//==============================================================

bool FindSwings(int s, ENUM_TIMEFRAMES tf, int bars, int wing,
                double &swHi, double &swLo, double &pSwHi, double &pSwLo,
                int &idxHi, int &idxLo)
{
   swHi = 0.0; swLo = 0.0; pSwHi = 0.0; pSwLo = 0.0;
   idxHi = -1; idxLo = -1;

   int w    = (int)MathMax(1, wing);
   int need = bars + w + 2;

   MqlRates rt[];
   if(CopyRates(syms[s], tf, 1, need, rt) < w * 2 + 3) return false;
   ArraySetAsSeries(rt, true);   // rt[0] = last closed bar

   int n    = ArraySize(rt);
   int last = n - 1 - w;

   int hiFound = 0, loFound = 0;
   for(int j = w; j <= last && (hiFound < 2 || loFound < 2); j++)
   {
      if(hiFound < 2)
      {
         bool isHi = true;
         for(int k = 1; k <= w && isHi; k++)
            if(rt[j-k].high >= rt[j].high || rt[j+k].high >= rt[j].high) isHi = false;
         if(isHi)
         {
            if(hiFound == 0) { swHi = rt[j].high; idxHi = j; }
            else               pSwHi = rt[j].high;
            hiFound++;
         }
      }
      if(loFound < 2)
      {
         bool isLo = true;
         for(int k = 1; k <= w && isLo; k++)
            if(rt[j-k].low <= rt[j].low || rt[j+k].low <= rt[j].low) isLo = false;
         if(isLo)
         {
            if(loFound == 0) { swLo = rt[j].low; idxLo = j; }
            else               pSwLo = rt[j].low;
            loFound++;
         }
      }
   }

   return (hiFound >= 1 && loFound >= 1);
}

//==============================================================
// Structure Map: everything this EA knows about one timeframe.
//==============================================================

bool BuildMap(int s, int t, TFMap &m)
{
   // Wipe first: g_map is reused across symbols, and a timeframe that fails to
   // build must never leave the previous symbol's readings behind.
   ZeroMemory(m);

   double atrv = ATRv(s, t);
   if(atrv <= 0.0) return false;
   m.atr = atrv;

   int need = (int)MathMax(SenkouB, Kijun + InpSlopeBars) + 4;

   MqlRates rt[];
   if(CopyRates(syms[s], tfs[t], 1, need, rt) < need) return false;
   ArraySetAsSeries(rt, true);   // rt[0] = last closed bar, rt[k] = k bars before it

   m.open  = rt[0].open;
   m.high  = rt[0].high;
   m.low   = rt[0].low;
   m.close = rt[0].close;

   // Ichimoku lines at the last closed bar. The Senkou buffers are pre-shifted:
   // the value read at shift p is the cloud as drawn at chart position p.
   double tk[1], kj[1], sa[1], sb[1];
   if(CopyBuffer(ich[s][t], 0, 1, 1, tk) <= 0) return false;
   if(CopyBuffer(ich[s][t], 1, 1, 1, kj) <= 0) return false;
   if(CopyBuffer(ich[s][t], 2, 1, 1, sa) <= 0) return false;
   if(CopyBuffer(ich[s][t], 3, 1, 1, sb) <= 0) return false;

   m.tenkan  = tk[0];
   m.kijun   = kj[0];
   m.spanA   = sa[0];
   m.spanB   = sb[0];
   m.cloudHi = MathMax(sa[0], sb[0]);
   m.cloudLo = MathMin(sa[0], sb[0]);

   // Where price sits
   if(m.close > m.cloudHi)      m.cloudSide =  1;
   else if(m.close < m.cloudLo) m.cloudSide = -1;
   else                         m.cloudSide =  0;

   m.cloudThickATR = (m.cloudHi - m.cloudLo) / atrv;
   m.dKijunATR     = (m.close - m.kijun)  / atrv;
   m.dTenkanATR    = (m.close - m.tenkan) / atrv;
   if(m.cloudSide ==  1)      m.dCloudATR = (m.close - m.cloudHi) / atrv;
   else if(m.cloudSide == -1) m.dCloudATR = (m.close - m.cloudLo) / atrv;
   else                       m.dCloudATR = 0.0;

   m.tkState = Sgn(m.tenkan - m.kijun);

   // The cloud as it will be drawn Kijun bars ahead: span A is today's
   // tenkan/kijun midpoint, span B today's SenkouB-bar midpoint. Reading it
   // this way avoids depending on how far forward the buffer is plotted.
   double hh = rt[0].high, ll = rt[0].low;
   for(int i = 1; i < SenkouB && i < ArraySize(rt); i++)
   {
      if(rt[i].high > hh) hh = rt[i].high;
      if(rt[i].low  < ll) ll = rt[i].low;
   }
   m.futA  = (m.tenkan + m.kijun) / 2.0;
   m.futB  = (hh + ll) / 2.0;
   m.twist = Sgn(m.futA - m.futB);

   // Kijun slope over InpSlopeBars bars
   double kjOld[1];
   if(CopyBuffer(ich[s][t], 1, 1 + InpSlopeBars, 1, kjOld) <= 0) return false;
   m.kijunSlopeATR = (m.kijun - kjOld[0]) / atrv;
   m.kijunFlat     = (MathAbs(m.kijunSlopeATR) <= InpFlatSlopeATR);

   // Chikou span: the last closed bar's close, plotted Kijun bars back. It is
   // "free" when it sits clear of the candle body/wick range at that position.
   m.chikou = 0;
   if(ArraySize(rt) > Kijun)
   {
      if(m.close > rt[Kijun].high)     m.chikou =  1;
      else if(m.close < rt[Kijun].low) m.chikou = -1;
   }

   // Swing legs (all leg fields stay at the ZeroMemory defaults when the
   // timeframe has no confirmed pivots yet)
   if(FindSwings(s, tfs[t], InpLegBars, InpSwingWing,
                 m.swHi, m.swLo, m.pSwHi, m.pSwLo, m.idxHi, m.idxLo))
   {
      if(m.pSwHi > 0.0 && m.pSwLo > 0.0)
      {
         if(m.swHi > m.pSwHi && m.swLo > m.pSwLo)      m.structDir =  1;
         else if(m.swHi < m.pSwHi && m.swLo < m.pSwLo) m.structDir = -1;
      }

      if(m.idxHi >= 0 && m.idxLo >= 0)
      {
         double impulse = MathAbs(m.swHi - m.swLo);
         m.impulseATR = impulse / atrv;

         // The leg in progress runs from the most recent pivot to price. Its
         // direction is taken from the sign of that move, not assumed from
         // which pivot came last — price can trade straight through a pivot.
         double d = (m.idxLo < m.idxHi) ? (m.close - m.swLo)    // low is newer
                                        : (m.close - m.swHi);   // high is newer
         m.legDir = Sgn(d);
         m.legATR = MathAbs(d) / atrv;
         if(m.impulseATR > 0.0) m.retraceFrac = m.legATR / m.impulseATR;
      }
   }

   m.ok = true;
   return true;
}

//==============================================================
// Score one timeframe's map into a normalised directional read.
// Every component is signed; the raw sum spans -SCORE_MAX..+SCORE_MAX.
//==============================================================

double ScoreMap(TFMap &m)
{
   if(!m.ok) return 0.0;

   double sc = 0.0;
   sc += 2.0 * m.cloudSide;                                  // side of the cloud
   sc += 1.0 * m.twist;                                      // future cloud direction
   sc += 1.0 * m.tkState;                                    // tenkan / kijun cross state
   sc += 1.5 * Sgn(m.close - m.kijun);                       // price vs kijun
   sc += 0.5 * Sgn(m.close - m.tenkan);                      // price vs tenkan
   sc += 1.5 * m.chikou;                                     // chikou free space
   sc += 2.0 * m.structDir;                                  // higher highs / lower lows
   sc += 0.5 * Clamp(m.kijunSlopeATR / 0.5, -1.0, 1.0);      // kijun slope

   m.score = Clamp(sc / SCORE_MAX, -1.0, 1.0);
   return m.score;
}

//==============================================================
// The "price and chikou free to move" read. For a long, price must
// be on top of its kijun with the chikou clear of the candle Kijun
// bars back — then nothing structural blocks the move upward. Being
// inside the cloud is acceptable: the cloud is a target/obstacle,
// never a veto. Returns +1 / -1 / 0.
//==============================================================

int ReadOpportunity(TFMap &m)
{
   if(!m.ok) return 0;
   if(m.close > m.kijun && m.chikou >= 0) return  1;
   if(m.close < m.kijun && m.chikou <= 0) return -1;
   return 0;
}

// How clean that read is, 0..100. A bare pass (price barely over a
// flat kijun, tangled chikou) scores ~40 and needs reaction quality
// elsewhere to reach the conviction gate.
double OppStrength(TFMap &m, int dir)
{
   if(!m.ok || dir == 0) return 0.0;
   double s = 0.0;
   if(dir == 1)
   {
      if(m.close > m.kijun)                 s += 40.0;
      if(m.chikou > 0)                      s += 30.0;
      else if(m.chikou == 0)                s += 15.0;
      if(m.twist > 0)                       s += 15.0;
      if(m.kijunSlopeATR > InpFlatSlopeATR) s += 15.0;
   }
   else
   {
      if(m.close < m.kijun)                 s += 40.0;
      if(m.chikou < 0)                      s += 30.0;
      else if(m.chikou == 0)                s += 15.0;
      if(m.twist < 0)                       s += 15.0;
      if(m.kijunSlopeATR < -InpFlatSlopeATR)s += 15.0;
   }
   return Clamp(s, 0.0, 100.0);
}

// Same idea without the opportunity gate: how much structure on this
// timeframe supports the trade direction, 0..100. Lower timeframes do
// not need to align — this only adds conviction when they do.
double DirStrength(TFMap &m, int dir)
{
   if(!m.ok || dir == 0) return 0.0;
   double s = 0.0;
   if(dir == 1)
   {
      if(m.close > m.kijun)                 s += 30.0;
      if(m.chikou > 0)                      s += 20.0;
      if(m.twist > 0)                       s += 20.0;
      if(m.structDir > 0)                   s += 20.0;
      if(m.kijunSlopeATR > InpFlatSlopeATR) s += 10.0;
   }
   else
   {
      if(m.close < m.kijun)                 s += 30.0;
      if(m.chikou < 0)                      s += 20.0;
      if(m.twist < 0)                       s += 20.0;
      if(m.structDir < 0)                   s += 20.0;
      if(m.kijunSlopeATR < -InpFlatSlopeATR)s += 10.0;
   }
   return Clamp(s, 0.0, 100.0);
}

// Build every timeframe's map for the symbol. The direction is NOT
// derived here — the anchor cascade in EvaluateSetup picks the highest
// timeframe with a "free to move" read, and the lower timeframes never
// gate the trade, they only add conviction. Returns false only when a
// slot needed for timing (trigger) or levels cannot be read.
bool BuildContext(int s)
{
   bool okTrig   = false;
   bool okAnyTop = false;

   for(int t = 0; t < TF_COUNT; t++)
   {
      if(!tfOn[t]) { ZeroMemory(g_map[t]); continue; }

      bool built = BuildMap(s, t, g_map[t]);
      if(built) ScoreMap(g_map[t]);

      if(t == InpTrigIdx && built) okTrig   = true;
      if(t <  InpLevelTFs && built) okAnyTop = true;
   }

   return (okTrig && okAnyTop);
}

// Compact human-readable dump of the map — the anchor read, its strength,
// and where price sits in relation to the Ichimoku structures per slot.
string MapToString(int s, int anchor, int opp, double strength)
{
   string out = syms[s] + " anchor=" + (anchor >= 0 ? TFName(anchor) : "none") +
                " opp=" + IntegerToString(opp) +
                " str=" + DoubleToString(strength, 0);
   for(int t = 0; t < TF_COUNT; t++)
   {
      if(!tfOn[t]) continue;
      if(!g_map[t].ok) { out += " | " + TFName(t) + "[n/a]"; continue; }
      string cloud = (g_map[t].cloudSide == 1) ? "aboveKumo"
                   : (g_map[t].cloudSide == -1 ? "belowKumo" : "inKumo");
      string legs  = (g_map[t].structDir == 1) ? "HH/HL"
                   : (g_map[t].structDir == -1 ? "LH/LL" : "mixed");
      string opps  = (g_map[t].close > g_map[t].kijun && g_map[t].chikou >= 0) ? "opp+"
                   : (g_map[t].close < g_map[t].kijun && g_map[t].chikou <= 0 ? "opp-" : "opp0");
      out += " | " + TFName(t) + "[" + opps + " " + cloud +
             " thick" + DoubleToString(g_map[t].cloudThickATR, 1) +
             " kj" + DoubleToString(g_map[t].dKijunATR, 2) +
             (g_map[t].kijunFlat ? "flat" : "") +
             " tn" + DoubleToString(g_map[t].dTenkanATR, 2) +
             " tk" + (g_map[t].tkState >= 0 ? "+" : "-") +
             " ch" + (g_map[t].chikou > 0 ? "+" : (g_map[t].chikou < 0 ? "-" : "0")) +
             " tw" + (g_map[t].twist  > 0 ? "+" : (g_map[t].twist  < 0 ? "-" : "0")) +
             " " + legs +
             " leg" + (g_map[t].legDir >= 0 ? "+" : "-") + DoubleToString(g_map[t].legATR, 1) +
             " retr" + DoubleToString(g_map[t].retraceFrac, 2) +
             " s" + DoubleToString(g_map[t].score, 2) + "]";
   }
   return out;
}

//==============================================================
// Levels price can react against, taken from the top timeframes.
// For a long only levels at or below price qualify (support);
// for a short only levels at or above it (resistance).
//==============================================================

int CollectLevels(int dir, double refPrice, Level &lv[])
{
   ArrayResize(lv, 0);
   int cnt = 0;

   for(int t = 0; t < InpLevelTFs && t < TF_COUNT; t++)
   {
      if(!tfOn[t] || !g_map[t].ok) continue;
      // Higher slot = stronger level. Ranked against the number of level slots
      // in play, not the slot capacity, so grades keep the same scale whether
      // the stack is anchored on H4 or on MN1. Max grade = 4 + InpLevelTFs.
      int tfBonus = (InpLevelTFs - t);

      double prices[4];
      int    grades[4];
      string names[4];
      int    n = 0;

      if(InpUseCloudLevels)
      {
         prices[n] = g_map[t].cloudHi; grades[n] = 4 + tfBonus; names[n] = TFName(t) + " kumo-top"; n++;
         prices[n] = g_map[t].cloudLo; grades[n] = 4 + tfBonus; names[n] = TFName(t) + " kumo-base"; n++;
      }
      if(InpUseKijunLevels)
      {
         // A flat kijun is the strongest form of the level — price has been
         // balancing around it, so it acts as a magnet rather than a slope.
         int kg = 3 + tfBonus + (g_map[t].kijunFlat ? 1 : 0);
         prices[n] = g_map[t].kijun;  grades[n] = kg;
         names[n] = TFName(t) + (g_map[t].kijunFlat ? " flat-kijun" : " kijun"); n++;
      }
      if(InpUseTenkanLevels)
      {
         prices[n] = g_map[t].tenkan; grades[n] = 1 + tfBonus; names[n] = TFName(t) + " tenkan"; n++;
      }

      for(int i = 0; i < n && cnt < MAX_LEVELS; i++)
      {
         if(prices[i] <= 0.0) continue;
         if(dir ==  1 && prices[i] > refPrice) continue;   // support only
         if(dir == -1 && prices[i] < refPrice) continue;   // resistance only

         ArrayResize(lv, cnt + 1);
         lv[cnt].price = prices[i];
         lv[cnt].grade = grades[i];
         lv[cnt].name  = names[i];
         cnt++;
      }
   }
   return cnt;
}

//==============================================================
// Reaction detection: within the last InpReactionBars closed bars
// of the trigger timeframe, did price reach into a level and close
// back out of it on the trade side? Returns the strongest such
// level, the extreme of the bar that touched it, and its index.
//==============================================================

bool FindReaction(int s, int dir, Level &best, double &touchExt, int &touchIdx)
{
   double atrTrig = g_map[InpTrigIdx].atr;
   if(atrTrig <= 0.0) return false;

   MqlRates rt[];
   int need = (int)MathMax(2, InpReactionBars);
   if(CopyRates(syms[s], tfs[InpTrigIdx], 1, need, rt) < need) return false;
   ArraySetAsSeries(rt, true);

   double refPrice = rt[0].close;
   Level  lv[];
   int    nLv = CollectLevels(dir, refPrice, lv);
   if(nLv <= 0) return false;

   double tol      = InpTouchATR * atrTrig;
   int    bestGrade = -1;
   bool   found     = false;
   touchExt = 0.0;
   touchIdx = -1;

   for(int i = 0; i < nLv; i++)
   {
      double L = lv[i].price;

      // Price must still be on the trade side of the level and close enough
      // to it that the reaction is fresh rather than a stale re-touch.
      if(dir == 1)
      {
         if(refPrice <= L) continue;
         if(refPrice - L > InpMaxEntryDistATR * atrTrig) continue;
      }
      else
      {
         if(refPrice >= L) continue;
         if(L - refPrice > InpMaxEntryDistATR * atrTrig) continue;
      }

      for(int j = 0; j < need; j++)
      {
         bool touched = (dir == 1)
                        ? (rt[j].low  <= L + tol && rt[j].close > L)
                        : (rt[j].high >= L - tol && rt[j].close < L);
         if(!touched) continue;

         if(lv[i].grade > bestGrade)
         {
            bestGrade   = lv[i].grade;
            best.price  = lv[i].price;
            best.grade  = lv[i].grade;
            best.name   = lv[i].name;
            touchExt    = (dir == 1) ? rt[j].low : rt[j].high;
            touchIdx    = j;
            found       = true;
         }
         break;   // most recent touch of this level is enough
      }
   }

   return found;
}

//==============================================================
// Candle structure at the reaction: rejection wick, engulfing,
// and a momentum close beyond the reaction bar's extreme. Higher
// score = a more convincing bounce candle.
//==============================================================

double CandleScore(int s, int dir, int touchIdx, string &desc)
{
   desc = "";
   MqlRates rt[];
   int need = (int)MathMax(3, touchIdx + 3);
   if(CopyRates(syms[s], tfs[InpTrigIdx], 1, need, rt) < need) return 0.0;
   ArraySetAsSeries(rt, true);

   double sc = 0.0;
   int    ti = (int)MathMax(0, touchIdx);

   // 1) Rejection candle at the level
   double range = rt[ti].high - rt[ti].low;
   if(range > 0.0)
   {
      double body   = MathAbs(rt[ti].close - rt[ti].open);
      double wick   = (dir == 1) ? (MathMin(rt[ti].open, rt[ti].close) - rt[ti].low)
                                 : (rt[ti].high - MathMax(rt[ti].open, rt[ti].close));
      bool   closeOK = (dir == 1) ? (rt[ti].close > rt[ti].low + 0.5 * range)
                                  : (rt[ti].close < rt[ti].high - 0.5 * range);
      if(wick >= InpPinWickFrac * range && body <= InpPinBodyFrac * range && closeOK)
      {
         sc += 1.0;
         desc += "pin ";
      }
   }

   // 2) Engulfing in the trade direction on the last closed bar
   double b0 = rt[0].close - rt[0].open;
   double b1 = rt[1].close - rt[1].open;
   if(dir == 1 && b0 > 0.0 && b1 < 0.0 && rt[0].close >= rt[1].open && rt[0].open <= rt[1].close)
   {
      sc += 1.0;
      desc += "engulf ";
   }
   if(dir == -1 && b0 < 0.0 && b1 > 0.0 && rt[0].close <= rt[1].open && rt[0].open >= rt[1].close)
   {
      sc += 1.0;
      desc += "engulf ";
   }

   // 3) Momentum: the last closed bar takes out the reaction bar's extreme
   if(InpUseMomentumBar && ti > 0)
   {
      if(dir == 1 && rt[0].close > rt[ti].high) { sc += 1.5; desc += "momentum "; }
      if(dir == -1 && rt[0].close < rt[ti].low) { sc += 1.5; desc += "momentum "; }
   }

   // 4) Baseline: the last closed bar simply closed in the trade direction
   if(dir == 1 && b0 > 0.0)  { sc += 0.5; desc += "close+ "; }
   if(dir == -1 && b0 < 0.0) { sc += 0.5; desc += "close- "; }

   if(StringLen(desc) == 0) desc = "none";
   return sc;
}

//==============================================================
// The next structural obstacle in the trade direction: the nearest
// of the mapped swing extremes, cloud edges, and kijun levels on
// the context timeframes. Returns 0 when nothing lies ahead.
//==============================================================

double NextObstacle(int dir, double entry)
{
   double best = 0.0;

   for(int t = 0; t < InpObstacleTFs && t < TF_COUNT; t++)
   {
      if(!tfOn[t] || !g_map[t].ok) continue;

      double cands[6];
      int    n = 0;
      cands[n++] = g_map[t].swHi;
      cands[n++] = g_map[t].swLo;
      cands[n++] = g_map[t].pSwHi;
      cands[n++] = g_map[t].pSwLo;
      cands[n++] = g_map[t].cloudHi;
      cands[n++] = g_map[t].cloudLo;

      for(int i = 0; i < n; i++)
      {
         double p = cands[i];
         if(p <= 0.0) continue;
         if(dir == 1)
         {
            if(p <= entry) continue;
            if(best == 0.0 || p < best) best = p;
         }
         else
         {
            if(p >= entry) continue;
            if(best == 0.0 || p > best) best = p;
         }
      }
   }
   return best;
}

//==============================================================
// Setup evaluation — the whole read in one place. Returns true
// with the direction, stop, target and conviction filled in when
// an optimal trade exists.
//==============================================================

bool EvaluateSetup(int s, int &dir, double &slOut, double &tpOut,
                   double &riskOut, double &convOut, string &why)
{
   dir = 0; slOut = 0.0; tpOut = 0.0; riskOut = 0.0; convOut = 0.0; why = "";

   if(!BuildContext(s)) return false;

   // 1) Direction: the FIRST (highest) timeframe with a "price and chikou
   //    free to move" read decides. No read on H4 -> drop to H1. Being
   //    inside the cloud does not disqualify a timeframe — the cloud is an
   //    obstacle and a target, not a veto. Lower timeframes never override.
   int    anchor = -1, opp = 0;
   double oppStr = 0.0;
   for(int t = 0; t < InpAnchorTFs && t < TF_COUNT; t++)
   {
      if(!tfOn[t] || !g_map[t].ok) continue;
      opp = ReadOpportunity(g_map[t]);
      if(opp != 0) { anchor = t; oppStr = OppStrength(g_map[t], opp); break; }
   }
   if(anchor < 0) return false;
   if(InpLogMap) Print(PCTime() + " | MAP " + MapToString(s, anchor, opp, oppStr));
   if(oppStr < InpMinContext) return false;    // read present but too weak to act on
   int d = opp;

   double atrTrig = g_map[InpTrigIdx].atr;
   if(atrTrig <= 0.0) return false;

   // 2) Price must be reacting off a real Ichimoku structure right now
   Level  lvl;
   double touchExt;
   int    touchIdx;
   if(!FindReaction(s, d, lvl, touchExt, touchIdx)) return false;

   // 3) The candle structure at that level must confirm the bounce
   string cdesc;
   double cs = CandleScore(s, d, touchIdx, cdesc);
   if(cs < InpMinCandleScore) return false;

   // 4) Leg quality: a continuation trade wants a pullback of sane depth
   //    against an impulse, not an already-extended run.
   double retraceBonus = 0.0, latePenalty = 0.0;
   TFMap  legs         = g_map[InpLegTFIdx];
   if(legs.ok && legs.impulseATR > 0.0)
   {
      if(legs.legDir == -d)
      {
         if(legs.retraceFrac >= InpMinRetrace && legs.retraceFrac <= InpMaxRetrace)
            retraceBonus = 10.0;
         else if(legs.retraceFrac > InpMaxRetrace)
            retraceBonus = -10.0;   // too deep to still read as a pullback
      }
      else if(legs.legDir == d)
      {
         // Already running in the trade direction — only late if far extended.
         if(InpLateLegATR > 0.0 && legs.legATR > InpLateLegATR) latePenalty = 15.0;
      }
   }

   // 5) Conviction — the anchor read leads, the reaction adds, and the
   //    lower timeframes only help. Nothing below the anchor can veto.
   double gradeBonus  = 10.0 * Clamp(lvl.grade / (4.0 + InpLevelTFs), 0.0, 1.0);
   double candleBonus = 10.0 * Clamp(cs / 3.0, 0.0, 1.0);
   double anchorBonus = 0.6 * oppStr;
   double trigBonus   = (InpTrigIdx != anchor) ? 0.2 * DirStrength(g_map[InpTrigIdx], d) : 0.0;
   double supportBonus = 0.0, wsum = 0.0;
   for(int t = 0; t < TF_COUNT; t++)
   {
      if(t == anchor || t == InpTrigIdx || !tfOn[t] || !g_map[t].ok) continue;
      if(wts[t] <= 0.0) continue;
      supportBonus += wts[t] * DirStrength(g_map[t], d);
      wsum += wts[t];
   }
   if(wsum > 0.0) supportBonus = 0.15 * (supportBonus / wsum);
   double conv = Clamp(anchorBonus + trigBonus + supportBonus + gradeBonus +
                       candleBonus + retraceBonus - latePenalty, 0.0, 100.0);
   if(conv < InpMinScore) return false;

   // 6) Structural stop: behind the reaction extreme, and behind the last
   //    trigger-TF swing when that sits further out.
   double price = (d == 1) ? SymbolInfoDouble(syms[s], SYMBOL_ASK)
                           : SymbolInfoDouble(syms[s], SYMBOL_BID);
   if(price <= 0.0) return false;

   double slAnchor = touchExt;
   if(InpSLBeyondSwing && g_map[InpTrigIdx].ok)
   {
      if(d == 1 && g_map[InpTrigIdx].swLo > 0.0) slAnchor = MathMin(slAnchor, g_map[InpTrigIdx].swLo);
      if(d == -1 && g_map[InpTrigIdx].swHi > 0.0) slAnchor = MathMax(slAnchor, g_map[InpTrigIdx].swHi);
   }

   double sl = (d == 1) ? slAnchor - InpSLBufferATR * atrTrig
                        : slAnchor + InpSLBufferATR * atrTrig;

   double point   = SymbolInfoDouble(syms[s], SYMBOL_POINT);
   double minDist = SymbolInfoInteger(syms[s], SYMBOL_TRADE_STOPS_LEVEL) * point;
   int    digits  = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);

   double risk = (d == 1) ? (price - sl) : (sl - price);
   if(risk <= 0.0)
   {
      // The structure is on the wrong side of price — fall back to an ATR stop.
      risk = InpATRMultiplier * atrTrig;
      sl   = (d == 1) ? price - risk : price + risk;
   }
   if(risk < minDist)
   {
      risk = minDist;
      sl   = (d == 1) ? price - risk : price + risk;
   }
   if(InpMaxRiskATR > 0.0 && risk > InpMaxRiskATR * atrTrig) return false;  // stop too wide to be optimal
   sl = NormalizeDouble(sl, digits);

   // 7) Room to the next obstacle decides whether the trade is worth taking
   double obst = NextObstacle(d, price);
   double tp   = 0.0;
   if(obst > 0.0)
   {
      double room = (d == 1) ? (obst - price) : (price - obst);
      room -= InpTPBufferATR * atrTrig;
      if(room < InpMinRR * risk) return false;                 // buying into a ceiling
      if(room <= InpMaxRR * risk)
      {
         tp = (d == 1) ? price + room : price - room;
         if(MathAbs(tp - price) < minDist) tp = 0.0;
         else                              tp = NormalizeDouble(tp, digits);
      }
   }

   dir     = d;
   slOut   = sl;
   tpOut   = tp;
   riskOut = risk;
   convOut = conv;
   why     = "anchor " + TFName(anchor) + " opp " + DoubleToString(oppStr, 0) +
             " | conv " + DoubleToString(conv, 0) +
             " | " + lvl.name + " @ " + DoubleToString(lvl.price, digits) +
             " | pa: " + cdesc +
             "| retr " + DoubleToString(legs.retraceFrac, 2) +
             " | leg " + DoubleToString(legs.legATR, 1) + "atr" +
             " | R " + DoubleToString(risk, digits) +
             " | TP " + (tp > 0.0 ? DoubleToString(tp, digits) : "runner");
   return true;
}

//==============================================================
// Risk Management (same equity ladder as the VPS builds)
//==============================================================

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
   else if(eq <= 130)  { count = 12; lots = 0.10; }
   else if(eq <= 150)  { count = 16; lots = 0.10; }
   else if(eq <= 170)  { count = 20; lots = 0.10; }
   else if(eq <= 200)  { count = 12; lots = 0.20; }
   else if(eq <= 300)  { count = 8;  lots = 0.30; }
   else if(eq <= 400)  { count = 12; lots = 0.30; }
   else if(eq <= 500)  { count = 12; lots = 0.30; }
   else if(eq <= 600)  { count = 16; lots = 0.30; }
   else if(eq <= 1000) { count = 8;  lots = 0.50; }
   else if(eq <= 3000) { count = 8;  lots = 0.30; }
   else if(eq <= 5000) { count = 8;  lots = 0.20; }
   else if(eq <= 8000) { count = 8;  lots = 0.10; }
   else                { count = 4;  lots = RiskBasedLots(sym, eq, stopDist, count); }
}

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

// Open the ladder: the first orders carry the obstacle take profit, the rest
// are left as runners for the structure trail to manage.
int OpenLadder(int s, bool isBuy, double sl, double tp, int count, double lots, double &firstFill)
{
   string sym = syms[s];
   firstFill  = 0.0;

   int runners = (tp > 0.0) ? (int)MathRound(count * Clamp(InpRunnerFrac, 0.0, 1.0)) : count;
   if(runners > count) runners = count;

   int filled = 0;
   for(int i = 0; i < count; i++)
   {
      double price = isBuy ? SymbolInfoDouble(sym, SYMBOL_ASK)
                           : SymbolInfoDouble(sym, SYMBOL_BID);
      double useSL = InpUseStopLoss ? sl : 0.0;
      double useTP = (i < count - runners) ? tp : 0.0;

      bool ok = isBuy ? trade.Buy(lots,  sym, price, useSL, useTP, "Buy StructMap")
                      : trade.Sell(lots, sym, price, useSL, useTP, "Sell StructMap");
      if(!ok) break;   // out of margin or rejected — don't hammer the server
      if(firstFill == 0.0) firstFill = price;
      filled++;
   }
   return filled;
}

// Close all positions for the symbol; returns true only when none remain, so a
// failed close is retried instead of freeing the symbol for a fresh entry.
bool ClosePositions(string sym)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != sym) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MAGIC) continue;
      if(!trade.PositionClose(ticket))
         Print(PCTime() + " | " + sym + " close failed, retcode " + IntegerToString(trade.ResultRetcode()));
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

double AvgOpenPrice(int s)
{
   double sum = 0.0, vol = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != syms[s]) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MAGIC) continue;
      sum += PositionGetDouble(POSITION_PRICE_OPEN) * PositionGetDouble(POSITION_VOLUME);
      vol += PositionGetDouble(POSITION_VOLUME);
   }
   return (vol > 0) ? sum / vol : 0.0;
}

// Apply a tighten-only stop to every open position on the symbol. Returns true
// when every position ended up at or beyond slNew — so a one-shot caller (the
// break-even move) can tell "done" from "blocked, try again next bar".
bool ApplyStop(int s, bool isLong, double slNew, double minImprove, string tag)
{
   string sym     = syms[s];
   double point   = SymbolInfoDouble(sym, SYMBOL_POINT);
   double minDist = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * point;
   int    digits  = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double price   = isLong ? SymbolInfoDouble(sym, SYMBOL_BID)
                           : SymbolInfoDouble(sym, SYMBOL_ASK);

   slNew = NormalizeDouble(slNew, digits);

   // Inside the broker's minimum stop distance — cannot be placed yet.
   if(isLong  && slNew >= price - minDist) return false;
   if(!isLong && slNew <= price + minDist) return false;

   bool allSet = true;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != sym) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MAGIC) continue;

      double slCur = PositionGetDouble(POSITION_SL);
      double tpCur = PositionGetDouble(POSITION_TP);

      // Already at or beyond the requested level — nothing to do.
      if(slCur != 0.0 && (isLong ? slCur >= slNew : slCur <= slNew)) continue;

      // Improvement below the noise threshold — leave the request unsent, but
      // treat the position as effectively at the level.
      bool improve = isLong ? (slCur == 0.0 || slNew - slCur >= minImprove)
                            : (slCur == 0.0 || slCur - slNew >= minImprove);
      if(!improve) continue;

      if(!trade.PositionModify(ticket, slNew, tpCur))
      {
         Print(PCTime() + " | " + sym + " " + tag + " SL modify failed, retcode " +
               IntegerToString(trade.ResultRetcode()));
         allSet = false;
      }
   }
   return allSet;
}

//==============================================================
// Exit Management
//==============================================================

// Trail the stop behind the most recent confirmed swing on the trigger
// timeframe — the structure itself is the trailing reference.
void ManageStructureTrail(int s)
{
   if(!InpStructTrail || state[s] == 0 || !InpUseStopLoss) return;

   // Everything here runs on the holding scale, not the timing scale: an M15
   // trail on a trade anchored to a monthly level would hand back the move.
   double atrv = ATRv(s, g_exitIdx);
   if(atrv <= 0.0) return;

   // The entry already carries a structural stop behind the reaction level.
   // The trail only takes over once the trade has earned it, so an early swing
   // just under the entry can't tighten the stop into the noise.
   bool   isLong = (state[s] == 1);
   double avg    = AvgOpenPrice(s);
   if(avg <= 0.0) return;
   if(isLong  && SymbolInfoDouble(syms[s], SYMBOL_BID) < avg + InpTrailActivateATR * atrv) return;
   if(!isLong && SymbolInfoDouble(syms[s], SYMBOL_ASK) > avg - InpTrailActivateATR * atrv) return;

   double swHi, swLo, pHi, pLo;
   int    iHi, iLo;
   if(!FindSwings(s, tfs[g_exitIdx], InpTrailSwingBars, InpTrailWing,
                  swHi, swLo, pHi, pLo, iHi, iLo)) return;

   double anchor = isLong ? swLo : swHi;
   if(anchor <= 0.0) return;

   double slNew = isLong ? anchor - InpSLBufferATR * atrv
                         : anchor + InpSLBufferATR * atrv;
   ApplyStop(s, isLong, slNew, 0.2 * atrv, "trail");
}

// Break even + spread cover once the trade has earned it.
void ManageBE(int s)
{
   if(!InpBEEnabled || state[s] == 0 || beMoved[s] || !InpUseStopLoss) return;

   // Break even arms on the holding scale too — on the timing scale a swing
   // trade would reach the activation buffer within minutes of entry.
   double atrv = ATRv(s, g_exitIdx);
   if(atrv <= 0.0) return;

   double avg = AvgOpenPrice(s);
   if(avg <= 0.0) return;

   bool   isLong = (state[s] == 1);
   double bid    = SymbolInfoDouble(syms[s], SYMBOL_BID);
   double ask    = SymbolInfoDouble(syms[s], SYMBOL_ASK);

   if(isLong  && bid < avg + InpBEActivateATR * atrv) return;
   if(!isLong && ask > avg - InpBEActivateATR * atrv) return;

   double point = SymbolInfoDouble(syms[s], SYMBOL_POINT);
   double slNew = isLong ? avg + InpBECoverPoints * point
                         : avg - InpBECoverPoints * point;

   // One-shot only once it actually landed; a stop blocked by the broker's
   // minimum distance is retried on the next bar.
   if(ApplyStop(s, isLong, slNew, point, "BE")) beMoved[s] = true;
}

// Fallback exit: the trigger timeframe closes back across its own kijun.
bool CheckKijunExit(int s, int dir)
{
   if(!InpKijunExit) return false;

   double kj[1];
   if(CopyBuffer(ich[s][g_exitIdx], 1, 1, 1, kj) <= 0) return false;

   MqlRates rt[];
   if(CopyRates(syms[s], tfs[g_exitIdx], 1, 1, rt) <= 0) return false;

   if(dir ==  1 && rt[0].close < kj[0]) return true;
   if(dir == -1 && rt[0].close > kj[0]) return true;
   return false;
}

// Optional: the anchor cascade now reads "free to move" against the trade.
bool CheckFlipExit(int s, int dir)
{
   if(!InpExitOnFlip) return false;
   if(!BuildContext(s)) return false;
   for(int t = 0; t < InpAnchorTFs && t < TF_COUNT; t++)
   {
      if(!tfOn[t] || !g_map[t].ok) continue;
      int opp = ReadOpportunity(g_map[t]);
      if(opp == -dir) return true;    // the anchor now reads the other way
      if(opp ==  dir) return false;   // a higher timeframe still confirms
   }
   return false;
}

//==============================================================
// Main Loop
//==============================================================

void OnTick()
{
   // Everything runs on closed bars, so one pass per minute is enough.
   int nowKey = (int)(TimeCurrent() / 60);
   if(nowKey == lastMinuteKey) return;
   lastMinuteKey = nowKey;

   bool synced = false;
   for(int s = 0; s < symsCount; s++)
   {
      // Exit management follows the M1 clock so stops react within a minute.
      MqlRates m1[];
      if(CopyRates(syms[s], PERIOD_M1, 0, 2, m1) < 2) continue;
      ArraySetAsSeries(m1, true);
      if(m1[1].time == lastM1bar[s]) continue;
      lastM1bar[s] = m1[1].time;

      if(!synced) { SyncStateFromPositions(); synced = true; }

      if(state[s] != 0)
      {
         ManageBE(s);
         ManageStructureTrail(s);
      }

      // Entries and the signal exits are evaluated on closed trigger-TF bars.
      MqlRates tb[];
      if(CopyRates(syms[s], tfs[InpTrigIdx], 0, 2, tb) < 2) continue;
      ArraySetAsSeries(tb, true);
      if(tb[1].time == lastTrigBar[s]) continue;
      lastTrigBar[s] = tb[1].time;

      // Signal exits
      if(state[s] != 0)
      {
         string reason = "";
         if(CheckKijunExit(s, state[s]))     reason = TFName(g_exitIdx) + " kijun crossed";
         else if(CheckFlipExit(s, state[s])) reason = "structure map flipped";

         if(reason != "")
         {
            string side = (state[s] == 1) ? "Long" : "Short";
            string msg  = PCTime() + " | Close " + syms[s] + " " + side + " (" + reason +
                          ", opened at conv " + DoubleToString(entryConv[s], 0) + ")";
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

      // Entry
      if(state[s] != 0) continue;
      if(TimeCurrent() < noReentryUntil[s]) continue;
      if(!SpreadOK(syms[s])) continue;

      int    dir;
      double sl, tp, risk, conv;
      string why;
      if(!EvaluateSetup(s, dir, sl, tp, risk, conv, why)) continue;

      bool isBuy = (dir == 1);
      int    count;
      double lots;
      GetEquityRisk(syms[s], risk, count, lots);

      // Size with conviction: only the strongest reads get the full ladder.
      if(conv < InpStrongScore) count = (int)MathMax(1, count / 2);

      CapToRisk(syms[s], risk, count, lots);
      CapToMargin(syms[s], isBuy, count, lots);

      double firstFill = 0.0;
      int filled = OpenLadder(s, isBuy, sl, tp, count, lots, firstFill);
      if(filled > 0)
      {
         state[s]      = dir;
         entryPrice[s] = firstFill;
         entryTime[s]  = TimeCurrent();
         beMoved[s]    = false;
         entryConv[s]  = conv;

         string action = isBuy ? "Buy" : "Sell";
         string msg = PCTime() + " | " + action + " " + syms[s] +
                      " x" + IntegerToString(filled) +
                      " @ " + DoubleToString(lots, 2) + " (StructMap) | " + why;
         Print(msg); SendNotification(msg);
      }
      else
         Print(PCTime() + " | " + syms[s] + " setup found but no order filled | " + why);
   }
}
//This work is my worship unto GOD
