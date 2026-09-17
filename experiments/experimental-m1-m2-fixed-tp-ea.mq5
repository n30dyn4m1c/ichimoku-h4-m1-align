//+------------------------------------------------------------------+
//| Ichimoku M1+M2 / M1+M2+M5 — FIXED TARGET EXPERIMENT              |
//| EXPERIMENTAL BUILD — not deployed. Magic 20260866.               |
//|                                                                  |
//| THE IDEA: the live VPS build (ichimoku-h4-m1-vps-ea.mq5) uses    |
//| the M1 cloud as the first rung of its stack and exits on a kumo  |
//| TOUCH — it has no profit target at all, and no stop loss beyond  |
//| the wide disaster one. This build tests the opposite exit        |
//| philosophy on the two SHORTEST rungs only:                       |
//|                                                                  |
//|   M1 + M2 aligned          -> M2 tier opens                      |
//|   M1 + M2 + M5 aligned     -> M5 tier opens                      |
//|                                                                  |
//| with ONE position and FIXED levels instead of a touch exit:      |
//|   SL  90 pips  — hard, attached at entry                         |
//|   TP  120 pips — attached at entry                               |
//| Both ride on the order, so the broker closes the trade on its    |
//| own. There is no break-even move, no trailing stop, no partial   |
//| close and no scale-out: a trade is opened, and it either stops   |
//| out at 90 or targets out at 120. The EA's only remaining job is  |
//| to re-attach a stop that has gone missing.                       |
//|                                                                  |
//| ONE POSITION AT A TIME. A tier opens only when it is flat, and   |
//| when both chains align on the same minute only the LARGER (M5)   |
//| opens while any running M2 trade is closed into it — the         |
//| parent's consolidation rule, kept. So the account never holds    |
//| more than one position per symbol.                               |
//|                                                                  |
//| SESSION FILTER: entries are restricted to two windows of the     |
//| daily H1 count — candles 7..11 and 15..19, counted from the day  |
//| open and inclusive of the candle in progress. Those two windows  |
//| are the +/-2 tolerance around kihon suchi 9 and 17, the only two |
//| counts a ~23-24 candle day can deliver, so together they cover   |
//| ten of the day's candles (~40% of the session). The day open is  |
//| taken from the D1 bar itself so a different broker rollover hour |
//| needs no special case. The filter gates ENTRIES ONLY: an open    |
//| trade keeps running and can still reach its SL or TP outside the |
//| windows. An unknown day count blocks rather than waves a trade   |
//| through, and a chain that aligned while the window was shut is   |
//| logged (throttled) so the suppressed signals are visible.        |
//|                                                                  |
//| GATES: deliberately NONE beyond the alignment chain itself. No   |
//| cloud-bias gate, no H4 bias, no H1 stand-in, no D1 filter — this |
//| build trades the bare M1+M2 / M1+M2+M5 condition in both         |
//| directions. That is a much higher trade count than the deployed  |
//| build and the point of the experiment: does the chain alone      |
//| carry an edge when the exit is a fixed target rather than a      |
//| touch. One gate the parent has is an input away from being       |
//| restored (InpCloudBiasEnabled) — but the bias gates are NOT      |
//| ported, so this is not an A/B of the parent.                     |
//|                                                                  |
//| ENTRY, per tier: the full stack M1..tierTF aligned the same way, |
//| each timeframe passing the parent's CheckAlign — price on one    |
//| side of tenkan, kijun AND the whole cloud, plus the Chikou       |
//| confirmation (the close projected Kijun bars back beyond that    |
//| bar's high/low and beyond tenkan, kijun and cloud as they stood  |
//| at that historical bar). M1 alone never trades; it is the shared |
//| first leg of both chains.                                        |
//|                                                                  |
//| M2 IS OPTIONAL AND NON-FATAL. Some brokers do not serve a 2-min  |
//| feed. CheckAlign returns 0 on unreadable data, so an M2 rung     |
//| enforced without data would silently block EVERY entry on the    |
//| symbol. A symbol that refuses an M2 handle at init, or that has  |
//| no M2 bars yet, therefore drops the M2 tier and runs M5-only,    |
//| with one journal line per symbol saying so — the same skip-      |
//| rather-than-block rule as the kihon-po3 experiment (§38).        |
//|                                                                  |
//| PIP SIZE: 1 pip = InpPipPoints points (default 10). On a gold    |
//| feed quoted to 2 decimals that makes one pip 0.10 of price, so   |
//| 4000.00 -> 4012.00 is 120 pips and 4000.00 -> 4009.00 is 90,     |
//| exactly as specified. The EA prints the resolved distances at    |
//| init so a wrong setting is visible in the journal before it      |
//| costs anything. On a 3-decimal gold feed set InpPipPoints = 100. |
//|                                                                  |
//| RISK: a fixed % of ACTUAL equity at entry, measured against the  |
//| full 90-pip stop, in the parent's three de-risking regimes:      |
//|   M2 tier 0.5% / 0.25% / 0.1%   (tier 1 / 2 / 3)                 |
//|   M5 tier 2.0% / 1.0%  / 0.5%                                    |
//| M5 is the higher-conviction chain (it needs M2 to agree as well) |
//| so it carries four times the M2 risk. The ladder is a judgement  |
//| call, not a tested result — it is the first thing to change.     |
//| Because the stop is fixed at 90 pips, the money at risk on a     |
//| stop-out is exactly the chosen % — no ATR approximation.        |
//|                                                                  |
//| WHAT THIS BUILD DELIBERATELY DOES NOT HAVE: the robustness pack, |
//| the disaster stop, the ATR size basis, the kumo-touch exit, the  |
//| rejection exit, the BE/chandelier trail, the H1/H4/D1 bias        |
//| gates, the "unknown position" guard and the margin cap. It is a  |
//| clean minimal test of one question, not a hardened build. Do not |
//| deploy it to the VPS without adding those back.                  |
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

