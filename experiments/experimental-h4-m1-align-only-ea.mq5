//+------------------------------------------------------------------+
//| Ichimoku H4-M1 Align Only EA — the live build's H4 tier alone     |
//| EXPERIMENTAL (2026-10-01, user request: "just h4-m1 align, no     |
//| other tiers"). A fork of the live VPS build ichimoku-h4-m1-vps-   |
//| ea.mq5 with every tier except H4 removed. With one tier left the  |
//| bottom-up stack collapses back into a single H4 -> M1 alignment:  |
//| every timeframe M1, M5, M15, M30, H1 and H4 must agree before the |
//| one trade opens. The tier ladder, the entry consolidation         |
//| (supersede-closes) and the H1 stand-in bias are gone — the H4     |
//| tier never used the stand-in, and with no smaller tiers there is  |
//| nothing to supersede. Everything that applied to the H4 tier in   |
//| the live build is kept as it was:                                 |
//| Entry: per-TF alignment (price + chikou above/below tenkan,       |
//|        kijun and cloud) on M1, M5, M15, M30, H1 and H4, all in    |
//|        the same direction. H4 is part of the chain, so the H4     |
//|        bias is satisfied by construction.                         |
//|        Cloud bias (InpCloudBiasEnabled): the FUTURE cloud (Span A |
//|        vs Span B, Kijun bars ahead) of H4 and of the TF directly  |
//|        below it, H1, must be twisted the trade's way; the current |
//|        cloud may be either direction.                             |
//|        D1 filter (InpD1Filter): D1 bullish -> buys only, D1       |
//|        bearish -> sells only, D1 in the cloud -> no trades.       |
//|        Spread cap InpMaxSpreadPoints.                             |
//| Exit:  price TOUCHES the H4 cloud edge (a long when the bid       |
//|        touches the upper edge, a short when the ask touches the   |
//|        lower edge). Optional strong-rejection-candle exit on H4   |
//|        (off by default, as live).                                 |
//| Protection: wide disaster SL at entry (ATR(H4) x 8), break-even   |
//|        at +0.5 x ATR(H4) (entry + 15 points), chandelier trail    |
//|        1 x ATR(H4) behind the peak once +0.5 x ATR(H4).           |
//| Risk:  one position per symbol, % of actual equity against        |
//|        ATR(H4) x InpRiskATRMult: 20% below $7000, 10% to $13000,  |
//|        2% above — the live H4 tier's three regimes. Lots capped   |
//|        to InpMarginUsePct of free margin.                         |
//| Robustness pack R2-R5 kept (unknown-position guard, disaster      |
//| stop, chandelier peak rebuild after restart, per-symbol filling + |
//| capped margin). VPS-style: journal Print + SendNotification only, |
//| logic on closed M1 bars. Position comment "Exp Buy H4" / "Exp     |
//| Sell H4", as in the live build.                                   |
//| Note: notes §50 already measured "H4 only" through the tier       |
//| switches of the §48 build (+$76 to +$303 a year from $100); this  |
//| file is the same logic as a standalone EA.                        |
//| Magic: 20260887 — unique (see notes §65).                         |
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

input group  "Risk Management (% of actual equity)"
input double InpFixedLots       = 0.10;   // Fixed lots fallback (sizing data unavailable)
input double InpRiskATRMult     = 2.0;    // Reference stop distance = ATR(H4) x this (risk sizing basis)
input double InpRiskTier2At     = 7000.0; // Equity where risk drops to tier 2 (half regime)
input double InpRiskTier3At     = 13000.0;// Equity where risk drops to tier 3 (tiny regime)
input double InpRiskPct         = 20.0;   // Risk % — tier 1 (equity < Tier2At)
input double InpRiskPct_T2      = 10.0;   // Risk % — tier 2 (half regime)
input double InpRiskPct_T3      = 2.0;    // Risk % — tier 3 (equity >= Tier3At)
input double InpMarginUsePct    = 80.0;   // Max % of FREE margin one order may commit

input group  "Entry Filters"
input bool   InpCloudBiasEnabled = true;   // Require the H4 and H1 future clouds (Span A vs Span B) to carry the trade
input bool   InpD1Filter         = true;   // D1 bias: trade only in the D1's direction; D1 in the cloud = no trades
input int    InpMaxSpreadPoints  = 60;     // Max spread in points to allow entry (0 = no limit)

