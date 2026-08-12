//+------------------------------------------------------------------+
//| Ichimoku H4-M1 Alignment EA (BE30) — NEWS FILTER experiment      |
//| Entry: H4→M1 price+chikou all above/below tenkan,kijun,cloud    |
//| Exit:  ATR chandelier trailing stop once profitable (locks in    |
//|        the peak), M15 close crosses M15 kijun as final fallback, |
//|        or ATR-based protective stop loss                         |
//| Experiment: fork of the H4-M1 desktop build that sits out        |
//|        high-impact ("red folder") news. Open positions are       |
//|        closed InpNewsBlockBeforeMin minutes before the event and |
//|        no new entry is taken until InpNewsBlockAfterMin minutes  |
//|        after it. Events come from the terminal's built-in MQL5   |
//|        Economic Calendar — no WebRequest, no DLL, no scraping.   |
//| Also:  if price reaches a profitable position within             |
//|        InpBE30Minutes of entry, the stop loss moves up to        |
//|        break even + a few points to cover the spread (BE30)      |
//| Desktop: Alert popups and the weekly equity-withdrawal alert are |
//|        enabled; all logic still runs only on closed M1 bars      |
//| Risk:   ladder optionally capped by InpMaxRiskPct (0 = off) and  |
//|        by free margin; exits are verified so failed closes retry |
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

input group  "Risk Protection"
input bool   InpUseStopLoss       = true;   // Attach ATR-based stop loss to every entry
input int    InpATRPeriod         = 14;     // ATR period (M15)
input double InpATRMultiplier     = 3.0;    // SL distance = ATR * multiplier
input int    InpMaxSpreadPoints   = 60;     // Max spread in points to allow entry (0 = no limit)
input double InpHighEquityRiskPct = 1.0;    // % of equity risked per trade once equity > $8000
input int    InpReentryCooldownSec = 0;     // Min seconds after an exit before re-entering same symbol (0 = none)
input double InpMaxRiskPct         = 0.0;   // Cap total initial-stop risk per ladder as % of equity (0 = no cap)

//--- Trail mode: off, always on, or choppy-only (ADX regime filter)
enum ENUM_TRAIL_MODE { TRAIL_OFF = 0, TRAIL_ALWAYS = 1, TRAIL_CHOPPY = 2 };

input group  "Exit Management"
input ENUM_TRAIL_MODE InpTrailMode        = TRAIL_CHOPPY;  // 0=off, 1=always, 2=choppy-only (ADX)
input double          InpTrailATR         = 2.0;   // Trail distance = ATR(M15) * multiplier
input double          InpTrailActivateATR = 1.0;   // Arm the trail once profit >= ATR(M15) * multiplier
input int             InpADXPeriod        = 14;    // ADX period for choppy-market detection (M15)
input double          InpChopADXLevel     = 22.0;  // ADX below this = choppy -> trail on in auto mode

input group  "Break-Even (BE30) Management"
input bool   InpBE30Enabled        = true;   // Move SL to break even when profitable in time
input int    InpBE30Minutes        = 30;     // Profit window after entry (minutes)
input double InpBE30ActivateATR    = 0.5;    // Min profit to arm BE (x ATR M15)
input int    InpBE30CoverPoints    = 15;     // Points beyond break even (covers spread)

input group  "News Filter (MT5 Economic Calendar)"
input bool   InpNewsFilterEnabled  = true;   // Flatten and stand aside around high-impact news
input int    InpNewsBlockBeforeMin = 60;     // Close positions / block entries this many minutes BEFORE the event
input int    InpNewsBlockAfterMin  = 5;      // Resume trading this many minutes AFTER the event
input bool   InpNewsIncludeMedium  = false;  // Also block on medium impact (orange); false = high (red) only
input string InpNewsCurrencies     = "";     // Extra currencies to watch, comma-separated (e.g. "USD,EUR")

input group             "Equity Alert Settings"
input double            InpMinProfitTrigger  = 5.0;        // Min Profit over Baseline to trigger alert
input double            InpWithdrawProfitPct = 50.0;       // Percentage of the PROFIT to withdraw
input ENUM_DAY_OF_WEEK  InpCheckDay          = FRIDAY;     // Day of the week to check
input bool              InpResetBaseline     = false;      // Set to true to reset baseline to current equity
input bool              InpSendPush          = true;       // Send push notification

    //--- Constants and Global Variables ---
