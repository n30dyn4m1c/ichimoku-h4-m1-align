//+------------------------------------------------------------------+
//| Ichimoku M15-H1-H4 Tiers EA — two tiers on an M15 base            |
//| EXPERIMENTAL (2026-10-01). Started as "just h4-m1 align, no other |
//| tiers": a fork of the live VPS build ichimoku-h4-m1-vps-ea.mq5    |
//| with every tier except H4 removed. Then, on user instruction, the |
//| D1 filter was turned off, the chain was cut from M1..H4 to        |
//| M15..H4, the disaster stop became a tight ATR x 1 stop loss, and  |
//| an M15-H1 tier was added. Two tiers now, grown bottom-up from M15 |
//| as in the live build (M1 and M5 take no part):                    |
//|   Tier H1: M15 + M30 + H1 aligned        -> open an H1 trade      |
//|   Tier H4: M15 + M30 + H1 + H4 aligned   -> open an H4 trade      |
//| Entry: per-TF alignment (price + chikou above/below tenkan,       |
//|        kijun and cloud), all TFs of the tier's chain in the same  |
//|        direction.                                                 |
//|        Cloud bias (InpCloudBiasEnabled): the FUTURE cloud (Span A |
//|        vs Span B, Kijun bars ahead) of the tier TF and of the TF  |
//|        directly below it (H1 tier: H1 + M30; H4 tier: H4 + H1)    |
//|        must be twisted the trade's way; the current cloud may be  |
//|        either direction — the live build's rule for M5+.          |
//|        H4 gate on the H1 tier (InpH1H4Gate, OFF by default): the  |
//|        live H1 tier needs H4 aligned WITH it, but on an M15 base  |
//|        that is the H4 tier's own signal, so the H1 tier would     |
//|        only fire alongside H4. Off, it trades M15..H1 alone;      |
//|        H1H4_NOT_AGAINST skips H1 trades against an aligned H4;    |
//|        H1H4_WITH restores the live rule.                          |
//|        D1 filter on the H4 tier (InpD1Filter): OFF by default.    |
//|        On, H4 trades only in the D1's direction, none while D1    |
//|        closes in its cloud — the live H4 tier's rule.             |
//|        Spread cap InpMaxSpreadPoints.                             |
//| No consolidation (user, 2026-10-01): H1 and H4 fire on their own  |
//| signals and may both open on the same bar when both are aligned;  |
//| an H4 entry no longer closes a running H1 trade. Each tier keeps  |
//| one position per symbol.                                          |
//| Exit:  price TOUCHES the tier TF's cloud edge (a long when the    |
//|        bid touches the upper edge, a short when the ask touches   |
//|        the lower edge). Optional strong-rejection-candle exit on  |
//|        the tier TF (off by default, as live).                     |
//| Protection: TIGHT stop loss at entry, ATR(H4) x InpStopATRMult    |
//|        (1) on BOTH tiers — the H1 tier uses the H4 tier's stop    |
//|        distance (user, 2026-10-01). It replaces the live build's  |
//|        wide x 8 disaster stop. Break-even at +0.5 x ATR (entry +  |
//|        15 points) and a chandelier trail 1 x ATR behind the peak  |
//|        once +0.5 x ATR, on the tier's own TF ATR — the live H1/H4 |
//|        tier settings.                                             |
//| Risk:  unchanged from the live VPS build — % of actual equity     |
//|        against ATR(tier TF) x InpRiskATRMult: H1 10/5/1%, H4      |
//|        20/10/2% (below $7000 / to $13000 / above), lots capped to |
//|        InpMarginUsePct of free margin. With both tiers open at    |
//|        once the account carries both risks (30% at tier 1).       |
//| Robustness pack R2-R5 kept (unknown-position guard, stop loss     |
//| self-heal, chandelier peak rebuild after restart, per-symbol      |
//| filling + capped margin). VPS-style: journal Print +              |
//| SendNotification only; logic runs once per closed M1 bar so the   |
//| cloud-touch exits and the stops react within a minute. Position   |
//| comments "Exp Buy H1" / "Exp Sell H4" etc., as in the live build. |
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