input group  "Profit Protection"
input int    InpATRPeriod         = 14;    // ATR period (H4)
input double InpBEProfitATR       = 0.5;   // BE arms once profit >= this x ATR(H4)
input int    InpBECoverPoints     = 15;    // Points beyond entry for the BE stop (covers spread)
input double InpTrailActivateATR  = 0.5;   // Chandelier trail arms once profit >= this x ATR(H4)
input double InpTrailATR          = 1.0;   // Trail distance behind the peak, x ATR(H4)

input group  "Disaster Stop (hard tail-risk stop)"
input bool   InpDisasterStopEnabled = true;   // Attach a wide hard SL at entry (bounds gap/disconnect loss)
input double InpDisasterATRMult     = 8.0;    // Disaster stop distance = ATR(H4) x this

input group  "Rejection Exit (strong rejection candle)"
input bool   InpRejectionExit = false;  // Close the trade when a very strong rejection candle forms against it on H4
input int    InpRejSwingBars  = 8;      // Recent swing window (bars) the rejection candle must sweep
input double InpRejWickPct    = 0.5;    // Wick must be >= this fraction of the candle's total range
input double InpRejClosePct   = 0.35;   // Close must sit in the outermost this fraction of the range (strong close-back)

//--- Constants and Global Variables ---
#define MAX_SYMS 60
#define TFS      6      // chain: M1, M5, M15, M30, H1, H4
#define IDX_H1   4      // index of H1 in tfs[] — the TF below H4 in the cloud bias gate
#define IDX_H4   5      // index of H4 in tfs[] — the traded timeframe

ENUM_TIMEFRAMES tfs[TFS] = { PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4 };
string          tfName[TFS] = { "M1", "M5", "M15", "M30", "H1", "H4" };

int      ich[MAX_SYMS][TFS];
int      ichD1[MAX_SYMS];           // D1 ichimoku handle — bias filter
int      atr[MAX_SYMS];             // ATR(H4) — sizing, BE, trail, disaster stop
string   syms[MAX_SYMS];
int      symsCount = 0;
datetime lastM1bar[MAX_SYMS];
int      state[MAX_SYMS];           // 0 = flat, 1 = long, -1 = short
int      lastMinuteKey = -1;

double   entryPrice[MAX_SYMS];      // reference entry price (BE + trail arming)
double   peakHigh[MAX_SYMS];        // highest high since entry (long chandelier reference)
double   peakLow[MAX_SYMS];         // lowest low since entry (short chandelier reference)
bool     beMoved[MAX_SYMS];         // BE stop already moved to break even (one-shot)

// R2: unknown-position guard. A position carrying our magic whose comment
// no longer reads "Exp Buy/Sell H4" cannot be managed — track it, block new
// entries on its symbol until it is gone, and log it once per ticket.
bool              symBlockedUnknown[MAX_SYMS];
ulong             unknownLoggedTickets[64];
int               unknownLoggedCount   = 0;

int MAGIC = 20260887;   // H4-M1 align only — unique

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
      symBlockedUnknown[s] = false;
      state[s] = 0;
      entryPrice[s] = 0.0;
      peakHigh[s]   = 0.0;
      peakLow[s]    = 0.0;
      beMoved[s]    = false;

      for(int t = 0; t < TFS; t++)
      {
         ich[s][t] = iIchimoku(syms[s], tfs[t], Tenkan, Kijun, SenkouB);
         if(ich[s][t] == INVALID_HANDLE) return(INIT_FAILED);
      }

      ichD1[s] = iIchimoku(syms[s], PERIOD_D1, Tenkan, Kijun, SenkouB);
      if(ichD1[s] == INVALID_HANDLE) return(INIT_FAILED);

      atr[s] = iATR(syms[s], PERIOD_H4, InpATRPeriod);
      if(atr[s] == INVALID_HANDLE) return(INIT_FAILED);
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
      if(ichD1[s] != INVALID_HANDLE) IndicatorRelease(ichD1[s]);
      if(atr[s] != INVALID_HANDLE) IndicatorRelease(atr[s]);
   }
}

//==============================================================
// Position State Sync (recover after restart)
//==============================================================

string TradeComment(int dir)
{
   return (dir == 1) ? "Exp Buy H4" : "Exp Sell H4";
}