#define MAX_SYMS  60
#define TF_COUNT  6
#define IDX_M15   3   // index of M15 in tfs[] — used for exit check

#define GV_BASE_EQUITY    "EA_EquityAlert_Base_"    + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))
#define GV_LAST_ALERT_DAY "EA_EquityAlert_Day_"     + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))

ENUM_TIMEFRAMES tfs[TF_COUNT] = {
   PERIOD_H4, PERIOD_H1, PERIOD_M30, PERIOD_M15, PERIOD_M5, PERIOD_M1
};

int      ich[MAX_SYMS][TF_COUNT];
int      atr[MAX_SYMS];
int      adx[MAX_SYMS];   // ADX(M15) handle for choppy-market regime detection
string   syms[MAX_SYMS];
int      symsCount = 0;
datetime lastM1bar[MAX_SYMS];
datetime lastEquityBar = 0;         // H4 bar gating for the equity alert
datetime noReentryUntil[MAX_SYMS];
int      lastMinuteKey = -1;
int      state[MAX_SYMS];   // 0=no position, 1=long, -1=short

double   entryPrice[MAX_SYMS];  // reference entry price per symbol (trail arming)
double   trailHigh[MAX_SYMS];   // highest high since entry (long chandelier reference)
double   trailLow[MAX_SYMS];    // lowest low since entry (short chandelier reference)

datetime entryTime[MAX_SYMS];   // entry time per symbol (BE30 profit window)
bool     beMoved[MAX_SYMS];     // BE30 stop already moved to break even (one-shot)

//--- News filter state (see the News Filter section below)
#define NEWS_MAX_EVENTS  256
#define NEWS_REFRESH_SEC 900          // rebuild the event cache every 15 minutes
#define NEWS_LOOK_BACK   (6*3600)     // cache window behind now
#define NEWS_LOOK_AHEAD  (36*3600)    // cache window ahead of now

struct NewsEvent
{
   datetime time;       // event time, trade-server timezone
   string   currency;   // currency the event moves (USD, EUR, ...)
   string   name;       // event name as shown in the terminal calendar
};

NewsEvent newsCache[NEWS_MAX_EVENTS];
int       newsCount       = 0;
datetime  newsRefreshedAt = 0;
bool      newsWarned      = false;          // one-shot "calendar unavailable" warning
string    newsCcy[32];                      // every currency watched across all symbols
int       newsCcyCount    = 0;
string    symCcy[MAX_SYMS];                 // ",USD,EUR," membership list per symbol
datetime  newsBlockUntil[MAX_SYMS];         // entries blocked until this server time
datetime  newsAnnounced[MAX_SYMS];          // event time of the blackout already alerted on

int MAGIC = 20260832;   // fresh number — news-filter experiment (20260830 is the H4 desktop build)

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
      state[s] = 0;
      lastM1bar[s] = 0;
      noReentryUntil[s] = 0;
      entryTime[s] = 0;
      beMoved[s] = false;
      newsBlockUntil[s] = 0;
      newsAnnounced[s]  = 0;
      for(int t = 0; t < TF_COUNT; t++)
      {
         ich[s][t] = iIchimoku(syms[s], tfs[t], Tenkan, Kijun, SenkouB);
         if(ich[s][t] == INVALID_HANDLE) return(INIT_FAILED);
      }

      atr[s] = INVALID_HANDLE;
      if(InpUseStopLoss)
      {
         atr[s] = iATR(syms[s], PERIOD_M15, InpATRPeriod);
         if(atr[s] == INVALID_HANDLE) return(INIT_FAILED);
      }

      adx[s] = INVALID_HANDLE;
      if(InpTrailMode == TRAIL_CHOPPY)
      {
         adx[s] = iADX(syms[s], PERIOD_M15, InpADXPeriod);
         if(adx[s] == INVALID_HANDLE) return(INIT_FAILED);
      }
   }

   trade.SetDeviationInPoints(Slippage);
   trade.SetExpertMagicNumber(MAGIC);
   BuildNewsCurrencies();
   SyncStateFromPositions();
   InitEquityAlert();
   return(INIT_SUCCEEDED);
}

