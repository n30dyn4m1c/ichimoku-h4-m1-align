//+------------------------------------------------------------------+
//| Ichimoku Bottom-Up Stack EA - STANDARD-ACCOUNT ($100) build      |
//| EXPERIMENTAL - NOT the live VPS build. Forked from the live      |
//| ichimoku-h4-m1-vps-ea.mq5 (magic 20260858, the M1-strict         |
//| cloud-bias build running on an XM Ultra Low MICRO account), to   |
//| run the same strategy on a STANDARD (full-size) account funded   |
//| with about $100. The VPS and desktop files are untouched.        |
//|                                                                  |
//| WHY A SEPARATE BUILD - the arithmetic that forces it             |
//| On a MICRO gold symbol one lot is 10 oz, so the 0.01 minimum is  |
//| 0.1 oz and moves about $0.10 per $1 of gold. On a STANDARD gold  |
//| symbol one lot is 100 oz: the same 0.01 minimum is 1 oz and      |
//| moves about $1.00 per $1 of gold - TEN TIMES the exposure for    |
//| the identical number in the volume box, and the smallest trade   |
//| the broker will accept.                                          |
//| The parent hides what that does. Its sizing ends with            |
//| MathMax(lotMin, lots), so whenever the risk-correct size lands   |
//| under the broker minimum the order is silently ROUNDED UP and    |
//| the trade risks whatever 0.01 lot happens to risk - not what its |
//| tier asked for. Below roughly $10k of equity that is EVERY       |
//| trade, and the risk table becomes decoration.                    |
//|                                                                  |
//| WHAT CHANGED FROM THE PARENT                                     |
//|  1. MINIMUM-LOT HONESTY GATE. When the risk-correct size lands   |
//|     below 0.01, SizedLots() prices what the minimum lot would    |
//|     actually risk over the reference distance and SKIPS the      |
//|     entry when it exceeds InpMaxRiskPerTradePct of equity (12%). |
//|     Tiers therefore unlock one at a time as the account grows    |
//|     rather than all firing at account-ending size on day one.    |
//|     At $100 on gold that typically means M5 and M15 can trade,   |
//|     M30 comes in around $150, H1 around $190 and H4 around $470  |
//|     - but those move with ATR, so the EA prints the live table   |
//|     to the journal on the first M1 bar (item 6).                 |
//|  2. A BLOCKED TIER NO LONGER VETOES THE SYMBOL. This is the      |
//|     important one and it is a BUG FIX, not a tuning change.      |
//|     ChainAligned() is nested - the M30 tier requires M1+M5+M15+  |
//|     M30 to agree - so whenever a high tier is aligned, every     |
//|     tier below it is aligned too, by construction. The first     |
//|     draft of this file picked the highest aligned tier, sized it |
//|     once, and skipped the WHOLE SYMBOL when that size came back  |
//|     zero. On a $100 account the high tiers are unaffordable      |
//|     nearly always, so every time the market trended hard enough  |
//|     to align M15/M30/H1 the EA chose that tier, could not pay    |
//|     for it, and opened nothing - while an affordable M5 entry    |
//|     sat right there aligned. It could only trade the narrow      |
//|     case where M1+M5 agreed and M15 did not. An 8-month          |
//|     backtest produced THREE trades. Now a tier that cannot be    |
//|     sized loses its turn and the scan walks down to the next     |
//|     one. No risk rule is relaxed by this - whatever opens has    |
//|     passed the same ceiling.                                     |
//|  3. Risk ladder re-cut for a $100 start: tier 1 (M5 1%, M15      |
//|     1.5%, M30 2%, H1 2.5%, H4 3%), tier 2 half of that from      |
//|     $2000, tier 3 half again from $10000. Note that below        |
//|     roughly $300-$1200 of equity these percentages do not bind   |
//|     at all - the lot floor does - so tune                        |
//|     InpMaxRiskPerTradePct, not this table, while the account is  |
//|     small.                                                       |
//|  4. CIRCUIT BREAKERS. Daily loss limit (20% of the day's         |
//|     opening equity) stops NEW entries for the rest of the        |
//|     server day; peak-to-trough drawdown limit (45%) stops them   |
//|     until equity recovers. Both survive a VPS restart via        |
//|     terminal globals, so a restart mid-drawdown does not hand    |
//|     the account a fresh budget. Neither ever abandons an open    |
//|     position - exits, break-even and the trail keep running.     |
//|     They are sized against the 4-12% per-trade risk the lot      |
//|     floor forces here, not against the 1-3% the risk table       |
//|     nominally asks for.                                          |
//|  5. No silent fixed-lot fallback (InpFixedLots defaults to 0),   |
//|     margin cap SKIPS instead of clamping back up to the          |
//|     minimum, and sizing runs BEFORE the supersede-close so a     |
//|     gated higher tier can never kill a running lower-tier trade  |
//|     and then open nothing.                                       |
//|  6. STARTUP RISK PREVIEW. On the first M1 bar the EA prints the  |
//|     contract size, the minimum lot, and per tier the live ATR,   |
//|     the reference distance, what 0.01 lot would risk in money    |
//|     and in % of equity, whether that tier is tradable right now  |
//|     and roughly what equity it needs to unlock. Read it before   |
//|     leaving the EA alone - it is the fastest way to catch a      |
//|     micro symbol left in the Symbols input.                      |
//|  7. OPTIONAL HARD STOP AT ENTRY (InpUseHardStop, InpStopLossATR  |
//|     x ATR of the tier TF). DEFAULT OFF - see the warning below.  |
//|                                                                  |
//| THE STOPLESS DEFAULT - UNDERSTAND THIS BEFORE DEPLOYING          |
//| InpUseHardStop defaults to FALSE (user choice, 2026-08-21), so   |
//| this build behaves like the live parent: NO entry stop, the      |
//| trade runs to the kumo-touch exit, and the BE/chandelier layer   |
//| is the only protection once it is green. That keeps the parent's |
//| let-it-run edge - the edge behind the $100 -> $14000 micro       |
//| result - fully intact, and a 2 x ATR stop would sometimes have   |
//| fired where the parent let a trade breathe and recover.          |
//| The cost is real and worth stating plainly: with no stop         |
//| attached, InpMaxRiskPerTradePct bounds the SIZE OF THE POSITION, |
//| not the size of the loss. The reference distance is a sizing     |
//| basis that nothing enforces. A trade can lose more than 12% if   |
//| price runs past it, the kumo exit is only evaluated on closed M1 |
//| bars, and a gap or a news spike between those bars is unbounded  |
//| - on a standard symbol at 1 oz per 0.01 lot, a $25 move in gold  |
//| is $25, a quarter of a $100 account, with no smaller size to     |
//| fall back on. The 45% drawdown halt is the only floor under      |
//| that. Set InpUseHardStop = true to make the ceiling a genuine    |
//| per-trade loss cap.                                              |
//|                                                                  |
//| SYMBOL - CHECK THIS FIRST. Symbols defaults to "GOLD#", the XM   |
//| Ultra Low STANDARD gold symbol, not the micro "GOLDm#" the live  |
//| VPS build trades. Confirm the exact name in Market Watch; if a   |
//| micro symbol is left here every risk figure in this build is     |
//| overstated tenfold and the account will simply under-trade.      |
//|                                                                  |
//| ENTRY LOGIC IS THE LIVE BUILD'S, UNCHANGED. InpStrictCloudUpTo   |
//| defaults to STRICTCLOUD_M1 - the M1-strict cloud rule the live   |
//| build runs and the most profitable one reported. It is exposed   |
//| as an input so the full current+future check can be walked up    |
//| to M5, M15 or M30 without editing code, but nothing above M1 is  |
//| on by default. Spread ceiling and the H1/H4/D1 bias gates are    |
//| the parent's values too.                                         |
//|                                                                  |
//| The parent's strategy description follows, unchanged.            |
//| DIFFERENT MODEL: the top-down builds required every timeframe    |
//| from the anchor down to M1 to agree before a single trade could  |
//| open. This build is BOTTOM-UP - the stack is grown upward from   |
//| M1 and each tier trades its own chain - with DIRECTION granted   |
//| by a bias timeframe (H4 primary, H1 stand-in) instead of by      |
//| top-down agreement.                                              |
//| Entry: per-TF alignment (price + chikou above/below tenkan,      |
//|        kijun and cloud), checked BOTTOM-UP: a tier opens only    |
//|        when the full stack M1..tier TF is aligned in one         |
//|        direction:                                                |
//|          Tier M5 : M1 + M5 aligned              -> open trade    |
//|          Tier M15: M1 + M5 + M15 aligned        -> open trade    |
//|          Tier M30: M1 + M5 + M15 + M30 aligned  -> open trade    |
//|          Tier H1 : M1 ... H1 aligned            -> open trade    |
//|          Tier H4 : M1 ... H4 aligned            -> open trade    |
//|        M1 alone never trades - it is only the start of the       |
//|        stack. The cloud bias gate applies to the tier TF and the |
//|        TF directly below it; at the M1 default, M1 needs current |
//|        AND future cloud agreement and M5 upward need only the    |
//|        future cloud. H4 is the bias for the whole stack (H4      |
//|        bullish -> buys only, bearish -> sells only, flat -> no   |
//|        trades), and the H4 tier itself is also gated by the D1   |
//|        bias: D1 bullish -> only H4 buys, D1 bearish -> only H4   |
//|        sells, D1 in the cloud -> no H4 trades.                   |
//|        H1 BIAS: an unaligned H4 would otherwise freeze the whole |
//|        stack, including M5. The lower tiers get a second,        |
//|        smaller bias to fall back on: when H4 carries no          |
//|        direction, a tier at or below InpH1BiasMaxTier may open   |
//|        provided H1 itself is aligned (same price+chikou test)    |
//|        with the trade. H4 aligned WITH the trade is still the    |
//|        primary path; H4 aligned AGAINST it stays blocked unless  |
//|        InpH1BiasMode = H1BIAS_ALWAYS. The H4 tier never uses the |
//|        stand-in, and the D1 filter on it is untouched.           |
//| Exit:  price TOUCHES the level TF's cloud edge (no wait for a    |
//|        candle close inside the kumo). A long exits when the bid  |
//|        touches the cloud's upper edge; a short when the ask      |
//|        touches the lower edge. A very strong REJECTION candle    |
//|        against the trade also closes it when InpRejectionExit is |
//|        on. The profit protection layer takes over once the trade |
//|        turns green:                                              |
//|          Break-even : profit >= ATR threshold (tighter for the   |
//|                       H1/H4 levels) -> SL to entry + cover       |
//|          Chandelier : H1/H4 levels trail the stop behind the     |
//|                       peak once profitable                       |
//|                       (InpTrailActivateATR); M5/M15/M30 keep the |
//|                       spike-gated trail (InpSpikeLockATR), only  |
//|                       ever tightening                            |
//|        ATR comes from each level's own TF.                       |
//| Risk:  single position per level per symbol, with consolidation: |
//|        when several tiers align at once the LARGEST AFFORDABLE   |
//|        one opens, and any smaller tier already running on the    |
//|        symbol is closed first. See items 1-5 for how the size of |
//|        that position is decided.                                 |
//| VPS:   no Alert() popups and no equity alert - every entry/exit  |
//|        sends a SendNotification push and a journal Print, and    |
//|        all logic runs only on closed M1 bars (once per minute).  |
//| Magic: 20260862 - FRESH. A standard-account instance must never  |
//|        adopt or manage positions belonging to the live VPS build |
//|        (20260858), the desktop twin (20260860), the earlier      |
//|        standard-account fork (20260854) or anything archived.    |
//|        Do not run this file and a micro-account build on the     |
//|        same account.                                             |
//| STATUS: NOT compiled and NOT backtested in this repo. The only   |
//|        recorded run is the user's 8-month backtest of the FIRST  |
//|        draft, which produced 3 trades and led to items 2 and 7.  |
//|        Compile and re-test before this touches real money.       |
//| Author: Neo Malesa                                               |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

