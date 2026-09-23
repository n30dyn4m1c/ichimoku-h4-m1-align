//+------------------------------------------------------------------+
//|                                           Unraided_Liquidity.mq5 |
//|                                                                  |
//|  Draws the swing highs and swing lows that price has not yet     |
//|  traded back through - the resting liquidity still waiting to    |
//|  be raided. Each one is a line from the tip of its wick running  |
//|  off to the right edge of the chart, one colour for highs and    |
//|  one for lows. When price takes a level out, its line goes.      |
//|                                                                  |
//|  A swing is found the way a fractal is: a high is a swing high   |
//|  when it stands above the InpLeftBars candles before it and the  |
//|  InpRightBars candles after it (6 and 6 by default; a Williams   |
//|  fractal is 2 and 2). Lows mirror it.                            |
//|                                                                  |
//|  Equal highs are liquidity too, so ties are settled one way:     |
//|  the swing must be strictly above the candles on its left but    |
//|  only as high as those on its right. Of a run of equal highs     |
//|  the OLDEST is the swing, and a later candle that only matches   |
//|  it has not raided it - to raid, price must trade beyond.        |
//|                                                                  |
//|  A swing is only confirmed once all its right-hand candles have  |
//|  closed, so a line never appears and then vanishes because the   |
//|  swing failed. It does vanish when raided, and a wick raid is    |
//|  read off the live candle, so that happens the moment price      |
//|  trades through. A close raid waits for the candle to close.     |
//|                                                                  |
//|  Timeframe: PERIOD_CURRENT follows the chart. Any other value    |
//|  locks the swings to that timeframe on every chart - H1 swings   |
//|  seen on M5, for instance. When the locked timeframe is higher   |
//|  than the chart's, the line starts at the chart candle inside    |
//|  the locked candle that printed the wick, not at the locked      |
//|  candle's open, so it sits on the wick you can actually see.     |
//|                                                                  |
//|  Built to share a chart with po3-levels.mq5: every object it     |
//|  draws is prefixed ULQ_ and it deletes nothing else.             |
//+------------------------------------------------------------------+
#property copyright "Unraided Liquidity"
#property version   "1.00"
#property description "Unraided swing highs and lows (fractal-style, 6 candles each side by default),"
#property description "drawn from the wick to the right edge until price trades through them."
#property description "Follows the chart timeframe or can be locked to one. Draws only - places no orders."
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

enum ENUM_RAID_MODE
  {
   RAID_WICK  = 0,   // Wick trades through the level
   RAID_CLOSE = 1    // A candle closes through the level
  };

input ENUM_TIMEFRAMES InpTimeframe      = PERIOD_CURRENT; // Timeframe (current = follow the chart)
input int             InpLeftBars       = 6;              // Candles to the left of a swing
input int             InpRightBars      = 6;              // Candles to the right of a swing
input int             InpLookback       = 1000;           // Candles of history to search
input ENUM_RAID_MODE  InpRaidMode       = RAID_WICK;      // What counts as a raid
input bool            InpShowHighs      = true;           // Show unraided highs
input bool            InpShowLows       = true;           // Show unraided lows
input color           InpHighColor      = clrOrangeRed;   // Colour of unraided highs
input color           InpLowColor       = clrDodgerBlue;  // Colour of unraided lows
input int             InpLineWidth      = 1;              // Line width
input ENUM_LINE_STYLE InpLineStyle      = STYLE_SOLID;    // Line style
input bool            InpSnapToWick     = true;           // Locked higher TF: start at the chart candle with the wick

#define ULQ_PREFIX "ULQ_"

string g_keep[];     // names drawn this pass; anything else with the prefix is stale
int    g_keepCount;
bool   g_changed;

ENUM_TIMEFRAMES SourceTF()
  {
   return (InpTimeframe == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : InpTimeframe;
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpLeftBars < 1 || InpRightBars < 1)
     {
      Print("Unraided Liquidity: left and right candles must both be at least 1");
      return INIT_PARAMETERS_INCORRECT;
     }
   IndicatorSetString(INDICATOR_SHORTNAME,
                      "Unraided Liquidity (" + StringSubstr(EnumToString(SourceTF()), 7) + ", " +
                      IntegerToString(InpLeftBars) + "/" + IntegerToString(InpRightBars) + ")");
   ObjectsDeleteAll(0, ULQ_PREFIX, -1, -1);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   ObjectsDeleteAll(0, ULQ_PREFIX, -1, -1);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//|  A locked timeframe's history may not be loaded on the first     |
//|  call; retry on a timer until it is, so a quiet market (no       |
//|  ticks) still gets its lines.                                    |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(!Refresh())
      EventSetTimer(1);
   return rates_total;
  }

void OnTimer()
  {
   if(Refresh())
      EventKillTimer();
  }