//==============================================================
// Equity Alert: weekly profit-withdrawal reminder
//==============================================================

void InitEquityAlert()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(!GlobalVariableCheck(GV_BASE_EQUITY) || InpResetBaseline)
   {
      GlobalVariableSet(GV_BASE_EQUITY, currentEquity);
   }
   if(!GlobalVariableCheck(GV_LAST_ALERT_DAY))
   {
      GlobalVariableSet(GV_LAST_ALERT_DAY, 0);
   }
}

void CheckEquityAlert()
{
   MqlDateTime dt;
   TimeCurrent(dt);

   if(dt.day_of_week != InpCheckDay) return;
   if((int)GlobalVariableGet(GV_LAST_ALERT_DAY) == dt.day) return;

   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double baseEquity    = GlobalVariableGet(GV_BASE_EQUITY);
   double profit        = currentEquity - baseEquity;

   if(profit >= InpMinProfitTrigger)
   {
      double withdrawAmount = profit * (InpWithdrawProfitPct / 100.0);
      string msg = StringFormat("Profit: %.2f. Suggest withdrawing: %.2f", profit, withdrawAmount);

      Alert(msg);
      if(InpSendPush) SendNotification(msg);

      GlobalVariableSet(GV_LAST_ALERT_DAY, (double)dt.day);
      GlobalVariablesFlush();
   }
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
   // Rebuild from scratch so positions closed by SL or manually free the
   // symbol for re-entry instead of leaving stale state behind.
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
             // EA (re)started mid-trade — rebuild the trail from the open price
             // and let it accumulate fresh extremes from here.
             if(entryPrice[s] == 0.0)
             {
                entryPrice[s] = PositionGetDouble(POSITION_PRICE_OPEN);
                trailHigh[s]  = entryPrice[s];
                trailLow[s]   = entryPrice[s];
             }
             // Restart mid-trade: restart the BE30 clock from the earliest
             // open position so the profit window keeps real entry semantics.
             if(entryTime[s] == 0)
                entryTime[s] = (datetime)PositionGetInteger(POSITION_TIME);
             break;
         }
      }
   }

   // Symbols with no open position get their trail memory cleared
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

   // A position that vanished since the last sync (SL hit, manual close) frees
   // the symbol; arm the optional re-entry cooldown so it can't flip instantly.
   for(int s = 0; s < symsCount; s++)
   {
      if(prevState[s] != 0 && state[s] == 0)
         noReentryUntil[s] = TimeCurrent() + InpReentryCooldownSec;
   }
}

//==============================================================
// Alignment Check: price and chikou both above/below tenkan,
// kijun, and cloud. Returns 1 (bullish), -1 (bearish), 0 (none)
//==============================================================

int CheckAlign(int s, int tfIdx)
{
   ENUM_TIMEFRAMES tf = tfs[tfIdx];

   int sh      = 1;              // last closed bar
   int chShift = sh + Kijun;     // chikou's chart position for bar sh (Kijun bars back)
   // MT5's iIchimoku Senkou buffers are pre-shifted: the value at shift p
   // is the cloud as drawn at chart position p — no extra offset needed.

   MqlRates rt[];
   if(CopyRates(syms[s], tf, 0, chShift + 1, rt) <= 0) return 0;
   ArraySetAsSeries(rt, true);

   if(ArraySize(rt) <= chShift) return 0;

   // price bar sh: tenkan, kijun, cloud (cloud read at sh = drawn at sh)
   double tenkan[1], kijun[1], senA[1], senB[1];
   if(CopyBuffer(ich[s][tfIdx], 0, sh,    1, tenkan)    <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 1, sh,    1, kijun)     <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 2, sh,    1, senA)      <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 3, sh,    1, senB)      <= 0) return 0;

   double closeP = rt[sh].close;
   double cHi    = MathMax(senA[0], senB[0]);
   double cLo    = MathMin(senA[0], senB[0]);

   // Short-circuit: most bars aren't aligned, so skip the chikou-side buffers
   // unless the close is already clearly on one side of tenkan/kijun/cloud.
   bool above = closeP > tenkan[0] && closeP > kijun[0] && closeP > cHi;
   bool below = closeP < tenkan[0] && closeP < kijun[0] && closeP < cLo;
   if(!above && !below) return 0;

   // tenkan, kijun, cloud at chikou's chart position (cloud read at
   // chShift = drawn at chikou's plotted bar)
   double tenkan_ch[1], kijun_ch[1], senA_ch[1], senB_ch[1];
   if(CopyBuffer(ich[s][tfIdx], 0, chShift,    1, tenkan_ch) <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 1, chShift,    1, kijun_ch)  <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 2, chShift,    1, senA_ch)   <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 3, chShift,    1, senB_ch)   <= 0) return 0;

   // The chikou span for bar sh IS its close, plotted Kijun bars back.
   // Compare it against the candle and Ichimoku levels at that chart position.
   double chik   = closeP;
   double cHiC   = MathMax(senA_ch[0], senB_ch[0]);
   double cLoC   = MathMin(senA_ch[0], senB_ch[0]);

   // bullish: price above tenkan, kijun, and cloud; chikou clear above price,
   // tenkan, kijun, and cloud at its plotted position
   if(above && chik > rt[chShift].high &&
      chik > tenkan_ch[0] && chik > kijun_ch[0] && chik > cHiC) return  1;

   // bearish: price below tenkan, kijun, and cloud; chikou clear below price,
   // tenkan, kijun, and cloud at its plotted position
   if(below && chik < rt[chShift].low &&
      chik < tenkan_ch[0] && chik < kijun_ch[0] && chik < cLoC) return -1;

   return 0;
}