//--- Input Parameters ---
// STANDARD-ACCOUNT symbol. "GOLD#" is XM Ultra Low's full-size gold;
// the live micro build trades "GOLDm#". Confirm the exact name in Market
// Watch before running — a micro symbol left here makes every risk figure
// in this build overstated tenfold.
input string Symbols  = "GOLD#";
input int    Tenkan   = 9;
input int    Kijun    = 26;
input int    SenkouB  = 52;
input int    Slippage = 30;

input group  "Risk — hard stop and per-trade ceiling (READ THESE FIRST)"
input bool   InpUseHardStop        = false; // Attach a real stop loss at entry. FALSE = the parent's stopless behaviour (user choice 2026-08-21) — see the warning in the header.
input double InpStopLossATR        = 2.0;   // Reference distance = ATR(tier TF) x this. Always the SIZING distance; also the hard stop when InpUseHardStop is true.
input double InpMaxRiskPerTradePct = 12.0;  // Ceiling: max % of equity a trade may risk over the reference distance. An entry whose MINIMUM lot exceeds it is skipped (that tier waits for more equity).
input double InpMinLots            = 0.01;  // Smallest lot this account can trade (standard account minimum)
input double InpFixedLots          = 0.0;   // Fallback lots when ATR/tick sizing data is unavailable (0 = skip the trade instead)

input group  "Risk Management (per level, % of actual equity, priced against the hard stop)"
input double InpRiskTier2At     = 2000.0; // Equity where risk halves (tier 2)
input double InpRiskTier3At     = 10000.0;// Equity where risk halves again (tier 3)
input double InpRiskPctM5       = 1.0;    // M5   — tier 1 (equity < Tier2At)
input double InpRiskPctM15      = 1.5;    // M15  — tier 1
input double InpRiskPctM30      = 2.0;    // M30  — tier 1
input double InpRiskPctH1       = 2.5;    // H1   — tier 1
input double InpRiskPctH4       = 3.0;    // H4   — tier 1
input double InpRiskPctM5_T2    = 0.5;    // M5   — tier 2 (half regime)
input double InpRiskPctM15_T2   = 0.75;   // M15  — tier 2
input double InpRiskPctM30_T2   = 1.0;    // M30  — tier 2
input double InpRiskPctH1_T2    = 1.25;   // H1   — tier 2
input double InpRiskPctH4_T2    = 1.5;    // H4   — tier 2
input double InpRiskPctM5_T3    = 0.25;   // M5   — tier 3 (equity >= Tier3At)
input double InpRiskPctM15_T3   = 0.375;  // M15  — tier 3
input double InpRiskPctM30_T3   = 0.5;    // M30  — tier 3
input double InpRiskPctH1_T3    = 0.625;  // H1   — tier 3
input double InpRiskPctH4_T3    = 0.75;   // H4   — tier 3

input group  "Circuit Breakers (block NEW entries; open trades keep being managed)"
input double InpDailyLossLimitPct = 20.0; // Stop new entries once the day is down this % of its opening equity (0 = off)
input double InpMaxDrawdownPct    = 45.0; // Stop new entries while equity is this % below its peak (0 = off)
input int    InpLossCooldownMin   = 0;    // After a LOSING close, no new entry on that symbol for this many minutes (0 = off, the default here)
input bool   InpResetBreakers     = false;// Set true for ONE init to clear the stored equity peak and daily budget (use after a deposit, a reset, or moving the EA to another account), then set it back to false

// H1 stand-in bias mode — what the lower tiers may do when the H4 bias
// does not carry the trade.
//   H1BIAS_OFF     : no stand-in; H4 governs every tier on its own
//   H1BIAS_FLAT_H4 : stand-in allowed only while H4 is FLAT (unaligned /
//                    in its cloud) — never against an aligned H4
//   H1BIAS_ALWAYS  : stand-in allowed even when H4 is aligned the OTHER
//                    way (counter-H4 trading on the lower tiers)
enum ENUM_H1_BIAS_MODE { H1BIAS_OFF = 0, H1BIAS_FLAT_H4 = 1, H1BIAS_ALWAYS = 2 };