bool IsOurComment(string comm)
{
   return comm == TradeComment(1) || comm == TradeComment(-1);
}

// R2: log an unparseable magic position once per ticket — without the
// ticket memory this would repeat every minute while the position lives.
// After 64 distinct tickets the log goes quiet but the block stays on.
void LogUnknownOnce(ulong ticket, string sym, string comm)
{
   for(int i = 0; i < unknownLoggedCount; i++)
      if(unknownLoggedTickets[i] == ticket) return;
   if(unknownLoggedCount < 64) unknownLoggedTickets[unknownLoggedCount++] = ticket;
   Print(PCTime() + " | !! " + sym + " position #" + IntegerToString((long)ticket) +
         " carries this EA's magic but its comment \"" + comm +
         "\" is not this EA's — BE/trail/cloud exits CANNOT manage it." +
         " New entries on " + sym + " are blocked until it is closed.");
}

// Rebuild state from the positions on the account so a restart mid-trade
// resumes the trade. Entry/peak/BE memory is rebuilt for a restart mid-
// trade — the chandelier references from the H4 history since the
// position opened (R4) — and cleared when the symbol is flat.
void SyncStateFromPositions()
{
   bool hasPos[MAX_SYMS];
   for(int s = 0; s < symsCount; s++)
   {
      symBlockedUnknown[s] = false;              // R2: re-evaluated every sync
      state[s]  = 0;
      hasPos[s] = false;
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

         if(!IsOurComment(comm))
         {
            symBlockedUnknown[s] = true;
            LogUnknownOnce(ticket, sym, comm);
            continue;
         }

         state[s]  = dir;
         hasPos[s] = true;

         // EA (re)started mid-trade — rebuild the protection references.
         // R4: peaks come from the H4 bars since the position actually
         // opened, so the chandelier resumes where it left off.
         if(entryPrice[s] == 0.0)
         {
            entryPrice[s] = PositionGetDouble(POSITION_PRICE_OPEN);
            double hi = entryPrice[s];
            double lo = entryPrice[s];
            MqlRates hist[];
            int nb = CopyRates(sym, PERIOD_H4,
                               (datetime)PositionGetInteger(POSITION_TIME),
                               TimeCurrent(), hist);
            for(int b = 0; b < nb; b++)
            {
               if(hist[b].high > hi) hi = hist[b].high;
               if(hist[b].low  < lo) lo = hist[b].low;
            }
            peakHigh[s] = hi;
            peakLow[s]  = lo;
         }
         break;
      }
   }

   // Symbols with no open position get their protection memory cleared
   for(int s = 0; s < symsCount; s++)
   {
      if(!hasPos[s])
      {
         entryPrice[s] = 0.0;
         peakHigh[s]   = 0.0;
         peakLow[s]    = 0.0;
         beMoved[s]    = false;
      }
   }
}

//==============================================================
// Alignment Check: price and chikou both above/below tenkan,
// kijun, and cloud on one timeframe. Returns 1 (bullish),
// -1 (bearish), 0 (none) — identical to the live VPS build.
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
// Chain Check: M1, M5, M15, M30, H1 and H4 must all be aligned
// in the SAME direction. Checked from M1 up so the cheap, most
// often failing timeframe short-circuits first.
//==============================================================

int ChainAligned(int s)
{
   int dir = CheckAlign(s, 0);
   if(dir == 0) return 0;

   for(int t = 1; t < TFS; t++)
   {
      if(CheckAlign(s, t) != dir) return 0;
   }
   return dir;
}

//==============================================================
// Daily Bias Filter: D1 bullish (price + chikou above tenkan,
// kijun and cloud) allows only buys, D1 bearish only sells. A D1
// close INSIDE the cloud (or unreadable) returns 0 — no trades.
//==============================================================

