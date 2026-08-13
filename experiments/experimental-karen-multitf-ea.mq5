//+------------------------------------------------------------------+
//| Experimental: Karen Peloille Multi-Timeframe EA                  |
//| Based on Karen Peloille, "Trading with Ichimoku: A Practical     |
//| Guide" (ch. 3-4) and her article "Trader avec Ichimoku:          |
//| 3 techniques" (karenpeloille.com).                               |
//|                                                                  |
//| Her system, made mechanical:                                     |
//|   - 3 timeframes per trade: ANALYSIS (general market state),     |
//|     STRATEGY (the signal), POSITION MANAGEMENT (entry/exit).     |
//|     Book table (ch. 4): medium term = D1 / H4 / H1.              |
//|   - "Kijun breaks are what provide trading signals": the         |
//|     ultimate signal is a close through the STRATEGY-TF Kijun     |
//|     ("my ultimate trading signal is given once prices have       |
//|     closed above the Kijun in this time frame").                 |
//|   - Lagging Span validation: the LS must be on the trade side    |
//|     of its own Kijun, on the strategy TF and (optional) on the   |
//|     analysis and management TFs ("a sell signal validated by     |
//|     the Lagging Span in both time frames").                      |
//|   - Entry timing on the management TF: a pullback that touched   |
//|     the Tenkan (wick test) but held the Kijun, then a bounce     |
//|     bar closing back on the trade side of the Tenkan ("test of   |
//|     the Tenkan which is validated"; "shadow tested the Kijun     |
//|     and validated").                                             |
//|   - Exit: close on a management-TF Tenkan cross against the      |
//|     trade ("the position will be closed once the Tenkan is       |
//|     broken") or on the strategy-TF Kijun crossing back (signal   |
//|     invalidation). Optional take-profit at the strategy-TF       |
//|     cloud edge, with her personal RR gate of 1:3.                |
//|   - Stops: ATR-based hard stop on every order plus the optional  |
//|     chandelier trail and BE30 management (same as the H4-M1      |
//|     VPS build, anchored on the management TF).                   |
//| Risk: identical to the VPS builds — equity-tiered ladder,        |
//|        CapToRisk, CapToMargin, spread filter, re-entry cooldown, |
//|        verified exits, once-per-minute gating.                   |
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

//--- The three screens of her system (book ch. 3 methodology):
//    TF1 ANALYSIS = general state of the market (prices vs cloud),
//    TF2 STRATEGY = the Kijun break signal + LS validation,
//    TF3 MANAGEMENT = entry timing, Tenkan exit, stop anchor.
//    Defaults are her "medium term" table: Daily / 240min / 60min.
input group  "Timeframes"
input ENUM_TIMEFRAMES InpAnalysisTF = PERIOD_D1;   // Analysis TF (general trend: prices vs cloud)
input ENUM_TIMEFRAMES InpSignalTF   = PERIOD_H4;   // Strategy TF (Kijun break = the signal)
input ENUM_TIMEFRAMES InpEntryTF    = PERIOD_H1;   // Management TF (pullback entry + Tenkan exit)

input group  "Karen Strategy"
input bool   InpSignalCloud       = true;  // Strategy TF close must be on the trade side of its cloud
input bool   InpSignalChikou      = true;  // Strategy TF chikou (LS) above/below its own Kijun
input bool   InpAnalysisChikou    = true;  // Analysis TF chikou (LS) on the trade side of its Kijun
input int    InpPullbackBars      = 6;     // Management-TF bars back to find the Tenkan wick test
input bool   InpBounceCandle      = true;  // Bounce bar must close in the trade direction (blue/red body)
input bool   InpChikouEntry       = true;  // Management TF chikou (LS) must confirm too
input double InpMinRR             = 3.0;   // Skip entries with less than this reward:risk to the cloud-edge target (0 = off)
input bool   InpUseTakeProfit     = true;  // Attach TP at the strategy-TF cloud edge (half-cloud buffer)

//--- Exit line: her two exits are the management-TF Tenkan (alert of
//    the end of the move) and the strategy-TF Kijun (invalidation
//    of the signal at the start). The management-TF Kijun is the
//    middle ground.
enum ENUM_EXIT_MODE { EXIT_TENKAN_ENTRY = 0, EXIT_KIJUN_ENTRY = 1, EXIT_KIJUN_SIGNAL = 2 };