//==============================================================
// Entry Check: all timeframes (H4→M1) aligned same direction
//==============================================================

int CheckAllAlign(int s)
{
   int dir = CheckAlign(s, 0);
   if(dir == 0) return 0;

   for(int t = 1; t < TF_COUNT; t++)
   {
      if(CheckAlign(s, t) != dir) return 0;
   }
   return dir;
}

//==============================================================
// Exit Check: M15 price closed on wrong side of M15 kijun
//==============================================================

bool CheckM15Exit(int s, int dir)
{
   double kij[1];
   if(CopyBuffer(ich[s][IDX_M15], 1, 1, 1, kij) <= 0) return false;

   MqlRates rt[];
   if(CopyRates(syms[s], PERIOD_M15, 1, 1, rt) <= 0) return false;
   double closeP = rt[0].close;

   if(dir ==  1 && closeP < kij[0]) return true;
   if(dir == -1 && closeP > kij[0]) return true;
   return false;
}

//==============================================================
// Choppy-market detection: ADX(M15) below InpChopADXLevel means no
// trend, so the trail is allowed. An unready/unknown ADX value is
// treated as choppy (trail on) to match the always-on default.
//==============================================================

bool IsChoppy(int s)
{
   double d[1];
   if(CopyBuffer(adx[s], 0, 1, 1, d) <= 0 || d[0] <= 0) return true;
   return d[0] < InpChopADXLevel;
}