input group  "Targets (in pips — SL 90 / TP 120 by default)"
input double InpPipPoints = 10.0;   // Points per pip (2-decimal gold feed = 10; 3-decimal gold = 100)
input double InpSLPips    = 90.0;   // Hard stop distance, pips
input double InpTPPips    = 120.0;  // Take profit distance, pips

input group  "Risk Management (per tier, % of actual equity against the full 90-pip stop)"
input double InpFixedLots     = 0.10;   // Fixed lots fallback (sizing data unavailable)
input double InpRiskTier2At   = 7000.0; // Equity where risk drops to tier 2 (half regime)
input double InpRiskTier3At   = 13000.0;// Equity where risk drops to tier 3 (tiny regime)
input double InpRiskPctM2     = 0.5;    // M2 tier — tier 1 (equity < Tier2At)
input double InpRiskPctM5     = 2.0;    // M5 tier — tier 1
input double InpRiskPctM2_T2  = 0.25;   // M2 tier — tier 2 (half regime)
input double InpRiskPctM5_T2  = 1.0;    // M5 tier — tier 2
input double InpRiskPctM2_T3  = 0.1;    // M2 tier — tier 3 (tiny regime)
input double InpRiskPctM5_T3  = 0.5;    // M5 tier — tier 3

input group  "Entry Filters"
input int    InpMaxSpreadPoints = 60;   // Max spread in points to allow entry (0 = no limit)
input bool   InpCloudBiasEnabled = false; // Require the far end of the future cloud to carry the trade (off = bare alignment)

input group  "Session Filter (H1 candles counted from the daily open)"
input bool   InpSessionFilterEnabled = true; // Gate ENTRIES to the two session windows below (exits never gated)
input int    InpSession1Start = 7;      // Window 1 — first daily H1 candle (inclusive)
input int    InpSession1End   = 11;     // Window 1 — last daily H1 candle (inclusive)
input int    InpSession2Start = 15;     // Window 2 — first daily H1 candle (inclusive)
input int    InpSession2End   = 19;     // Window 2 — last daily H1 candle (inclusive)

//--- Constants and Global Variables ---
#define MAX_SYMS 60
#define LEVELS   2      // tradable tiers: M2, M5 — and nothing above them
#define TFS      3      // what the EA reads: M1, M2, M5

ENUM_TIMEFRAMES tfs[TFS] = { PERIOD_M1, PERIOD_M2, PERIOD_M5 };
string          tfName[TFS] = { "M1", "M2", "M5" };