input group  "Exit Selection"
input ENUM_EXIT_MODE InpExitMode = EXIT_TENKAN_ENTRY;  // 0=entry-TF Tenkan cross, 1=entry-TF Kijun cross, 2=signal-TF Kijun cross

input group  "Risk Protection"
input bool   InpUseStopLoss       = true;   // Attach ATR-based stop loss to every entry
input int    InpATRPeriod         = 14;     // ATR period (management TF)
input double InpATRMultiplier     = 3.0;    // SL distance = ATR * multiplier
input int    InpMaxSpreadPoints   = 60;     // Max spread in points to allow entry (0 = no limit)
input double InpHighEquityRiskPct = 1.0;    // % of equity risked per trade once equity > $8000
input int    InpReentryCooldownSec = 0;     // Min seconds after an exit before re-entering same symbol (0 = none)
input double InpMaxRiskPct         = 0.0;   // Cap total initial-stop risk per ladder as % of equity (0 = no cap)

//--- Trail mode: off, always on, or choppy-only (ADX regime filter)
enum ENUM_TRAIL_MODE { TRAIL_OFF = 0, TRAIL_ALWAYS = 1, TRAIL_CHOPPY = 2 };

input group  "Exit Management"
input ENUM_TRAIL_MODE InpTrailMode        = TRAIL_CHOPPY;  // 0=off, 1=always, 2=choppy-only (ADX)
input double          InpTrailATR         = 2.0;   // Trail distance = ATR(entry TF) * multiplier
input double          InpTrailActivateATR = 1.0;   // Arm the trail once profit >= ATR(entry TF) * multiplier
input int             InpADXPeriod        = 14;    // ADX period for choppy-market detection (entry TF)
input double          InpChopADXLevel     = 22.0;  // ADX below this = choppy -> trail on in auto mode

input group  "Break-Even (BE30) Management"
input bool   InpBE30Enabled        = true;   // Move SL to break even when profitable in time
input int    InpBE30Minutes        = 30;     // Profit window after entry (minutes)
input double InpBE30ActivateATR    = 0.5;    // Min profit to arm BE (x ATR entry TF)
input int    InpBE30CoverPoints    = 15;     // Points beyond break even (covers spread)

//--- Constants and Global Variables ---
#define MAX_SYMS  60
#define TF_COUNT  3
#define IDX_ANALYSIS 0
#define IDX_SIGNAL   1
#define IDX_ENTRY    2

ENUM_TIMEFRAMES tfs[TF_COUNT] = { PERIOD_D1, PERIOD_H4, PERIOD_H1 };

int      ich[MAX_SYMS][TF_COUNT];
int      atr[MAX_SYMS];
int      adx[MAX_SYMS];   // ADX(entry TF) handle for choppy-market regime detection
string   syms[MAX_SYMS];
int      symsCount = 0;
datetime lastBar[MAX_SYMS];     // last closed bar of the gating TF per symbol
datetime noReentryUntil[MAX_SYMS];
int      lastMinuteKey = -1;
int      state[MAX_SYMS];   // 0=no position, 1=long, -1=short

double   entryPrice[MAX_SYMS];  // reference entry price per symbol (trail arming)
double   trailHigh[MAX_SYMS];   // highest high since entry (long chandelier reference)
double   trailLow[MAX_SYMS];    // lowest low since entry (short chandelier reference)
double   tpHold[MAX_SYMS];      // take-profit price per symbol (cloud-edge target)

datetime entryTime[MAX_SYMS];   // entry time per symbol (BE30 profit window)
bool     beMoved[MAX_SYMS];     // BE30 stop already moved to break even (one-shot)