// Highest tier permitted to enter on the H1 stand-in bias. The H4 tier is
// deliberately absent — it always needs H4 (and D1) itself.
enum ENUM_H1_BIAS_TIER { H1TIER_M5 = 0, H1TIER_M15 = 1, H1TIER_M30 = 2, H1TIER_H1 = 3 };

// How far up the stack the STRICT cloud rule reaches. A timeframe at or
// below this index must have the cloud twisted the trade's way at BOTH
// the current bar and the far end of the future cloud; every timeframe
// above it needs only the future cloud. The parent build stopped at M1
// (STRICTCLOUD_M1); this build reaches M15, so fewer and better entries.
enum ENUM_STRICT_CLOUD_TF
{
   STRICTCLOUD_M1  = 0,   // M1 only — the parent's rule
   STRICTCLOUD_M5  = 1,   // M1 + M5
   STRICTCLOUD_M15 = 2,   // M1 + M5 + M15 (this build's default)
   STRICTCLOUD_M30 = 3    // M1 + M5 + M15 + M30
};

input group  "Entry Filters"
input bool   InpCloudBiasEnabled = true;   // Require the Span A vs Span B cloud bias at all
input ENUM_STRICT_CLOUD_TF InpStrictCloudUpTo = STRICTCLOUD_M1;  // TFs needing current+future cloud agreement (above this: future cloud only). M1 = the live build's proven rule.
input bool   InpH4Bias           = true;   // H4 is the bias — tiers trade in H4's direction (H4 flat = no trades unless the H1 bias stands in)
input bool   InpD1Filter         = true;   // D1 filter for the H4 tier: H4 trades only in the D1's direction; D1 in the cloud = no H4 trades
input int    InpMaxSpreadPoints  = 60;     // Max spread in points to allow entry (0 = no limit) — same as the live build

input group  "H1 Bias (lets the lower tiers trade when H4 is flat)"
input ENUM_H1_BIAS_MODE InpH1BiasMode    = H1BIAS_FLAT_H4; // 0=off (H4 only), 1=stand in only while H4 is flat, 2=stand in even against an aligned H4
input ENUM_H1_BIAS_TIER InpH1BiasMaxTier = H1TIER_M30;     // Highest tier allowed to enter on the H1 bias (0=M5, 1=M15, 2=M30, 3=H1)
input bool   InpH1BiasCloudCheck = true;   // Also require the H1 cloud (Span A vs Span B) to carry the trade's bias

input group  "Profit Protection"
input int    InpATRPeriod         = 14;    // ATR period (each level uses its own TF's ATR)
input double InpBEProfitATR       = 1.0;   // BE arms once profit >= this x ATR (M5/M15/M30 levels)
input double InpBEProfitH1H4      = 0.5;   // BE arms once profit >= this x ATR (H1/H4 levels — tighter)
input int    InpBECoverPoints     = 15;    // Points beyond entry for the BE stop (covers spread)
input double InpSpikeLockATR      = 2.0;   // Chandelier trail arms once profit >= this x ATR (M5/M15/M30 spike lock)
input double InpTrailActivateATR  = 0.5;   // H1/H4 chandelier trail arms once profit >= this x ATR
input double InpTrailATR          = 1.0;   // Trail distance behind the peak, x ATR (level TF)

input group  "Rejection Exit (strong rejection candle)"
input bool   InpRejectionExit = false;  // Close a trade when a very strong rejection candle forms against it on the tier TF
input int    InpRejSwingBars  = 8;      // Recent swing window (bars) the rejection candle must sweep
input double InpRejWickPct    = 0.5;    // Wick must be >= this fraction of the candle's total range
input double InpRejClosePct   = 0.35;   // Close must sit in the outermost this fraction of the range (strong close-back)

//--- Constants and Global Variables ---
#define MAX_SYMS 60
#define LEVELS   5      // tradable levels: M5, M15, M30, H1, H4
#define TFS      6      // stack: M1, M5, M15, M30, H1, H4
#define IDX_H1   4      // index of H1 in tfs[] — the stand-in bias TF
#define IDX_H4   5      // index of H4 in tfs[] — the primary bias TF

ENUM_TIMEFRAMES tfs[TFS] = { PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4 };
string          tfName[TFS] = { "M1", "M5", "M15", "M30", "H1", "H4" };

int      ich[MAX_SYMS][TFS];
int      ichD1[MAX_SYMS];           // D1 ichimoku handle — H4-tier bias filter
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

// Standard-account additions
datetime lastSkipLog[MAX_SYMS][LEVELS];  // sizing-skip log throttle (one line per symbol/level per hour)
datetime lastLossTime[MAX_SYMS];         // close time of the most recent LOSING trade per symbol (cooldown)
datetime cdLogged[MAX_SYMS];             // which loss a cooldown message has already been printed for
bool     riskPreviewDone = false;        // startup risk table printed (one-shot, on the first M1 bar)
double   dayStartEquity  = 0.0;          // equity at the start of the current server day
int      dayKey          = -1;           // server day the dayStartEquity belongs to
double   peakEquity      = 0.0;          // highest equity ever seen (drawdown breaker reference)
bool     haltLogged      = false;        // circuit-breaker halt already announced (throttle)

// Positions closed because a LARGER tier superseded them. Those closes are
// not "losing trades" in the sense the post-loss cooldown is meant to catch
// — they are position upgrades — so their deals are excluded from it. A
// ring of the last 64 is far more than the cooldown window can ever need.
#define SUPERSEDE_RING 64
ulong    supersededPos[SUPERSEDE_RING];
int      supersededIdx = 0;

int MAGIC = 20260862;   // FRESH — never manages positions of the live VPS build (20260858), the desktop twin (20260860) or the earlier standard-account fork (20260854)

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
      lastM1bar[s]    = 0;
      lastLossTime[s] = 0;
      cdLogged[s]     = 0;
      for(int l = 0; l < LEVELS; l++)
      {
         state[s][l] = 0;
         entryPrice[s][l] = 0.0;
         peakHigh[s][l]   = 0.0;
         peakLow[s][l]    = 0.0;
         beMoved[s][l]    = false;
         lastSkipLog[s][l] = 0;
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
         atr[s][l] = iATR(syms[s], tfs[l + 1], InpATRPeriod);
         if(atr[s][l] == INVALID_HANDLE) return(INIT_FAILED);
      }
   }

   for(int i = 0; i < SUPERSEDE_RING; i++) supersededPos[i] = 0;
   supersededIdx = 0;

   trade.SetDeviationInPoints(Slippage);
   trade.SetExpertMagicNumber(MAGIC);

   // Circuit-breaker references survive a terminal or VPS restart —
   // otherwise every restart would hand the account a fresh daily budget
   // and reset the drawdown peak, which is exactly the wrong behaviour
   // on the day the breakers are needed.
   RestoreBreakerState();

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
// Daily Bias Filter (H4 tier): D1 is the bias for H4 trades.
// Same alignment semantics as CheckAlign but on D1 — D1 bullish
// (price + chikou above tenkan, kijun and cloud) allows only H4
// buys, D1 bearish only H4 sells. A D1 close INSIDE the cloud
// (or unreadable) returns 0 — no new H4 trades then.
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
// Cloud Bias Filter — FULL check: the cloud must carry the
// trade's bias (Span A above Span B for a long, below for a
// short) at BOTH the last closed bar (the immediate cloud where
// price sits) and the far end of the future-cloud window. In the
// parent this applied to M1 alone; here it reaches every
// timeframe at or below InpStrictCloudUpTo (M15 by default).
// Unreadable values count as blocking.
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

//==============================================================
// Cloud Bias Filter — FUTURE-ONLY: the far end of the future-
// cloud window (Kijun bars ahead of the last closed bar) must
// carry the trade's bias; the immediate cloud where price sits
// may be either direction. Used for every timeframe from M5 up
// in the level gate, and for the H1 stand-in bias confirmation
// (InpH1BiasCloudCheck).
//==============================================================

