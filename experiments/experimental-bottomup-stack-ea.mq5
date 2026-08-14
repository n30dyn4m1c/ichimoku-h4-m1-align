//+------------------------------------------------------------------+
//| Ichimoku Bottom-Up Stack EA (EXPERIMENT)                          |
//| Entry: same per-TF alignment as the H4 VPS build (price + chikou  |
//|        above/below tenkan, kijun and cloud), checked BOTTOM-UP:   |
//|        a tier opens only when the full stack M1..tier TF is       |
//|        aligned in one direction:                                  |
//|          Tier M5 : M1 + M5 aligned              -> open trade     |
//|          Tier M15: M1 + M5 + M15 aligned        -> open trade     |
//|          Tier M30: M1 + M5 + M15 + M30 aligned  -> open trade     |
//|          Tier H1 : M1 ... H1 aligned            -> open trade     |
//|          Tier H4 : M1 ... H4 aligned            -> open trade     |
//|        M1 alone never trades — it is only the start of the stack. |
//|        The cloud bias gate (Span A vs Span B) applies to the tier |
//|        TF and the TF directly below it.                           |
//| Exit:  the level's own TF bar closes back inside its cloud.       |
//|        Long  -> close below the cloud's upper edge (inside/under) |
//|        Short -> close above the cloud's lower edge (inside/over)  |
//|        No initial stop loss — the trade runs until the cloud      |
//|        close, with profit protection once it turns green:         |
//|          Break-even   : profit >= ATR threshold (tighter for the  |
//|                         H1/H4 levels) -> SL to entry + cover      |
//|          Chandelier   : H1/H4 levels trail the stop behind the    |
//|                         peak once profitable (InpTrailActivateATR);|
//|                         M5/M15/M30 keep the spike-gated trail     |
//|                         (InpSpikeLockATR), only ever tightening   |
//|        ATR comes from each level's own TF.                        |
//| Risk:  single position per level per symbol; levels run           |
//|        concurrently (up to 5 per symbol); each level re-enters    |
//|        independently whenever its chain re-aligns. Every trade    |
//|        risks a fixed % of the ACTUAL equity at entry (M5/M15 1%,  |
//|        M30 5%, H1 10%, H4 20%), measured against ATR(level TF) x  |
//|        InpRiskATRMult. No multipliers, no streak compounding.     |
//|        No initial stop loss.                                      |
//| Magic: 20260848 — fresh, distinct from the live VPS builds        |
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

input group  "Risk Management (per level, % of actual equity)"
input double InpFixedLots       = 0.10;   // Fixed lots fallback (sizing data unavailable)
input double InpRiskATRMult     = 2.0;    // Reference stop distance = ATR(level TF) x this (risk sizing basis)
input double InpRiskPctM5       = 1.0;    // M5   — % of equity risked per trade
input double InpRiskPctM15      = 1.0;    // M15  — % of equity risked per trade
input double InpRiskPctM30      = 5.0;    // M30  — % of equity risked per trade
input double InpRiskPctH1       = 10.0;   // H1   — % of equity risked per trade
input double InpRiskPctH4       = 20.0;   // H4   — % of equity risked per trade

input group  "Entry Filters"
input bool   InpCloudBiasEnabled = true;   // Require Span A vs Span B bias on the level TF + the TF below
input int    InpMaxSpreadPoints  = 60;     // Max spread in points to allow entry (0 = no limit)

input group  "Profit Protection"
input int    InpATRPeriod         = 14;    // ATR period (each level uses its own TF's ATR)
input double InpBEProfitATR       = 1.0;   // BE arms once profit >= this x ATR (M5/M15/M30 levels)
input double InpBEProfitH1H4      = 0.5;   // BE arms once profit >= this x ATR (H1/H4 levels — tighter)
input int    InpBECoverPoints     = 15;    // Points beyond entry for the BE stop (covers spread)
input double InpSpikeLockATR      = 2.0;   // Chandelier trail arms once profit >= this x ATR (M5/M15/M30 spike lock)
input double InpTrailActivateATR  = 1.0;   // H1/H4 chandelier trail arms once profit >= this x ATR
input double InpTrailATR          = 1.5;   // Trail distance behind the peak, x ATR (level TF)