int MAGIC = 20260840;   // fresh — no other EA uses this

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

   tfs[IDX_ANALYSIS] = InpAnalysisTF;
   tfs[IDX_SIGNAL]   = InpSignalTF;
   tfs[IDX_ENTRY]    = InpEntryTF;

   for(int s = 0; s < symsCount; s++)
   {
      state[s] = 0;
      lastBar[s] = 0;
      noReentryUntil[s] = 0;
      entryTime[s] = 0;
      beMoved[s] = false;
      tpHold[s] = 0.0;
      for(int t = 0; t < TF_COUNT; t++)
      {
         ich[s][t] = iIchimoku(syms[s], tfs[t], Tenkan, Kijun, SenkouB);
         if(ich[s][t] == INVALID_HANDLE) return(INIT_FAILED);
      }

      atr[s] = INVALID_HANDLE;
      if(InpUseStopLoss)
      {
         atr[s] = iATR(syms[s], tfs[IDX_ENTRY], InpATRPeriod);
         if(atr[s] == INVALID_HANDLE) return(INIT_FAILED);
      }

      adx[s] = INVALID_HANDLE;
      if(InpTrailMode == TRAIL_CHOPPY)
      {
         adx[s] = iADX(syms[s], tfs[IDX_ENTRY], InpADXPeriod);
         if(adx[s] == INVALID_HANDLE) return(INIT_FAILED);
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
   {
      for(int t = 0; t < TF_COUNT; t++)
         if(ich[s][t] != INVALID_HANDLE) IndicatorRelease(ich[s][t]);
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
            if(entryPrice[s] == 0.0)
            {
               entryPrice[s] = PositionGetDouble(POSITION_PRICE_OPEN);
               trailHigh[s]  = entryPrice[s];
               trailLow[s]   = entryPrice[s];
            }
            if(entryTime[s] == 0)
               entryTime[s] = (datetime)PositionGetInteger(POSITION_TIME);
            break;
         }
      }
   }

   for(int s = 0; s < symsCount; s++)
   {
      if(!hasPos[s])
      {
         entryPrice[s] = 0.0;
         trailHigh[s]  = 0.0;
         trailLow[s]   = 0.0;
         entryTime[s]  = 0;
         beMoved[s]    = false;
      }
   }

   for(int s = 0; s < symsCount; s++)
   {
      if(prevState[s] != 0 && state[s] == 0)
         noReentryUntil[s] = TimeCurrent() + InpReentryCooldownSec;
   }
}

//==============================================================
// Chikou (Lagging Span) reading. The chikou of bar 1 IS its close,
// plotted Kijun bars back; we compare it against the kijun at that
// chart position (same offset handling as the alignment builds).
// Returns true when the chikou is on 'dir' side of its Kijun.
//==============================================================

bool ChikouOnSide(int s, int tfIdx, int dir)
{
   int sh      = 1;
   int chShift = sh + Kijun;

   MqlRates rt[];
   if(CopyRates(syms[s], tfs[tfIdx], 0, chShift + 1, rt) <= 0) return false;
   ArraySetAsSeries(rt, true);
   if(ArraySize(rt) <= chShift) return false;

   double kij_ch[1];
   if(CopyBuffer(ich[s][tfIdx], 1, chShift, 1, kij_ch) <= 0) return false;

   double chik = rt[sh].close;
   if(dir ==  1) return chik > kij_ch[0];
   if(dir == -1) return chik < kij_ch[0];
   return false;
}

//==============================================================
// Screen 1 — ANALYSIS TF: prices on the trade side of the cloud.
// "The highest time frame is used to define the general state of
// the market" (ch. 3 methodology). Optional chikou validation.
//==============================================================

bool AnalysisScreen(int s, int dir)
{
   double senA[1], senB[1];
   if(CopyBuffer(ich[s][IDX_ANALYSIS], 2, 1, 1, senA) <= 0) return false;
   if(CopyBuffer(ich[s][IDX_ANALYSIS], 3, 1, 1, senB) <= 0) return false;

   MqlRates rt[];
   if(CopyRates(syms[s], tfs[IDX_ANALYSIS], 1, 1, rt) <= 0) return false;
   double closeP = rt[0].close;
   double cHi = MathMax(senA[0], senB[0]);
   double cLo = MathMin(senA[0], senB[0]);

   if(dir ==  1 && closeP <= cHi) return false;
   if(dir == -1 && closeP >= cLo) return false;

   if(InpAnalysisChikou && !ChikouOnSide(s, IDX_ANALYSIS, dir)) return false;
   return true;
}