int      ich[MAX_SYMS][TFS];
string   syms[MAX_SYMS];
int      symsCount = 0;
datetime lastM1bar[MAX_SYMS];
int      state[MAX_SYMS][LEVELS];     // per tier: 0 = flat, 1 = long, -1 = short
int      lastMinuteKey = -1;

double   entryPrice[MAX_SYMS][LEVELS];   // fill price — the TP/SL basis
double   tpPrice[MAX_SYMS][LEVELS];      // absolute TP level, set at entry
double   slPrice[MAX_SYMS][LEVELS];      // absolute stop level, set at entry

//--- M2 availability, per symbol. M2 is skipped rather than enforced when the
//--- symbol cannot serve it — see M2TierActive for why that matters.
bool     m2Ok[MAX_SYMS];      // the symbol accepted an M2 Ichimoku handle at init
bool     m2Warned[MAX_SYMS];  // the "no M2 history yet" note, once per symbol

int MAGIC = 20260866;   // experimental M1+M2 split-target build (nothing else uses this)

CTrade trade;

//==============================================================
// Pips
//
// A pip here is InpPipPoints * SYMBOL_POINT, which is what makes
// "4000 -> 4012 is 120 pips" true on a 2-decimal gold feed. The
// value is resolved per symbol so a watch list of mixed digits
// still measures each symbol in its own points.
//==============================================================

double PipPrice(const int s)
{
   double point = SymbolInfoDouble(syms[s], SYMBOL_POINT);
   return InpPipPoints * point;
}

string PipLabel(const int s)
{
   double p = PipPrice(s);
   int    d = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);
   return DoubleToString(p, d) + " price units per pip";
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

   if(InpPipPoints <= 0)
   {
      Print("Pip: InpPipPoints must be positive — got " + DoubleToString(InpPipPoints, 2) + ". Aborting.");
      return(INIT_FAILED);
   }
   if(InpSLPips <= 0 || InpTPPips <= 0)
   {
      Print("Targets: InpSLPips and InpTPPips must both be positive. Aborting.");
      return(INIT_FAILED);
   }

   for(int s = 0; s < symsCount; s++)
   {
      lastM1bar[s]    = 0;
      m2Ok[s]         = false;
      m2Warned[s]     = false;

      for(int l = 0; l < LEVELS; l++)
      {
         state[s][l]      = 0;
         entryPrice[s][l] = 0.0;
         tpPrice[s][l]    = 0.0;
         slPrice[s][l]    = 0.0;
      }

      for(int t = 0; t < TFS; t++)
      {
         ich[s][t] = iIchimoku(syms[s], tfs[t], Tenkan, Kijun, SenkouB);

         //--- M2 is OPTIONAL and non-fatal. A symbol that will not give an M2
         //--- handle loses the M2 tier and runs M5-only rather than going silent.
         if(t == 1)
         {
            if(ich[s][t] == INVALID_HANDLE)
            {
               Print("M2 tier: " + syms[s] + " refused an M2 Ichimoku handle — the M2 tier is "
                     "DISABLED for this symbol and only M1+M2+M5 (M5 tier) will trade. "
                     "This broker does not serve M2.");
               continue;
            }
            m2Ok[s] = true;
            continue;
         }

         if(ich[s][t] == INVALID_HANDLE) return(INIT_FAILED);
      }

      Print("Targets: " + syms[s] + " — 1 pip = " + PipLabel(s) +
            " | SL " + DoubleToString(InpSLPips, 1) + " pips, TP " +
            DoubleToString(InpTPPips, 1) + " pips");
   }

   for(int s = 0; s < symsCount; s++)
   {
      if(m2Ok[s])
         Print("M2 tier: " + syms[s] + " ON — the M2 and M5 tiers both trade (M1+M2 and M1+M2+M5).");
      else
         Print("M2 tier: " + syms[s] + " UNAVAILABLE — the M2 tier is disabled for this symbol; "
               "its chain runs as M1+M2+M5 (the M5 tier) only.");
   }

   if(InpSessionFilterEnabled)
      PrintFormat("Session filter: ON — entries only while the daily H1 count is %d..%d or %d..%d "
                  "(counted from the day open, inclusive, developing candle included). Exits and "
                  "target management are never gated.",
                  InpSession1Start, InpSession1End, InpSession2Start, InpSession2End);
   else
      Print("Session filter: OFF — entries run at any hour.");

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
// Position State Sync (recover after restart)
//
// The position comment carries the tier, exactly as the parent
// build does, so a restart mid-trade resumes the right tier. Both
// levels ride on the order, so the entry is recovered by inverting
// them: the stop was placed at exactly InpSLPips and the target at
// exactly InpTPPips, either of which gives the entry back.
//==============================================================