bool CloudBiasFarOK(int s, int tfIdx, int dir)
{
   double aFar[1], bFar[1];
   if(CopyBuffer(ich[s][tfIdx], 2, 1 - Kijun, 1, aFar) <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 3, 1 - Kijun, 1, bFar) <= 0) return false;

   if(dir == 1) return aFar[0] > bFar[0];
   return aFar[0] < bFar[0];
}

//==============================================================
// Per-TF cloud rule, now a tunable rather than a hard-coded split.
// Every timeframe at or below InpStrictCloudUpTo takes the FULL
// check — current AND future cloud must both be twisted the
// trade's way. Every timeframe above it needs only the FUTURE
// cloud; its current cloud may be any value.
//
// DEFAULT IS STRICTCLOUD_M1 — exactly the live VPS build's rule,
// the most profitable one reported. An earlier draft of this file
// shipped with the cut at M15, which (together with the tier bug
// fixed in OnTick) is why an 8-month backtest produced 3 trades.
// STRICTCLOUD_M5 and _M15 are the second- and third-strictest
// settings if this proves to over-trade; nothing else changes.
//==============================================================

bool CloudBiasTFOK(int s, int tfIdx, int dir)
{
   if(tfIdx > (int)InpStrictCloudUpTo) return CloudBiasFarOK(s, tfIdx, dir);
   return CloudBiasOK(s, tfIdx, dir);
}

//==============================================================
// Level Cloud Bias Gate: unchanged in shape — the tier's own TF
// (lvl+1) and the TF directly below it (lvl) must both pass —
// but each is now judged by CloudBiasTFOK above rather than by a
// hard-coded M1-versus-the-rest split. Per tier, at the shipped
// STRICTCLOUD_M1 default:
//   M5  tier : M1 current+future + M5  future
//   M15 tier : M5 future         + M15 future
//   M30 tier : M15 future        + M30 future
//   H1  tier : M30 future        + H1  future
//   H4  tier : H1 future         + H4  future
// Raising InpStrictCloudUpTo walks the full check up the stack one
// timeframe at a time; each step also tightens the tier ABOVE the
// one named, because every tier checks the TF directly below it.
//==============================================================

bool LevelCloudBiasOK(int s, int lvl, int dir)
{
   if(!CloudBiasTFOK(s, lvl + 1, dir)) return false;   // tier TF
   if(!CloudBiasTFOK(s, lvl,     dir)) return false;   // TF directly below
   return true;
}

//==============================================================
// H4 Bias Filter: H4 is the bias for the whole stack. Every tier
// only trades in H4's direction — H4 bullish means only buys on
// all timeframes (a lower-TF sell is just a pullback), H4 bearish
// means only sells. If H4 has no alignment, no trades open —
// except on the tiers the new H1 stand-in bias covers (below).
//==============================================================

int H4Bias(int s)
{
   return CheckAlign(s, IDX_H4);    // 1 = bullish, -1 = bearish, 0 = flat/unreadable
}

//==============================================================
// H1 Bias Filter (NEW). The stand-in bias for the lower tiers:
// same alignment test as the H4 bias, one timeframe down, with
// an optional H1 cloud-bias confirmation on top. It is only ever
// consulted by EntryBiasOK() below, and only for the tiers the
// user has opened up via InpH1BiasMaxTier.
//==============================================================

bool H1BiasOK(int s, int dir)
{
   int h1 = CheckAlign(s, IDX_H1);
   if(h1 != dir) return false;      // H1 flat or opposed — nothing to stand in with

   // Optional extra confirmation: the H1 kumo's far end (future
   // cloud) must be twisted the trade's way — the same future-only
   // rule that applies to every M5+ timeframe in the level gate.
   // The immediate cloud is NOT required to match.
   if(InpH1BiasCloudCheck && !CloudBiasFarOK(s, IDX_H1, dir)) return false;

   return true;
}

// Is this tier allowed to fall back on the H1 bias at all?
bool H1BiasTier(int lvl)
{
   if(InpH1BiasMode == H1BIAS_OFF)     return false;
   if(lvl >= LEVELS - 1)               return false;   // never the H4 tier
   return lvl <= (int)InpH1BiasMaxTier;
}

//==============================================================
// Entry Bias Gate: H4 primary, H1 stand-in for the lower tiers.
//
//   1. H4 aligned WITH the trade  -> allowed, whatever the tier.
//      This is the primary path.
//   2. H4 FLAT -> the tiers at or below InpH1BiasMaxTier may still
//      open if H1 carries the trade — an undecided H4 no longer
//      freezes the whole stack.
//   3. H4 aligned AGAINST the trade -> still blocked, unless the
//      user opts into H1BIAS_ALWAYS.
//
// Writes into 'via' the bias that authorised the entry so the caller
// can log it: "H4", "H1" (stand-in on a flat H4), "H1x" (stand-in
// against an aligned H4), "--" when no bias gate applied at all.
//==============================================================

bool EntryBiasOK(int s, int lvl, int dir, string &via)
{
   via = "--";

   if(!InpH4Bias)
   {
      // H4 bias switched off: the H1 stand-in, where enabled, is the only
      // directional gate left on those tiers. Higher tiers stay ungated,
      // exactly as they were when the H4 bias is switched off.
      if(!H1BiasTier(lvl)) return true;
      if(!H1BiasOK(s, dir)) return false;
      via = "H1";
      return true;
   }

   int h4 = H4Bias(s);
   if(h4 == dir) { via = "H4"; return true; }          // primary path

   if(!H1BiasTier(lvl)) return false;                  // H1/H4 tiers need H4 itself
   if(h4 != 0 && InpH1BiasMode != H1BIAS_ALWAYS)       // H4 is aligned the other way
      return false;
   if(!H1BiasOK(s, dir)) return false;

   via = (h4 == 0) ? "H1" : "H1x";   // H1x = taken against an aligned H4
   return true;
}

//==============================================================
// Exit Check: price TOUCHES the level TF's cloud edge — no wait
// for a candle to close inside it. A long (entered above the
// cloud) exits when the bid touches the cloud's upper edge; a
// short (entered below) exits when the ask touches the lower
// edge. Evaluated once per closed M1 bar, so a touch triggers
// the exit within a minute. This is the trade's main exit; the
// BE/chandelier stop is the profit-protection layer on top.
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

// Server day as a single integer, so "has the day rolled over" is one
// comparison. Server time, not local — the trading day the broker keeps.
int ServerDayKey()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return dt.year * 10000 + dt.mon * 100 + dt.day;
}

//==============================================================
// Circuit Breakers (NEW). Two account-level guards, both of
// which block only NEW ENTRIES — an open position is never
// abandoned, its kumo exit, break-even and trail keep running.
//
//   * Daily loss limit — once equity is InpDailyLossLimitPct
//     below where the server day opened, the day is done. The
//     budget resets on the next server day, not on restart.
//   * Drawdown limit — once equity is InpMaxDrawdownPct below
//     the highest equity ever recorded, entries stop until the
//     account climbs back inside the band.
//
// Both references live in terminal GLOBAL VARIABLES keyed by the
// magic number, so a VPS restart mid-drawdown does not hand the
// account a fresh budget and a reset peak — which is precisely
// when the breakers matter most. They are per-terminal, not
// per-account: run one instance of this build per terminal.
//==============================================================

string GVName(string suffix) { return "ICH" + IntegerToString(MAGIC) + "_" + suffix; }