//==============================================================
// Screen 2 — STRATEGY TF: the Kijun break signal.
// "Kijun breaks are what provide trading signals"; the ultimate
// signal is a close through the Kijun in this time frame. The
// Lagging Span must validate the break (chikou on the trade side
// of its own Kijun). Optional cloud-side requirement.
//==============================================================

bool SignalScreen(int s, int dir)
{
   double kij[1];
   if(CopyBuffer(ich[s][IDX_SIGNAL], 1, 1, 1, kij) <= 0) return false;

   MqlRates rt[];
   if(CopyRates(syms[s], tfs[IDX_SIGNAL], 1, 1, rt) <= 0) return false;
   double closeP = rt[0].close;

   // the signal itself: last closed bar through the Kijun
   if(dir ==  1 && closeP <= kij[0]) return false;
   if(dir == -1 && closeP >= kij[0]) return false;

   if(InpSignalChikou && !ChikouOnSide(s, IDX_SIGNAL, dir)) return false;

   if(InpSignalCloud)
   {
      double senA[1], senB[1];
      if(CopyBuffer(ich[s][IDX_SIGNAL], 2, 1, 1, senA) <= 0) return false;
      if(CopyBuffer(ich[s][IDX_SIGNAL], 3, 1, 1, senB) <= 0) return false;
      double cHi = MathMax(senA[0], senB[0]);
      double cLo = MathMin(senA[0], senB[0]);
      if(dir ==  1 && closeP <= cHi) return false;
      if(dir == -1 && closeP >= cLo) return false;
   }
   return true;
}

//==============================================================
// Screen 3 — ENTRY (management) TF: the Tenkan pullback.
// Within the last InpPullbackBars bars a wick tested the Tenkan
// ("rebond sur la Tenkan") while the bar held the Kijun (the
// correction stayed within the trend), and the last closed bar
// bounced back on the trade side of the Tenkan ("test of the
// Tenkan which is validated"). Optional chikou confirmation.
//==============================================================

bool PullbackScreen(int s, int dir)
{
   int win = InpPullbackBars;
   if(win < 1) win = 1;
   int cnt = win + 2;   // bars 1..win+1

   double ten[], kij[];
   if(CopyBuffer(ich[s][IDX_ENTRY], 0, 0, cnt, ten) <= 0) return false;
   if(CopyBuffer(ich[s][IDX_ENTRY], 1, 0, cnt, kij) <= 0) return false;
   ArraySetAsSeries(ten, true);
   ArraySetAsSeries(kij, true);

   MqlRates rt[];
   if(CopyRates(syms[s], tfs[IDX_ENTRY], 0, cnt, rt) <= 0) return false;
   ArraySetAsSeries(rt, true);
   if(ArraySize(rt) < cnt) return false;

   // bounce bar = the last closed bar (bar 1)
   if(dir ==  1)
   {
      if(rt[1].close <= ten[1]) return false;
      if(InpBounceCandle && rt[1].close <= rt[1].open) return false;
   }
   else
   {
      if(rt[1].close >= ten[1]) return false;
      if(InpBounceCandle && rt[1].close >= rt[1].open) return false;
   }

   // the pullback: a wick touched the Tenkan while the bar held the Kijun
   bool touched = false;
   for(int i = 1; i <= win + 1; i++)
   {
      if(dir ==  1 && rt[i].low  <= ten[i] && rt[i].close > kij[i]) { touched = true; break; }
      if(dir == -1 && rt[i].high >= ten[i] && rt[i].close < kij[i]) { touched = true; break; }
   }
   if(!touched) return false;

   if(InpChikouEntry && !ChikouOnSide(s, IDX_ENTRY, dir)) return false;
   return true;
}

//==============================================================
// Full check: ANALYSIS + SIGNAL + ENTRY screens all on the same
// side. Returns 1 (long), -1 (short) or 0.
//==============================================================

int CheckKarenSignal(int s)
{
   if(AnalysisScreen(s,  1) && SignalScreen(s,  1) && PullbackScreen(s,  1)) return  1;
   if(AnalysisScreen(s, -1) && SignalScreen(s, -1) && PullbackScreen(s, -1)) return -1;
   return 0;
}