input group  "Risk Management (per tier, % of actual equity)"
input double InpFixedLots       = 0.10;   // Fixed lots fallback (sizing data unavailable)
input double InpRiskATRMult     = 2.0;    // Reference stop distance = ATR(tier TF) x this (risk sizing basis)
input double InpRiskTier2At     = 7000.0; // Equity where risk drops to tier 2 (half regime)
input double InpRiskTier3At     = 13000.0;// Equity where risk drops to tier 3 (tiny regime)
input double InpRiskPctH1       = 10.0;   // H1 — tier 1 (equity < Tier2At)
input double InpRiskPctH4       = 20.0;   // H4 — tier 1
input double InpRiskPctH1_T2    = 5.0;    // H1 — tier 2 (half regime)
input double InpRiskPctH4_T2    = 10.0;   // H4 — tier 2
input double InpRiskPctH1_T3    = 1.0;    // H1 — tier 3 (equity >= Tier3At)
input double InpRiskPctH4_T3    = 2.0;    // H4 — tier 3
input double InpMarginUsePct    = 80.0;   // Max % of FREE margin one order may commit

// What the H4 alignment means for the H1 tier.
//   H1H4_OFF         : ignored — the H1 tier trades M15..H1 on its own
//   H1H4_NOT_AGAINST : no H1 trade against an ALIGNED H4 (flat H4 is fine)
//   H1H4_WITH        : H4 must be aligned with the trade (the live rule)
enum ENUM_H1_H4_GATE { H1H4_OFF = 0, H1H4_NOT_AGAINST = 1, H1H4_WITH = 2 };

input group  "Entry Filters"
input bool   InpH1Tier           = true;   // H1 tier (M15 + M30 + H1 aligned) opens trades
input bool   InpH4Tier           = true;   // H4 tier (M15 + M30 + H1 + H4 aligned) opens trades
input bool   InpCloudBiasEnabled = true;   // Require the tier TF and the TF below to have their future cloud (Span A vs Span B) with the trade
input ENUM_H1_H4_GATE InpH1H4Gate = H1H4_OFF; // H1 tier vs H4: 0=ignore H4, 1=not against an aligned H4, 2=H4 aligned with it (live)
input bool   InpD1Filter         = false;  // H4 tier only: trade in the D1's direction, D1 in the cloud = no H4 trades (live: on)
input int    InpMaxSpreadPoints  = 60;     // Max spread in points to allow entry (0 = no limit)

input group  "Profit Protection"
input int    InpATRPeriod         = 14;    // ATR period (each tier uses its own TF's ATR)
input double InpBEProfitATR       = 0.5;   // BE arms once profit >= this x ATR
input int    InpBECoverPoints     = 15;    // Points beyond entry for the BE stop (covers spread)
input double InpTrailActivateATR  = 0.5;   // Chandelier trail arms once profit >= this x ATR
input double InpTrailATR          = 1.0;   // Trail distance behind the peak, x ATR

input group  "Stop Loss (tight, ATR(H4) on both tiers)"
input bool   InpStopLossEnabled = true;   // Attach a tight hard SL at entry
input double InpStopATRMult     = 1.0;    // Stop distance = ATR(H4) x this, H1 and H4 tiers alike (live build's disaster stop: 8)

input group  "Rejection Exit (strong rejection candle)"
input bool   InpRejectionExit = false;  // Close a trade when a very strong rejection candle forms against it on the tier TF
input int    InpRejSwingBars  = 8;      // Recent swing window (bars) the rejection candle must sweep
input double InpRejWickPct    = 0.5;    // Wick must be >= this fraction of the candle's total range
input double InpRejClosePct   = 0.35;   // Close must sit in the outermost this fraction of the range (strong close-back)

//--- Constants and Global Variables ---
#define MAX_SYMS 60
#define TFS      4      // stack: M15, M30, H1, H4
#define LEVELS   2      // tradable tiers: H1, H4
#define IDX_H4   3      // index of H4 in tfs[]
#define LVL_H1   0
#define LVL_H4   1

ENUM_TIMEFRAMES tfs[TFS]     = { PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4 };
string          tfName[TFS]  = { "M15", "M30", "H1", "H4" };
int             lvlTf[LEVELS] = { 2, 3 };   // tfs[] index of each tier's TF