//--- Constants and Global Variables ---
#define MAX_SYMS 60
#define LEVELS   5      // tradable levels: M5, M15, M30, H1, H4
#define TFS      6      // stack: M1, M5, M15, M30, H1, H4

ENUM_TIMEFRAMES tfs[TFS] = { PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4 };
string          tfName[TFS] = { "M1", "M5", "M15", "M30", "H1", "H4" };

int      ich[MAX_SYMS][TFS];
int      atr[MAX_SYMS][LEVELS];       // ATR(level TF) — BE and spike-lock trail sizing
string   syms[MAX_SYMS];
int      symsCount = 0;
datetime lastM1bar[MAX_SYMS];
int      state[MAX_SYMS][LEVELS];     // per level: 0 = flat, 1 = long, -1 = short
int      lastMinuteKey = -1;

double   entryPrice[MAX_SYMS][LEVELS];   // reference entry price per level (BE + trail arming)
double   peakHigh[MAX_SYMS][LEVELS];     // highest high since entry (long chandelier reference)
double   peakLow[MAX_SYMS][LEVELS];      // lowest low since entry (short chandelier reference)
bool     beMoved[MAX_SYMS][LEVELS];      // BE stop already moved to break even (one-shot)

int MAGIC = 20260848;   // fresh — bottom-up stack experiment (20260846/47 are the live VPS builds)

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
      for(int l = 0; l < LEVELS; l++)
      {
         state[s][l] = 0;
         entryPrice[s][l] = 0.0;
         peakHigh[s][l]   = 0.0;
         peakLow[s][l]    = 0.0;
         beMoved[s][l]    = false;
      }

      for(int t = 0; t < TFS; t++)
      {
         ich[s][t] = iIchimoku(syms[s], tfs[t], Tenkan, Kijun, SenkouB);
         if(ich[s][t] == INVALID_HANDLE) return(INIT_FAILED);
      }

      for(int l = 0; l < LEVELS; l++)
      {
         atr[s][l] = iATR(syms[s], tfs[l + 1], InpATRPeriod);
         if(atr[s][l] == INVALID_HANDLE) return(INIT_FAILED);
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
      for(int t = 0; t < TFS; t++)
         if(ich[s][t] != INVALID_HANDLE) IndicatorRelease(ich[s][t]);
      for(int l = 0; l < LEVELS; l++)
         if(atr[s][l] != INVALID_HANDLE) IndicatorRelease(atr[s][l]);
   }
}

//==============================================================
// Position State Sync (recover after restart)
//==============================================================

string LevelComment(int lvl, int dir)
{
   return (dir == 1 ? "Exp Buy " : "Exp Sell ") + tfName[lvl + 1];
}