//==============================================================
// Take-profit at the strategy-TF cloud edge (her price targets
// are always a level: SSB, cloud edge, Kijun). The buffer keeps
// the order a few ATRs short of the level since price often
// stalls just below it. Returns 0 when no target is usable.
//==============================================================

double BuildTakeProfit(int s, int dir, double atrVal)
{
   if(!InpUseTakeProfit) return 0.0;

   double senA[1], senB[1];
   if(CopyBuffer(ich[s][IDX_SIGNAL], 2, 1, 1, senA) <= 0) return 0.0;
   if(CopyBuffer(ich[s][IDX_SIGNAL], 3, 1, 1, senB) <= 0) return 0.0;

   double target = 0.0;
   if(dir ==  1) target = MathMax(senA[0], senB[0]);
   else          target = MathMin(senA[0], senB[0]);
   if(target <= 0) return 0.0;

   int digits = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);
   return NormalizeDouble(target - dir * 0.25 * atrVal, digits);
}

//==============================================================
// Exit check: the selected line crossed against the trade.
//==============================================================

bool CheckExit(int s, int dir)
{
   int tfIdx = (InpExitMode == EXIT_KIJUN_SIGNAL) ? IDX_SIGNAL : IDX_ENTRY;
   int buf   = (InpExitMode == EXIT_TENKAN_ENTRY) ? 0 : 1;

   double line[1];
   if(CopyBuffer(ich[s][tfIdx], buf, 1, 1, line) <= 0) return false;

   MqlRates rt[];
   if(CopyRates(syms[s], tfs[tfIdx], 1, 1, rt) <= 0) return false;
   double closeP = rt[0].close;

   if(dir ==  1 && closeP < line[0]) return true;
   if(dir == -1 && closeP > line[0]) return true;
   return false;
}

//==============================================================
// Choppy-market detection: ADX(entry TF) below InpChopADXLevel
// means no trend, so the trail is allowed.
//==============================================================

bool IsChoppy(int s)
{
   double d[1];
   if(CopyBuffer(adx[s], 0, 1, 1, d) <= 0 || d[0] <= 0) return true;
   return d[0] < InpChopADXLevel;
}

//==============================================================
// Exit Trail: ATR chandelier stop anchored on the entry-TF bar
// extremes. Re-evaluated on every new bar; only ever tightens.
//==============================================================

void ManageTrail(int s)
{
   if(state[s] == 0 || InpTrailMode == TRAIL_OFF || !InpUseStopLoss) return;
   if(InpTrailMode == TRAIL_CHOPPY && !IsChoppy(s)) return;

   double atrVal;
   if(atr[s] == INVALID_HANDLE) return;
   double a[1];
   if(CopyBuffer(atr[s], 0, 1, 1, a) <= 0 || a[0] <= 0) return;
   atrVal = a[0];

   MqlRates rt[];
   if(CopyRates(syms[s], tfs[IDX_ENTRY], 0, 1, rt) <= 0) return;
   ArraySetAsSeries(rt, true);

   bool isLong = (state[s] == 1);
   if(isLong)
   {
      if(rt[0].high > trailHigh[s]) trailHigh[s] = rt[0].high;
   }
   else
   {
      if(rt[0].low < trailLow[s]) trailLow[s] = rt[0].low;
   }

   double point   = SymbolInfoDouble(syms[s], SYMBOL_POINT);
   double minDist = SymbolInfoInteger(syms[s], SYMBOL_TRADE_STOPS_LEVEL) * point;
   int    digits  = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);

   if(isLong && SymbolInfoDouble(syms[s], SYMBOL_BID) < entryPrice[s] + InpTrailActivateATR * atrVal) return;
   if(!isLong && SymbolInfoDouble(syms[s], SYMBOL_ASK) > entryPrice[s] - InpTrailActivateATR * atrVal) return;

   double price = isLong ? SymbolInfoDouble(syms[s], SYMBOL_BID)
                         : SymbolInfoDouble(syms[s], SYMBOL_ASK);
   double slNew = isLong ? trailHigh[s] - InpTrailATR * atrVal
                         : trailLow[s] + InpTrailATR * atrVal;
   slNew = NormalizeDouble(slNew, digits);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != syms[s]) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MAGIC) continue;

      double slCur = PositionGetDouble(POSITION_SL);

      if(isLong && slNew > slCur + point && slNew < price - minDist &&
         slNew - slCur >= 0.3 * atrVal)
      {
         if(!trade.PositionModify(ticket, slNew, 0))
            Print(PCTime() + " | " + syms[s] + " trail SL modify failed, retcode " + IntegerToString(trade.ResultRetcode()));
      }
      if(!isLong && slNew < slCur - point && slNew > price + minDist &&
         slCur - slNew >= 0.3 * atrVal)
      {
         if(!trade.PositionModify(ticket, slNew, 0))
            Print(PCTime() + " | " + syms[s] + " trail SL modify failed, retcode " + IntegerToString(trade.ResultRetcode()));
      }
   }
}