int      ich[MAX_SYMS][TFS];
int      ichD1[MAX_SYMS];             // D1 ichimoku handle — H4-tier bias filter
int      atr[MAX_SYMS][LEVELS];       // ATR(tier TF) — sizing, BE, trail; ATR(H4) also sizes both stop losses
string   syms[MAX_SYMS];
int      symsCount = 0;
datetime lastM1bar[MAX_SYMS];
int      state[MAX_SYMS][LEVELS];     // per tier: 0 = flat, 1 = long, -1 = short
int      lastMinuteKey = -1;

double   entryPrice[MAX_SYMS][LEVELS];   // reference entry price per tier (BE + trail arming)
double   peakHigh[MAX_SYMS][LEVELS];     // highest high since entry (long chandelier reference)
double   peakLow[MAX_SYMS][LEVELS];      // lowest low since entry (short chandelier reference)
bool     beMoved[MAX_SYMS][LEVELS];      // BE stop already moved to break even (one-shot)

// R2: unknown-position guard. A position carrying our magic whose comment
// no longer names a tier cannot be managed — track it, block new entries
// on its symbol until it is gone, and log it once per ticket.
bool              symBlockedUnknown[MAX_SYMS];
ulong             unknownLoggedTickets[64];
int               unknownLoggedCount   = 0;

int MAGIC = 20260887;   // M15-H1-H4 tiers — unique

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

      ichD1[s] = iIchimoku(syms[s], PERIOD_D1, Tenkan, Kijun, SenkouB);
      if(ichD1[s] == INVALID_HANDLE) return(INIT_FAILED);

      for(int l = 0; l < LEVELS; l++)
      {
         atr[s][l] = iATR(syms[s], tfs[lvlTf[l]], InpATRPeriod);
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
      if(ichD1[s] != INVALID_HANDLE) IndicatorRelease(ichD1[s]);
      for(int l = 0; l < LEVELS; l++)
         if(atr[s][l] != INVALID_HANDLE) IndicatorRelease(atr[s][l]);
   }
}

//==============================================================
// Position State Sync (recover after restart)
//==============================================================

string LvlName(int lvl)
{
   return tfName[lvlTf[lvl]];
}

string LevelComment(int lvl, int dir)
{
   return (dir == 1 ? "Exp Buy " : "Exp Sell ") + LvlName(lvl);
}

bool IsLevelComment(int lvl, string comm)
{
   return comm == LevelComment(lvl, 1) || comm == LevelComment(lvl, -1);
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
         "\" names no tier — BE/trail/cloud exits CANNOT manage it." +
         " New entries on " + sym + " are blocked until it is closed.");
}

// Rebuild per-tier state from the positions on the account so a restart
// mid-trade resumes the correct tiers. Entry/peak/BE memory is rebuilt for
// a restart mid-trade — the chandelier references from the tier-TF history
// since the position opened (R4) — and cleared when the tier is flat.
void SyncStateFromPositions()
{
   bool hasPos[MAX_SYMS][LEVELS];
   for(int s = 0; s < symsCount; s++)
   {
      symBlockedUnknown[s] = false;              // R2: re-evaluated every sync
      for(int l = 0; l < LEVELS; l++)
      {
         state[s][l]  = 0;
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

         int lvlMatch = -1;
         for(int l = 0; l < LEVELS; l++)
            if(IsLevelComment(l, comm)) { lvlMatch = l; break; }

         if(lvlMatch < 0)
         {
            symBlockedUnknown[s] = true;
            LogUnknownOnce(ticket, sym, comm);
            continue;
         }

         state[s][lvlMatch]  = dir;
         hasPos[s][lvlMatch] = true;

         // EA (re)started mid-trade — rebuild the protection references.
         // R4: peaks come from the tier-TF bars since the position actually
         // opened, so the chandelier resumes where it left off.
         if(entryPrice[s][lvlMatch] == 0.0)
         {
            entryPrice[s][lvlMatch] = PositionGetDouble(POSITION_PRICE_OPEN);
            double hi = entryPrice[s][lvlMatch];
            double lo = entryPrice[s][lvlMatch];
            MqlRates hist[];
            int nb = CopyRates(sym, tfs[lvlTf[lvlMatch]],
                               (datetime)PositionGetInteger(POSITION_TIME),
                               TimeCurrent(), hist);
            for(int b = 0; b < nb; b++)
            {
               if(hist[b].high > hi) hi = hist[b].high;
               if(hist[b].low  < lo) lo = hist[b].low;
            }
            peakHigh[s][lvlMatch] = hi;
            peakLow[s][lvlMatch]  = lo;
         }
         break;
      }
   }

   // Tiers with no open position get their protection memory cleared
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
// Chain Check (bottom-up): the stack M15..topIdx must be aligned
// in the SAME direction for a tier to open.
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
// Daily Bias Filter (H4 tier): D1 bullish (price + chikou above
// tenkan, kijun and cloud) allows only H4 buys, D1 bearish only
// H4 sells. A D1 close INSIDE the cloud (or unreadable) returns
// 0 — no new H4 trades then.
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
   if(!above && !below) return 0;   // D1 close inside the cloud — no H4 trades

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
// Checked on the tier TF and the TF directly below it, as in
// the live build: H1 tier -> H1 + M30, H4 tier -> H4 + H1.
//==============================================================

bool CloudBiasFarOK(int s, int tfIdx, int dir)
{
   double aFar[1], bFar[1];
   if(CopyBuffer(ich[s][tfIdx], 2, 1 - Kijun, 1, aFar) <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 3, 1 - Kijun, 1, bFar) <= 0) return false;

   if(dir == 1) return aFar[0] > bFar[0];
   return aFar[0] < bFar[0];
}