// Rebuild per-level state from the positions on the account so a restart
// mid-trade resumes the correct levels. The position comment carries the
// level (e.g. "Exp Buy M15"). Entry/peak/BE memory is rebuilt from the
// open price for a restart mid-trade and cleared when the level is flat.
void SyncStateFromPositions()
{
   bool hasPos[MAX_SYMS][LEVELS];
   for(int s = 0; s < symsCount; s++)
   {
      for(int l = 0; l < LEVELS; l++)
      {
         state[s][l] = 0;
         hasPos[s][l] = false;
      }
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      string sym   = PositionGetString(POSITION_SYMBOL);
      int    magic = (int)PositionGetInteger(POSITION_MAGIC);
      int    type  = (int)PositionGetInteger(POSITION_TYPE);
      string comm  = PositionGetString(POSITION_COMMENT);

      if(magic != MAGIC) continue;

      int dir = (type == POSITION_TYPE_BUY) ? 1 : -1;

      for(int s = 0; s < symsCount; s++)
      {
         if(syms[s] != sym) continue;
         for(int l = 0; l < LEVELS; l++)
         {
            if(comm == LevelComment(l, 1) || comm == LevelComment(l, -1))
            {
               state[s][l] = dir;
               hasPos[s][l] = true;
               // EA (re)started mid-trade — rebuild the peak reference from
               // the open price and let it accumulate fresh extremes from here
               if(entryPrice[s][l] == 0.0)
               {
                  entryPrice[s][l] = PositionGetDouble(POSITION_PRICE_OPEN);
                  peakHigh[s][l]   = entryPrice[s][l];
                  peakLow[s][l]    = entryPrice[s][l];
               }
               break;
            }
         }
      }
   }

   // Levels with no open position get their protection memory cleared
   for(int s = 0; s < symsCount; s++)
   {
      for(int l = 0; l < LEVELS; l++)
      {
         if(!hasPos[s][l])
         {
            entryPrice[s][l] = 0.0;
            peakHigh[s][l]   = 0.0;
            peakLow[s][l]    = 0.0;
            beMoved[s][l]    = false;
         }
      }
   }
}

//==============================================================
// Alignment Check: price and chikou both above/below tenkan,
// kijun, and cloud on one timeframe. Returns 1 (bullish),
// -1 (bearish), 0 (none) — identical to the H4 VPS build.
//==============================================================

int CheckAlign(int s, int tfIdx)
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
// Chain Check (bottom-up): the full stack M1..topIdx must be
// aligned in the SAME direction for a level to open.
//==============================================================

int ChainAligned(int s, int topIdx)
{
   int dir = CheckAlign(s, 0);
   if(dir == 0) return 0;

   for(int t = 1; t <= topIdx; t++)
   {
      if(CheckAlign(s, t) != dir) return 0;
   }
   return dir;
}

//==============================================================
// Cloud Bias Filter: the cloud must carry the trade's bias
// (Span A above Span B for a long, below for a short) at both
// the last closed bar and the far end of the future-cloud
// window. Unreadable values count as blocking.
//==============================================================

bool CloudBiasOK(int s, int tfIdx, int dir)
{
   double aNow[1], bNow[1], aFar[1], bFar[1];
   if(CopyBuffer(ich[s][tfIdx], 2, 1,         1, aNow) <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 3, 1,         1, bNow) <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 2, 1 - Kijun, 1, aFar) <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 3, 1 - Kijun, 1, bFar) <= 0) return false;

   if(dir == 1) return aNow[0] > bNow[0] && aFar[0] > bFar[0];
   return aNow[0] < bNow[0] && aFar[0] < bFar[0];
}

// The bias must hold on the level TF and the TF directly below it
// (level lvl opens on TF lvl+1, so the pair is TF lvl and TF lvl+1).
bool LevelCloudBiasOK(int s, int lvl, int dir)
{
   if(!CloudBiasOK(s, lvl + 1, dir)) return false;
   if(!CloudBiasOK(s, lvl, dir))     return false;
   return true;
}

//==============================================================
// Exit Check: the level TF's last closed bar closes back inside
// its cloud (or beyond it — a long that closes below the cloud,
// a short that closes above it). This is the trade's main exit;
// the BE/chandelier stop is the profit-protection layer on top.
//==============================================================

bool InCloudClose(int s, int tfIdx, int dir)
{
   double senA[1], senB[1];
   if(CopyBuffer(ich[s][tfIdx], 2, 1, 1, senA) <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 3, 1, 1, senB) <= 0) return false;

   MqlRates rt[];
   if(CopyRates(syms[s], tfs[tfIdx], 1, 1, rt) <= 0) return false;
   double closeP = rt[0].close;

   if(dir ==  1) return closeP < MathMax(senA[0], senB[0]);
   if(dir == -1) return closeP > MathMin(senA[0], senB[0]);
   return false;
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