//==============================================================
// Break-Even Management (BE30): identical to the VPS build.
//==============================================================

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

void ManageBE(int s)
{
   if(state[s] == 0 || !InpBE30Enabled) return;
   if(entryTime[s] == 0 || beMoved[s]) return;

   if(TimeCurrent() - entryTime[s] > InpBE30Minutes * 60) return;

   double avg = AvgOpenPrice(s);
   if(avg <= 0) return;

   if(atr[s] == INVALID_HANDLE) return;
   double a[1];
   if(CopyBuffer(atr[s], 0, 1, 1, a) <= 0 || a[0] <= 0) return;
   double atrVal = a[0];

   bool   isLong = (state[s] == 1);
   double bid    = SymbolInfoDouble(syms[s], SYMBOL_BID);
   double ask    = SymbolInfoDouble(syms[s], SYMBOL_ASK);

   if(isLong && bid < avg + InpBE30ActivateATR * atrVal) return;
   if(!isLong && ask > avg - InpBE30ActivateATR * atrVal) return;

   double point   = SymbolInfoDouble(syms[s], SYMBOL_POINT);
   double minDist = SymbolInfoInteger(syms[s], SYMBOL_TRADE_STOPS_LEVEL) * point;
   int    digits  = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);

   double slNew = isLong ? avg + InpBE30CoverPoints * point
                         : avg - InpBE30CoverPoints * point;
   slNew = NormalizeDouble(slNew, digits);

   double price = isLong ? bid : ask;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != syms[s]) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MAGIC) continue;

      double slCur = PositionGetDouble(POSITION_SL);

      if(isLong && slNew > slCur + point && slNew < price - minDist)
      {
         if(!trade.PositionModify(ticket, slNew, 0))
            Print(PCTime() + " | " + syms[s] + " BE SL modify failed, retcode " + IntegerToString(trade.ResultRetcode()));
         else
            beMoved[s] = true;
      }
      if(!isLong && slNew < slCur - point && slNew > price + minDist)
      {
         if(!trade.PositionModify(ticket, slNew, 0))
            Print(PCTime() + " | " + syms[s] + " BE SL modify failed, retcode " + IntegerToString(trade.ResultRetcode()));
         else
            beMoved[s] = true;
      }
   }
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