//==============================================================
// Exit Trail: ATR chandelier stop once the trade is in profit.
// The reference point is the extreme (high/low) of the M15 bar
// that is still forming, so a peak is locked in before it
// retraces. Re-evaluated on every new M1 bar; only ever
// tightens and never sits inside the broker minimum stop.
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

   MqlRates m15[];
   if(CopyRates(syms[s], PERIOD_M15, 0, 1, m15) <= 0) return;
   ArraySetAsSeries(m15, true);

   bool isLong = (state[s] == 1);
   if(isLong)
   {
      if(m15[0].high > trailHigh[s]) trailHigh[s] = m15[0].high;
   }
   else
   {
      if(m15[0].low < trailLow[s]) trailLow[s] = m15[0].low;
   }

   double point   = SymbolInfoDouble(syms[s], SYMBOL_POINT);
   double minDist = SymbolInfoInteger(syms[s], SYMBOL_TRADE_STOPS_LEVEL) * point;
   int    digits  = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);

   // Not profitable enough yet to arm the trail
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

      // Only ever tighten, keep out of the broker's minimum stop distance,
      // and skip microscopic improvements (0.3x ATR) to cut request volume.
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
// Break-Even Management (BE30): if the trade reaches a profitable
// position within InpBE30Minutes of entry, the stop loss moves up
// to break even plus a few points to cover the spread. One-shot
// per trade (beMoved); the chandelier trail may tighten further
// afterwards but never lowers the stop back down.
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

   // The profit window: once InpBE30Minutes have passed without the trade
   // turning profitable, the stop stays where it is for this trade.
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

   // Not yet profitable enough to arm the break-even move
   if(isLong && bid < avg + InpBE30ActivateATR * atrVal) return;
   if(!isLong && ask > avg - InpBE30ActivateATR * atrVal) return;

   double point   = SymbolInfoDouble(syms[s], SYMBOL_POINT);
   double minDist = SymbolInfoInteger(syms[s], SYMBOL_TRADE_STOPS_LEVEL) * point;
   int    digits  = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);

   // Break even plus a few points to cover the spread
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

      // Only ever tighten, and keep out of the broker's minimum stop distance
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
// News Filter — MT5 Economic Calendar (high-impact "red folder")
//==============================================================
// Events come from the terminal's built-in economic calendar (the same
// feed as the Calendar tab, supplied by MetaQuotes rather than the
// broker), so no WebRequest permission, no DLL and no external site are
// involved. CALENDAR_IMPORTANCE_HIGH is what Forex Factory paints as a
// red folder.
//
// Calendar times are trade-server time, which is what TimeTradeServer()
// returns, so the two compare directly — no broker GMT offset handling.
//
// Two limitations worth knowing: the calendar is empty in the Strategy
// Tester (the tester has no calendar access), so a backtest of this file
// trades as if no news existed; and the calendar needs a connected
// terminal. When the calendar can't be read the filter fails OPEN — it
// warns once and lets the EA keep trading, rather than silently freezing
// the account forever.

// Register a currency in the global watch list, once.
void NewsAddCcy(string ccy)
{
   StringTrimLeft(ccy);
   StringTrimRight(ccy);
   StringToUpper(ccy);
   if(StringLen(ccy) != 3) return;
   for(int i = 0; i < newsCcyCount; i++)
      if(newsCcy[i] == ccy) return;
   if(newsCcyCount < ArraySize(newsCcy)) newsCcy[newsCcyCount++] = ccy;
}

// Attach a currency to one symbol's watch list (and to the global one).
void SymAddCcy(int s, string ccy)
{
   StringTrimLeft(ccy);
   StringTrimRight(ccy);
   StringToUpper(ccy);
   if(StringLen(ccy) != 3) return;
   if(StringFind(symCcy[s], "," + ccy + ",") < 0) symCcy[s] += ccy + ",";
   NewsAddCcy(ccy);
}

// Which currencies each symbol reacts to: its own base and profit
// currency plus anything in InpNewsCurrencies. Metals and crypto carry a
// base the calendar has no events for (XAU, BTC) — harmless, they simply
// never match; GOLDm# still picks up USD through its profit currency.
void BuildNewsCurrencies()
{
   newsCcyCount = 0;

   string extra[];
   int extraCount = StringSplit(InpNewsCurrencies, ',', extra);

   for(int s = 0; s < symsCount; s++)
   {
      symCcy[s] = ",";
      SymAddCcy(s, SymbolInfoString(syms[s], SYMBOL_CURRENCY_BASE));
      SymAddCcy(s, SymbolInfoString(syms[s], SYMBOL_CURRENCY_PROFIT));
      for(int i = 0; i < extraCount; i++) SymAddCcy(s, extra[i]);
   }
}

// Rebuild the cache of qualifying events around now. Cheap enough to call
// on every M1 bar — it returns immediately until the refresh interval is up.
void RefreshNewsCache()
{
   datetime now = TimeTradeServer();
   if(newsRefreshedAt > 0 && now - newsRefreshedAt < NEWS_REFRESH_SEC) return;
   newsRefreshedAt = now;
   newsCount = 0;

   bool calendarOK = false;
   int  lastErr    = 0;

   for(int c = 0; c < newsCcyCount; c++)
   {
      MqlCalendarValue vals[];
      ResetLastError();
      int n = CalendarValueHistory(vals, now - NEWS_LOOK_BACK, now + NEWS_LOOK_AHEAD, NULL, newsCcy[c]);
      if(n <= 0)
      {
         int err = GetLastError();
         if(err == 0) calendarOK = true;   // no events for this currency is not a failure
         else         lastErr = err;
         continue;
      }
      calendarOK = true;

      for(int i = 0; i < n; i++)
      {
         if(newsCount >= NEWS_MAX_EVENTS) break;

         MqlCalendarEvent ev;
         if(!CalendarEventById(vals[i].event_id, ev)) continue;

         bool wanted = (ev.importance == CALENDAR_IMPORTANCE_HIGH) ||
                       (InpNewsIncludeMedium && ev.importance == CALENDAR_IMPORTANCE_MODERATE);
         if(!wanted) continue;

         newsCache[newsCount].time     = vals[i].time;
         newsCache[newsCount].currency = newsCcy[c];
         newsCache[newsCount].name     = ev.name;
         newsCount++;
      }
   }

   if(!calendarOK && !newsWarned)
   {
      newsWarned = true;
      string msg = PCTime() + " | News filter: MT5 calendar unavailable (err " +
                   IntegerToString(lastErr) + ") — trading WITHOUT the news blackout";
      Print(msg); Alert(msg);
      if(InpSendPush) SendNotification(msg);
   }
   if(calendarOK) newsWarned = false;
}