bool LevelCloudBiasOK(int s, int lvl, int dir)
{
   int t = lvlTf[lvl];
   return CloudBiasFarOK(s, t, dir) && CloudBiasFarOK(s, t - 1, dir);
}

//==============================================================
// H4 gate for the H1 tier (InpH1H4Gate). The H4 tier needs no
// gate — H4 is part of its own chain.
//==============================================================

bool H1TierH4OK(int s, int dir)
{
   if(InpH1H4Gate == H1H4_OFF) return true;
   int h4 = CheckAlign(s, IDX_H4);
   if(InpH1H4Gate == H1H4_WITH) return h4 == dir;
   return h4 != -dir;                // NOT_AGAINST: flat or with
}

//==============================================================
// Exit Check: price TOUCHES the tier TF's cloud edge — no wait
// for a candle to close inside it. A long exits when the bid
// touches the cloud's upper edge; a short when the ask touches
// the lower edge. Evaluated once per closed M1 bar.
//==============================================================

bool InCloudTouch(int s, int tfIdx, int dir)
{
   double senA[1], senB[1];
   if(CopyBuffer(ich[s][tfIdx], 2, 1, 1, senA) <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 3, 1, 1, senB) <= 0) return false;

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
// Risk Management — per-tier risk as a fixed % of the ACTUAL
// equity at entry, in the live tiers' three regimes that DE-RISK
// as the account grows (H1 10/5/1%, H4 20/10/2%), measured
// against a reference distance of ATR(tier TF) x InpRiskATRMult.
// Falls back to InpFixedLots when the sizing data is unavailable.
//==============================================================

double LevelRiskPct(int lvl)
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   bool t3 = (eq >= InpRiskTier3At);
   bool t2 = (eq >= InpRiskTier2At);
   if(lvl == LVL_H1) return t3 ? InpRiskPctH1_T3 : t2 ? InpRiskPctH1_T2 : InpRiskPctH1;
   return t3 ? InpRiskPctH4_T3 : t2 ? InpRiskPctH4_T2 : InpRiskPctH4;
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