bool GetStopDistance(int s, double &dist)
{
   dist = 0.0;
   double a[1];
   if(CopyBuffer(atr[s], 0, 1, 1, a) <= 0 || a[0] <= 0) return false;

   dist = a[0] * InpATRMultiplier;
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

int OpenPositions(int s, bool isBuy, double dist, double tp, int count, double lots, double &firstFill)
{
   string sym = syms[s];

   int filled = 0;
   firstFill = 0.0;
   for(int i = 0; i < count; i++)
   {
      double price = isBuy ? SymbolInfoDouble(sym, SYMBOL_ASK)
                           : SymbolInfoDouble(sym, SYMBOL_BID);
      double sl = InpUseStopLoss ? BuildStopLoss(s, isBuy, price, dist) : 0.0;

      bool ok = isBuy ? trade.Buy(lots,  sym, price, sl, tp, "Buy Karen MTF")
                      : trade.Sell(lots, sym, price, sl, tp, "Sell Karen MTF");
      if(!ok) break;
      if(firstFill == 0.0) firstFill = price;
      filled++;
   }
   return filled;
}

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
   // VPS perf: all logic runs only on closed bars, at most once per
   // minute (the management TF is usually slower than M1, so the
   // minute gate is a cheap upper bound).
   int nowKey = (int)(TimeCurrent() / 60);
   if(nowKey == lastMinuteKey) return;
   lastMinuteKey = nowKey;

   bool synced = false;
   for(int s = 0; s < symsCount; s++)
   {
      // Per-symbol bar gating on the management TF — her rule: "always
      // wait for the current candlestick to close in the time frame
      // studied, especially in the lower ones".
      MqlRates rt[];
      if(CopyRates(syms[s], tfs[IDX_ENTRY], 0, 2, rt) < 2) continue;
      ArraySetAsSeries(rt, true);
      if(rt[1].time == lastBar[s]) continue;
      lastBar[s] = rt[1].time;

      if(!synced) { SyncStateFromPositions(); synced = true; }

      // Exit check: the selected line (entry-TF Tenkan by default)
      // closed against the trade
      if(state[s] != 0 && CheckExit(s, state[s]))
      {
         string side = (state[s] == 1) ? "Long" : "Short";
         string msg  = PCTime() + " | Close " + syms[s] + " " + side + " (Karen exit line crossed)";
         Print(msg); SendNotification(msg);

         if(ClosePositions(syms[s]))
         {
            state[s] = 0;
            noReentryUntil[s] = TimeCurrent() + InpReentryCooldownSec;
         }
         else
            Print(PCTime() + " | " + syms[s] + " exit signal but positions still open — will retry");
      }

      // Chandelier trail + BE30 on the management TF
      if(state[s] != 0) ManageTrail(s);
      if(state[s] != 0) ManageBE(s);

      // Entry check: all three screens must agree, spread must be sane
      if(state[s] == 0 && TimeCurrent() >= noReentryUntil[s] && SpreadOK(syms[s]))
      {
         int st = CheckKarenSignal(s);
         if(st != 0)
         {
            bool   isBuy = (st == 1);
            double dist  = 0.0;
            if(InpUseStopLoss && !GetStopDistance(s, dist)) continue;   // ATR unavailable — skip entry

            double tp = 0.0;
            if(InpUseTakeProfit)
            {
               double atrVal = 0.0;
               double a[1];
               if(atr[s] != INVALID_HANDLE && CopyBuffer(atr[s], 0, 1, 1, a) > 0 && a[0] > 0)
                  atrVal = a[0];
               tp = BuildTakeProfit(s, st, atrVal);
               if(tp <= 0) tp = 0.0;

               // her personal risk rule: only trades with RR >= InpMinRR
               if(InpMinRR > 0 && tp > 0 && dist > 0)
               {
                  double price = isBuy ? SymbolInfoDouble(syms[s], SYMBOL_ASK)
                                       : SymbolInfoDouble(syms[s], SYMBOL_BID);
                  double rr = MathAbs(tp - price) / dist;
                  if(rr < InpMinRR) continue;
               }
            }

            int count; double lots;
            GetEquityRisk(syms[s], dist, count, lots);
            CapToRisk(syms[s], dist, count, lots);
            CapToMargin(syms[s], isBuy, count, lots);

            double firstFill = 0.0;
            int filled = OpenPositions(s, isBuy, dist, tp, count, lots, firstFill);
            if(filled > 0)
            {
               state[s] = st;
               entryPrice[s] = firstFill;
               trailHigh[s]  = firstFill;
               trailLow[s]   = firstFill;
               entryTime[s]  = TimeCurrent();
               beMoved[s]    = false;
               tpHold[s]     = tp;
               string action = isBuy ? "Buy" : "Sell";
               string msg = PCTime() + " | " + action + " " + syms[s] +
                            " x" + IntegerToString(filled) +
                            " @ " + DoubleToString(lots, 2) + " (Karen MTF)";
               if(tp > 0)
                  msg += " TP " + DoubleToString(tp, (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS));
               Print(msg); SendNotification(msg);
            }
            else
               Print(PCTime() + " | " + syms[s] + " entry signal but no order filled");
         }
      }
   }
}
//This work is my worship unto GOD