string LevelComment(int lvl, int dir)
{
   return (dir == 1 ? "Exp Buy " : "Exp Sell ") + tfName[lvl + 1];
}

void SyncStateFromPositions()
{
   bool hasPos[MAX_SYMS][LEVELS];
   for(int s = 0; s < symsCount; s++)
      for(int l = 0; l < LEVELS; l++)
      {
         state[s][l] = 0;
         hasPos[s][l] = false;
      }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      string sym   = PositionGetString(POSITION_SYMBOL);
      int    magic = (int)PositionGetInteger(POSITION_MAGIC);
      if(magic != MAGIC) continue;

      int    type = (int)PositionGetInteger(POSITION_TYPE);
      string comm = PositionGetString(POSITION_COMMENT);
      int    dir  = (type == POSITION_TYPE_BUY) ? 1 : -1;

      for(int s = 0; s < symsCount; s++)
      {
         if(syms[s] != sym) continue;

         int lvlMatch = -1;
         for(int l = 0; l < LEVELS; l++)
            if(comm == LevelComment(l, 1) || comm == LevelComment(l, -1))
            {
               lvlMatch = l;
               break;
            }

         if(lvlMatch < 0)
         {
            Print(PCTime() + " | !! " + sym + " position #" + IntegerToString((long)ticket) +
                  " carries this EA's magic but its comment \"" + comm +
                  "\" names no tier — it cannot be managed by this build.");
            continue;
         }

         state[s][lvlMatch] = dir;
         hasPos[s][lvlMatch] = true;

         if(entryPrice[s][lvlMatch] == 0.0)
         {
            double curSL  = PositionGetDouble(POSITION_SL);
            double curTP  = PositionGetDouble(POSITION_TP);
            double openPx = PositionGetDouble(POSITION_PRICE_OPEN);
            double pip    = PipPrice(s);

            // The position carries its own stop and target, so recovery is a
            // straight inversion: the stop was placed at exactly InpSLPips from
            // the entry and the target at exactly InpTPPips. Either one recovers
            // the entry; the stop is preferred because this build never moves it.
            if(curSL > 0.0)
               entryPrice[s][lvlMatch] = (dir == 1) ? curSL + InpSLPips * pip
                                                    : curSL - InpSLPips * pip;
            else if(curTP > 0.0)
               entryPrice[s][lvlMatch] = (dir == 1) ? curTP - InpTPPips * pip
                                                    : curTP + InpTPPips * pip;
            else
               entryPrice[s][lvlMatch] = openPx;

            // An inversion that came out unusable can only mean the levels were
            // tampered with by hand — trust the broker's fill instead.
            if(entryPrice[s][lvlMatch] <= 0.0) entryPrice[s][lvlMatch] = openPx;

            RebuildTargets(s, lvlMatch, dir);
         }
         break;
      }
   }

   for(int s = 0; s < symsCount; s++)
      for(int l = 0; l < LEVELS; l++)
         if(!hasPos[s][l])
         {
            entryPrice[s][l] = 0.0;
            tpPrice[s][l]    = 0.0;
            slPrice[s][l]    = 0.0;
         }
}

// Recompute the two absolute levels from the entry price and the pip inputs.
void RebuildTargets(const int s, const int lvl, const int dir)
{
   double pip = PipPrice(s);
   int    d   = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);

   if(dir == 1)
   {
      slPrice[s][lvl]  = NormalizeDouble(entryPrice[s][lvl] - InpSLPips * pip, d);
      tpPrice[s][lvl]  = NormalizeDouble(entryPrice[s][lvl] + InpTPPips * pip, d);
   }
   else
   {
      slPrice[s][lvl]  = NormalizeDouble(entryPrice[s][lvl] + InpSLPips * pip, d);
      tpPrice[s][lvl]  = NormalizeDouble(entryPrice[s][lvl] - InpTPPips * pip, d);
   }
}