//+------------------------------------------------------------------+
bool Refresh()
  {
   ENUM_TIMEFRAMES tf = SourceTF();
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int n = CopyRates(_Symbol, tf, 0, InpLookback, r);
   if(n < InpLeftBars + InpRightBars + 2)
      return false;

   g_keepCount = 0;
   ArrayResize(g_keep, 0, 256);
   g_changed = false;

   if(InpShowHighs)
      Scan(r, n, tf, true);
   if(InpShowLows)
      Scan(r, n, tf, false);
   Prune();

   if(g_changed)
      ChartRedraw();
   return true;
  }

//+------------------------------------------------------------------+
//|  Walk from the newest candle back, carrying the most extreme     |
//|  price traded since. A swing is unraided when nothing newer has  |
//|  gone beyond it, so one pass settles every swing at once.        |
//+------------------------------------------------------------------+
void Scan(const MqlRates &r[], const int n, const ENUM_TIMEFRAMES tf, const bool isHigh)
  {
   double reach = isHigh ? -DBL_MAX : DBL_MAX;   // furthest price beyond, newer than bar i

   for(int i = 0; i < n; i++)
     {
      // bars 1..InpRightBars must all be closed, and InpLeftBars must exist behind
      if(i > InpRightBars && i + InpLeftBars < n && IsSwing(r, i, isHigh))
        {
         double level  = isHigh ? r[i].high : r[i].low;
         bool   raided = isHigh ? (reach > level) : (reach < level);
         if(!raided)
            Draw(r[i].time, level, tf, isHigh);
        }

      if(InpRaidMode == RAID_CLOSE && i == 0)
         continue;                               // the live candle has not closed yet
      double probe = (InpRaidMode == RAID_WICK) ? (isHigh ? r[i].high : r[i].low) : r[i].close;
      reach = isHigh ? MathMax(reach, probe) : MathMin(reach, probe);
     }
  }

bool IsSwing(const MqlRates &r[], const int i, const bool isHigh)
  {
   double v = isHigh ? r[i].high : r[i].low;
   for(int j = 1; j <= InpLeftBars; j++)          // older: strictly beyond
     {
      double o = isHigh ? r[i + j].high : r[i + j].low;
      if(isHigh ? (v <= o) : (v >= o))
         return false;
     }
   for(int j = 1; j <= InpRightBars; j++)         // newer: at least as far
     {
      double o = isHigh ? r[i - j].high : r[i - j].low;
      if(isHigh ? (v < o) : (v > o))
         return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
void Draw(const datetime t, const double level, const ENUM_TIMEFRAMES tf, const bool isHigh)
  {
   string name = ULQ_PREFIX + (isHigh ? "H_" : "L_") + IntegerToString((long)t);
   ArrayResize(g_keep, g_keepCount + 1, 256);
   g_keep[g_keepCount++] = name;

   if(ObjectFind(0, name) >= 0)
      return;                                    // a confirmed swing never moves

   datetime start = InpSnapToWick ? WickTime(t, tf, isHigh) : t;
   if(!ObjectCreate(0, name, OBJ_TREND, 0, start, level, start + PeriodSeconds(_Period), level))
      return;
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT,  false);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     isHigh ? InpHighColor : InpLowColor);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,     InpLineWidth);
   ObjectSetInteger(0, name, OBJPROP_STYLE,     InpLineStyle);
   ObjectSetInteger(0, name, OBJPROP_BACK,      true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,    true);
   ObjectSetString(0, name, OBJPROP_TOOLTIP,
                   "Unraided " + (isHigh ? "high " : "low ") + DoubleToString(level, _Digits) +
                   "  " + StringSubstr(EnumToString(tf), 7) + "  " +
                   TimeToString(t, TIME_DATE | TIME_MINUTES));
   g_changed = true;
  }

//+------------------------------------------------------------------+
//|  For a swing from a higher timeframe, the chart candle inside it |
//|  that printed the extreme. Falls back to the swing candle's open |
//|  when the chart's own history does not reach back that far.      |
//+------------------------------------------------------------------+
datetime WickTime(const datetime t, const ENUM_TIMEFRAMES tf, const bool isHigh)
  {
   if(PeriodSeconds(_Period) >= PeriodSeconds(tf))
      return t;
   MqlRates c[];
   int m = CopyRates(_Symbol, _Period, t, t + PeriodSeconds(tf) - 1, c);
   if(m <= 0)
      return t;
   int best = 0;
   for(int k = 1; k < m; k++)
      if(isHigh ? (c[k].high > c[best].high) : (c[k].low < c[best].low))
         best = k;
   return c[best].time;
  }

//+------------------------------------------------------------------+
void Prune()
  {
   for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, ULQ_PREFIX) != 0)
         continue;
      bool keep = false;
      for(int k = 0; k < g_keepCount && !keep; k++)
         keep = (g_keep[k] == name);
      if(!keep)
        {
         ObjectDelete(0, name);
         g_changed = true;
        }
     }
  }
//+------------------------------------------------------------------+