bool SpreadOK(string sym)
{
   if(InpMaxSpreadPoints <= 0) return true;
   return SymbolInfoInteger(sym, SYMBOL_SPREAD) <= InpMaxSpreadPoints;
}

//==============================================================
// Risk Management — per-level risk as a fixed % of the ACTUAL
// equity at entry (M5/M15 1%, M30 5%, H1 10%, H4 20%), measured
// against a reference distance of ATR(level TF) x InpRiskATRMult,
// the same ATR-based sizing philosophy as the H4 VPS build. More
// equity -> more risk money -> bigger lots at the same ATR
// distance; no multipliers on top. Falls back to InpFixedLots
// when the sizing data is unavailable, and every order is capped
// to the free margin so it fills fully.
//==============================================================

double LevelRiskPct(int lvl)
{
   switch(lvl)
   {
      case 0:  return InpRiskPctM5;
      case 1:  return InpRiskPctM15;
      case 2:  return InpRiskPctM30;
      case 3:  return InpRiskPctH1;
      case 4:  return InpRiskPctH4;
   }
   return 0.0;
}

double RiskLots(int s, int lvl)
{
   double riskPct = LevelRiskPct(lvl);
   if(riskPct <= 0) return InpFixedLots;

   double a[1];
   if(CopyBuffer(atr[s][lvl], 0, 1, 1, a) <= 0 || a[0] <= 0) return InpFixedLots;
   double stopDist = a[0] * InpRiskATRMult;

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

// Scale a single order down to the free margin so it fills fully.
// lots never drops below the broker minimum.
void CapLotsToMargin(string sym, bool isBuy, double &lots)
{
   if(lots <= 0) return;
   double price = isBuy ? SymbolInfoDouble(sym, SYMBOL_ASK)
                        : SymbolInfoDouble(sym, SYMBOL_BID);
   double marginOne = 0.0;
   if(!OrderCalcMargin(isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, sym, lots, price, marginOne))
      return;
   if(marginOne <= 0) return;
   double maxLots = AccountInfoDouble(ACCOUNT_MARGIN_FREE) * lots / marginOne;
   double lotStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double lotMin  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   if(lotStep > 0) maxLots = MathFloor(maxLots / lotStep) * lotStep;
   maxLots = MathMax(lotMin, maxLots);
   if(lots > maxLots) lots = maxLots;
}

//==============================================================
// Trading Functions
//==============================================================

bool OpenLevel(int s, int lvl, int dir, double lots)
{
   string sym = syms[s];
   string comment = LevelComment(lvl, dir);
   double price = (dir == 1) ? SymbolInfoDouble(sym, SYMBOL_ASK)
                             : SymbolInfoDouble(sym, SYMBOL_BID);
   bool ok = (dir == 1) ? trade.Buy(lots, sym, price, 0, 0, comment)
                        : trade.Sell(lots, sym, price, 0, 0, comment);
   if(ok)
   {
      state[s][lvl] = dir;
      entryPrice[s][lvl] = price;   // BE + spike-lock trail references
      peakHigh[s][lvl]   = price;
      peakLow[s][lvl]    = price;
      beMoved[s][lvl]    = false;
      string action = (dir == 1) ? "Buy" : "Sell";
      string msg = PCTime() + " | " + action + " " + sym + " " + tfName[lvl + 1] +
                   " @ " + DoubleToString(lots, 2) + " (bottom-up)";
      Print(msg); SendNotification(msg);
   }
   return ok;
}

// Close all positions of the level; returns true only when none remain
// open, so a failed close (requote, halt) is retried instead of freeing
// the level for a fresh entry.
bool CloseLevelPositions(int s, int lvl)
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
// Profit Protection (VPS-style systems, per level):
//   * Break-even — once the trade is in profit by >= the ATR
//     threshold (InpBEProfitATR x ATR for M5/M15/M30, the tighter
//     InpBEProfitH1H4 x ATR for H1/H4), the stop moves to entry
//     plus InpBECoverPoints. One-shot per trade (beMoved).
//   * Chandelier trail — H1/H4 levels trail the stop behind the
//     peak once profitable by InpTrailActivateATR x ATR; the
//     lower levels arm it only on a spike (InpSpikeLockATR x ATR).
//     The reference is the highest high / lowest low of the level
//     TF, including the bar still forming; it only ever tightens
//     and never sits inside the broker minimum stop.
// ATR comes from the level's own TF, so H4/H1 protection is sized
// to those timeframes. There is still no initial stop loss.
//==============================================================

bool LevelTicket(int s, int lvl, ulong &ticket)
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

void ManageLevelProtection(int s, int lvl)
{
   int dir = state[s][lvl];
   if(dir == 0) return;

   double a[1];
   if(CopyBuffer(atr[s][lvl], 0, 1, 1, a) <= 0 || a[0] <= 0) return;
   double atrVal = a[0];

   // The reference point is the extreme of the level-TF bar that is still
   // forming, so a peak is locked in before it retraces
   MqlRates tfx[];
   if(CopyRates(syms[s], tfs[lvl + 1], 0, 1, tfx) <= 0) return;
   ArraySetAsSeries(tfx, true);

   bool isLong = (dir == 1);
   if(isLong)
   {
      if(tfx[0].high > peakHigh[s][lvl]) peakHigh[s][lvl] = tfx[0].high;
   }
   else
   {
      if(tfx[0].low < peakLow[s][lvl]) peakLow[s][lvl] = tfx[0].low;
   }

   double point   = SymbolInfoDouble(syms[s], SYMBOL_POINT);
   double minDist = SymbolInfoInteger(syms[s], SYMBOL_TRADE_STOPS_LEVEL) * point;
   int    digits  = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);

   ulong ticket;
   if(!LevelTicket(s, lvl, ticket)) return;
   double slCur = PositionGetDouble(POSITION_SL);

   double bid = SymbolInfoDouble(syms[s], SYMBOL_BID);
   double ask = SymbolInfoDouble(syms[s], SYMBOL_ASK);

   // Break-even: tighter arming threshold on the long-running H1/H4 levels
   double beATR = (lvl >= 3) ? InpBEProfitH1H4 : InpBEProfitATR;
   if(!beMoved[s][lvl])
   {
      bool armed = isLong ? (bid >= entryPrice[s][lvl] + beATR * atrVal)
                          : (ask <= entryPrice[s][lvl] - beATR * atrVal);
      if(armed)
      {
         double slNew = isLong ? entryPrice[s][lvl] + InpBECoverPoints * point
                               : entryPrice[s][lvl] - InpBECoverPoints * point;
         slNew = NormalizeDouble(slNew, digits);

         bool ok = isLong ? (slNew > slCur + point && slNew < bid - minDist)
                          : (slNew < slCur - point && slNew > ask + minDist);
         if(ok)
         {
            if(!trade.PositionModify(ticket, slNew, 0))
               Print(PCTime() + " | " + syms[s] + " " + tfName[lvl + 1] + " BE SL modify failed, retcode " +
                     IntegerToString(trade.ResultRetcode()));
            else
               beMoved[s][lvl] = true;
         }
      }
   }

   // Chandelier trail behind the peak. H1/H4 levels get the full
   // chandelier: it arms once the trade is profitable by InpTrailActivateATR
   // x ATR so long-running higher-TF trades are always protected. The lower
   // levels keep the spike-gated trail (InpSpikeLockATR x ATR). Only ever
   // tightens, keeps out of the broker minimum stop distance, and skips
   // microscopic improvements (0.3x ATR).
   // Re-read the current stop first — the BE block above may have moved it.
   if(!LevelTicket(s, lvl, ticket)) return;
   slCur = PositionGetDouble(POSITION_SL);

   double armATR = (lvl >= 3) ? InpTrailActivateATR : InpSpikeLockATR;
   bool armed = isLong ? (bid >= entryPrice[s][lvl] + armATR * atrVal)
                       : (ask <= entryPrice[s][lvl] - armATR * atrVal);
   if(armed)
   {
      double slNew = isLong ? peakHigh[s][lvl] - InpTrailATR * atrVal
                            : peakLow[s][lvl] + InpTrailATR * atrVal;
      slNew = NormalizeDouble(slNew, digits);

      bool ok = isLong ? (slNew > slCur + point && slNew < bid - minDist &&
                          slNew - slCur >= 0.3 * atrVal)
                       : (slNew < slCur - point && slNew > ask + minDist &&
                          slCur - slNew >= 0.3 * atrVal);
      if(ok)
      {
         if(!trade.PositionModify(ticket, slNew, 0))
            Print(PCTime() + " | " + syms[s] + " " + tfName[lvl + 1] + " trail SL modify failed, retcode " +
                  IntegerToString(trade.ResultRetcode()));
      }
   }
}