//==============================================================
// Alignment Check — identical to the deployed build's CheckAlign:
// price and chikou both above/below tenkan, kijun, and cloud on
// one timeframe. Returns 1 (bullish), -1 (bearish), 0 (none).
// ==============================================================

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

//==============================================================
// Cloud Bias Filter — the parent's FUTURE-ONLY rule, kept as an
// input (default OFF here, because this build tests the bare
// alignment chain). The far end of the future-cloud window
// (Kijun bars ahead of the last closed bar) must carry the
// trade's bias; the immediate cloud may be either direction.
//==============================================================

bool CloudBiasFarOK(const int s, const int tfIdx, const int dir)
{
   double aFar[1], bFar[1];
   if(CopyBuffer(ich[s][tfIdx], 2, 1 - Kijun, 1, aFar) <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 3, 1 - Kijun, 1, bFar) <= 0) return false;

   if(dir == 1) return aFar[0] > bFar[0];
   return aFar[0] < bFar[0];
}

//==============================================================
// M2 Tier Availability
//
// M2 is skipped rather than enforced when the symbol cannot serve
// it. CheckAlign returns 0 on unreadable data, so an M2 tier that
// was enforced without an M2 feed would block every entry on the
// symbol — the EA would go silent with nothing in the journal to
// say why. A symbol that refused the handle at init, or that has
// no M2 bars yet, therefore drops the tier and runs M5-only.
//==============================================================

bool M2TierActive(const int s)
{
   if(!m2Ok[s]) return false;

   //--- History loads asynchronously, so a valid handle can still have no
   //--- bars for a while after init. iTime is a local read.
   if(iTime(syms[s], PERIOD_M2, 0) == 0)
   {
      if(!m2Warned[s])
      {
         m2Warned[s] = true;
         Print("M2 tier: " + syms[s] + " has no M2 history yet — the M2 tier is being SKIPPED "
               "and only the M5 chain (M1+M2+M5) will trade. It joins automatically once the "
               "timeframe loads; if it never does, this broker does not serve M2.");
      }
      return false;
   }
   return true;
}

//==============================================================
// Chain Check (bottom-up): the full stack M1..topIdx must be
// aligned in the SAME direction for a tier to open.
//   M2 tier -> topIdx = 1 : M1 + M2 aligned
//   M5 tier -> topIdx = 2 : M1 + M2 + M5 aligned
// The M2 leg is skipped when the symbol has no M2 feed, which
// degrades the M5 chain to M1 + M5 (and removes the M2 tier).
//==============================================================

int ChainAligned(const int s, const int topIdx)
{
   int dir = CheckAlign(s, 0);
   if(dir == 0) return 0;

   for(int t = 1; t <= topIdx; t++)
   {
      if(t == 1 && !M2TierActive(s)) continue;   // no M2 feed — drop the rung
      if(CheckAlign(s, t) != dir) return 0;
   }
   return dir;
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

//==============================================================
// Risk Management — a fixed % of ACTUAL equity at entry,
// measured against the FULL stop distance (InpSLPips), in the
// parent's three equity regimes that de-risk as the account
// grows. Because the stop here is fixed in pips rather than
// sized in ATR, the risk in money is exact: lots such that a
// stop-out loses the chosen % of equity. No multipliers.
//==============================================================

double LevelRiskPct(const int lvl)
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   bool t3 = (eq >= InpRiskTier3At);
   bool t2 = (eq >= InpRiskTier2At);
   switch(lvl)
   {
      case 0:  return t3 ? InpRiskPctM2_T3 : t2 ? InpRiskPctM2_T2 : InpRiskPctM2;
      case 1:  return t3 ? InpRiskPctM5_T3 : t2 ? InpRiskPctM5_T2 : InpRiskPctM5;
   }
   return 0.0;
}