// Is this symbol inside a news blackout right now? Reports the end of the
// window — the latest one when several events overlap — and the event that
// opened it.
bool NewsBlackout(int s, datetime &until, string &evName, datetime &evTime)
{
   until  = 0;
   evName = "";
   evTime = 0;
   if(!InpNewsFilterEnabled) return false;

   RefreshNewsCache();

   datetime now = TimeTradeServer();
   for(int i = 0; i < newsCount; i++)
   {
      if(StringFind(symCcy[s], "," + newsCache[i].currency + ",") < 0) continue;

      datetime from = newsCache[i].time - InpNewsBlockBeforeMin * 60;
      datetime to   = newsCache[i].time + InpNewsBlockAfterMin  * 60;
      if(now < from || now > to) continue;

      if(to > until)
      {
         until  = to;
         evName = newsCache[i].name;
         evTime = newsCache[i].time;
      }
   }
   return (until > 0);
}

//==============================================================
// Risk Management
//==============================================================

// Lot size that risks InpHighEquityRiskPct% of equity, split evenly across
// 'count' concurrent orders, if the ATR stop loss is hit on all of them.
// Falls back to a conservative fixed lot when the stop distance or the
// symbol's tick value/size aren't available (e.g. InpUseStopLoss = false).
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

// Scale the ladder down so the initial stop on all orders risks at most
// InpMaxRiskPct% of equity. count never drops below 1.
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

// Scale the ladder down to the free margin so the orders fill fully
// instead of silently breaking mid-way. count never drops below 1.
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

// ATR(M15) * multiplier, widened to the broker's minimum stop distance if
// needed. Returns false when the ATR value is unavailable so the caller
// skips the entry instead of trading unprotected.
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

int OpenPositions(int s, bool isBuy, double dist, int count, double lots, double &firstFill)
{
   string sym = syms[s];

   int filled = 0;
   firstFill = 0.0;
   for(int i = 0; i < count; i++)
   {
      double price = isBuy ? SymbolInfoDouble(sym, SYMBOL_ASK)
                           : SymbolInfoDouble(sym, SYMBOL_BID);
      double sl = InpUseStopLoss ? BuildStopLoss(s, isBuy, price, dist) : 0.0;

      bool ok = isBuy ? trade.Buy(lots,  sym, price, sl, 0, "Buy H4-M1")
                      : trade.Sell(lots, sym, price, sl, 0, "Sell H4-M1");
      if(!ok) break;   // out of margin or rejected — don't hammer the server
      if(firstFill == 0.0) firstFill = price;
      filled++;
   }
   return filled;
}