int DailyAlign(int s)
{
   ENUM_TIMEFRAMES tf = PERIOD_D1;

   int sh      = 1;
   int chShift = sh + Kijun;

   MqlRates rt[];
   if(CopyRates(syms[s], tf, 0, chShift + 1, rt) <= 0) return 0;
   ArraySetAsSeries(rt, true);
   if(ArraySize(rt) <= chShift) return 0;

   double tenkan[1], kijun[1], senA[1], senB[1];
   if(CopyBuffer(ichD1[s], 0, sh, 1, tenkan) <= 0) return 0;
   if(CopyBuffer(ichD1[s], 1, sh, 1, kijun)  <= 0) return 0;
   if(CopyBuffer(ichD1[s], 2, sh, 1, senA)   <= 0) return 0;
   if(CopyBuffer(ichD1[s], 3, sh, 1, senB)   <= 0) return 0;

   double closeP = rt[sh].close;
   double cHi    = MathMax(senA[0], senB[0]);
   double cLo    = MathMin(senA[0], senB[0]);

   bool above = closeP > tenkan[0] && closeP > kijun[0] && closeP > cHi;
   bool below = closeP < tenkan[0] && closeP < kijun[0] && closeP < cLo;
   if(!above && !below) return 0;   // D1 close inside the cloud — no trades

   double tenkan_ch[1], kijun_ch[1], senA_ch[1], senB_ch[1];
   if(CopyBuffer(ichD1[s], 0, chShift, 1, tenkan_ch) <= 0) return 0;
   if(CopyBuffer(ichD1[s], 1, chShift, 1, kijun_ch)  <= 0) return 0;
   if(CopyBuffer(ichD1[s], 2, chShift, 1, senA_ch)   <= 0) return 0;
   if(CopyBuffer(ichD1[s], 3, chShift, 1, senB_ch)   <= 0) return 0;

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
// Cloud Bias Filter — FUTURE-ONLY: the far end of the future-
// cloud window (Kijun bars ahead of the last closed bar) must
// carry the trade's bias; the immediate cloud where price sits
// may be either direction. Unreadable values count as blocking.
// The live build's H4 tier checks H4 and the TF below it, H1.
//==============================================================

bool CloudBiasFarOK(int s, int tfIdx, int dir)
{
   double aFar[1], bFar[1];
   if(CopyBuffer(ich[s][tfIdx], 2, 1 - Kijun, 1, aFar) <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 3, 1 - Kijun, 1, bFar) <= 0) return false;

   if(dir == 1) return aFar[0] > bFar[0];
   return aFar[0] < bFar[0];
}

bool CloudBiasOK(int s, int dir)
{
   return CloudBiasFarOK(s, IDX_H4, dir) && CloudBiasFarOK(s, IDX_H1, dir);
}

//==============================================================
// Exit Check: price TOUCHES the H4 cloud edge — no wait for a
// candle to close inside it. A long exits when the bid touches
// the cloud's upper edge; a short when the ask touches the lower
// edge. Evaluated once per closed M1 bar.
//==============================================================

bool InCloudTouch(int s, int dir)
{
   double senA[1], senB[1];
   if(CopyBuffer(ich[s][IDX_H4], 2, 1, 1, senA) <= 0) return false;
   if(CopyBuffer(ich[s][IDX_H4], 3, 1, 1, senB) <= 0) return false;

   if(dir ==  1)
   {
      double bid = SymbolInfoDouble(syms[s], SYMBOL_BID);
      return bid <= MathMax(senA[0], senB[0]);
   }
   if(dir == -1)
   {
      double ask = SymbolInfoDouble(syms[s], SYMBOL_ASK);
      return ask >= MathMin(senA[0], senB[0]);
   }
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
// Risk Management — risk as a fixed % of the ACTUAL equity at
// entry, in the live H4 tier's three regimes that DE-RISK as the
// account grows (20% / 10% / 2% by default), measured against a
// reference distance of ATR(H4) x InpRiskATRMult. Falls back to
// InpFixedLots when the sizing data is unavailable.
//==============================================================

double RiskPct()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq >= InpRiskTier3At) return InpRiskPct_T3;
   if(eq >= InpRiskTier2At) return InpRiskPct_T2;
   return InpRiskPct;
}