//==============================================================
// Main Loop
//==============================================================

void OnTick()
{
   // VPS perf: all logic runs only on closed M1 bars, which change at most
   // once per minute. Skip every intermediate tick entirely.
   int nowKey = (int)(TimeCurrent() / 60);
   if(nowKey == lastMinuteKey) return;
   lastMinuteKey = nowKey;

   bool synced = false;
   for(int s = 0; s < symsCount; s++)
   {
      // Per-symbol M1 bar gating — only act on a new closed M1 bar for this symbol
      MqlRates m1[];
      if(CopyRates(syms[s], PERIOD_M1, 0, 2, m1) < 2) continue;
      ArraySetAsSeries(m1, true);
      if(m1[1].time == lastM1bar[s]) continue;
      lastM1bar[s] = m1[1].time;

      // Sync position state once per tick on the first new M1 bar instead of
      // rebuilding it on every single tick.
      if(!synced) { SyncStateFromPositions(); synced = true; }

      for(int l = 0; l < LEVELS; l++)
      {
         // Exit check: the level's own TF closed a bar back inside its cloud
         if(state[s][l] != 0 && InCloudClose(s, l + 1, state[s][l]))
         {
            string side = (state[s][l] == 1) ? "Long" : "Short";
            string msg  = PCTime() + " | Close " + syms[s] + " " + side + " " +
                          tfName[l + 1] + " (cloud close)";
            Print(msg); SendNotification(msg);

            if(CloseLevelPositions(s, l))
            {
               state[s][l] = 0;
               msg = PCTime() + " | " + syms[s] + " " + tfName[l + 1] + " level closed";
               Print(msg); SendNotification(msg);
            }
            else
               Print(PCTime() + " | " + syms[s] + " " + tfName[l + 1] + " exit signal but positions still open — will retry");
         }

         // Profit protection: BE + spike-lock chandelier trail
         if(state[s][l] != 0) ManageLevelProtection(s, l);

         // Entry check: the level is flat and the full chain M1..level TF
         // aligns in one direction (plus spread and cloud bias gates)
         if(state[s][l] == 0 && SpreadOK(syms[s]))
         {
            int st = ChainAligned(s, l + 1);
            if(st != 0)
            {
               if(InpCloudBiasEnabled && !LevelCloudBiasOK(s, l, st)) continue;

               // Size: per-level risk % of equity vs ATR(level TF) x multiplier, capped to free margin
               double lots = RiskLots(s, l);
               CapLotsToMargin(syms[s], (st == 1), lots);

               if(!OpenLevel(s, l, st, lots))
                  Print(PCTime() + " | " + syms[s] + " " + tfName[l + 1] +
                        " entry signal but order failed, retcode " + IntegerToString(trade.ResultRetcode()));
            }
         }
      }
   }
}
//This work is my worship unto GOD