void RestoreBreakerState()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);

   // Escape hatch. The stored peak is per-terminal, so it follows the EA
   // onto a different account and a stale high-water mark would halt a
   // fresh account on its first bar. One init with InpResetBreakers = true
   // clears it; the drawdown breaker is otherwise deliberately sticky —
   // it does not reset itself, because a 30% hole is a decision to make,
   // not a limit to wait out.
   if(InpResetBreakers)
   {
      GlobalVariableDel(GVName("PEAK"));
      GlobalVariableDel(GVName("DAYKEY"));
      GlobalVariableDel(GVName("DAYEQ"));
      Print(PCTime() + " | Circuit-breaker state reset — peak and daily budget re-anchored at equity ",
            DoubleToString(eq, 2), ". Set InpResetBreakers back to false.");
   }

   peakEquity = GlobalVariableCheck(GVName("PEAK")) ? GlobalVariableGet(GVName("PEAK")) : 0.0;
   if(peakEquity < eq) peakEquity = eq;
   GlobalVariableSet(GVName("PEAK"), peakEquity);

   dayKey = GlobalVariableCheck(GVName("DAYKEY")) ? (int)GlobalVariableGet(GVName("DAYKEY")) : -1;
   dayStartEquity = GlobalVariableCheck(GVName("DAYEQ")) ? GlobalVariableGet(GVName("DAYEQ")) : 0.0;

   // Unknown day, a day that has already rolled over, or a nonsense
   // stored equity: start the day here.
   if(dayKey != ServerDayKey() || dayStartEquity <= 0.0)
   {
      dayKey = ServerDayKey();
      dayStartEquity = eq;
      GlobalVariableSet(GVName("DAYKEY"), dayKey);
      GlobalVariableSet(GVName("DAYEQ"),  dayStartEquity);
   }
}

// Refresh the peak and roll the day over. Called once per M1 bar.
void UpdateBreakerState()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);

   if(eq > peakEquity)
   {
      peakEquity = eq;
      GlobalVariableSet(GVName("PEAK"), peakEquity);
   }

   int today = ServerDayKey();
   if(today != dayKey)
   {
      dayKey = today;
      dayStartEquity = eq;
      GlobalVariableSet(GVName("DAYKEY"), dayKey);
      GlobalVariableSet(GVName("DAYEQ"),  dayStartEquity);
      haltLogged = false;              // a new day gets a fresh announcement
      Print(PCTime() + " | New trading day — equity " + DoubleToString(eq, 2) +
            ", daily loss budget " + DoubleToString(InpDailyLossLimitPct, 1) + "%");
   }
}

// True when NEW entries are blocked account-wide. 'why' explains it.
bool EntriesHalted(string &why)
{
   why = "";
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);

   if(InpDailyLossLimitPct > 0 && dayStartEquity > 0)
   {
      double dayPct = 100.0 * (dayStartEquity - eq) / dayStartEquity;
      if(dayPct >= InpDailyLossLimitPct)
      {
         why = "daily loss limit hit — down " + DoubleToString(dayPct, 1) + "% on the day (" +
               DoubleToString(dayStartEquity, 2) + " -> " + DoubleToString(eq, 2) +
               "), limit " + DoubleToString(InpDailyLossLimitPct, 1) + "%. No new entries until the next server day.";
         return true;
      }
   }

   if(InpMaxDrawdownPct > 0 && peakEquity > 0)
   {
      double ddPct = 100.0 * (peakEquity - eq) / peakEquity;
      if(ddPct >= InpMaxDrawdownPct)
      {
         why = "drawdown limit hit — " + DoubleToString(ddPct, 1) + "% below the equity peak (" +
               DoubleToString(peakEquity, 2) + " -> " + DoubleToString(eq, 2) +
               "), limit " + DoubleToString(InpMaxDrawdownPct, 1) + "%. No new entries until equity recovers.";
         return true;
      }
   }
   return false;
}

//==============================================================
// Post-loss cooldown (NEW). Adding a hard stop introduces a
// failure mode the stopless parent did not have: the stack can
// be stopped out and then find the SAME setup still aligned on
// the very next M1 bar, re-enter, and be stopped again — a slow
// bleed that no per-trade risk cap catches, because every single
// trade is inside its budget.
//
// So: after a LOSING close on a symbol, that symbol takes no new
// entry for InpLossCooldownMin minutes. The close time is read
// from the DEAL HISTORY rather than from our own exit path,
// because a stop-out is executed by the server and never passes
// through ExitLevel(). Refreshed once per M1 bar.
//==============================================================

void MarkSuperseded(ulong posId)
{
   if(posId == 0) return;
   supersededPos[supersededIdx] = posId;
   supersededIdx = (supersededIdx + 1) % SUPERSEDE_RING;
}

bool WasSuperseded(ulong posId)
{
   for(int i = 0; i < SUPERSEDE_RING; i++)
      if(supersededPos[i] == posId) return true;
   return false;
}

// Record every position a level currently holds as superseded, so the
// closes about to follow do not start a cooldown.
void MarkLevelSuperseded(int s, int lvl)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != syms[s]) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MAGIC) continue;
      string comm = PositionGetString(POSITION_COMMENT);
      if(comm == LevelComment(lvl, 1) || comm == LevelComment(lvl, -1))
         MarkSuperseded((ulong)PositionGetInteger(POSITION_IDENTIFIER));
   }
}

void RefreshLossCooldowns()
{
   if(InpLossCooldownMin <= 0) return;

   datetime now  = TimeCurrent();
   datetime from = now - (datetime)(InpLossCooldownMin * 60) - 3600;   // an hour of slack for late-settling deals
   if(!HistorySelect(from, now + 60)) return;

   for(int s = 0; s < symsCount; s++) lastLossTime[s] = 0;

   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if((int)HistoryDealGetInteger(ticket, DEAL_MAGIC) != MAGIC) continue;
      if((int)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      // Net result of the closing deal — commission and swap included, so a
      // "small win" that costs are turned into a loss counts as a loss.
      double net = HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                   HistoryDealGetDouble(ticket, DEAL_SWAP) +
                   HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      if(net >= 0) continue;

      // A tier closed out because a bigger one took over is an upgrade,
      // not the losing trade this cooldown exists to follow.
      if(WasSuperseded((ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID))) continue;

      string dsym = HistoryDealGetString(ticket, DEAL_SYMBOL);
      datetime t  = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      for(int s = 0; s < symsCount; s++)
         if(syms[s] == dsym && t > lastLossTime[s]) lastLossTime[s] = t;
   }
}

bool CooldownActive(int s, int &minsLeft)
{
   minsLeft = 0;
   if(InpLossCooldownMin <= 0 || lastLossTime[s] == 0) return false;
   int elapsed = (int)((TimeCurrent() - lastLossTime[s]) / 60);
   if(elapsed >= InpLossCooldownMin) return false;
   minsLeft = InpLossCooldownMin - elapsed;
   return true;
}

//==============================================================
// Risk Management (REBUILT for a $100 STANDARD account).
//
// THE PROBLEM THIS SOLVES. The parent sizes every trade against a
// "reference distance" of ATR(level TF) x 2 and then ends with
// MathMax(lotMin, lots), silently rounding any sub-minimum size UP
// to 0.01. On a micro symbol that rounding is harmless. On a
// STANDARD gold symbol 0.01 lot is 1 oz — about $1 of P/L per $1
// of gold — so below roughly $10k of equity EVERY trade is a
// minimum-lot trade whose real exposure is set by the broker's lot
// floor rather than by the risk table. The percentages become
// decoration.
//
// WHAT THIS BUILD DOES INSTEAD. When the risk-correct size lands
// below the minimum lot the trade is not silently inflated:
// SizedLots() prices what 0.01 lot would risk over the reference
// distance and returns 0 — skip — when that exceeds
// InpMaxRiskPerTradePct of equity. Tiers therefore unlock one at a
// time as the account grows instead of all firing at
// account-ending size on day one. A tier that returns 0 does NOT
// veto the symbol: the entry scan in OnTick walks down to the next
// affordable tier (see the long note there).
//
// READ THIS IF InpUseHardStop IS FALSE — it is, by default.
// With no stop attached, the reference distance is a SIZING BASIS
// ONLY. Nothing enforces it. InpMaxRiskPerTradePct then bounds the
// size of the position, not the size of the loss: the trade runs
// to the kumo-touch exit and can lose more than the ceiling names
// if price runs past the reference distance, and a gap or a news
// spike between closed M1 bars is unbounded. That is the live
// build's behaviour and it was chosen deliberately here (user,
// 2026-08-21) to keep the parent's let-it-run edge intact. Set
// InpUseHardStop = true to make the ceiling a real loss cap.
//
// Also: no silent fixed-lot fallback (InpFixedLots defaults to 0)
// and the margin cap SKIPS rather than clamping back up to the
// minimum. Skips are logged, throttled to one line per
// symbol/level per hour so the tiers that stay blocked all
// afternoon do not flood the journal.
//==============================================================