// Close all positions for the symbol; returns true only when none remain
// open, so a failed close (requote, halt) is retried instead of freeing
// the symbol for a fresh entry.
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
   // VPS perf: all logic runs only on closed M1 bars, which change at most
   // once per minute. Skip every intermediate tick entirely.
   int nowKey = (int)(TimeCurrent() / 60);
   if(nowKey == lastMinuteKey) return;
   lastMinuteKey = nowKey;

   // Equity alert: fire only on a new H4 bar (CheckEquityAlert self-guards on day-of-week)
   MqlRates h4eq[];
   if(symsCount > 0 && CopyRates(syms[0], PERIOD_H4, 0, 1, h4eq) > 0 && h4eq[0].time != lastEquityBar)
   {
      lastEquityBar = h4eq[0].time;
      CheckEquityAlert();
   }

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

      // News blackout: flatten ahead of a high-impact event and stay out
      // until the post-event window closes. Runs before every other check
      // so the news exit wins over the trail, BE and entry logic.
      datetime newsUntil = 0, newsTime = 0;
      string   newsName  = "";
      if(NewsBlackout(s, newsUntil, newsName, newsTime))
      {
         newsBlockUntil[s] = newsUntil;

         if(newsAnnounced[s] != newsTime)
         {
            newsAnnounced[s] = newsTime;
            string msg = PCTime() + " | News blackout " + syms[s] + ": " + newsName +
                         " at " + TimeToString(newsTime, TIME_MINUTES) +
                         " — flat until " + TimeToString(newsUntil, TIME_MINUTES) + " (server)";
            Print(msg); Alert(msg);
            if(InpSendPush) SendNotification(msg);
         }

         if(state[s] != 0)
         {
            string side = (state[s] == 1) ? "Long" : "Short";
            string msg  = PCTime() + " | Close " + syms[s] + " " + side + " (news: " + newsName + ")";
            Print(msg); Alert(msg);
            if(InpSendPush) SendNotification(msg);

            if(ClosePositions(syms[s]))
               state[s] = 0;
            else
               Print(PCTime() + " | " + syms[s] + " news close failed — will retry next bar");
         }

         // Flat and blocked: nothing left to manage this bar. A position that
         // refused to close falls through so the trail and BE keep guarding it.
         if(state[s] == 0) continue;
      }

      // Exit check: close all when M15 closes against direction across M15 kijun
      if(state[s] != 0 && CheckM15Exit(s, state[s]))
      {
         string side = (state[s] == 1) ? "Long" : "Short";
         string msg  = PCTime() + " | Close " + syms[s] + " " + side + " (M15 kijun crossed)";
         Print(msg); Alert(msg); SendNotification(msg);

         if(ClosePositions(syms[s]))
         {
            state[s] = 0;
            noReentryUntil[s] = TimeCurrent() + InpReentryCooldownSec;
         }
         else
            Print(PCTime() + " | " + syms[s] + " exit signal but positions still open — will retry");
      }

      // Chandelier trail: tighten stops behind the peak on each new M1 bar
      if(state[s] != 0) ManageTrail(s);

      // BE30: move the stop to break even + cover if profitable in time
      if(state[s] != 0) ManageBE(s);

      // Entry check: all timeframes H4→M1 must align, spread must be sane,
      // and the symbol must be clear of its news blackout
      if(state[s] == 0 && TimeCurrent() >= noReentryUntil[s] &&
         TimeTradeServer() >= newsBlockUntil[s] && SpreadOK(syms[s]))
      {
         int st = CheckAllAlign(s);
         if(st != 0)
         {
            bool   isBuy = (st == 1);
            double dist  = 0.0;
            if(InpUseStopLoss && !GetStopDistance(s, dist)) continue;   // ATR unavailable — skip entry

            int count; double lots;
            GetEquityRisk(syms[s], dist, count, lots);
            CapToRisk(syms[s], dist, count, lots);
            CapToMargin(syms[s], isBuy, count, lots);

            // Track state if any order filled — keeps exit logic and re-entry
            // guard correct even when only some of the orders go through.
            // Alert reports the actual fill count, not the requested count.
            double firstFill = 0.0;
            int filled = OpenPositions(s, isBuy, dist, count, lots, firstFill);
            if(filled > 0)
            {
               state[s] = st;
               entryPrice[s] = firstFill;   // chandelier trail reference
               trailHigh[s]  = firstFill;
               trailLow[s]   = firstFill;
               entryTime[s]  = TimeCurrent();   // start the BE30 profit window
               beMoved[s]    = false;
               string action = isBuy ? "Buy" : "Sell";
               string msg = PCTime() + " | " + action + " " + syms[s] +
                            " x" + IntegerToString(filled) +
                            " @ " + DoubleToString(lots, 2) + " (H4-M1)";
               Print(msg); Alert(msg); SendNotification(msg);
            }
            else
               Print(PCTime() + " | " + syms[s] + " entry signal but no order filled");
         }
      }
   }
}
//This work is my worship unto GOD