double RiskLots(int s)
{
   double riskPct = RiskPct();
   if(riskPct <= 0) return InpFixedLots;

   double a[1];
   if(CopyBuffer(atr[s], 0, 1, 1, a) <= 0 || a[0] <= 0) return InpFixedLots;
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

// Scale a single order down so it commits at most InpMarginUsePct % of the
// free margin (R5). lots never drops below the broker minimum.
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

//==============================================================
// Trading Functions
//==============================================================

bool OpenTrade(int s, int dir, double lots)
{
   string sym = syms[s];
   string comment = TradeComment(dir);
   double price = (dir == 1) ? SymbolInfoDouble(sym, SYMBOL_ASK)
                             : SymbolInfoDouble(sym, SYMBOL_BID);

   // R5: pick a filling mode this symbol actually supports.
   trade.SetTypeFillingBySymbol(sym);

   // R3: disaster stop — a wide hard SL bounding gap/disconnect loss,
   // anchored at the entry price. If ATR or the broker distance check makes
   // it invalid right now, the order goes out without it and
   // ManageProtection re-attaches it next minute.
   double sl = 0.0;
   if(InpDisasterStopEnabled)
   {
      double a[1];
      if(CopyBuffer(atr[s], 0, 1, 1, a) > 0 && a[0] > 0)
      {
         double point   = SymbolInfoDouble(sym, SYMBOL_POINT);
         double minDist = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * point;
         int    digits  = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
         double dist    = MathMax(a[0] * InpDisasterATRMult, minDist + point);
         sl             = NormalizeDouble((dir == 1) ? price - dist : price + dist, digits);

         // A long's SL triggers on the BID, a short's on the ASK — validate
         // against the side that will actually trip it.
         double bidNow  = SymbolInfoDouble(sym, SYMBOL_BID);
         double askNow  = SymbolInfoDouble(sym, SYMBOL_ASK);
         bool   slValid = (dir == 1) ? (sl > 0 && sl < bidNow - minDist)
                                     : (sl > 0 && sl > askNow + minDist);
         if(!slValid) sl = 0.0;
      }
   }

   bool ok = (dir == 1) ? trade.Buy(lots, sym, price, sl, 0, comment)
                        : trade.Sell(lots, sym, price, sl, 0, comment);
   if(ok)
   {
      state[s]      = dir;
      entryPrice[s] = price;
      peakHigh[s]   = price;
      peakLow[s]    = price;
      beMoved[s]    = false;
      string action = (dir == 1) ? "Buy" : "Sell";
      string msg = PCTime() + " | " + action + " " + sym + " H4 @ " +
                   DoubleToString(lots, 2) + " (H4-M1 align)";
      Print(msg); SendNotification(msg);
   }
   return ok;
}

// Close the symbol's positions; returns true only when none remain open,
// so a failed close (requote, halt) is retried instead of freeing the
// symbol for a fresh entry.
bool ClosePositions(int s)
{
   string sym = syms[s];
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) == sym &&
         (int)PositionGetInteger(POSITION_MAGIC) == MAGIC &&
         IsOurComment(PositionGetString(POSITION_COMMENT)))
      {
         if(!trade.PositionClose(ticket))
            Print(PCTime() + " | " + sym + " H4 close failed, retcode " +
                  IntegerToString(trade.ResultRetcode()));
      }
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) == sym &&
         (int)PositionGetInteger(POSITION_MAGIC) == MAGIC &&
         IsOurComment(PositionGetString(POSITION_COMMENT))) return false;
   }
   return true;
}

//==============================================================
// Profit Protection (the live build's H4-tier rules):
//   * Break-even — once the trade is in profit by >=
//     InpBEProfitATR x ATR(H4), the stop moves to entry plus
//     InpBECoverPoints. One-shot per trade (beMoved).
//   * Chandelier trail — trails the stop InpTrailATR x ATR(H4)
//     behind the peak once profitable by InpTrailActivateATR x
//     ATR(H4). The reference is the highest high / lowest low of
//     H4, including the bar still forming; it only ever tightens
//     and never sits inside the broker minimum stop.
// The only hard stop is the wide R3 disaster SL; if it ever goes
// missing, it is re-attached here.
//==============================================================

bool TradeTicket(int s, ulong &ticket)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != syms[s]) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MAGIC) continue;
      if(IsOurComment(PositionGetString(POSITION_COMMENT))) return true;
   }
   return false;
}