double RiskLots(const int s, const int lvl)
{
   double riskPct = LevelRiskPct(lvl);
   if(riskPct <= 0) return InpFixedLots;

   double stopDist = InpSLPips * PipPrice(s);
   if(stopDist <= 0) return InpFixedLots;

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

//==============================================================
// Trading Functions
//==============================================================

bool OpenTier(const int s, const int lvl, const int dir, double lots)
{
   string sym     = syms[s];
   string comment = LevelComment(lvl, dir);
   double price   = (dir == 1) ? SymbolInfoDouble(sym, SYMBOL_ASK)
                               : SymbolInfoDouble(sym, SYMBOL_BID);

   // Pick a filling mode this symbol actually supports — CTrade's FOK
   // default gets retcode 10030 (invalid fill) on IOC-only brokers.
   trade.SetTypeFillingBySymbol(sym);

   double pip = PipPrice(s);
   int    d   = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double sl  = NormalizeDouble((dir == 1) ? price - InpSLPips * pip : price + InpSLPips * pip, d);
   double tp  = NormalizeDouble((dir == 1) ? price + InpTPPips * pip : price - InpTPPips * pip, d);

   // The stop must clear the broker's minimum distance or the order is rejected
   // outright. If the symbol demands more room than InpSLPips allows, the trade
   // is skipped rather than silently opened with a wider stop than the risk
   // sizing assumed.
   double point   = SymbolInfoDouble(sym, SYMBOL_POINT);
   double minDist = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * point;
   double bidNow  = SymbolInfoDouble(sym, SYMBOL_BID);
   double askNow  = SymbolInfoDouble(sym, SYMBOL_ASK);

   bool slValid = (dir == 1) ? (sl > 0 && sl < bidNow - minDist)
                             : (sl > 0 && sl > askNow + minDist);
   if(!slValid)
   {
      Print(PCTime() + " | " + sym + " " + tfName[lvl + 1] + " entry skipped — a " +
            DoubleToString(InpSLPips, 1) + "-pip stop is inside the broker's minimum stop distance.");
      return false;
   }

   // Both the stop and the target ride on the order, so the trade is fully
   // defined at the broker even if this EA stops running.
   bool ok = (dir == 1) ? trade.Buy(lots, sym, price, sl, tp, comment)
                        : trade.Sell(lots, sym, price, sl, tp, comment);
   if(ok)
   {
      state[s][lvl]      = dir;
      entryPrice[s][lvl] = price;
      RebuildTargets(s, lvl, dir);

      string action = (dir == 1) ? "Buy" : "Sell";
      string msg = PCTime() + " | " + action + " " + sym + " " + tfName[lvl + 1] +
                   " @ " + DoubleToString(lots, 2) + " (SL " + DoubleToString(InpSLPips, 0) +
                   " / TP " + DoubleToString(InpTPPips, 0) + " pips)" +
                   (InpSessionFilterEnabled ? " [" + SessionInfo(s) + "]" : "");
      Print(msg); SendNotification(msg);
   }
   return ok;
}

// Close positions of one tier; returns true only when none remain open, so a
// failed close (requote, halt) is retried instead of freeing the tier.
bool CloseTierPositions(const int s, const int lvl)
{
   string sym = syms[s];
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) == sym &&
         (int)PositionGetInteger(POSITION_MAGIC) == MAGIC &&
         (PositionGetString(POSITION_COMMENT) == LevelComment(lvl, 1) ||
          PositionGetString(POSITION_COMMENT) == LevelComment(lvl, -1)))
      {
         if(!trade.PositionClose(ticket))
            Print(PCTime() + " | " + sym + " " + tfName[lvl + 1] + " close failed, retcode " +
                  IntegerToString(trade.ResultRetcode()));
      }
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) == sym &&
         (int)PositionGetInteger(POSITION_MAGIC) == MAGIC &&
         (PositionGetString(POSITION_COMMENT) == LevelComment(lvl, 1) ||
          PositionGetString(POSITION_COMMENT) == LevelComment(lvl, -1))) return false;
   }
   return true;
}

//==============================================================
// Tier Ticket Lookup — the position carrying the tier's comment.
//==============================================================

bool TierTicket(const int s, const int lvl, ulong &ticket)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != syms[s]) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MAGIC) continue;
      string comm = PositionGetString(POSITION_COMMENT);
      if(comm == LevelComment(lvl, 1) || comm == LevelComment(lvl, -1)) return true;
   }
   return false;
}