double LevelRiskPct(int lvl)
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   bool t3 = (eq >= InpRiskTier3At);
   bool t2 = (eq >= InpRiskTier2At);
   switch(lvl)
   {
      case 0:  return t3 ? InpRiskPctM5_T3  : t2 ? InpRiskPctM5_T2  : InpRiskPctM5;
      case 1:  return t3 ? InpRiskPctM15_T3 : t2 ? InpRiskPctM15_T2 : InpRiskPctM15;
      case 2:  return t3 ? InpRiskPctM30_T3 : t2 ? InpRiskPctM30_T2 : InpRiskPctM30;
      case 3:  return t3 ? InpRiskPctH1_T3  : t2 ? InpRiskPctH1_T2  : InpRiskPctH1;
      case 4:  return t3 ? InpRiskPctH4_T3  : t2 ? InpRiskPctH4_T2  : InpRiskPctH4;
   }
   return 0.0;
}

// The smallest volume this account can send: the broker's own
// minimum, never below the configured InpMinLots (0.01 here).
double MinLotFor(string sym)
{
   double brokerMin = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   return MathMax(brokerMin, InpMinLots);
}

// Snap a volume DOWN onto the broker's step grid. The epsilon matters
// now that sizing no longer rescues itself with MathMax(lotMin, lots):
// without it floating-point dust can turn a legitimate 0.01 into
// 0.00999... and send an otherwise fine trade into the min-lot gate.
double SnapLots(string sym, double lots)
{
   double lotStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if(lotStep <= 0) return lots;
   double steps = MathFloor(lots / lotStep + 1e-8);
   int    digits = 0;
   double st = lotStep;
   while(digits < 8 && MathAbs(st - MathRound(st)) > 1e-9) { st *= 10.0; digits++; }
   return NormalizeDouble(steps * lotStep, digits);
}

// The deliberate InpFixedLots fallback, snapped to the broker's volume
// grid so it is actually sendable. Returns 0 when no fallback is set.
double FallbackLots(string sym)
{
   if(InpFixedLots <= 0) return 0.0;
   double lots   = SnapLots(sym, InpFixedLots);
   double lotMax = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   lots = MathMax(MinLotFor(sym), lots);
   if(lotMax > 0 && lots > lotMax) lots = lotMax;
   return lots;
}

// One journal line per symbol/level per hour, so a tier that stays
// aligned and blocked for hours logs once rather than every minute.
void LogSizingSkip(int s, int lvl, string why)
{
   datetime now = TimeCurrent();
   if(lastSkipLog[s][lvl] != 0 && (now - lastSkipLog[s][lvl]) < 3600) return;
   lastSkipLog[s][lvl] = now;
   Print(PCTime() + " | " + syms[s] + " " + tfName[lvl + 1] + " entry skipped — " + why);
}

// The reference distance in PRICE for a tier: ATR(tier TF) x
// InpStopLossATR. This is ALWAYS the sizing distance, and it is
// additionally attached to the order as a real stop when
// InpUseHardStop is true. Floored so a stop the server would reject
// is never sent (a rejected stop takes the whole order with it).
// Returns 0 when ATR is unreadable.
double StopDistanceFor(int s, int lvl)
{
   double a[1];
   if(CopyBuffer(atr[s][lvl], 0, 1, 1, a) <= 0 || a[0] <= 0) return 0.0;
   double dist = a[0] * InpStopLossATR;

   // Two floors. The broker's stops level, because a stop inside it gets
   // the whole ORDER rejected, not just the stop. And three spreads,
   // because in a dead market ATR can shrink toward the spread itself and
   // a stop that close is taken out by the bid/ask alone.
   double point   = SymbolInfoDouble(syms[s], SYMBOL_POINT);
   double minDist = SymbolInfoInteger(syms[s], SYMBOL_TRADE_STOPS_LEVEL) * point;
   double spread  = SymbolInfoInteger(syms[s], SYMBOL_SPREAD) * point;

   double floorDist = MathMax(minDist * 1.5, spread * 3.0);
   if(dist < floorDist) dist = floorDist;

   return dist;
}

// What 1.00 lot would lose over 'dist' of price. 0 when unpriceable.
double MoneyPerLotOver(string sym, double dist)
{
   double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0 || tickSize <= 0 || dist <= 0) return 0.0;
   return (dist / tickSize) * tickValue;
}

// The volume to trade, or 0.0 when this entry must be SKIPPED.
// 'quiet' suppresses the journal skip lines — used by the startup risk
// preview, which prices every tier including the ones it expects to be
// blocked and reports them in its own table instead.
double SizedLots(int s, int lvl, bool quiet = false)
{
   string sym    = syms[s];
   double lotMin = MinLotFor(sym);
   double lotMax = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   double riskPct = LevelRiskPct(lvl);
   if(riskPct <= 0)
   {
      if(!quiet) LogSizingSkip(s, lvl, "risk % for this level is 0");
      return 0.0;
   }
   if(equity <= 0)
   {
      if(!quiet) LogSizingSkip(s, lvl, "equity is not positive");
      return 0.0;
   }

   // The stop distance doubles as the sizing distance, so the risk % is
   // the money the trade can actually lose rather than a notional figure.
   double stopDist   = StopDistanceFor(s, lvl);
   double moneyPerLot = MoneyPerLotOver(sym, stopDist);
   if(stopDist <= 0 || moneyPerLot <= 0)
   {
      // Nothing here can be priced, so the ceiling cannot be enforced on
      // this path either — which is exactly why InpFixedLots defaults to 0
      // and skipping is the default. If a fallback IS configured, say out
      // loud that the trade is going out unchecked.
      if(InpFixedLots > 0)
      {
         if(!quiet) LogSizingSkip(s, lvl, "sizing data unavailable — sending the InpFixedLots fallback " +
                       DoubleToString(InpFixedLots, 2) + " WITHOUT a risk-ceiling check");
         return FallbackLots(sym);
      }
      if(!quiet) LogSizingSkip(s, lvl, "ATR/tick sizing data unavailable and no InpFixedLots fallback");
      return 0.0;
   }

   // The hard ceiling applies to every path, so compute it once.
   double ceilingMoney = equity * (InpMaxRiskPerTradePct / 100.0);
   double riskMoney    = equity * (riskPct / 100.0);
   if(InpMaxRiskPerTradePct > 0 && riskMoney > ceilingMoney) riskMoney = ceilingMoney;

   double lots = SnapLots(sym, riskMoney / moneyPerLot);

   // The risk-correct size does not reach the smallest tradable lot.
   // Round up to it ONLY when the minimum lot's real loss at the stop
   // stays inside InpMaxRiskPerTradePct — otherwise refuse the trade.
   // This is the gate that keeps the higher tiers off a $100 account.
   if(lots < lotMin)
   {
      double minLotRisk = moneyPerLot * lotMin;
      double minLotPct  = 100.0 * minLotRisk / equity;
      if(InpMaxRiskPerTradePct <= 0 || minLotPct > InpMaxRiskPerTradePct)
      {
         if(!quiet) LogSizingSkip(s, lvl, "min lot " + DoubleToString(lotMin, 2) + " would risk " +
                       DoubleToString(minLotRisk, 2) + " (" + DoubleToString(minLotPct, 1) +
                       "% of equity) over a " + DoubleToString(stopDist, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)) +
                       (InpUseHardStop ? " stop" : " reference distance") +
                       ", vs the " + DoubleToString(riskPct, 3) + "% this level asks for; ceiling is " +
                       DoubleToString(InpMaxRiskPerTradePct, 1) + "%. This tier unlocks as equity grows.");
         return 0.0;
      }
      lots = lotMin;
   }

   if(lotMax > 0 && lots > lotMax) lots = lotMax;
   return (lots > 0) ? lots : 0.0;
}