void ManageProtection(int s)
{
   int dir = state[s];
   if(dir == 0) return;

   double a[1];
   if(CopyBuffer(atr[s], 0, 1, 1, a) <= 0 || a[0] <= 0) return;
   double atrVal = a[0];

   // The reference point is the extreme of the H4 bar that is still
   // forming, so a peak is locked in before it retraces
   MqlRates tfx[];
   if(CopyRates(syms[s], PERIOD_H4, 0, 1, tfx) <= 0) return;
   ArraySetAsSeries(tfx, true);

   bool isLong = (dir == 1);
   if(isLong)
   {
      if(tfx[0].high > peakHigh[s]) peakHigh[s] = tfx[0].high;
   }
   else
   {
      if(tfx[0].low < peakLow[s]) peakLow[s] = tfx[0].low;
   }

   double point   = SymbolInfoDouble(syms[s], SYMBOL_POINT);
   double minDist = SymbolInfoInteger(syms[s], SYMBOL_TRADE_STOPS_LEVEL) * point;
   int    digits  = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);

   ulong ticket;
   if(!TradeTicket(s, ticket)) return;
   double slCur = PositionGetDouble(POSITION_SL);

   double bid = SymbolInfoDouble(syms[s], SYMBOL_BID);
   double ask = SymbolInfoDouble(syms[s], SYMBOL_ASK);

   // R3: self-heal a missing disaster stop. Anchored at the ENTRY price so
   // the tail definition never drifts; only attaches while no other stop
   // exists — BE/chandelier take over from there and only ever tighten.
   if(InpDisasterStopEnabled && slCur == 0.0)
   {
      double dSl = NormalizeDouble(isLong ? entryPrice[s] - InpDisasterATRMult * atrVal
                                          : entryPrice[s] + InpDisasterATRMult * atrVal,
                                   digits);
      bool okD = isLong ? (dSl > 0 && dSl < bid - minDist)
                        : (dSl > ask + minDist);
      if(okD)
      {
         if(trade.PositionModify(ticket, dSl, 0))
            slCur = dSl;
         else
            Print(PCTime() + " | " + syms[s] + " H4 disaster SL attach failed, retcode " +
                  IntegerToString(trade.ResultRetcode()));
      }
   }

   // Break-even
   if(!beMoved[s])
   {
      bool armed = isLong ? (bid >= entryPrice[s] + InpBEProfitATR * atrVal)
                          : (ask <= entryPrice[s] - InpBEProfitATR * atrVal);
      if(armed)
      {
         double slNew = isLong ? entryPrice[s] + InpBECoverPoints * point
                               : entryPrice[s] - InpBECoverPoints * point;
         slNew = NormalizeDouble(slNew, digits);

         bool ok = isLong ? (slNew > slCur + point && slNew < bid - minDist)
                          : (slNew < slCur - point && slNew > ask + minDist);
         if(ok)
         {
            if(!trade.PositionModify(ticket, slNew, 0))
               Print(PCTime() + " | " + syms[s] + " H4 BE SL modify failed, retcode " +
                     IntegerToString(trade.ResultRetcode()));
            else
               beMoved[s] = true;
         }
      }
   }

   // Chandelier trail behind the peak. Only ever tightens, keeps out of the
   // broker minimum stop distance, and skips microscopic improvements
   // (0.3x ATR). Re-read the current stop first — BE may have moved it.
   if(!TradeTicket(s, ticket)) return;
   slCur = PositionGetDouble(POSITION_SL);

   bool armed = isLong ? (bid >= entryPrice[s] + InpTrailActivateATR * atrVal)
                       : (ask <= entryPrice[s] - InpTrailActivateATR * atrVal);
   if(armed)
   {
      double slNew = isLong ? peakHigh[s] - InpTrailATR * atrVal
                            : peakLow[s] + InpTrailATR * atrVal;
      slNew = NormalizeDouble(slNew, digits);

      bool ok = isLong ? (slNew > slCur + point && slNew < bid - minDist &&
                          slNew - slCur >= 0.3 * atrVal)
                       : (slNew < slCur - point && slNew > ask + minDist &&
                          slCur - slNew >= 0.3 * atrVal);
      if(ok)
      {
         if(!trade.PositionModify(ticket, slNew, 0))
            Print(PCTime() + " | " + syms[s] + " H4 trail SL modify failed, retcode " +
                  IntegerToString(trade.ResultRetcode()));
      }
   }
}

//==============================================================
// Rejection Candle Exit: closes the trade when a VERY STRONG
// rejection forms against it on H4 (last closed bar). All four
// conditions must hold — a swing sweep plus a dominant wick plus
// a strong close-back on a candle whose body opposes the trade.
// Returns 1 (bullish), -1 (bearish), 0 (none).
//==============================================================