//==============================================================
// Position Management
//
// There is almost nothing to manage. Both the 90-pip stop and the
// 120-pip target ride on the order, so the broker takes the trade
// out on its own — this build never trails, never scales out and
// never moves a stop. The only jobs left here are defensive:
//
//   * re-attach a stop that has gone missing, because an unstopped
//     position is unbounded and this build's whole risk story is
//     the fixed 90 pips;
//   * clear the tier's state when the position is gone, so a slot
//     freed by an SL/TP hit is available again on the next bar.
//
// Both are evaluated once per closed M1 bar, like everything else.
// ==============================================================

void ManageTierTargets(const int s, const int lvl)
{
   int dir = state[s][lvl];
   if(dir == 0) return;

   ulong ticket;
   if(!TierTicket(s, lvl, ticket))
   {
      // The broker closed it on the stop or the target — free the tier.
      state[s][lvl]      = 0;
      entryPrice[s][lvl] = 0.0;
      Print(PCTime() + " | " + syms[s] + " " + tfName[lvl + 1] +
            " position closed at the broker (SL or TP).");
      return;
   }

   string sym    = syms[s];
   double curSL  = PositionGetDouble(POSITION_SL);
   double bid    = SymbolInfoDouble(sym, SYMBOL_BID);
   double ask    = SymbolInfoDouble(sym, SYMBOL_ASK);
   double minDist= SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(sym, SYMBOL_POINT);
   bool   isLong = (dir == 1);

   //--- Self-heal a stop that is missing entirely.
   if(curSL == 0.0 && slPrice[s][lvl] > 0.0)
   {
      double slHeal = NormalizeDouble(slPrice[s][lvl], (int)SymbolInfoInteger(sym, SYMBOL_DIGITS));
      bool okHeal = isLong ? (slHeal < bid - minDist) : (slHeal > ask + minDist);
      if(okHeal && trade.PositionModify(ticket, slHeal, tpPrice[s][lvl]))
         Print(PCTime() + " | " + sym + " " + tfName[lvl + 1] +
               " stop was missing — re-attached at " + DoubleToString(slHeal, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)));
      else if(okHeal)
         Print(PCTime() + " | " + sym + " " + tfName[lvl + 1] +
               " stop is missing and could not be re-attached, retcode " +
               IntegerToString(trade.ResultRetcode()));
   }
}

//==============================================================
// Session Filter — H1 candles counted from the daily open
//
// The count is INCLUSIVE of the candle that is still forming, and
// it counts every H1 candle whose open time falls inside the
// window [day open, now]. So candle 1 is the H1 bar that opens at
// the day's open (00:00 on a 00:00 rollover), candle 7 is the bar
// opening six hours later, and a bar in progress at the moment of
// the read is counted as the candle it belongs to.
//
// The day open comes from the D1 bar itself (iTime D1 shift 0)
// rather than from a clock offset, so a broker whose day rolls at
// a different hour, and a weekend gap, are both handled without a
// special case. Bars() is used rather than a shift calculation for
// the same reason the kihon experiment does: a bar BEFORE the
// anchor is simply not in the window, which keeps candle 1 on the
// correct side of the open.
//
// The default windows — 7..11 and 15..19 — are the +/-2 tolerance
// around kihon suchi 9 and 17, the only two counts a ~23-24 candle
// trading day can deliver. On a 24-candle day they cover ten of
// the day's candles, roughly 40% of the session.
//
// An UNKNOWN or IMPLAUSIBLE count does not open the gate. The gate
// cannot be evaluated while the history is still loading, and an
// unevaluable filter blocks rather than waves the trade through —
// the same stance the cloud gate takes on unreadable buffers.
//==============================================================

int DailyH1Count(const string sym)
{
   datetime anchor = iTime(sym, PERIOD_D1, 0);
   if(anchor <= 0) return(0);

   datetime now = TimeCurrent();
   datetime cur = iTime(sym, PERIOD_H1, 0);
   if(cur == 0) return(0);              // H1 history not loaded yet

   // The anchor falls inside the developing candle → that candle is candle 1.
   if(anchor >= cur) return(1);

   long elapsed = ((long)TimeCurrent() - (long)anchor) / 3600;
   if(elapsed > 48) return(-1);         // anomalous — do not guess

   int n = Bars(sym, PERIOD_H1, anchor, now);
   if(n <= 0)   return(0);
   if(n > 30)   return(-1);             // implausible for a trading day
   return(n);
}