// Scale a single order down to the free margin so it fills fully.
// Unlike the parent this never clamps UP to the broker minimum:
// when the free margin cannot carry even the smallest lot, lots is
// set to 0 and the entry is skipped.
void CapLotsToMargin(int s, int lvl, bool isBuy, double &lots)
{
   if(lots <= 0) return;
   string sym = syms[s];
   double price = isBuy ? SymbolInfoDouble(sym, SYMBOL_ASK)
                        : SymbolInfoDouble(sym, SYMBOL_BID);
   double marginOne = 0.0;
   if(!OrderCalcMargin(isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, sym, lots, price, marginOne))
      return;
   if(marginOne <= 0) return;
   double maxLots = SnapLots(sym, AccountInfoDouble(ACCOUNT_MARGIN_FREE) * lots / marginOne);
   double lotMin  = MinLotFor(sym);

   if(maxLots < lotMin)
   {
      LogSizingSkip(s, lvl, "free margin cannot carry the minimum lot " + DoubleToString(lotMin, 2));
      lots = 0.0;
      return;
   }
   if(lots > maxLots) lots = maxLots;
}

//==============================================================
// Startup Risk Preview (NEW). Printed once, on the first M1 bar
// (not in OnInit — the indicator handles have no data yet there).
// It answers the only question that matters before leaving this
// EA alone on a $100 standard account: at today's ATR, which
// tiers can actually trade, and what does each one risk?
//
// The contract-size line is also the fastest way to catch a MICRO
// symbol accidentally left in the Symbols input — a standard gold
// symbol reports 100, a micro one 10.
//==============================================================

void PrintRiskPreview(int s)
{
   string sym    = syms[s];
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   int    digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);

   Print("=== ", sym, " risk preview — equity ", DoubleToString(equity, 2),
         ", contract size ", DoubleToString(SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE), 2),
         ", min lot ", DoubleToString(MinLotFor(sym), 2),
         ", per-trade ceiling ", DoubleToString(InpMaxRiskPerTradePct, 1), "% ===");

   for(int l = 0; l < LEVELS; l++)
   {
      double a[1];
      double atrVal   = (CopyBuffer(atr[s][l], 0, 1, 1, a) > 0) ? a[0] : 0.0;
      double stopDist = StopDistanceFor(s, l);
      double mpl      = MoneyPerLotOver(sym, stopDist);
      double lotMin   = MinLotFor(sym);

      if(stopDist <= 0 || mpl <= 0 || equity <= 0)
      {
         Print("  ", tfName[l + 1], " — sizing data not ready yet");
         continue;
      }

      double minLotRisk = mpl * lotMin;
      double minLotPct  = 100.0 * minLotRisk / equity;
      double lots       = SizedLots(s, l, true);

      Print("  ", tfName[l + 1],
            " | ATR ", DoubleToString(atrVal, digits),
            (InpUseHardStop ? " | stop " : " | ref dist "), DoubleToString(stopDist, digits),
            " | risk% ", DoubleToString(LevelRiskPct(l), 3),
            " | min lot risks ", DoubleToString(minLotRisk, 2),
            " (", DoubleToString(minLotPct, 1), "% of equity)",
            " | ", (lots > 0 ? "TRADABLE at " + DoubleToString(lots, 2) + " lot" : "BLOCKED — unlocks as equity grows"));
   }

   // Roughly what equity each blocked tier needs before its minimum lot
   // fits inside the ceiling. A guide, not a promise — it moves with ATR.
   if(InpMaxRiskPerTradePct > 0)
   {
      string unlocks = "  Approx equity needed to unlock at today's ATR:";
      for(int l = 0; l < LEVELS; l++)
      {
         double mpl = MoneyPerLotOver(sym, StopDistanceFor(s, l));
         if(mpl <= 0) continue;
         double need = mpl * MinLotFor(sym) * 100.0 / InpMaxRiskPerTradePct;
         unlocks += "  " + tfName[l + 1] + " ~" + DoubleToString(need, 0);
      }
      Print(unlocks);
   }
}

//==============================================================
// Trading Functions
//==============================================================

// 'via' names the bias that authorised the entry ("H4", "H1" stand-in,
// "H1x" counter-H4 stand-in, "--" none) — logged so the H1-bias trades
// are separable from the H4 ones when reviewing the journal.
bool OpenLevel(int s, int lvl, int dir, double lots, string via)
{
   string sym = syms[s];
   string comment = LevelComment(lvl, dir);
   double price = (dir == 1) ? SymbolInfoDouble(sym, SYMBOL_ASK)
                             : SymbolInfoDouble(sym, SYMBOL_BID);
   int    digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);

   // OPTIONAL hard stop at entry — OFF by default in this build.
   //
   // When on, it sits at the same distance the position was sized against,
   // so the loss it caps is the loss the risk table priced, and it is the
   // backstop for the gap and the news spike that the once-a-minute kumo
   // check cannot catch. When off (the default, user choice 2026-08-21)
   // this build behaves exactly like the live parent: no entry stop, the
   // trade runs to the kumo-touch exit, and the BE/chandelier layer is the
   // only protection once it turns green. The trade-off is stated in the
   // file header — a stop at 2 x ATR would sometimes fire where the parent
   // would have let the trade breathe and recover.
   double sl = 0.0;
   if(InpUseHardStop)
   {
      double stopDist = StopDistanceFor(s, lvl);
      if(stopDist > 0)
         sl = NormalizeDouble((dir == 1) ? price - stopDist : price + stopDist, digits);
      else
         Print(PCTime() + " | " + sym + " " + tfName[lvl + 1] +
               " WARNING: stop distance unavailable, sending the order WITHOUT a stop loss");
   }

   bool ok = (dir == 1) ? trade.Buy(lots, sym, price, sl, 0, comment)
                        : trade.Sell(lots, sym, price, sl, 0, comment);
   if(ok)
   {
      state[s][lvl] = dir;
      entryPrice[s][lvl] = price;   // BE + spike-lock trail references
      peakHigh[s][lvl]   = price;
      peakLow[s][lvl]    = price;
      beMoved[s][lvl]    = false;
      string action = (dir == 1) ? "Buy" : "Sell";
      string risk = "";
      if(sl > 0)
      {
         double mpl = MoneyPerLotOver(sym, MathAbs(price - sl));
         double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
         if(mpl > 0 && eq > 0)
            risk = ", risk " + DoubleToString(mpl * lots, 2) +
                   " (" + DoubleToString(100.0 * mpl * lots / eq, 1) + "%)";
      }
      string msg = PCTime() + " | " + action + " " + sym + " " + tfName[lvl + 1] +
                   " @ " + DoubleToString(lots, 2) + " (bottom-up, bias " + via + ")" +
                   (sl > 0 ? ", SL " + DoubleToString(sl, digits) : ", NO SL") + risk;
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
// to those timeframes. Unlike the parent the position already
// carries a HARD STOP from entry (see OpenLevel), so both blocks
// below start from that stop and can only ever pull it tighter,
// never wider.
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
// Rejection Candle Exit: closes a trade when a VERY STRONG
// rejection forms against it on the tier TF (last closed bar).
// All four conditions must hold — a swing sweep plus a dominant
// wick plus a strong close-back on a candle whose body opposes
// the trade:
//   Bearish rejection (kills a LONG):
//     - bearish body (c1 < o1)
//     - takes out the swing high of the previous
//       InpRejSwingBars bars (h1 > highest high before it)
//     - upper wick >= InpRejWickPct of the candle's total range
//     - close in the bottom InpRejClosePct of the range
//       (closed strongly back from the sweep high)
//   Bullish rejection (kills a SHORT): mirrored.
// Returns 1 (bullish), -1 (bearish), 0 (none).
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
      double upperWick = h1 - o1;               // bearish: high minus open
      double closeBack = c1 - l1;               // distance closed back from the low
      if(upperWick >= InpRejWickPct * range &&
         closeBack <= InpRejClosePct * range)
         return -1;
   }

   // Bullish rejection: sweeps the swing low and closes strongly back
   if(c1 > o1 && l1 < swingLo)
   {
      double lowerWick = o1 - l1;               // bullish: open minus low
      double closeBack = h1 - c1;               // distance closed back from the high
      if(lowerWick >= InpRejWickPct * range &&
         closeBack <= InpRejClosePct * range)
         return 1;
   }
   return 0;
}