int RejectionCandle(int s)
{
   int need = 2 + InpRejSwingBars;
   MqlRates r[];
   if(CopyRates(syms[s], PERIOD_H4, 0, need, r) < need) return 0;
   ArraySetAsSeries(r, true);

   double o1 = r[1].open, c1 = r[1].close, h1 = r[1].high, l1 = r[1].low;

   // Swing extreme of the InpRejSwingBars bars before the rejection candle
   double swingHi = r[2].high, swingLo = r[2].low;
   for(int i = 3; i < need; i++)
   {
      if(r[i].high > swingHi) swingHi = r[i].high;
      if(r[i].low  < swingLo) swingLo = r[i].low;
   }

   double range = h1 - l1;
   if(range <= 0) return 0;

   // Bearish rejection: sweeps the swing high and closes strongly back
   if(c1 < o1 && h1 > swingHi)
   {
      double upperWick = h1 - o1;
      double closeBack = c1 - l1;
      if(upperWick >= InpRejWickPct * range &&
         closeBack <= InpRejClosePct * range)
         return -1;
   }

   // Bullish rejection: sweeps the swing low and closes strongly back
   if(c1 > o1 && l1 < swingLo)
   {
      double lowerWick = o1 - l1;
      double closeBack = h1 - c1;
      if(lowerWick >= InpRejWickPct * range &&
         closeBack <= InpRejClosePct * range)
         return 1;
   }
   return 0;
}

// Close the trade with a notification; returns true only when nothing
// remains open, so a failed close is retried next bar.
bool ExitTrade(int s, string reason)
{
   string side = (state[s] == 1) ? "Long" : "Short";
   string msg  = PCTime() + " | Close " + syms[s] + " " + side + " H4 (" + reason + ")";
   Print(msg); SendNotification(msg);

   if(ClosePositions(s))
   {
      state[s] = 0;
      msg = PCTime() + " | " + syms[s] + " H4 trade closed";
      Print(msg); SendNotification(msg);
      return true;
   }
   Print(PCTime() + " | " + syms[s] + " H4 exit signal but positions still open — will retry");
   return false;
}

//==============================================================
// Main Loop
//==============================================================

void OnTick()
{
   // All logic runs only on closed M1 bars, which change at most once per
   // minute. Skip every intermediate tick entirely.
   int nowKey = (int)(TimeCurrent() / 60);
   if(nowKey == lastMinuteKey) return;
   lastMinuteKey = nowKey;

   bool synced = false;
   for(int s = 0; s < symsCount; s++)
   {
      // Per-symbol M1 bar gating — only act on a new closed M1 bar
      MqlRates m1[];
      if(CopyRates(syms[s], PERIOD_M1, 0, 2, m1) < 2) continue;
      ArraySetAsSeries(m1, true);
      if(m1[1].time == lastM1bar[s]) continue;
      lastM1bar[s] = m1[1].time;

      if(!synced) { SyncStateFromPositions(); synced = true; }

      // Exits and profit protection
      if(state[s] != 0 && InCloudTouch(s, state[s]))
         ExitTrade(s, "kumo touch");

      if(InpRejectionExit && state[s] != 0)
      {
         int rj = RejectionCandle(s);
         if(rj != 0 && rj == -state[s])
            ExitTrade(s, "rejection");
      }

      if(state[s] != 0) ManageProtection(s);

      // Entry: one trade per symbol, only when M1..H4 all agree.
      // R2: never add exposure while an unmanageable magic position sits
      // on this symbol.
      if(state[s] != 0 || symBlockedUnknown[s] || !SpreadOK(syms[s])) continue;

      int dir = ChainAligned(s);
      if(dir == 0) continue;
      if(InpCloudBiasEnabled && !CloudBiasOK(s, dir)) continue;
      if(InpD1Filter && DailyAlign(s) != dir) continue;

      double lots = RiskLots(s);
      CapLotsToMargin(syms[s], (dir == 1), lots);

      if(!OpenTrade(s, dir, lots))
         Print(PCTime() + " | " + syms[s] + " H4 entry signal but order failed, retcode " +
               IntegerToString(trade.ResultRetcode()));
   }
}
//This work is my worship unto GOD