string SessionInfo(const int s)
{
   int c = DailyH1Count(syms[s]);
   if(c < 0)  return("off");
   if(c == 0) return("no data");
   return("candle " + IntegerToString(c));
}

bool SessionGateOK(const int s, string &info)
{
   info = "off";
   if(!InpSessionFilterEnabled) return(true);

   int c = DailyH1Count(syms[s]);
   if(c <= 0)
   {
      info = (c < 0) ? "day count anomalous" : "day count unknown";
      return(false);
   }

   bool inWindow = (c >= InpSession1Start && c <= InpSession1End) ||
                   (c >= InpSession2Start && c <= InpSession2End);
   info = "H1 candle " + IntegerToString(c) +
          (inWindow ? " in window" : " outside window");
   return(inWindow);
}

//==============================================================
// Main Loop
//
// All logic runs only on closed M1 bars, which change at most once
// per minute — the parent VPS build's gating, kept so this
// experiment behaves the same way when it is run on the VPS.
// NOTE this means the fixed 90/120-pip levels are evaluated ONCE
// PER MINUTE: an intra-minute spike through a target is only acted
// on at the next M1 open (the broker-side SL/TP on the order is
// what covers the gap between those reads).
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

      // Rebuild state from the account once per tick, on the first new M1 bar.
      if(!synced) { SyncStateFromPositions(); synced = true; }

      // Position upkeep per tier — free a slot the broker closed, and
      // re-attach a stop that has gone missing. The targets themselves
      // are the broker's job; nothing here moves them.
      for(int l = 0; l < LEVELS; l++)
      {
         if(l == 0 && !M2TierActive(s)) continue;   // no M2 feed — no M2 tier
         if(state[s][l] != 0) ManageTierTargets(s, l);
      }

      // Entries: highest tier first, so when both chains fire on the
      // same bar only the larger (M5) tier opens. The session filter
      // gates ENTRIES ONLY — running trades keep being managed and can
      // still reach their SL/TP outside the windows.
      int topTier = -1;
      int topDir  = 0;
      for(int l = LEVELS - 1; l >= 0; l--)
      {
         if(l == 0 && !M2TierActive(s)) continue;
         if(state[s][l] != 0) continue;

         int st = ChainAligned(s, l + 1);
         if(st == 0) continue;
         if(InpCloudBiasEnabled && !CloudBiasFarOK(s, l + 1, st)) continue;

         topTier = l;
         topDir  = st;
         break;
      }

      // The chain is evaluated even when the entry gates are shut, so a
      // signal that the session window suppressed leaves a trace instead of
      // disappearing. Throttled to once every 15 minutes per symbol.
      string sessInfo = "off";
      bool spreadOK   = SpreadOK(syms[s]);
      bool sessionOK  = SessionGateOK(s, sessInfo);

      if(topTier >= 0 && (!spreadOK || !sessionOK) && (nowKey % 15) == 0)
      {
         string why = !spreadOK ? "spread " + IntegerToString((int)SymbolInfoInteger(syms[s], SYMBOL_SPREAD)) +
                                  " > " + IntegerToString(InpMaxSpreadPoints) + " pts"
                                : "session (" + sessInfo + ")";
         Print(PCTime() + " | " + syms[s] + " " + tfName[topTier + 1] +
               " chain aligned but entry blocked — " + why);
      }

      if(topTier >= 0 && spreadOK && sessionOK)
      {
         // One position per symbol: close any smaller tier still running.
         for(int l = 0; l < topTier; l++)
         {
            if(state[s][l] != 0)
            {
               string msg = PCTime() + " | Close " + syms[s] + " " + tfName[l + 1] +
                            " (superseded by " + tfName[topTier + 1] + ")";
               Print(msg); SendNotification(msg);

               if(CloseTierPositions(s, l))
                  state[s][l] = 0;
               else
                  Print(PCTime() + " | " + syms[s] + " " + tfName[l + 1] +
                        " superseded but positions still open — will retry");
            }
         }

         double lots = RiskLots(s, topTier);
         if(!OpenTier(s, topTier, topDir, lots))
            Print(PCTime() + " | " + syms[s] + " " + tfName[topTier + 1] +
                  " entry signal but order failed, retcode " + IntegerToString(trade.ResultRetcode()));
      }
   }
}
//This work is my worship unto GOD