// Close a level's positions with a notification; returns true only
// when nothing remains open, so a failed close is retried next bar.
bool ExitLevel(int s, int l, string reason)
{
   string side = (state[s][l] == 1) ? "Long" : "Short";
   string msg  = PCTime() + " | Close " + syms[s] + " " + side + " " +
                 tfName[l + 1] + " (" + reason + ")";
   Print(msg); SendNotification(msg);

   if(CloseLevelPositions(s, l))
   {
      state[s][l] = 0;
      msg = PCTime() + " | " + syms[s] + " " + tfName[l + 1] + " level closed";
      Print(msg); SendNotification(msg);
      return true;
   }
   Print(PCTime() + " | " + syms[s] + " " + tfName[l + 1] + " exit signal but positions still open — will retry");
   return false;
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

   // Account-level bookkeeping, once per minute rather than per symbol:
   // roll the daily budget over, refresh the equity peak, and re-read the
   // deal history for the post-loss cooldowns.
   UpdateBreakerState();
   RefreshLossCooldowns();

   // Is the account allowed to open anything at all this minute? Exits,
   // break-even and the trail run regardless — a breaker stops NEW risk,
   // it never abandons a position that is already on.
   string haltWhy = "";
   bool   halted  = EntriesHalted(haltWhy);
   if(halted && !haltLogged)
   {
      string hmsg = PCTime() + " | ENTRIES HALTED — " + haltWhy;
      Print(hmsg); SendNotification(hmsg);
      haltLogged = true;
   }
   else if(!halted && haltLogged)
   {
      Print(PCTime() + " | Entries re-enabled — equity back inside the circuit-breaker limits");
      haltLogged = false;
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

      // One-shot startup risk table, now that the indicator handles have
      // data. Read it before leaving the EA unattended — it is the fastest
      // check that the symbol and the sizing are what you think they are.
      if(!riskPreviewDone)
      {
         for(int ps = 0; ps < symsCount; ps++) PrintRiskPreview(ps);
         riskPreviewDone = true;
      }

      // Exits and profit protection per level
      for(int l = 0; l < LEVELS; l++)
      {
         // Exit check: price touched the level TF's cloud edge
         if(state[s][l] != 0 && InCloudTouch(s, l + 1, state[s][l]))
            ExitLevel(s, l, "kumo touch");

         // Rejection exit: a very strong rejection candle formed on
         // the tier TF against the trade (bearish kills a long,
         // bullish kills a short)
         if(InpRejectionExit && state[s][l] != 0)
         {
            int rj = RejectionCandle(s, l + 1);
            if(rj != 0 && rj == -state[s][l])
               ExitLevel(s, l, "rejection");
         }

         // Profit protection: BE + spike-lock chandelier trail
         if(state[s][l] != 0) ManageLevelProtection(s, l);
      }

      // Entry consolidation: when several tiers align at once, the LARGEST
      // AFFORDABLE one opens — highest TF that clears the risk ceiling,
      // not simply the highest TF. Any smaller tier already running on the
      // symbol is closed first: M15 and M30 align together and M30 can be
      // paid for, so the running M15 trade closes and only M30 opens.
      int    topTier = -1;
      int    topDir  = 0;
      string topVia  = "--";
      double topLots = 0.0;

      // Entry gates that apply to the whole symbol, checked before the
      // per-tier scan so a halted account does nothing but manage.
      int  cdLeft     = 0;
      bool inCooldown = CooldownActive(s, cdLeft);
      if(inCooldown && cdLogged[s] != lastLossTime[s])
      {
         Print(PCTime() + " | " + syms[s] + " in post-loss cooldown — " +
               IntegerToString(cdLeft) + " min left, no new entries");
         cdLogged[s] = lastLossTime[s];
      }

      bool symBlocked = halted || inCooldown;
      if(!symBlocked && SpreadOK(syms[s]))
      {
         for(int l = LEVELS - 1; l >= 0; l--)
         {
            if(state[s][l] != 0) continue;
            int st = ChainAligned(s, l + 1);
            if(st == 0) continue;
            if(InpCloudBiasEnabled && !LevelCloudBiasOK(s, l, st)) continue;

            // Directional bias: H4 as before, with the new H1 stand-in for
            // the lower tiers when H4 has no direction of its own.
            string via = "--";
            if(!EntryBiasOK(s, l, st, via)) continue;

            // H4 tier: D1 must carry the same bias (D1 in the cloud = no H4 trades)
            if(l == LEVELS - 1 && InpD1Filter && DailyAlign(s) != st) continue;

            // AFFORDABILITY IS PART OF TIER SELECTION, NOT A VETO ON THE
            // SYMBOL. This is the fix for the 3-trades-in-8-months result.
            //
            // ChainAligned() is nested: the M30 tier requires M1+M5+M15+M30
            // to agree, so whenever a HIGH tier is aligned every tier below
            // it is aligned too, by construction. The build used to pick the
            // highest aligned tier, size it once, and skip the whole symbol
            // when that size came back 0. On a $100 account the high tiers
            // are unaffordable almost always — so every time the market
            // trended hard enough to align M15/M30/H1, the EA selected that
            // tier, could not pay for it, and opened NOTHING, while a
            // perfectly good M5 entry sat right there aligned and affordable.
            // It could only ever trade the narrow case where M1+M5 agreed and
            // M15 did not. The strongest setups were the ones discarded.
            //
            // Now a tier that cannot be sized simply loses its turn and the
            // scan walks DOWN to the next one. No risk rule is relaxed by
            // this: whatever finally opens has passed the same ceiling. As
            // equity grows the bigger tiers become affordable and take over
            // through the normal supersede path.
            double lots = SizedLots(s, l);
            if(lots <= 0) continue;

            topTier = l;
            topDir  = st;
            topVia  = via;
            topLots = lots;
            break;
         }
      }

      if(topTier >= 0)
      {
         // Sized during the scan above, BEFORE anything is superseded — so a
         // tier that cannot be paid for never kills a running lower-tier
         // trade on its way to opening nothing.
         double lots = topLots;

         // Close any smaller (lower-tier) trades still running
         for(int l = 0; l < topTier; l++)
         {
            if(state[s][l] != 0)
            {
               string msg = PCTime() + " | Close " + syms[s] + " " + tfName[l + 1] +
                            " (superseded by " + tfName[topTier + 1] + ")";
               Print(msg); SendNotification(msg);

               // Flag these positions before they close so a red supersede
               // does not put the symbol into a post-loss cooldown.
               MarkLevelSuperseded(s, l);

               if(CloseLevelPositions(s, l))
                  state[s][l] = 0;
               else
                  Print(PCTime() + " | " + syms[s] + " " + tfName[l + 1] + " superseded but positions still open — will retry");
            }
         }

         // Margin cap last, once the superseded tiers have released their
         // margin. Still 0 = the free margin cannot carry the minimum lot.
         CapLotsToMargin(s, topTier, (topDir == 1), lots);
         if(lots <= 0) continue;

         if(!OpenLevel(s, topTier, topDir, lots, topVia))
            Print(PCTime() + " | " + syms[s] + " " + tfName[topTier + 1] +
                  " entry signal but order failed, retcode " + IntegerToString(trade.ResultRetcode()));
      }
   }
}
//This work is my worship unto GOD