bool OpenLevel(int s, int lvl, int dir, double lots)
{
   string sym = syms[s];
   string comment = LevelComment(lvl, dir);
   double price = (dir == 1) ? SymbolInfoDouble(sym, SYMBOL_ASK)
                             : SymbolInfoDouble(sym, SYMBOL_BID);

   // R5: pick a filling mode this symbol actually supports.
   trade.SetTypeFillingBySymbol(sym);

   // Stop loss (the live build's R3 disaster stop, made tight), sized on
   // ATR(H4) for BOTH tiers and anchored at the entry price. If ATR or the broker distance check makes it
   // invalid right now, the order goes out without it and
   // ManageLevelProtection re-attaches it next minute.
   double sl = 0.0;
   if(InpStopLossEnabled)
   {
      double a[1];
      if(CopyBuffer(atr[s][LVL_H4], 0, 1, 1, a) > 0 && a[0] > 0)
      {
         double point   = SymbolInfoDouble(sym, SYMBOL_POINT);
         double minDist = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * point;
         int    digits  = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
         double dist    = MathMax(a[0] * InpStopATRMult, minDist + point);
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
      state[s][lvl]      = dir;
      entryPrice[s][lvl] = price;
      peakHigh[s][lvl]   = price;
      peakLow[s][lvl]    = price;
      beMoved[s][lvl]    = false;
      string action = (dir == 1) ? "Buy" : "Sell";
      string msg = PCTime() + " | " + action + " " + sym + " " + LvlName(lvl) +
                   " @ " + DoubleToString(lots, 2) + " (M15 base)";
      Print(msg); SendNotification(msg);
   }
   return ok;
}

// Close all positions of the tier; returns true only when none remain
// open, so a failed close (requote, halt) is retried instead of freeing
// the tier for a fresh entry.
bool CloseLevelPositions(int s, int lvl)
{
   string sym = syms[s];
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) == sym &&
         (int)PositionGetInteger(POSITION_MAGIC) == MAGIC &&
         IsLevelComment(lvl, PositionGetString(POSITION_COMMENT)))
      {
         if(!trade.PositionClose(ticket))
            Print(PCTime() + " | " + sym + " " + LvlName(lvl) + " close failed, retcode " +
                  IntegerToString(trade.ResultRetcode()));
      }
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) == sym &&
         (int)PositionGetInteger(POSITION_MAGIC) == MAGIC &&
         IsLevelComment(lvl, PositionGetString(POSITION_COMMENT))) return false;
   }
   return true;
}

//==============================================================
// Profit Protection (the live build's H1/H4 rules, per tier):
//   * Break-even — once the trade is in profit by >=
//     InpBEProfitATR x ATR, the stop moves to entry plus
//     InpBECoverPoints. One-shot per trade (beMoved).
//   * Chandelier trail — trails the stop InpTrailATR x ATR behind
//     the peak once profitable by InpTrailActivateATR x ATR. The
//     reference is the highest high / lowest low of the tier TF,
//     including the bar still forming; it only ever tightens and
//     never sits inside the broker minimum stop.
// BE and trail use the tier's own TF ATR. The hard stop is the
// tight ATR(H4) stop loss on both tiers; if it ever goes missing,
// it is re-attached here.
//==============================================================

bool LevelTicket(int s, int lvl, ulong &ticket)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != syms[s]) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MAGIC) continue;
      if(IsLevelComment(lvl, PositionGetString(POSITION_COMMENT))) return true;
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

   // The reference point is the extreme of the tier-TF bar that is still
   // forming, so a peak is locked in before it retraces
   MqlRates tfx[];
   if(CopyRates(syms[s], tfs[lvlTf[lvl]], 0, 1, tfx) <= 0) return;
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

   // R3: self-heal a missing stop loss. Sized on ATR(H4) for both tiers and
   // anchored at the ENTRY price so it never drifts; only attaches while no
   // other stop exists — BE/chandelier take over from there and only ever
   // tighten.
   double aH4[1];
   if(InpStopLossEnabled && slCur == 0.0 &&
      CopyBuffer(atr[s][LVL_H4], 0, 1, 1, aH4) > 0 && aH4[0] > 0)
   {
      double dSl = NormalizeDouble(isLong ? entryPrice[s][lvl] - InpStopATRMult * aH4[0]
                                          : entryPrice[s][lvl] + InpStopATRMult * aH4[0],
                                   digits);
      bool okD = isLong ? (dSl > 0 && dSl < bid - minDist)
                        : (dSl > ask + minDist);
      if(okD)
      {
         if(trade.PositionModify(ticket, dSl, 0))
            slCur = dSl;
         else
            Print(PCTime() + " | " + syms[s] + " " + LvlName(lvl) + " stop loss attach failed, retcode " +
                  IntegerToString(trade.ResultRetcode()));
      }
   }

   // Break-even
   if(!beMoved[s][lvl])
   {
      bool armed = isLong ? (bid >= entryPrice[s][lvl] + InpBEProfitATR * atrVal)
                          : (ask <= entryPrice[s][lvl] - InpBEProfitATR * atrVal);
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
               Print(PCTime() + " | " + syms[s] + " " + LvlName(lvl) + " BE SL modify failed, retcode " +
                     IntegerToString(trade.ResultRetcode()));
            else
               beMoved[s][lvl] = true;
         }
      }
   }

   // Chandelier trail behind the peak. Only ever tightens, keeps out of the
   // broker minimum stop distance, and skips microscopic improvements
   // (0.3x ATR). Re-read the current stop first — BE may have moved it.
   if(!LevelTicket(s, lvl, ticket)) return;
   slCur = PositionGetDouble(POSITION_SL);

   bool armed = isLong ? (bid >= entryPrice[s][lvl] + InpTrailActivateATR * atrVal)
                       : (ask <= entryPrice[s][lvl] - InpTrailActivateATR * atrVal);
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
            Print(PCTime() + " | " + syms[s] + " " + LvlName(lvl) + " trail SL modify failed, retcode " +
                  IntegerToString(trade.ResultRetcode()));
      }
   }
}

//==============================================================
// Rejection Candle Exit: closes a trade when a VERY STRONG
// rejection forms against it on the tier TF (last closed bar).
// All four conditions must hold — a swing sweep plus a dominant
// wick plus a strong close-back on a candle whose body opposes
// the trade. Returns 1 (bullish), -1 (bearish), 0 (none).
//==============================================================

int RejectionCandle(int s, int tfIdx)
{
   int need = 2 + InpRejSwingBars;
   MqlRates r[];
   if(CopyRates(syms[s], tfs[tfIdx], 0, need, r) < need) return 0;
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

// Close a tier's positions with a notification; returns true only when
// nothing remains open, so a failed close is retried next bar.
bool ExitLevel(int s, int l, string reason)
{
   string side = (state[s][l] == 1) ? "Long" : "Short";
   string msg  = PCTime() + " | Close " + syms[s] + " " + side + " " +
                 LvlName(l) + " (" + reason + ")";
   Print(msg); SendNotification(msg);

   if(CloseLevelPositions(s, l))
   {
      state[s][l] = 0;
      msg = PCTime() + " | " + syms[s] + " " + LvlName(l) + " tier closed";
      Print(msg); SendNotification(msg);
      return true;
   }
   Print(PCTime() + " | " + syms[s] + " " + LvlName(l) + " exit signal but positions still open — will retry");
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

      // Exits and profit protection per tier
      for(int l = 0; l < LEVELS; l++)
      {
         if(state[s][l] != 0 && InCloudTouch(s, lvlTf[l], state[s][l]))
            ExitLevel(s, l, "kumo touch");

         if(InpRejectionExit && state[s][l] != 0)
         {
            int rj = RejectionCandle(s, lvlTf[l]);
            if(rj != 0 && rj == -state[s][l])
               ExitLevel(s, l, "rejection");
         }

         if(state[s][l] != 0) ManageLevelProtection(s, l);
      }

      // Entries: every flat tier that is aligned opens on its own — no
      // consolidation, so H1 and H4 can both open on the same bar and an H4
      // entry leaves a running H1 trade alone. R2: never add exposure while
      // an unmanageable magic position sits on this symbol.
      if(symBlockedUnknown[s] || !SpreadOK(syms[s])) continue;

      for(int l = LEVELS - 1; l >= 0; l--)
      {
         if(state[s][l] != 0) continue;
         if(l == LVL_H4 && !InpH4Tier) continue;
         if(l == LVL_H1 && !InpH1Tier) continue;

         int st = ChainAligned(s, lvlTf[l]);
         if(st == 0) continue;
         if(InpCloudBiasEnabled && !LevelCloudBiasOK(s, l, st)) continue;
         if(l == LVL_H1 && !H1TierH4OK(s, st)) continue;
         if(l == LVL_H4 && InpD1Filter && DailyAlign(s) != st) continue;

         double lots = RiskLots(s, l);
         CapLotsToMargin(syms[s], (st == 1), lots);

         if(!OpenLevel(s, l, st, lots))
            Print(PCTime() + " | " + syms[s] + " " + LvlName(l) +
                  " entry signal but order failed, retcode " + IntegerToString(trade.ResultRetcode()));
      }
   }
}
//This work is my worship unto GOD
