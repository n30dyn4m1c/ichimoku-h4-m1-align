//+------------------------------------------------------------------+
//|                                                   PO3_Levels.mq5 |
//|                                                                  |
//|  Draws PO3 (power of three) levels around the current price.     |
//|                                                                  |
//|  Every PO3 number from 1 to 19683 has its own checkbox and its   |
//|  own colour. Tick as many as you like; the chart refreshes on    |
//|  the selection. Width and style follow the magnitude, so the     |
//|  bigger numbers read as the stronger levels:                     |
//|        1, 3, 9, 27       thin, dotted                            |
//|        81, 243           thin, solid                             |
//|        729, 2187         medium, solid                           |
//|        6561, 19683       thick, solid                            |
//|                                                                  |
//|  Levels come from the workbook's "All PO3" sheet, which is       |
//|  multiplier x 3^power for powers 1..15, divided by the scale     |
//|  divisor.                                                        |
//|                                                                  |
//|  1 is the exception and the only grid off by default. It is      |
//|  3^0, the power the sheet starts one above, and at scale 1 it    |
//|  is every whole number - on gold a line per dollar. That is the  |
//|  floor the nest stands on rather than a level to trade, so it    |
//|  is there to be ticked deliberately, for reading where price     |
//|  sits inside a 3 cell, and not to be left on.                    |
//|                                                                  |
//|  Scale 1 gives whole numbers and is the default: gold levels     |
//|  land on 4374, 4455, 4536 and so on, the sheet's raw figures     |
//|  with nothing to divide. Scale 100 gives the workbook's          |
//|  two-decimal gold form (2799.36, 3542.94).                       |
//|                                                                  |
//|  The two agree. A level m x 3^n / 100 is a whole number only     |
//|  when 100 divides m, because 3^n shares no factor with 100, and  |
//|  m = 100k reduces to k x 3^n. So the scale 1 grid IS exactly the |
//|  whole-number subset of the scale 100 grid: choosing whole       |
//|  numbers drops the fractional levels, it does not move any.      |
//|                                                                  |
//|  Powers of three nest: 27 is a multiple of 9, so every 27 level  |
//|  sits exactly on a 9 level. Ticking both would stack duplicate   |
//|  objects on the same price, so a level is drawn ONCE and belongs |
//|  to the HIGHEST ticked PO3 number that lands on it, taking that  |
//|  number's colour and label. That is the sheet's own rule, "The   |
//|  higher the power, stronger the level". Gold at 4374 divides by  |
//|  every number from 3 to 2187, so it is labelled 2187.            |
//|                                                                  |
//|  It also counts candles from the market open and marks the kihon |
//|  suchi numbers on that count - time levels the way the grid is   |
//|  price levels. The numbers, and why each one is what it is, are  |
//|  set out in the KIHON SUCHI section below, which was a separate  |
//|  PO3_Kihon.mqh until the indicator that shared it was removed.   |
//|  The panel counts the same open on H1, M30, M15, M5 and M1 at    |
//|  once, so the timeframes can be read against each other.         |
//|  Nothing here acts on those numbers; they mark where a turn is   |
//|  due, not that one is happening.                                 |
//|                                                                  |
//|  When an H4 or an H1 count lands ON a kihon number - a lime row  |
//|  in that panel - the candle carrying the number is itself a      |
//|  kihon candle, and a second block standing beside the panel      |
//|  counts the candles inside it - M15, M5 and M1, as many of them  |
//|  as can reach a kihon number in the time there is, and every one |
//|  of them counted from that candle's own open. That gives the     |
//|  hour a turn is due in a finer count to place it in, rather than |
//|  leaving it as one bar.                                          |
//|                                                                  |
//|  A third block beside those two turns the counts into a          |
//|  timetable. Where the first says where the count stands and the  |
//|  second where it stands inside the candle, this one says WHEN -  |
//|  the clock time each kihon suchi candle of the week opens at, on |
//|  D1, H4, H1, M30 and M15 counted from the week open, and then    |
//|  the ones still in front of you today on H1, M30 and M15. Both   |
//|  lists are held to the numbers 9 to 33, which are the ones a     |
//|  week of those timeframes can actually reach. Times read off     |
//|  real bars where the bars exist; a ~ marks the ones ahead, which |
//|  are projected and skip the weekend but not a broker's daily     |
//|  break.                                                          |
//|                                                                  |
//|  That block reads in a fixed offset from UTC rather than in the  |
//|  broker's clock, +10 by default, and on the 12-hour clock - the  |
//|  one part of the chart whose times are meant to be copied into   |
//|  a diary, so the one part written the way a diary is. The        |
//|  offset is display only: which candle carries a number, and      |
//|  whether it is done, NOW or due, are worked out from the         |
//|  broker's own clock and do not move with it.                     |
//|                                                                  |
//|  It also draws the UNRAIDED LIQUIDITY - the swing highs and      |
//|  lows price has not yet traded back through - as a line from     |
//|  the tip of each wick to the right edge, light blue for highs    |
//|  and purple for lows. A line goes the moment price takes its     |
//|  level out. A swing is fractal-style, 6 candles each side by     |
//|  default, on the chart's timeframe or on one locked timeframe.   |
//|  The last raided high and low stay, dashed, from the wick to    |
//|  the candle that took them out.                                  |
//|  The UNRAIDED LIQUIDITY section below sets out the rules.        |
//|                                                                  |
//|  And it shades the UNMITIGATED FAIR VALUE GAPS - three-candle    |
//|  imbalances price has not yet traded back through - as a box     |
//|  from the middle candle to the right edge, dark green for        |
//|  bullish and dark red for bearish, over the last 200 candles of  |
//|  the chart's timeframe or of one locked timeframe. A box goes    |
//|  the moment price fills it. The FAIR VALUE GAPS section below    |
//|  sets out the rules.                                             |
//|                                                                  |
//|  The three kihon blocks - count, segments, schedule - each have  |
//|  a button in a row at the bottom left of the chart, so a block   |
//|  can be hidden and brought back with one click instead of a trip |
//|  to the properties dialog. All three start hidden; the schedule  |
//|  is the tall one.                                                |
//|                                                                  |
//|  Verified against the PO3 workbook's Gold sheet, 14 Mar 2025:    |
//|    2187  around 2900 -> 2799.36 .. 3083.67   (row 35, x128..141) |
//|    6561  around 2950 -> 2755.62 .. 3149.28   (row 39, x42..48)   |
//|   19683  around 2950 -> 2755.62 .. 3149.28   (row 40, x14..16)   |
//+------------------------------------------------------------------+
#property copyright "PO3 Levels"
#property version   "1.47"
//--- Shown in the Navigator and in the properties dialog. The indicator does
//--- two things now, and a name that says only "PO3 Levels" undersells half of
//--- it to anyone reading the list.
#property description "Power of Three support and resistance levels on gold, by checkbox from 1 to 19683."
#property description "Also counts candles from the year, month, week and day opens and marks the"
#property description "Ichimoku kihon suchi numbers on that count, and times the ones this week"
#property description "still has to come, and draws the unraided swing highs and lows as liquidity"
#property description "lines, and shades the fair value gaps price has not yet filled. Draws only -"
#property description "places no orders."
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//+------------------------------------------------------------------+
//|  KIHON SUCHI - Ichimoku's basic time numbers, and the candle     |
//|  count they are read against. This section was PO3_Kihon.mqh     |
//|  until the indicator that shared it was removed.                 |
//|                                                                  |
//|  The count is inclusive at both ends: the candle you start from  |
//|  is candle 1, not candle 0. That one convention is the whole of  |
//|  the arithmetic below, so it is worth stating plainly. Two       |
//|  17-spans laid end to end do not make 34, because the last       |
//|  candle of the first span IS the first candle of the second:     |
//|  17 + 17 - 1 = 33. Every compound number is built that way, by   |
//|  chaining simple spans that share their turning candle.          |
//|                                                                  |
//|  THE SIMPLE NUMBERS (tanjun kihon suchi) - 9, 17, 26             |
//|                                                                  |
//|    9   ichi-moku, the span the Tenkan is built on                |
//|    17  9 + 9 - 1                                                 |
//|    26  GIVEN, not derived. The Kijun span and the cloud          |
//|        displacement, and historically a month of trading days    |
//|        under the six-day week Japan kept when this was written.  |
//|        It is the one number the overlap rule does not produce -  |
//|        see the note below.                                       |
//|                                                                  |
//|  THE COMPOUND NUMBERS (fukugo kihon suchi)                       |
//|                                                                  |
//|    33   17 + 17 - 1                                              |
//|    42   26 + 17 - 1                                              |
//|    51   26 + 26 - 1                                              |
//|    65   33 + 33 - 1        (four 17s chained)                    |
//|    76   26 + 26 + 26 - 2   (also 51 + 26 - 1)                    |
//|    129  65 + 65 - 1                                              |
//|    172  65 + 42 + 42 + 26 - 3                                    |
//|    226  76 + 76 + 76 - 2                                         |
//|    257  129 + 129 - 1                                            |
//|                                                                  |
//|  26 is the exception, not 172. Every compound above chains       |
//|  simple spans sharing a candle, so k spans subtract k-1. 26 does |
//|  not come out that way: three 9s chained give 9+9+9-2 = 25, and  |
//|  17+9-1 is 25 as well. Reaching 26 needs either a plain 9+17     |
//|  with no shared candle or 9+9+9-1 with one overlap too few, and  |
//|  neither is the rule. That is expected - 26 is one of the three  |
//|  SIMPLE numbers, and a simple number is a given, not a result.   |
//|  It is a calendar figure that the rule then builds on.           |
//|                                                                  |
//|  An earlier version of this file claimed 172 was the outlier and |
//|  wrote it as the plain sum 65 + 65 + 42. That sum is right, but  |
//|  172 chains perfectly well as 65 + 42 + 42 + 26 - 3: four spans, |
//|  three shared candles. 172 obeys the rule. 26 is the one that    |
//|  does not, and it is the one that never claimed to.              |
//|                                                                  |
//|  Above 257 the series keeps doubling - 257 + 257 - 1 = 513 - but |
//|  a number that large has no meaning on an intraday chart, where  |
//|  even 257 M1 candles is only a little over four hours. The list  |
//|  stops where the classical one stops.                            |
//|                                                                  |
//|  What the numbers are FOR: they are candidate turning points in  |
//|  time, not in price. Counting from a swing, or from the session  |
//|  open, candle 9, 17, 26, 33 and so on are where a move is due to |
//|  change character. They say nothing about direction. Read them   |
//|  against the PO3 grid in PO3_Core.mqh: a kihon suchi candle      |
//|  landing on a 27 or 81 level is time and price agreeing, which   |
//|  is the only reason both files are in this project.              |
//|                                                                  |
//|  This was a separate header while a second indicator shared it.  |
//|  That indicator is gone, so it lives here instead: one file to   |
//|  copy into MQL5/Indicators and compile, with no second file to   |
//|  keep in step with it. PO3_Core.mqh is still separate, because   |
//|  the EA genuinely does share it.                                 |
//+------------------------------------------------------------------+
//--- 3 simple + 9 compound. The simple ones come first and the whole list is
//--- ascending, so a scan can stop early and the first KIHON_SIMPLE entries
//--- are exactly the simple numbers.
#define KIHON_SIMPLE   3
#define KIHON_COUNT    12

const int KihonNumbers[KIHON_COUNT] =
  {
   9, 17, 26,                                   // simple
   33, 42, 51, 65, 76, 129, 172, 226, 257       // compound
  };

//+------------------------------------------------------------------+
//| Is n a kihon suchi number, and which kind.                       |
//|                                                                  |
//| The compound flag is a filter, not a separate list: pass false   |
//| and only 9, 17 and 26 answer true, which is the quiet chart.     |
//+------------------------------------------------------------------+
bool KihonIs(const int n, const bool withCompound = true)
  {
   int last = withCompound ? KIHON_COUNT : KIHON_SIMPLE;
   for(int i = 0; i < last; i++)
     {
      if(KihonNumbers[i] == n)
         return(true);
      if(KihonNumbers[i] > n)               // ascending, so no point going on
         break;
     }
   return(false);
  }

//--- a number is simple when it is one of the first KIHON_SIMPLE entries
bool KihonIsSimple(const int n)
  {
   return(KihonIs(n, false));
  }

//+------------------------------------------------------------------+
//| The next kihon suchi number strictly above n, or 0 past the end. |
//|                                                                  |
//| Strictly above, so standing ON 26 tells you 33 is next rather    |
//| than repeating the number you are already on.                    |
//+------------------------------------------------------------------+
int KihonNext(const int n, const bool withCompound = true)
  {
   int last = withCompound ? KIHON_COUNT : KIHON_SIMPLE;
   for(int i = 0; i < last; i++)
      if(KihonNumbers[i] > n)
         return(KihonNumbers[i]);
   return(0);
  }

//--- the last kihon suchi number at or below n, or 0 below the first
int KihonAtOrBelow(const int n, const bool withCompound = true)
  {
   int last = withCompound ? KIHON_COUNT : KIHON_SIMPLE;
   int best = 0;
   for(int i = 0; i < last; i++)
      if(KihonNumbers[i] <= n)
         best = KihonNumbers[i];
      else
         break;
   return(best);
  }

//+------------------------------------------------------------------+
//| Signed distance from n to the NEAREST kihon suchi number.        |
//|                                                                  |
//| 0 means n is one. Negative means the number is still ahead: 7    |
//| returns -2, two candles short of 9. Positive means it has just   |
//| gone by: 11 returns +2, two candles past 9.                      |
//|                                                                  |
//| The sign convention is n minus the number, so it reads the way   |
//| the chart does - a count running up towards a level shows a      |
//| negative gap closing to zero, then goes positive as it leaves.   |
//|                                                                  |
//| Nearest, not next, because either side matters. A count two      |
//| candles PAST 26 is as much "around 26" as one two candles short  |
//| of it, and a turn that was due at 26 is not cancelled by the     |
//| candle after it.                                                 |
//+------------------------------------------------------------------+
int KihonOffset(const int n, const bool withCompound = true)
  {
   int last = withCompound ? KIHON_COUNT : KIHON_SIMPLE;
   int best = n - KihonNumbers[0];

   for(int i = 1; i < last; i++)
     {
      int d  = n - KihonNumbers[i];
      int ad = (d    < 0) ? -d    : d;
      int ab = (best < 0) ? -best : best;
      if(ad < ab)
         best = d;
     }
   return(best);
  }

//+------------------------------------------------------------------+
//| Where the candle count starts.                                   |
//+------------------------------------------------------------------+
enum ENUM_KIHON_ANCHOR
  {
   KIHON_ANCHOR_DAY   = 0,  // Day open (the D1 candle)
   KIHON_ANCHOR_WEEK  = 1,  // Week open
   KIHON_ANCHOR_MONTH = 2,  // Month open (the 1st)
   KIHON_ANCHOR_YEAR  = 3,  // Year open (1 January)
   KIHON_ANCHOR_TIME  = 4   // Custom time of day (server)
  };

//--- Ceiling on how many candles a count will chase. Past 257 every count
//--- reads the same - there is no kihon number above it - so an exact figure
//--- buys nothing, while getting one forces the history to load: a year anchor
//--- on M1 is a third of a million candles, asked for once a second by the
//--- panel. Beyond this the count reports "too far" instead. Deliberately far
//--- above 257 so a legitimate deep count, a week of M1 at around 7200, is
//--- still counted exactly.
#define KIHON_SPAN_CAP  20000

//+------------------------------------------------------------------+
//| Midnight on the first day of the current server month, or of     |
//| the current server year.                                         |
//|                                                                  |
//| Built from the calendar rather than from a bar. There is no      |
//| yearly candle to read a year off, and the monthly candle would   |
//| only tell you what the calendar already does. Counts against     |
//| these therefore start at the first candle that OPENS inside the  |
//| period: a weekly candle straddling New Year belongs to the old   |
//| year, which is the same rule the day and week anchors follow.    |
//+------------------------------------------------------------------+
datetime KihonPeriodOpen(const bool year)
  {
   MqlDateTime st;
   TimeToStruct(TimeCurrent(), st);

   if(year)
      st.mon = 1;
   st.day  = 1;
   st.hour = 0;
   st.min  = 0;
   st.sec  = 0;

   //--- day_of_week and day_of_year are ignored by StructToTime, so the
   //--- stale values left in the struct cannot move the result
   return(StructToTime(st));
  }

//+------------------------------------------------------------------+
//| The time the count starts from.                                  |
//|                                                                  |
//| Day and week open come from the D1 and W1 bars themselves, so    |
//| they follow the broker's own day boundary rather than a guess at |
//| it - on a five-decimal broker rolling at 00:00 server that is    |
//| midnight, on a New York close broker it is not, and the bar      |
//| knows which.                                                     |
//|                                                                  |
//| A custom time is today's date at that hour and minute, rolled    |
//| back a day if it has not come round yet, and then CLAMPED to the |
//| day open. The clamp is the part worth explaining: without it, an |
//| 08:00 London anchor read at 03:00 on Monday would roll back to   |
//| 08:00 on FRIDAY and count the whole weekend gap. Clamping means  |
//| a session anchor never counts across a day boundary - before     |
//| the session opens you get the count from the day open, and the   |
//| moment it opens the count restarts from there.                   |
//+------------------------------------------------------------------+
datetime KihonAnchor(const string sym, const ENUM_KIHON_ANCHOR mode,
                     const int hour = 0, const int minute = 0)
  {
   datetime day = iTime(sym, PERIOD_D1, 0);

   if(mode == KIHON_ANCHOR_WEEK)
      return(iTime(sym, PERIOD_W1, 0));
   if(mode == KIHON_ANCHOR_MONTH)
      return(KihonPeriodOpen(false));
   if(mode == KIHON_ANCHOR_YEAR)
      return(KihonPeriodOpen(true));
   if(mode == KIHON_ANCHOR_DAY || day == 0)
      return(day);

   //--- Midnight of the current server day, then the wanted time of day. The
   //--- arithmetic is done in long rather than on datetime: a datetime is
   //--- unsigned, so an intermediate that goes below zero would wrap to the
   //--- far end of the epoch instead of clamping.
   long now = (long)TimeCurrent();
   long mid = now - (now % 86400);
   long h   = (hour   < 0) ? 0 : (hour   > 23 ? 23 : hour);
   long m   = (minute < 0) ? 0 : (minute > 59 ? 59 : minute);
   long at  = mid + h * 3600 + m * 60;

   if(at > now)
      at -= 86400;                    // that time of day has not come round yet

   return((datetime)at < day ? day : (datetime)at);
  }

//+------------------------------------------------------------------+
//| How many candles of this timeframe have printed since the        |
//| anchor, on the inclusive rule: the candle at the anchor is 1, so |
//| the developing candle carries the number this returns. Bar       |
//| indices run unbroken, so candle 1 sits at shift (count - 1).     |
//|                                                                  |
//| Returns 0 when the answer is not known yet - history still       |
//| loading, or the anchor older than the bars this chart holds -    |
//| so a caller can tell "nothing to show" from "candle zero", which |
//| does not exist under inclusive counting. Returns -1 when the     |
//| anchor is further back than KIHON_SPAN_CAP periods, which is a   |
//| refusal rather than a failure: the count is knowable, it is just |
//| not worth the history load to know it exactly.                   |
//|                                                                  |
//| Bars() over the window rather than iBarShift() on the anchor.    |
//| The difference shows up whenever the anchor lands in a gap: a    |
//| day opening at 00:00 whose first M1 candle is 00:01 has no       |
//| candle at the anchor, and iBarShift with exact=false answers     |
//| with the nearest EARLIER bar, which is last night's close. That  |
//| would put candle 1 on the wrong side of the open and shift every |
//| kihon mark by one. Bars() counts open times inside the window,   |
//| so a candle before the anchor is simply not in it.               |
//+------------------------------------------------------------------+
int KihonCount(const string sym, const ENUM_TIMEFRAMES tf, const datetime anchor)
  {
   if(anchor <= 0)
      return(0);

   datetime cur = iTime(sym, tf, 0);
   if(cur == 0)
      return(0);                       // history not ready on this timeframe
   if(anchor >= cur)
      return(1);                       // anchor falls inside the developing candle

   //--- Estimate the span before asking for the bars. Bars() over a window
   //--- this side of the cap is cheap; over a year of M1 it drags that whole
   //--- history in. The estimate is from elapsed time, so it ignores weekends
   //--- and overstates - which is the safe direction for a cost guard.
   int secs = PeriodSeconds(tf);
   if(secs > 0 && ((long)TimeCurrent() - (long)anchor) / secs > KIHON_SPAN_CAP)
      return(-1);

   //--- inclusive of both ends, and the developing candle's open time is
   //--- always at or before now, so it is the last one counted
   int n = Bars(sym, tf, anchor, TimeCurrent());
   return(n > 0 ? n : 0);
  }

//+------------------------------------------------------------------+
//| Where the current nested count restarts.                         |
//|                                                                  |
//| A count can be run inside another one: count H1 candles from the |
//| day open, and start the M1 count over at every H1 candle that is |
//| itself a kihon suchi number. Within one day that puts the resets |
//| at H1 candle 1, 9 and 17 - 26 needs a longer day than there is.  |
//| The finer count then answers "how far into this phase of the     |
//| session are we", instead of a number that only grows.            |
//|                                                                  |
//| Returns the open time of the candle the finer count restarts at, |
//| and sets segNo to that candle's number in the coarse count. Zero |
//| and segNo 0 when the coarse count is not known yet.              |
//|                                                                  |
//| Note that the reset happens AT the kihon candle, not after it:   |
//| on H1 candle 9 the segment starts at that same candle's open, so |
//| the M1 count reads 1 as the ninth hour opens.                    |
//+------------------------------------------------------------------+
datetime KihonSegmentStart(const string sym, const ENUM_TIMEFRAMES tf,
                           const datetime anchor, const bool withCompound,
                           int &segNo)
  {
   segNo = 0;

   int c = KihonCount(sym, tf, anchor);
   if(c <= 0)
      return(0);

   //--- Below the first kihon number the segment is the whole span so far, so
   //--- it starts at candle 1 - the anchor candle itself.
   segNo = KihonAtOrBelow(c, withCompound);
   if(segNo < 1)
      segNo = 1;

   //--- candle number segNo sits this far back from the developing candle
   return(iTime(sym, tf, c - segNo));
  }

//+------------------------------------------------------------------+
//| THE TIMETABLE: WHEN THE NUMBERS FALL                             |
//|                                                                  |
//| Everything above answers where a count has got to. What follows  |
//| answers when it arrives, which is the part a plan is made        |
//| against: a count reading 14 says 17 is due, not that 17 opens at |
//| 16:00, and 16:00 is what goes in a diary.                        |
//|                                                                  |
//| Here rather than in the indicator because two programs now need  |
//| it - the panel that draws the timetable and the mailer that      |
//| sends it - and a projection walk kept in two copies is a         |
//| projection walk that will eventually disagree with itself. Same  |
//| reason the numbers themselves are here.                          |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| A timeframe's short name, "M15" rather than "PERIOD_M15".        |
//|                                                                  |
//| Here because every program that prints a kihon count prints the  |
//| timeframe it counted on beside it.                               |
//+------------------------------------------------------------------+
string TfNameOf(const ENUM_TIMEFRAMES tf)
  {
   return(StringSubstr(EnumToString(tf), 7));
  }

//--- The week ladder, coarse to fine. All five rows count from the SAME
//--- anchor, the week open, so their times can be read against each other: a
//--- 16:00 on the H4 row and a 16:00 on the M30 row are one instant, and two
//--- timeframes turning together there is the agreement the panel is for.
//---
//--- D1 is in the list knowing full well where its numbers land. A trading
//--- week holds five D1 candles, so D1 9 is the middle of NEXT week and D1 33
//--- over a month out. They are listed anyway, as projections: the D1 count is
//--- genuinely running from this week's open, and where it arrives is worth
//--- knowing even when the answer is "not in this week".
const ENUM_TIMEFRAMES g_schWeek[5] = { PERIOD_D1,  PERIOD_H4, PERIOD_H1,
                                       PERIOD_M30, PERIOD_M15 };

//--- The intraday ladder. H4 is not in it: six H4 candles fit in a trading day,
//--- so the first number it can reach is days away and belongs to the week list
//--- above. H1 reaches 17 within a day, M30 reaches 33 and M15 clears the whole
//--- window, which is why the groups are different lengths.
const ENUM_TIMEFRAMES g_schDay[3]  = { PERIOD_H1, PERIOD_M30, PERIOD_M15 };

//--- The window of numbers the schedule lists, inclusive: 9, 17, 26, 33. Past
//--- 33 a week of any of these timeframes cannot reach the next number - 42 H4
//--- candles is seven trading days - so every further row would be a date in a
//--- later week sitting under this week's heading. With the compounds switched
//--- off the window ends at 26 instead, since 33 is one of them.
#define SCH_FIRST   9
#define SCH_LAST   33

//--- MqlDateTime.day_of_week is 0 for Sunday, so the table is indexed off it
//--- directly.
const string g_schDow[7] = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };

//+------------------------------------------------------------------+
//| Does this symbol trade at all on that weekday.                   |
//|                                                                  |
//| Asked of the symbol rather than assumed, because "the weekend"   |
//| is not the same two days everywhere: a broker quoting from       |
//| Sunday evening has real Sunday candles, and a rule that pushed   |
//| them to Monday would put every projection out by the length of   |
//| that session.                                                    |
//|                                                                  |
//| Session 0 is the first of the day, so a day with no session at   |
//| all answers false - which is the question. A symbol whose        |
//| session table cannot be read answers false on every day, and the |
//| fallback then gives the ordinary Monday-to-Friday week, so the   |
//| two cases need no telling apart.                                 |
//+------------------------------------------------------------------+
bool SchedTradingDay(const string sym, const int dow)
  {
   datetime from = 0, to = 0;

   if(SymbolInfoSessionTrade(sym, (ENUM_DAY_OF_WEEK)dow, 0, from, to))
      return(true);

   return(dow != 0 && dow != 6);
  }

//+------------------------------------------------------------------+
//| Where a candle that has not opened yet will open.                |
//|                                                                  |
//| Stepped one period at a time rather than multiplied out, because |
//| of the closed days: no timeframe carries candles through one, so |
//| a step landing in one is pushed on a whole day at a time until   |
//| it clears. Whole days, so the time of day survives the skip - a  |
//| D1 candle stays at midnight, an H1 on the hour.                  |
//|                                                                  |
//| It is an ESTIMATE, and every row built on one says so with a ~.  |
//| The closed days it handles; the daily maintenance break a broker |
//| takes it does not, so an intraday projection crossing several    |
//| days drifts by roughly that break per day crossed. Which is why  |
//| times are read off real bars wherever the bars exist and this is |
//| asked only about the part of the ladder still in front.          |
//+------------------------------------------------------------------+
datetime SchedProject(const string sym, const datetime from,
                      const int steps, const int secs)
  {
   if(from <= 0 || steps <= 0 || secs <= 0)
      return(from);

   //--- long rather than datetime: the arithmetic is plain addition either
   //--- way, but datetime is unsigned and an intermediate that went below zero
   //--- would wrap to the far end of the epoch instead of staying wrong in an
   //--- obvious way.
   long        t = (long)from;
   MqlDateTime st;

   for(int i = 0; i < steps; i++)
     {
      t += secs;

      //--- A stretch of closed days is at most two on any normal calendar, so
      //--- three turns is one more than this can need. The spare turn is what
      //--- stops a symbol that claims to trade on no day at all from spinning
      //--- the loop for ever.
      for(int skip = 0; skip < 3; skip++)
        {
         TimeToStruct((datetime)t, st);
         if(SchedTradingDay(sym, st.day_of_week))
            break;
         t += 86400;
        }
     }

   return((datetime)t);
  }

enum ENUM_LIQ_RAID
  {
   LIQ_RAID_WICK  = 0,   // Wick trades through the level
   LIQ_RAID_CLOSE = 1    // A candle closes through the level
  };

//--- How far price has to trade back into a fair value gap before it is
//--- mitigated and its box goes. Read off wicks, so it lands on the live candle.
enum ENUM_FVG_MIT
  {
   FVG_MIT_FULL  = 0,   // Price trades through the whole gap
   FVG_MIT_HALF  = 1,   // Price reaches the middle of the gap
   FVG_MIT_TOUCH = 2    // Price trades into the gap at all
  };

input group "Grid";
input double InpScale     = 1.0;   // Scale divisor (1 = whole numbers, 100 = workbook 2dp)
input int    InpEachSide  = 3;     // Levels each side of price
//--- The fine grids sit within a few dollars of price, which is exactly where
//--- the candles are. Drawn behind them they are invisible at the one place
//--- they matter, so the default is in front. Set true for the older look.
input bool   InpLinesBehind = false; // Draw lines behind the candles

input group "Labels";
input bool   InpShowLabels  = true; // Write the PO3 number on each line
//--- The default of 3 also leaves the optional 1 grid unlabelled, which is
//--- what you want: its levels are a dollar apart and a column of 1s on top of
//--- each other says nothing the line spacing does not.
input int    InpLabelMinPO3 = 3;    // Label only levels of PO3 >= this (1 to label the 1 grid)
input int    InpFontSize    = 7;    // Label text size
input int    InpLabelShift  = 0;    // Label shift right, in bars (0 = at the last bar)

input group "Candle countdown";
//--- The countdown rides the developing candle rather than sitting in a corner,
//--- so the time left is read in the same glance as the candle it belongs to.
//--- It is anchored to that candle's time and to the current price, so it
//--- travels with both. See UpdateClock.
input bool   InpShowClock   = true;         // Show time left on the current candle
input int    InpClockShift  = 1;            // Bars right of the developing candle (0 = beside it)
input int    InpClockGapPts = 0;            // Vertical offset from price, in points (+ up)
input int    InpClockSize   = 8;            // Text size
input color  InpClockColor  = clrLime;      // Text colour

input group "Session timer";
//--- Wall-clock time this chart has been open, for capping screen time. It
//--- starts when the indicator loads and survives a timeframe or input change;
//--- only reloading the indicator or the chart resets it. See OnInit / OnDeinit.
input bool             InpShowSession    = true;                 // Show time spent on this chart
input ENUM_BASE_CORNER InpSessionCorner  = CORNER_RIGHT_UPPER;   // Corner
input int              InpSessionX       = 12;                   // Distance from corner, X
input int              InpSessionY       = 40;                   // Distance from corner, Y
input int              InpSessionSize    = 10;                   // Text size
input color            InpSessionColor   = clrSilver;            // Text colour
input int              InpSessionLimitMin = 0;                   // Minutes on chart before it turns red (0 = off)
input color            InpSessionOverColor = clrTomato;          // Text colour once over the limit

input group "Candle count";
//--- Ichimoku's counting rule, not a zero-based index: the candle the count
//--- starts on is candle 1, so a 26 count spans 26 candles inclusive. That is
//--- what makes the compound numbers overlap by one. See the KIHON SUCHI
//--- section at the top of this file.
//---
//--- The anchor set here feeds both the on-chart marks and the panel, so the
//--- two can never disagree about where the count started. Each has its own
//--- show/hide switch below.
input bool              InpShowCount   = true;              // Draw the count on the chart
input ENUM_KIHON_ANCHOR InpCountAnchor = KIHON_ANCHOR_DAY;  // Count from
input int               InpAnchorHour  = 8;                 // Custom anchor, hour (server)
input int               InpAnchorMin   = 0;                 // Custom anchor, minute (server)
input bool              InpMarkOpen    = true;              // Line on the candle the count starts at
input color             InpOpenColor   = clrDimGray;        // Open line colour

input group "Kihon suchi";
//--- The numbers are time levels the way the PO3 grid is price levels. Marked
//--- on the chart timeframe only; the panel below carries the rest.
//---
//--- Three colour bands, not two. The old split was simple against compound,
//--- which put 33 in with 257 - true to the arithmetic and wrong on the chart,
//--- because a marker's colour is read as how much weight to give it and those
//--- two are nothing like each other in practice.
//---
//--- 9, 17, 26 and 33 are the band that carries the reading. They are the only
//--- numbers a week of the timeframes on this chart can actually reach, which
//--- is the same reason the schedule panel stops at 33 - see SCH_LAST. 42 and
//--- up still mark, and still mean what they mean, but in a recessive colour
//--- so they read as the background series they are rather than competing with
//--- the four that matter.
input bool  InpMarkKihon     = true;             // Mark the kihon suchi candles
input bool  InpKihonCompound = true;             // Include the compound numbers (33 and up)
input bool  InpKihonLines    = true;             // Vertical line on each marked candle
input color InpKihonSimple   = clrDeepSkyBlue;   // 9, 17, 26      - colour
input color InpKihonComp     = clrMediumOrchid;  // 33             - colour
input color InpKihonFar      = clrDarkGreen;     // 42 and up      - colour
input int   InpKihonSize     = 8;                // Marker text size
input int   InpKihonGapPts   = 0;                // Marker offset from the candle low, in points
input bool  InpNumberAll     = false;            // Number every candle, not just the kihon ones

input group "Candle count panel";
//--- A ladder of calendar periods, each counted in the candles that divide it:
//--- the year in months, weeks and days; the month in days, H4s and H1s;
//--- the week the same ladder on down to M30; the day from H1 down to M1. Every
//--- block carries its own anchor. What you read for is agreement - one row on
//--- a kihon number is a small turn due, several blocks landing together is a
//--- bigger one.
input bool             InpShowPanel   = false;              // Show the count panel
input bool             InpShowYear    = true;               // Year block    - MN1, W1, D1
input bool             InpShowMonth   = true;               // Month block   - D1, H4, H1
input bool             InpShowWeek    = true;               // Week block    - H4, H1, M30
input bool             InpShowDay     = true;               // Day block     - H1, M30, M15, M5, M1
//--- Mid left. The vertical centre is worked out from the chart height and the
//--- number of rows rather than set as a fixed Y, because both change - the day
//--- block grows and shrinks with the chart period, and a Y that centred a
//--- 19-row panel would sit low on a 13-row one.
input ENUM_BASE_CORNER InpPanelCorner = CORNER_LEFT_UPPER;  // Corner
input bool             InpPanelMiddle = true;               // Centre it vertically (ignores Y)
input int              InpPanelX      = 12;                 // Distance from corner, X
input int              InpPanelY      = 20;                 // Distance from corner, Y (when not centred)
input int              InpPanelSize   = 9;                  // Text size

//--- A solid block behind the rows. Over candles, unbacked text is legible
//--- only where the chart happens to be empty, which is not something you can
//--- rely on while reading a count.
input bool             InpPanelBox    = true;               // Solid block behind the panel
input color            InpPanelBg     = C'18,18,24';        // Block colour
input color            InpPanelBorder = clrDimGray;         // Block border colour
input color            InpPanelColor  = clrSilver;          // Text colour
input color            InpPanelHit    = clrLime;            // Colour of a row standing ON a kihon number
input color            InpPanelNear   = clrOrange;          // Colour of a row within reach of one
input int              InpPanelNearTol = 2;                 // How many candles either side counts as near

input group "Kihon segment panel";
//--- The second block, standing beside the count panel, and the only place a
//--- count is nested inside a candle rather than run across a calendar period.
//--- When the H4 or H1 count stands ON a kihon number, the candle carrying that
//--- number is a kihon candle, so the minutes inside it are worth counting in
//--- their own right: M15, M5 and M1 from that candle's open, marked against
//--- the numbers the same way every other row is. Only the rows that can reach
//--- a number appear, which is why an H4 gets M15 and an H1 does not.
//---
//--- Every figure in the block is measured from the candle it heads, and none
//--- from a day, week or month open. The calendar anchors decide whether the
//--- block opens and take no further part: inside it the question is only how
//--- far into THIS H4, or THIS H1, the market has come. The counts against the
//--- calendar are the panel beside it, which carries them in full.
//---
//--- It sits BESIDE the count panel rather than in a corner of its own: same
//--- corner, same top edge, one gap further along, in its own block. So it has
//--- no position inputs - it follows the panel above wherever that is put, and
//--- the only thing to set is how far apart the two blocks stand. Its X comes
//--- from the MEASURED width of the count panel, so the two cannot overlap
//--- whatever the rows happen to say.
//---
//--- Colours and text size come from the panel group above too, so the two read
//--- as one instrument in three blocks - the schedule panel past it takes
//--- them from the same place.
input bool  InpShowSeg = false;  // Show the kihon segment panel
input bool  InpSegH4   = true;   // Segments inside a kihon H4 candle
input bool  InpSegH1   = true;   // Segments inside a kihon H1 candle
input int   InpSegGap  = 8;      // Gap between the two blocks, in pixels

input group "Kihon schedule panel";
//--- The third block, standing beside the segment panel, and the only one that
//--- answers WHEN rather than where. The two blocks before it read the counts
//--- as they stand; this one reads the clock those counts arrive on.
//---
//--- The week list is every kihon suchi candle of this week from D1 down to
//--- M15, all five counted from the same week open so their times can be read
//--- against each other - an H4 and an M30 landing on 16:00 together is two
//--- timeframes turning at one instant, which is the agreement the whole panel
//--- is for. It shows the numbers that have been and gone as well as the ones
//--- still ahead, because "all of this week's" is what makes it a timetable
//--- rather than a countdown.
//---
//--- The today list is the other half: only what is still in front, on H1, M30
//--- and M15, and only the candles that open before the day is out.
//---
//--- Both are held to the numbers 9 to 33. Past 33 a week of any of these
//--- timeframes cannot reach the next number, so every further row would be a
//--- date in a later week sitting under this week's heading.
//---
//--- Like the segment panel it has no position inputs - same corner, same top
//--- edge, one gap further along - so the only thing to set is how far it
//--- stands from the block before it. Colours and text size come from the
//--- count panel group, so all three read as one instrument in three blocks.
input bool  InpShowSched = false;  // Show the kihon schedule panel
input bool  InpSchedWeek = true;   // This week's kihon candles, D1 down to M15
input bool  InpSchedDay  = true;   // Still ahead today, H1 down to M15
//--- The today list is held to 9-33 like the week list above, and on the finer
//--- timeframes that window is spent early: M30 passes 33 by mid-morning and
//--- M15 well before that, after which the section reads "none" for the rest of
//--- the session. Tick this to let it run to whatever number each timeframe can
//--- still reach before the day is out - M15 to 76, M30 to 42, H1 to 17 - which
//--- keeps it saying something all day at the cost of a longer block.
input bool  InpSchedDayAll = false; // ... and past 33, as far as the day reaches
input int   InpSchedGap  = 8;      // Gap from the block before it, in pixels
//--- The times are the broker's by default, which is the clock the chart is
//--- drawn in but rarely the one a diary is kept in. Tick this and the block
//--- reads in a fixed offset from UTC instead - 10 for Papua New Guinea, which
//--- keeps no daylight saving, so a fixed offset is the whole of the rule
//--- there. The offset is applied to the DISPLAY only: which candle carries a
//--- number, and whether it is done, NOW or due, are worked out from the
//--- broker's own clock and do not move.
input bool   InpSchedTz      = true;   // Show the times in a fixed UTC offset
input double InpSchedTzHours = 10.0;   // ... that offset, in hours (10 = PNG)
//--- Half-hour and quarter-hour zones exist - India is 5.5, Chatham 12.75 - so
//--- this is hours as a decimal rather than a whole number.
input bool   InpSchedTzBoth  = false;  // ... and keep the server time beside it
//--- The 12-hour clock for the timetable, which is the block whose times get
//--- written into a diary. The count and segment blocks are unaffected: they
//--- print period opens, not appointments, and 00:00 there is a label on an
//--- anchor rather than a time anyone reads off and acts on.
input bool   InpSchedAmPm    = true;   // Write the times as AM / PM, not 24-hour

input group "Kihon panel buttons";
//--- One click shows or hides a block, without opening the properties dialog.
//--- All three blocks start hidden - the schedule alone is taller than most
//--- charts have room for - and a click brings back the one wanted.
//--- The three "Show the ..." inputs above set how each block starts; the
//--- buttons flip it from there, and the choice survives a timeframe change.
//--- Changing the inputs, or re-adding the indicator, goes back to them.
//---
//--- Bottom left by default: the panel sits mid left and the session timer top
//--- right, so the corner is otherwise empty.
input bool             InpShowButtons  = true;               // Show the Count / Segments / Schedule buttons
input ENUM_BASE_CORNER InpButtonCorner = CORNER_LEFT_LOWER;  // Corner
input int              InpButtonX      = 12;                 // Distance from corner, X
input int              InpButtonY      = 12;                 // Distance from corner, Y

input group "Unraided liquidity";
//--- Swing highs and lows that price has not yet traded through, drawn from
//--- the wick to the right edge. A swing is a fractal with a wider window:
//--- above (below) the candles either side of it. The timeframe follows the
//--- chart unless locked. See the UNRAIDED LIQUIDITY section for the rules.
input bool            InpShowLiq      = true;             // Show unraided liquidity
input ENUM_TIMEFRAMES InpLiqTF        = PERIOD_CURRENT;   // Timeframe (current = follow the chart)
input int             InpLiqLeft      = 6;                // Candles to the left of a swing
input int             InpLiqRight     = 6;                // Candles to the right of a swing
input int             InpLiqLookback  = 100;              // Candles of history to search
input ENUM_LIQ_RAID   InpLiqRaid      = LIQ_RAID_WICK;    // What counts as a raid
input bool            InpLiqHighs     = true;             // Show unraided highs
input bool            InpLiqLows      = true;             // Show unraided lows
input color           InpLiqHighColor = clrLightSkyBlue;  // Unraided highs - colour
input color           InpLiqLowColor  = clrMediumPurple;  // Unraided lows  - colour
input int             InpLiqWidth     = 2;                // Line width (styles other than solid need 1)
input ENUM_LINE_STYLE InpLiqStyle     = STYLE_SOLID;      // Line style
input bool            InpLiqSnap      = true;             // Locked higher TF: start at the chart candle with the wick
input bool            InpLiqLastRaid  = true;             // Show the last raided high and low (dashed, same width)
input bool            InpLiqValues    = true;             // Write the price beside each unraided / last raided swing
input string          InpLiqFont      = "Segoe UI Light"; // Price font (size follows the PO3 labels)

input group "Fair value gaps";
//--- Three-candle imbalances not yet filled, shaded from the middle candle to
//--- the right edge. The timeframe follows the chart unless locked, like the
//--- liquidity above. See the FAIR VALUE GAPS section for the rules.
//---
//--- The fills are dark on purpose. A box sits behind the candles and MT5
//--- gives it no transparency, so the colour is the only way to keep it from
//--- burying them - tuned, like the 1 grid, for a black chart. On a light
//--- background pick pale fills instead.
input bool            InpShowFvg      = true;              // Show unmitigated fair value gaps
input ENUM_TIMEFRAMES InpFvgTF        = PERIOD_CURRENT;    // Timeframe (current = follow the chart)
input int             InpFvgLookback  = 200;               // Candles of history to search
input ENUM_FVG_MIT    InpFvgMit       = FVG_MIT_FULL;      // What counts as mitigated
input int             InpFvgMinPts    = 0;                 // Smallest gap drawn, in points (0 = all)
input bool            InpFvgBull      = true;              // Show bullish gaps
input bool            InpFvgBear      = true;              // Show bearish gaps
input color           InpFvgBullColor = C'0,64,48';        // Bullish gaps - fill colour
input color           InpFvgBearColor = C'80,24,32';       // Bearish gaps - fill colour

input group "PO3 levels to show";
//--- Every grid from 3 up is on by default: the model is the whole nest of
//--- powers, and a level's strength is meant to be read from how many grids
//--- agree on it, which is only visible with all of them drawn. Untick the fine
//--- ones for a quieter chart; the levels that remain do not move.
//--- 3^0 = 1, the bottom of the ladder, and the one grid OFF by default. At
//--- scale 1 it is every whole number, so on gold it draws a line per dollar
//--- and the 3 grid's cells each get their two interior lines - the finest
//--- subdivision the model has, and more than a chart wants standing on it
//--- unasked. Tick it when the question is where inside a 3 cell price is.
//---
//--- M1 ONLY, on top of being off by default. Ticking it on any higher
//--- timeframe draws nothing, by the rule in OnInit rather than by anything in
//--- this input - a dollar grid is the size of an M1 candle and a rounding
//--- error to an H1 one. The Experts log says so on load rather than leaving a
//--- ticked box drawing nothing.
//---
//--- It is drawn very faint on purpose. MT5 gives an OBJ_HLINE no
//--- transparency, so faintness is the colour and nothing else - and since the
//--- colour IS the effect, it is tuned for a black chart: 48,48,48 is a near
//--- black that separates from the background by just enough to read as
//--- texture inside a 3 cell rather than as a level competing with it.
//---
//--- Below about 32 it stops resolving on most monitors and the grid is there
//--- in name only; above about 80 it starts arguing with the 3 grid it is
//--- meant to sit underneath. That is the usable band on black.
//---
//--- On a LIGHT background invert the thinking rather than nudging this: a
//--- near-black is the loudest line on a white chart, not the quietest, and
//--- the faint end there is a near-white like 220,220,220.
input bool  InpUse_1     = false;              // 1      - show (M1 only)
input color InpCol_1     = C'48,48,48';        // 1      - colour
input bool  InpUse_3     = true;               // 3      - show
input color InpCol_3     = clrGray;            // 3      - colour
input bool  InpUse_9     = true;               // 9      - show
input color InpCol_9     = clrDarkGray;        // 9      - colour
input bool  InpUse_27    = true;               // 27     - show
input color InpCol_27    = clrCadetBlue;       // 27     - colour
input bool  InpUse_81    = true;               // 81     - show
input color InpCol_81    = clrSteelBlue;       // 81     - colour
input bool  InpUse_243   = true;               // 243    - show
input color InpCol_243   = clrMediumSeaGreen;  // 243    - colour
input bool  InpUse_729   = true;               // 729    - show
input color InpCol_729   = clrDarkOrange;      // 729    - colour
input bool  InpUse_2187  = true;               // 2187   - show
input color InpCol_2187  = clrGoldenrod;       // 2187   - colour
input bool  InpUse_6561  = true;               // 6561   - show
input color InpCol_6561  = clrOrangeRed;       // 6561   - colour
input bool  InpUse_19683 = true;               // 19683  - show
input color InpCol_19683 = clrCrimson;         // 19683  - colour

#define PO3_PREFIX  "PO3_"
//--- Level lines and their labels share a sub-prefix so the redraw sweep can
//--- take them alone. The countdown is an OBJ_TEXT too, and a sweep by type
//--- over the whole prefix would delete it on every rebuild.
#define PO3_LEVEL   "PO3_L"
//--- Markers are swept and redrawn as a block whenever the count moves; the
//--- panel rows are rewritten in place. Separate sub-prefixes so the marker
//--- sweep cannot take the panel with it.
#define PO3_KMARK   "PO3_KM"
#define PO3_KPANEL  "PO3_KP"
//--- Its own prefix, not a suffix on the panel's: the two are swept
//--- independently, and "PO3_KP" as a prefix would take the segment panel with
//--- the main one every time the main one was rebuilt from scratch.
#define PO3_KSEG    "PO3_KS"
//--- And again for the third block. "PO3_KC" shares no prefix with the other
//--- three, so each panel's sweep takes only its own rows.
#define PO3_KSCHED  "PO3_KC"
//--- Unraided liquidity lines. "PO3_U" is no other sub-prefix's prefix, so
//--- the level and marker sweeps cannot take them, and its own prune takes
//--- nothing else.
#define PO3_LIQ     "PO3_U"
//--- The last raided high and low, drawn dashed. "PO3_UR" cannot be the start
//--- of an unraided name ("PO3_UH_" / "PO3_UL_"), so neither prune takes the
//--- other's objects, and OnDeinit's PO3_PREFIX sweep takes both.
#define PO3_LIQR    "PO3_UR"
//--- Fair value gap boxes. "PO3_F" is no other sub-prefix's prefix either.
#define PO3_FVG     "PO3_F"
//--- The panel toggle buttons.
#define PO3_BTN     "PO3_B"

//--- The last number of the band that carries the reading. At or below it a
//--- marker takes one of the two prominent colours; above it the recessive one.
//--- The same 33 the schedule panel stops at, and for the same reason - past it
//--- no timeframe on this chart reaches the next number inside a week - but
//--- kept as its own constant, because how a marker is COLOURED and which
//--- numbers get a row in the timetable are two decisions that only happen to
//--- agree today.
#define KIHON_MAIN_LAST  33
#define PO3_COUNT   10

//--- resolved table, built in OnInit, ascending by PO3 number
int             g_po3[PO3_COUNT];
color           g_col[PO3_COUNT];
int             g_wid[PO3_COUNT];
ENUM_LINE_STYLE g_sty[PO3_COUNT];
int             g_n      = 0;
long            g_finest = 0;
int             g_each   = 3;

//--- Rebuild only when price crosses into a new grid cell or a new bar opens,
//--- not on every tick. The new-bar check keeps labels pinned to the right edge.
long     g_anchor   = LONG_MIN;
datetime g_lastTime = 0;
bool     g_dirty    = true;
//--- The level objects the last rebuild drew, so the next one can diff
//--- against them instead of sweeping the chart, and a new bar can slide the
//--- labels along without touching the lines.
string   g_lvlObj[];
int      g_lvlObjN  = 0;
string   g_lvlLab[];
int      g_lvlLabN  = 0;
string   g_liqKeep[];     // names drawn this pass
int      g_liqKeepN  = 0;
string   g_liqNames[];    // names on the chart after the last pass
int      g_liqNamesN = 0;
bool     g_liqChanged = false;
//--- The gate. Lines can only change when a source candle opens (a swing is
//--- confirmed, or a close raid lands) or price trades beyond the nearest
//--- unraided level. Anything else and a tick costs three reads.
bool     g_liqDirty  = true;
datetime g_liqBar    = 0;
double   g_liqHiNear = DBL_MAX;    // lowest unraided high
double   g_liqLoNear = -DBL_MAX;   // highest unraided low
int      g_liqScale  = -1;         // chart zoom the dashes were cut for
//--- The last raided swing per side, [0] highs and [1] lows: the one whose
//--- raid is the newest. Set by the scan, drawn by LiqDrawRaided, which
//--- redraws only when the key (swing, raid, zoom) changes.
bool     g_rdHas[2];
datetime g_rdSwing[2];
datetime g_rdRaid[2];
double   g_rdLevel[2];
int      g_rdAge[2];               // source candles since the raid, 0 = live
string   g_rdKey[2];
//--- Fair value gaps, kept and pruned the same way as the liquidity lines.
string   g_fvgKeep[];
int      g_fvgKeepN  = 0;
string   g_fvgNames[];
int      g_fvgNamesN = 0;
bool     g_fvgChanged = false;
//--- The gate. Boxes can only change when a source candle opens (a gap is
//--- confirmed), a chart candle opens (the boxes stretch to it) or price
//--- reaches the nearest mitigation price on either side.
bool     g_fvgDirty    = true;
datetime g_fvgBar      = 0;
datetime g_fvgEdge     = 0;           // chart candle the boxes run to
double   g_fvgBullNear = -DBL_MAX;    // highest mitigation price, bullish gaps
double   g_fvgBearNear = DBL_MAX;     // lowest mitigation price, bearish gaps

bool     g_logged   = false;

//--- Session timer. The start time lives in a terminal global variable keyed by
//--- chart id, so it outlives the OnInit/OnDeinit cycle that a timeframe or
//--- input change triggers. On such a change OnDeinit leaves g_gvCarry set and
//--- the next OnInit adopts the stored start instead of restarting. g_gvAlerted
//--- flags that the over-limit alert has already fired for this session.
//--- Candle count. Markers only move when a candle closes or the anchor rolls
//--- over, so they are rebuilt on a change rather than on every timer tick.
datetime g_kAnchor = 0;
int      g_kCount  = 0;
bool     g_kDirty  = true;

//--- Panel gate. Nothing the panel prints can change except on a minute
//--- boundary: M1 is the finest thing counted and every coarser timeframe's
//--- boundary is minute-aligned, as are the day, week, month and year rollovers
//--- in the block titles. So the whole panel is rebuilt once a minute rather
//--- than on every tick, which is what it was doing.
//---
//--- g_pUnknown holds the gate open while any row still reads "no data". A
//--- row resolves when its history finishes loading, which does NOT happen on
//--- a minute boundary, so latching on the clock alone would leave the panel
//--- showing "no data" until the next minute arrived. Its own dirty flag, not
//--- g_kDirty: UpdateCount clears that one before UpdatePanel ever sees it.
datetime g_pLast    = 0;
bool     g_pUnknown = true;
bool     g_pDirty   = true;
//--- A centred panel has to move when the window does, and a resize is not a
//--- minute boundary. ChartGetInteger is a local read, so checking it every
//--- pass costs nothing next to the rebuild it usually prevents.
int      g_pHeight  = 0;

//--- What the kihon blocks are showing right now: the inputs to start with,
//--- then whatever the buttons last set. See ToggleInit.
bool     g_showPanel = true;
bool     g_showSeg   = true;
bool     g_showSched = true;
string   g_gvToggle  = "";

string   g_gvStart      = "";
string   g_gvCarry      = "";
string   g_gvAlerted    = "";
datetime g_sessionStart = 0;

//+------------------------------------------------------------------+
//| Whole levels print without decimals, so a scale 1 gold level     |
//| reads 4374 rather than 4374.00.                                  |
//+------------------------------------------------------------------+
string PriceText(const double price)
  {
   int dig = (MathAbs(price - MathRound(price)) < 1e-9)
             ? 0 : (int)MathMax(_Digits, 2);
   return(DoubleToString(price, dig));
  }

//+------------------------------------------------------------------+
//| How many levels each side this grid draws.                       |
//|                                                                  |
//| Every grid gets the input's own count, with one exception. The   |
//| 1 grid is not a level ladder in its own right - it is the        |
//| subdivision of the 3 grid, the two interior lines that split a 3 |
//| cell into thirds - so it has to span what the 3 grid spans or    |
//| the subdivision is partial. At the default of 3 each side, the 3 |
//| grid reaches about nine dollars either way and a 1 grid drawing  |
//| three would fill only the middle cell, leaving the outer cells   |
//| bare and looking like lines that failed to draw.                 |
//|                                                                  |
//| Three times the count is exactly the 3 grid's reach, because     |
//| that is what the ratio between the two grids is. It costs lines  |
//| - eighteen instead of six at the default - which is the price of |
//| the subdivision being whole.                                     |
//+------------------------------------------------------------------+
int PO3EachFor(const int po3)
  {
   return((po3 == 1) ? g_each * 3 : g_each);
  }

//+------------------------------------------------------------------+
//| Register one ticked PO3 number. Each checkbox is a distinct      |
//| number, so nothing can collide and no selection can be silently  |
//| dropped the way a free-choice slot could.                        |
//+------------------------------------------------------------------+
void AddPO3(const bool on, const int po3, const color col)
  {
   if(!on || g_n >= PO3_COUNT)
      return;

   g_po3[g_n] = po3;
   g_col[g_n] = col;
   g_wid[g_n] = (po3 >= 6561) ? 3 : (po3 >= 729) ? 2 : 1;
   //--- MT5 renders a non-solid style only at width 1, which is where the
   //--- dotted small grids sit anyway
   g_sty[g_n] = (po3 <= 27) ? STYLE_DOT : STYLE_SOLID;
   g_n++;
  }

//+------------------------------------------------------------------+
//| Start, or adopt, the session timer.                              |
//|                                                                  |
//| MT5 tears the indicator down and rebuilds it on a timeframe or   |
//| input change, so a start time held in a plain variable would     |
//| reset every time the chart period was switched. It lives in a    |
//| terminal global instead, keyed by chart id. OnDeinit sets the    |
//| carry flag for exactly the reasons that should not reset the     |
//| count, so its presence here means "adopt the stored start". A    |
//| crash never runs OnDeinit, so the flag is absent and the count   |
//| starts clean, which is what you want after a crash anyway.       |
//+------------------------------------------------------------------+
void SessionInit()
  {
   string base = "PO3_Session_" + IntegerToString(ChartID());
   g_gvStart   = base;
   g_gvCarry   = base + "_carry";
   g_gvAlerted = base + "_alert";

   bool carry = GlobalVariableCheck(g_gvCarry) && GlobalVariableCheck(g_gvStart);
   GlobalVariableDel(g_gvCarry);

   if(!carry)
     {
      GlobalVariableSet(g_gvStart, (double)TimeLocal());
      GlobalVariableDel(g_gvAlerted);
     }

   g_sessionStart = (datetime)(long)GlobalVariableGet(g_gvStart);
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpScale <= 0.0)
     {
      Print("PO3 Levels: scale divisor must be greater than zero.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   SessionInit();
   ToggleInit(UninitializeReason());

   //--- Before the early return below, so a chart with no grid ticked still
   //--- gets its candle count rebuilt on an input change.
   g_kAnchor  = 0;
   g_kCount   = 0;
   g_kDirty   = true;
   g_lvlObjN  = 0;
   g_lvlLabN  = 0;
   g_liqDirty = true;
   g_liqNamesN = 0;
   g_liqScale  = -1;
   g_rdKey[0]  = "";
   g_rdKey[1]  = "";
   g_fvgDirty  = true;
   g_fvgNamesN = 0;
   g_fvgEdge   = 0;
   g_pLast    = 0;
   g_pUnknown = true;
   g_pDirty   = true;
   g_pHeight  = 0;

   //--- The sizes actually in force, printed every load. MT5 stores inputs per
   //--- applied indicator, not per source file, so a chart carries whatever it
   //--- was given when it was added and a recompile does not update it. A
   //--- timeframe change reloads from that store, which is when a stale size
   //--- becomes visible. Printing it turns "it went small again" into a fact
   //--- you can check in the Experts tab against the defaults you expect.
   PrintFormat("PO3 Levels: panel text size %d, marker %d, level label %d. "
               "These come from this chart's stored inputs - if they are not "
               "the ones you expect, remove the indicator and re-add it.",
               (int)MathMax(6, MathMin(20, InpPanelSize)),
               (int)MathMax(5, MathMin(20, InpKihonSize)),
               (int)MathMax(5, MathMin(20, InpFontSize)));

   //--- The 1 grid is M1 only, and that is a rule rather than an input. At
   //--- scale 1 its lines are a dollar apart, which is the scale an M1 candle
   //--- moves in - the grid and the candles are the same size, so the lines
   //--- read as the floor the candle is standing on. One rung up they are not:
   //--- an M1 chart's dollar is an H1 candle's rounding error, and the grid
   //--- stops being a subdivision you can see and becomes a wash of lines
   //--- behind candles that step straight over three of them at a time.
   //---
   //--- Enforced here rather than at draw time so g_n and g_finest are right
   //--- everywhere else: on anything above M1 the finest ticked grid is 3
   //--- again, and the rebuild goes back to firing every three dollars of
   //--- travel instead of every one.
   //---
   //--- MT5 reinitialises an indicator on a timeframe change, so this is
   //--- re-decided on every switch with no state to keep in step.
   bool onM1 = (_Period == PERIOD_M1);

   g_n = 0;                                  // ascending, so g_po3[0] is finest
   AddPO3(InpUse_1 && onM1, 1, InpCol_1);
   AddPO3(InpUse_3,     3,     InpCol_3);
   AddPO3(InpUse_9,     9,     InpCol_9);
   AddPO3(InpUse_27,    27,    InpCol_27);
   AddPO3(InpUse_81,    81,    InpCol_81);
   AddPO3(InpUse_243,   243,   InpCol_243);
   AddPO3(InpUse_729,   729,   InpCol_729);
   AddPO3(InpUse_2187,  2187,  InpCol_2187);
   AddPO3(InpUse_6561,  6561,  InpCol_6561);
   AddPO3(InpUse_19683, 19683, InpCol_19683);

   //--- Said out loud, because a ticked checkbox drawing nothing is otherwise
   //--- indistinguishable from a broken one. The rest of the grids report
   //--- their line counts below; this is the one that can be on and absent.
   if(InpUse_1 && !onM1)
      Print("PO3 Levels: PO3 1 is ticked but not drawn - it is M1 only. "
            "Drop to M1 to see it.");

   if(g_n == 0)
     {
      Print("PO3 Levels: no PO3 number ticked, no levels will be drawn.");
      //--- No grid, but the counts may still be the reason it is on the chart
      IndicatorSetString(INDICATOR_SHORTNAME,
                         (InpShowCount || InpShowPanel || InpShowSeg || InpShowSched)
                         ? "Kihon count" : "PO3 (none ticked)");
      g_dirty = true;
      EventSetTimer(1);          // the countdown is independent of the levels
      return(INIT_SUCCEEDED);
     }

   //--- Freeze guard. The clamp alone caps ten ticked grids at 2400 candidate
   //--- levels - 1800 for the nine, 600 for the 1 grid's triple window, and
   //--- that last 600 only on M1 - which MT5 handles. Deliberately no further trim on top: quietly
   //--- rewriting the count would make the input mean something other than what
   //--- it says, and the warning would sit in a log nobody is watching.
   g_each = (int)MathMax(1, MathMin(100, InpEachSide));

   //--- Powers of three nest, so the finest ticked grid's cell boundaries are a
   //--- superset of every coarser one. Tracking its cell is enough to know when
   //--- any ticked level would move. On M1 with the 1 grid drawn that cell is
   //--- a dollar wide at scale 1, so the rebuild runs on every dollar of
   //--- travel rather than every three - the honest cost of the finest grid,
   //--- and paid only where it is drawn. Above M1 the 1 grid is suppressed, so
   //--- g_po3[0] is 3 again and the old cadence comes back with it.
   g_finest = g_po3[0];

   string names = "";
   for(int i = 0; i < g_n; i++)
     {
      names += (i > 0 ? " + " : "") + IntegerToString(g_po3[i]);
      PrintFormat("PO3 Levels: active %d of %d = PO3 %d, step %s, %d each side.",
                  i + 1, g_n, g_po3[i],
                  PriceText((double)g_po3[i] / InpScale),
                  PO3EachFor(g_po3[i]));
     }
   IndicatorSetString(INDICATOR_SHORTNAME, "PO3 " + names +
                      ((InpShowCount || InpShowPanel || InpShowSeg || InpShowSched)
                       ? " + kihon" : ""));

   g_anchor   = LONG_MIN;
   g_lastTime = 0;
   g_dirty    = true;
   g_logged   = false;

   EventSetTimer(1);                    // one-second countdown
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();

   //--- A timeframe or input change keeps the session clock running; anything
   //--- that genuinely reloads the indicator or the chart ends it.
   if(reason == REASON_CHARTCHANGE || reason == REASON_PARAMETERS)
      GlobalVariableSet(g_gvCarry, 1.0);
   else
     {
      GlobalVariableDel(g_gvStart);
      GlobalVariableDel(g_gvCarry);
      GlobalVariableDel(g_gvAlerted);
     }
   ToggleSave(reason);

   ObjectsDeleteAll(0, PO3_PREFIX, -1, -1);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Draw one level. "raw" is the workbook's own integer, m * 3^n,    |
//| so it doubles as a unique object name and keeps the arithmetic   |
//| exact: the divide happens once, at the end. Accumulating         |
//| m * 21.87 in doubles would drift off the sheet value.            |
//|                                                                  |
//| Deliberately NOT run through NormalizeDouble. The division       |
//| already yields the nearest double to the workbook figure, so     |
//| rounding can only move it away: on a feed quoting _Digits 1,     |
//| NormalizeDouble(5314.41, 1) would put the line at 5314.4.        |
//+------------------------------------------------------------------+
void DrawLevel(const long raw, const int idx, const datetime labelTime)
  {
   double price = (double)raw / InpScale;
   string name  = PO3_LEVEL + IntegerToString(raw);

   //--- a failed create means the object survived the sweep, so fall through
   //    and restyle it rather than leaving it on stale settings
   ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ArrayResize(g_lvlObj, g_lvlObjN + 1, 128);
   g_lvlObj[g_lvlObjN++] = name;

   ObjectSetDouble (0, name, OBJPROP_PRICE,      price);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      g_col[idx]);
   ObjectSetInteger(0, name, OBJPROP_STYLE,      g_sty[idx]);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,      g_wid[idx]);
   ObjectSetInteger(0, name, OBJPROP_BACK,       InpLinesBehind);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   ObjectSetString (0, name, OBJPROP_TOOLTIP,
                    StringFormat("%s   %d x %I64d",
                                 PriceText(price),
                                 g_po3[idx], raw / (long)g_po3[idx]));

   //--- Every label shares one time anchor, so the fine grids can pile digits on
   //--- top of each other: 3 puts levels $3 apart, far closer than a line of
   //--- text is tall. The threshold thins them - raise it to label the stronger
   //--- grids only, at the cost of not being able to name the lines it hides.
   if(!InpShowLabels || g_po3[idx] < InpLabelMinPO3)
      return;

   //--- The label carries the owning PO3 number, so a merged level reads as the
   //--- strongest grid that produced it, matching the colour it was given.
   string tname = PO3_LEVEL + "T" + IntegerToString(raw);

   ObjectCreate(0, tname, OBJ_TEXT, 0, labelTime, price);
   ArrayResize(g_lvlObj, g_lvlObjN + 1, 128);
   g_lvlObj[g_lvlObjN++] = tname;
   ArrayResize(g_lvlLab, g_lvlLabN + 1, 128);
   g_lvlLab[g_lvlLabN++] = tname;

   ObjectSetInteger(0, tname, OBJPROP_TIME,       labelTime);
   ObjectSetDouble (0, tname, OBJPROP_PRICE,      price);
   ObjectSetString (0, tname, OBJPROP_TEXT,       IntegerToString(g_po3[idx]));
   ObjectSetInteger(0, tname, OBJPROP_COLOR,      g_col[idx]);
   ObjectSetInteger(0, tname, OBJPROP_FONTSIZE,   (int)MathMax(5, MathMin(20, InpFontSize)));
   //--- anchored right-lower: the text sits just above the line and ends at the
   //    anchor bar, so it stays on screen even with chart shift switched off
   ObjectSetInteger(0, tname, OBJPROP_ANCHOR,     ANCHOR_RIGHT_LOWER);
   ObjectSetInteger(0, tname, OBJPROP_BACK,       false);
   ObjectSetInteger(0, tname, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, tname, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, tname, OBJPROP_HIDDEN,     true);
  }

//+------------------------------------------------------------------+
//| Collect every ticked grid's window around price, merge levels    |
//| that land on the same price under the highest PO3 number, draw.  |
//+------------------------------------------------------------------+
void Rebuild(const double price, const datetime labelTime)
  {
   //--- Only the level objects. A blanket delete by prefix would take the
   //--- countdown text with it on every redraw, and the clock would flicker
   //--- out whenever price crossed a grid cell.
   //--- Diffed against the last pass rather than swept: a level still in the
   //--- window is restyled in place by DrawLevel, and only the ones that left
   //--- it are deleted. A price step no longer tears down and recreates every
   //--- line, which was the flicker and most of the cost.
   string old[];
   int    oldN = g_lvlObjN;
   ArrayResize(old, oldN);
   for(int i = 0; i < oldN; i++)
      old[i] = g_lvlObj[i];
   g_lvlObjN = 0;
   g_lvlLabN = 0;

   if(g_n <= 0)
     {
      for(int i = 0; i < oldN; i++)
         ObjectDelete(0, old[i]);
      ChartRedraw();
      return;
     }

   long raws[];
   int  owner[];

   //--- Summed rather than g_n * 2 * g_each, because the grids no longer all
   //--- draw the same number of levels - see PO3EachFor.
   int cap = 0;
   for(int s = 0; s < g_n; s++)
      cap += 2 * PO3EachFor(g_po3[s]);

   ArrayResize(raws,  cap);
   ArrayResize(owner, cap);
   int n = 0;

   for(int s = 0; s < g_n; s++)
     {
      long po3  = (long)g_po3[s];
      int  each = PO3EachFor(g_po3[s]);

      //--- The epsilon matters. A price sitting exactly on a level, e.g. 2952.45
      //--- with PO3 2187, divides to 134.99999999999997 rather than 135, so a
      //--- bare floor() would anchor one level too low and shift the window down.
      long m0 = (long)MathFloor(price * InpScale / (double)po3 + 1e-9);

      for(long m = m0 - each + 1; m <= m0 + each; m++)
        {
         if(m <= 0)                     // zero anchor and negatives are not prices
            continue;

         long raw = m * po3;
         int  idx = -1;
         for(int i = 0; i < n; i++)
            if(raws[i] == raw)
              { idx = i; break; }

         if(idx < 0)
           {
            if(n >= cap)
               continue;
            raws[n]  = raw;
            owner[n] = s;
            n++;
           }
         else
            if(g_po3[s] > g_po3[owner[idx]])   // stronger number owns the level
               owner[idx] = s;
        }
     }

   for(int i = 0; i < n; i++)
      DrawLevel(raws[i], owner[i], labelTime);

   for(int i = 0; i < oldN; i++)
     {
      bool kept = false;
      for(int k = 0; k < g_lvlObjN && !kept; k++)
         kept = (g_lvlObj[k] == old[i]);
      if(!kept)
         ObjectDelete(0, old[i]);
     }

   //--- Once per load, report what each grid actually contributed after the
   //--- merge. A grid showing 0 was outbid on every level; a grid showing a
   //--- count that you cannot see on the chart is a visibility problem, not a
   //--- selection one. Ctrl+B lists the objects by name to confirm.
   if(!g_logged)
     {
      g_logged = true;
      for(int s = 0; s < g_n; s++)
        {
         int c = 0;
         for(int i = 0; i < n; i++)
            if(owner[i] == s)
               c++;
         PrintFormat("PO3 Levels: PO3 %d drew %d line(s) after merging.",
                     g_po3[s], c);
        }
     }

   ChartRedraw();
  }

//--- the chart's own timeframe
string TfName()
  {
   return(TfNameOf((ENUM_TIMEFRAMES)_Period));
  }

//+------------------------------------------------------------------+
//| A span of seconds in units that suit its size: mm:ss under an    |
//| hour, hh:mm:ss above it, and days once past one. The candle      |
//| countdown and the session timer both format through here, so     |
//| M15 reads 14:59 while an hour on the chart reads 01:00:00.       |
//+------------------------------------------------------------------+
string HMS(const long secs)
  {
   long s = (secs > 0) ? secs : 0;
   long d = s / 86400; s -= d * 86400;
   long h = s / 3600;  s -= h * 3600;
   long m = s / 60;    s -= m * 60;

   if(d > 0)
      return(StringFormat("%dd %02d:%02d:%02d", (int)d, (int)h, (int)m, (int)s));
   if(h > 0)
      return(StringFormat("%02d:%02d:%02d", (int)h, (int)m, (int)s));
   return(StringFormat("%02d:%02d", (int)m, (int)s));
  }

//+------------------------------------------------------------------+
//| The anchor that suits a screen corner, for the session timer.    |
//+------------------------------------------------------------------+
ENUM_ANCHOR_POINT AnchorFor(const ENUM_BASE_CORNER c)
  {
   //--- Match the anchor to the corner so X and Y always measure inward. A
   //--- fixed right anchor would push the text off the left edge of the chart
   //--- as soon as someone chose a left corner.
   switch(c)
     {
      case CORNER_LEFT_UPPER:  return(ANCHOR_LEFT_UPPER);
      case CORNER_LEFT_LOWER:  return(ANCHOR_LEFT_LOWER);
      case CORNER_RIGHT_LOWER: return(ANCHOR_RIGHT_LOWER);
      default:                 return(ANCHOR_RIGHT_UPPER);
     }
  }

//+------------------------------------------------------------------+
//| Time left on the developing candle, printed beside that candle.  |
//|                                                                  |
//| Anchored to the open time of bar 0 and to the current price, so  |
//| the text tracks the candle as the chart scrolls and rides price  |
//| as it moves, instead of parking in a corner away from the bar it |
//| describes.                                                       |
//|                                                                  |
//| MN1 is nominal: PeriodSeconds() calls a month 30 days, so the    |
//| monthly countdown is approximate. Every other timeframe is exact.|
//+------------------------------------------------------------------+
void UpdateClock()
  {
   string name = PO3_PREFIX + "CLOCK";

   if(!InpShowClock)
     {
      ObjectDelete(0, name);
      return;
     }

   datetime open  = iTime (_Symbol, _Period, 0);
   double   price = iClose(_Symbol, _Period, 0);
   if(open == 0 || price <= 0.0)
      return;                                   // history not ready yet

   long left = (long)(open + PeriodSeconds()) - (long)TimeCurrent();

   //--- Shift is in bars, so the gap to the candle holds at every zoom level.
   //--- Signed arithmetic before the cast: a negative shift on an unsigned
   //--- datetime would wrap and throw the text to the far end of the chart.
   long     bars = (long)PeriodSeconds() * InpClockShift;
   datetime at   = (datetime)MathMax(0, (long)open + bars);

   //--- Past the last bar the text has to read rightwards, into the empty
   //--- space; at or behind it, ending at the anchor keeps the text off the
   //--- candles and, with chart shift off, on screen.
   ENUM_ANCHOR_POINT anchor = (InpClockShift > 0) ? ANCHOR_LEFT : ANCHOR_RIGHT;

   //--- The fixed properties are written once, when the object is made; each
   //--- tick and second after that moves it and rewrites the text only.
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_TEXT, 0, at, price);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR,     anchor);
      ObjectSetInteger(0, name, OBJPROP_COLOR,      InpClockColor);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   (int)MathMax(6, MathMin(24, InpClockSize)));
      ObjectSetInteger(0, name, OBJPROP_BACK,       false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
     }

   ObjectSetInteger(0, name, OBJPROP_TIME,       at);
   ObjectSetDouble (0, name, OBJPROP_PRICE,      price + InpClockGapPts * _Point);
   ObjectSetString (0, name, OBJPROP_TEXT,       TfName() + "  " + HMS(left));
  }

//+------------------------------------------------------------------+
//| Wall-clock time this chart has been open. Counts through closed  |
//| markets and weekends, since the point is screen time, not        |
//| session time, and turns red once a set number of minutes is up.  |
//+------------------------------------------------------------------+
void UpdateSession()
  {
   string name = PO3_PREFIX + "SESSION";

   if(!InpShowSession || g_sessionStart == 0)
     {
      ObjectDelete(0, name);
      return;
     }

   long elapsed = (long)TimeLocal() - (long)g_sessionStart;
   if(elapsed < 0)
      elapsed = 0;                               // local clock stepped back

   long  limit = (long)InpSessionLimitMin * 60;
   bool  over  = (limit > 0 && elapsed >= limit);

   //--- One alert the moment the budget is spent. The flag is a terminal global
   //--- so switching timeframe mid-session does not make it fire a second time.
   if(over && !GlobalVariableCheck(g_gvAlerted))
     {
      GlobalVariableSet(g_gvAlerted, 1.0);
      Alert(_Symbol, ": ", InpSessionLimitMin, " minutes on the chart.");
     }

   //--- As with the clock: fixed properties once, then text and colour only.
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER,     InpSessionCorner);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  InpSessionX);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  InpSessionY);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR,     AnchorFor(InpSessionCorner));
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   (int)MathMax(6, MathMin(24, InpSessionSize)));
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
     }
   ObjectSetString (0, name, OBJPROP_TEXT,       "On chart  " + HMS(elapsed));
   ObjectSetInteger(0, name, OBJPROP_COLOR,      over ? InpSessionOverColor : InpSessionColor);
  }

//+------------------------------------------------------------------+
//| The candle count, and the kihon suchi numbers marked on it.      |
//|                                                                  |
//| Counting is inclusive at both ends, which is the Ichimoku rule   |
//| and the reason the compound numbers overlap by one candle: the   |
//| candle sitting at the anchor is candle 1, so the developing      |
//| candle is (shift of the anchor) + 1. The KIHON SUCHI section at  |
//| the top of this file has the numbers themselves and where each   |
//| one comes from.                                                  |
//+------------------------------------------------------------------+

//--- The panel is a ladder of calendar periods, each counted in the candles
//--- that divide it sensibly: months, weeks and days make up a year; days, H4s
//--- and H1s make up a month; H4s, H1s and M30s make up a week; and H1
//--- down to M5 makes up a day. Every block carries its OWN anchor, which is
//--- the whole point - a week count from the day open would read 1 forever.
//--- The lists are fixed rather than inputs so no block can be pointed at a
//--- period its timeframe does not divide.
//---
//--- M30 is on the week rather than anywhere else because that is where it
//--- fits: a trading week is 240 M30 candles, so the count runs through eleven
//--- of the twelve numbers and stops just short of 257 without ever running
//--- off the end of the list.
//---
//--- H2 is not counted anywhere on the panel. It was on the month and the week
//--- and has been taken off both, so the ladder steps H4 straight to H1 on each
//--- of them. What that costs is the middle of the month: H1 over a month is
//--- 504 candles, so it passes 257 around the first of July and reads "past
//--- 257" for the rest of it, while D1 at 21 candles only ever reaches 9 and
//--- 17, and no remaining row covers a month end to end. That is the trade, and
//--- it is worth knowing before adding a row back.
//---
//--- The year, month and week blocks are FIXED. They are the same counts
//--- whatever period the chart is on, so switching timeframe must not change
//--- what they say - a week is 26 H1 candles in whether you are looking at M1
//--- or D1, and a row that came and went with the chart period could not be
//--- read across a timeframe change.
//---
//--- The day block is fixed too, and runs the whole intraday ladder on every
//--- chart period: H1, M30, M15, M5, then the nested M1 row. It used to
//--- stop at the chart's own period, on the argument that detail finer than the
//--- candles in front of you is a count of something you cannot see. That was
//--- wrong about what the panel is for. The count of M5 candles since the day
//--- open is the same number whatever period you look at it from, and it is
//--- often the reason to look - an H1 chart that shows only its own hour count
//--- hides the three rows underneath it that say where inside that hour the
//--- session has got to. The ladder is now read the same way the year, month
//--- and week blocks are, which is the point of a ladder.
//---
//--- H2 was never in that ladder, and the reason it was kept out is the reason
//--- it is now off the other blocks too. Twelve H2 candles fit in a day, so the
//--- only number it could ever reach here is 9, once, at +16h - and 2:1 nesting
//--- puts that on the same candle as H1 17, M30 33 and M15 65, every single
//--- time, because 2k-1 carries a kihon number onto a kihon number. A row that
//--- fires at an instant three other rows are already marking makes the block
//--- look more agreed with itself without any more agreement being there.
//---
//--- M1 is missing from that ladder on purpose, on every chart period. The M1
//--- row is ALWAYS the nested one, which restarts at each kihon suchi H1 candle
//--- rather than running the whole day - see the nested row in UpdatePanel. A
//--- plain M1 row beside it would read "past 257" from mid-morning on and say
//--- nothing for the rest of the session. That is the one row a chart period
//--- could never have justified either way.
const ENUM_TIMEFRAMES g_kpYear[3]  = { PERIOD_MN1, PERIOD_W1,  PERIOD_D1 };
const ENUM_TIMEFRAMES g_kpMonth[3] = { PERIOD_D1,  PERIOD_H4,  PERIOD_H1 };
const ENUM_TIMEFRAMES g_kpWeek[3]  = { PERIOD_H4,  PERIOD_H1,  PERIOD_M30 };
const ENUM_TIMEFRAMES g_kpDay[4]   = { PERIOD_H1,  PERIOD_M30, PERIOD_M15,
                                       PERIOD_M5 };

//--- Rows are built into a fixed array and the unused tail deleted, so
//--- switching a block off cannot leave an orphaned row behind on the chart.
//--- The ceiling is shared by all three panels and sized for the tallest: the
//--- schedule panel runs to 39 rows on the 9-33 window - five timeframes of
//--- four numbers for the week, three more groups for today, and the titles and
//--- spacers between them - and to 44 with the today list opened past 33, where
//--- M15 alone contributes eight. The count panel's own worst case is 21 and
//--- the segment panel's 9, so the number is the schedule panel's and the
//--- headroom above it is deliberate.
#define KP_MAX_ROWS   48

//--- Ceiling on plain candle numbers. A whole day of M1 is 1440 labels, which
//--- is both unreadable and a real drag on redraw, so only the most recent run
//--- is numbered. The kihon markers are never capped - there are at most twelve
//--- of them, and they are the ones worth seeing at the left edge.
#define KP_LABEL_CAP  300

//+------------------------------------------------------------------+
//| One marked candle: an optional vertical line through it and its  |
//| number printed under the low.                                    |
//|                                                                  |
//| Anchored to the candle's own time, so the marks stay on their    |
//| candles as the chart scrolls, and to that candle's low, so the   |
//| numbers sit clear of the body rather than across it.             |
//+------------------------------------------------------------------+
void DrawCountMark(const string id, const int shift, const string text,
                   const color col, const bool line, const int size)
  {
   if(shift < 0 || shift >= Bars(_Symbol, _Period))
      return;                                   // off the loaded history

   datetime when = iTime(_Symbol, _Period, shift);
   double   low  = iLow (_Symbol, _Period, shift);
   if(when == 0 || low <= 0.0)
      return;

   if(line)
     {
      string vname = PO3_KMARK + "V" + id;

      ObjectCreate(0, vname, OBJ_VLINE, 0, when, 0);

      ObjectSetInteger(0, vname, OBJPROP_TIME,       when);
      ObjectSetInteger(0, vname, OBJPROP_COLOR,      col);
      ObjectSetInteger(0, vname, OBJPROP_STYLE,      STYLE_DOT);
      ObjectSetInteger(0, vname, OBJPROP_WIDTH,      1);
      //--- behind the candles: a time marker that hides the candle it marks
      //--- has defeated itself
      ObjectSetInteger(0, vname, OBJPROP_BACK,       true);
      ObjectSetInteger(0, vname, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, vname, OBJPROP_SELECTED,   false);
      ObjectSetInteger(0, vname, OBJPROP_HIDDEN,     true);
      ObjectSetString (0, vname, OBJPROP_TOOLTIP,
                       StringFormat("candle %s   %s", text,
                                    TimeToString(when, TIME_DATE | TIME_MINUTES)));
     }

   string tname = PO3_KMARK + "T" + id;

   ObjectCreate(0, tname, OBJ_TEXT, 0, when, low);

   ObjectSetInteger(0, tname, OBJPROP_TIME,       when);
   ObjectSetDouble (0, tname, OBJPROP_PRICE,      low - InpKihonGapPts * _Point);
   ObjectSetString (0, tname, OBJPROP_TEXT,       text);
   ObjectSetInteger(0, tname, OBJPROP_COLOR,      col);
   ObjectSetInteger(0, tname, OBJPROP_FONTSIZE,   size);
   //--- upper anchor hangs the number below the low, clear of the wick
   ObjectSetInteger(0, tname, OBJPROP_ANCHOR,     ANCHOR_UPPER);
   ObjectSetInteger(0, tname, OBJPROP_BACK,       false);
   ObjectSetInteger(0, tname, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, tname, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, tname, OBJPROP_HIDDEN,     true);
  }

//+------------------------------------------------------------------+
//| The colour a marked candle's number is drawn in.                 |
//|                                                                  |
//| Three bands: the simple numbers, then 33, then everything above  |
//| it. Taken from the number itself rather than from its position   |
//| in the list, so the bands cannot drift out of step with          |
//| KihonNumbers if that list ever changes.                          |
//+------------------------------------------------------------------+
color KihonMarkColor(const int k)
  {
   if(KihonIsSimple(k))
      return(InpKihonSimple);

   return((k <= KIHON_MAIN_LAST) ? InpKihonComp : InpKihonFar);
  }

//+------------------------------------------------------------------+
//| Rebuild the on-chart marks, but only when they would move.       |
//|                                                                  |
//| The count changes exactly when a candle closes or the anchor     |
//| rolls into a new day, so a sweep-and-redraw on every timer tick  |
//| would rebuild an identical set of objects once a second and      |
//| flicker while doing it.                                          |
//+------------------------------------------------------------------+
void UpdateCount()
  {
   datetime anchor = InpShowCount
                     ? KihonAnchor(_Symbol, InpCountAnchor, InpAnchorHour, InpAnchorMin)
                     : 0;
   int count = InpShowCount ? KihonCount(_Symbol, _Period, anchor) : 0;

   if(!g_kDirty && anchor == g_kAnchor && count == g_kCount)
      return;

   g_kAnchor = anchor;
   g_kCount  = count;
   g_kDirty  = false;

   ObjectsDeleteAll(0, PO3_KMARK, -1, -1);

   if(count <= 0)
     {
      ChartRedraw();
      return;
     }

   int size   = (int)MathMax(5, MathMin(20, InpKihonSize));
   int aShift = count - 1;                      // candle 1 lives here

   if(InpMarkOpen)
      DrawCountMark("OPEN", aShift, "1", InpOpenColor, true, size);

   if(InpMarkKihon)
      for(int i = 0; i < KIHON_COUNT; i++)
        {
         if(!InpKihonCompound && i >= KIHON_SIMPLE)
            break;

         int k = KihonNumbers[i];
         if(k > count)                          // not reached yet
            break;

         DrawCountMark("K" + IntegerToString(k), aShift - (k - 1),
                       IntegerToString(k), KihonMarkColor(k),
                       InpKihonLines, size);
        }

   //--- Plain numbers on the rest. Drawn after the kihon marks and skipping
   //--- them, so a kihon candle keeps its own colour instead of being
   //--- overwritten by a neutral label of the same number.
   if(InpNumberAll)
     {
      int first = (count > KP_LABEL_CAP) ? count - KP_LABEL_CAP + 1 : 1;

      for(int k = first; k <= count; k++)
        {
         if(k == 1 && InpMarkOpen)
            continue;
         if(InpMarkKihon && KihonIs(k, InpKihonCompound))
            continue;

         DrawCountMark("N" + IntegerToString(k), aShift - (k - 1),
                       IntegerToString(k), InpPanelColor, false,
                       (int)MathMax(5, size - 1));
        }
     }

   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| One panel row: a timeframe's count against its block's anchor,   |
//| and what it owes the next kihon suchi number.                    |
//|                                                                  |
//| "no data" and "too far" are different answers. The first means   |
//| the history is not there to count; the second means the count    |
//| was refused because the anchor is further back than              |
//| KIHON_SPAN_CAP periods, where the exact figure would cost a      |
//| large history load to say something "past 257" already says.     |
//+------------------------------------------------------------------+
string PanelRow(const ENUM_TIMEFRAMES tf, const datetime anchor, color &col,
                const string label = "")
  {
   int    c = KihonCount(_Symbol, tf, anchor);
   string tail;

   if(c < 0)
      tail = "too far";                        // refused, and it will stay refused
   else
      if(c == 0)
        {
         tail = "no data";
         //--- History still arriving. Hold the panel's gate open so the row is
         //--- rewritten the moment it resolves, rather than at the next minute.
         g_pUnknown = true;
        }
      else
        {
         //--- Distance to the nearest number, either side. Zero is standing on
         //--- one; within the tolerance is close enough to say so, and the sign
         //--- says which way - "-2" is two candles short, "+2" two candles past.
         int off = KihonOffset(c, InpKihonCompound);
         int tol = (int)MathMax(0, MathMin(8, InpPanelNearTol));
         int mag = (off < 0) ? -off : off;

         if(off == 0)
           {
            //--- "KS" rather than the whole word. It is the only thing in the
            //--- row that repeats, and shouting it in a column of counts made
            //--- the numbers - which are the reading - the quieter half.
            tail = "KS";
            col  = InpPanelHit;
           }
         else
            if(mag <= tol)
              {
               //--- Sign written by hand rather than with %+d, so the text
               //--- cannot depend on how the format handles a signed zero or
               //--- a locale. off is non-zero here by the branch above.
               tail = "KS " + ((off > 0) ? "+" : "-") + IntegerToString(mag);
               col  = InpPanelNear;
              }
            else
              {
               //--- Past the last number there is nothing left to count to, so
               //--- say that rather than print a countdown to nowhere. The last
               //--- number is the last of the ACTIVE list: with the compounds
               //--- switched off the series ends at 26, not at 257.
               int last = (InpKihonCompound ? KIHON_COUNT : KIHON_SIMPLE) - 1;
               int nx   = KihonNext(c, InpKihonCompound);
               tail = (nx == 0)
                      ? "past " + IntegerToString(KihonNumbers[last])
                      : StringFormat("%d in %d", nx, nx - c);
              }
        }

   //--- The tail is padded to a fixed width so every row is the same length.
   //--- From a right-hand corner the labels are right-anchored, and ragged
   //--- rows would step the timeframe column in and out.
   //---
   //--- Ten, which is one clear of the longest tail there is: "226 in 53", the
   //--- widest gap between two kihon numbers written out. Padding is a minimum
   //--- and never truncates, and the block is sized by measuring the rows, so
   //--- an unexpectedly long tail would widen the block rather than be cut.
   return(StringFormat("%s %-5s %5s  %-10s",
                       (tf == (ENUM_TIMEFRAMES)_Period) ? ">" : " ",
                       (label == "") ? TfNameOf(tf) : label,
                       (c > 0) ? IntegerToString(c) : "-",
                       tail));
  }

//--- Breathing room between the text and the edge of the block behind it
#define KP_PAD  6

//--- Row pitch. All three panels are laid out on it and the tallest of them
//--- decides where they all start, so it is worked out in one place.
int PanelLineH(const int size)
  {
   return((int)(size * 1.9) + 2);
  }

//+------------------------------------------------------------------+
//| Width of the widest row, in pixels.                              |
//|                                                                  |
//| Measured rather than estimated from the character count: the     |
//| block has to fit whatever font MetaTrader actually resolved, and |
//| a block cut short of its text is worse than no block at all.     |
//| TextSetFont takes tenths of a point when the size is negative,   |
//| which is what OBJPROP_FONTSIZE is quoted in.                     |
//|                                                                  |
//| The estimate is only a fallback for TextGetSize coming back      |
//| empty, and it is deliberately generous - too wide is invisible,  |
//| too narrow is not.                                               |
//+------------------------------------------------------------------+
int PanelWidth(const string &txt[], const int n, const int size)
  {
   int wmax = 0;

   TextSetFont("Consolas", -size * 10, 0, 0);

   //--- TextGetSize writes back through uint references, so the locals have to
   //--- be uint - an int argument will not bind and does not compile.
   for(int i = 0; i < n; i++)
     {
      uint w = 0, h = 0;
      if(TextGetSize(txt[i], w, h) && (int)w > wmax)
         wmax = (int)w;
     }

   if(wmax <= 0)
     {
      int longest = 0;
      for(int i = 0; i < n; i++)
         longest = (int)MathMax(longest, StringLen(txt[i]));
      wmax = (int)(longest * size * 0.7) + 8;
     }

   return(wmax);
  }

//--- One row onto the end, or nothing if the panel is already full
void PanelPush(string &txt[], color &clr[], int &n,
               const string text, const color col)
  {
   if(n >= KP_MAX_ROWS)
      return;

   txt[n] = text;
   clr[n] = col;
   n++;
  }

//+------------------------------------------------------------------+
//| Append one block - a blank line, a title, then its rows.         |
//|                                                                  |
//| The whole block is dropped rather than truncated when it will    |
//| not fit, so the panel never shows a title with its rows missing. |
//+------------------------------------------------------------------+
void PanelAdd(const string title, const datetime anchor, const int fmt,
              const ENUM_TIMEFRAMES &tfs[],
              string &txt[], color &clr[], int &n)
  {
   int rows = ArraySize(tfs);
   if(n + rows + 2 > KP_MAX_ROWS)
      return;

   //--- An empty row reserves a slot without drawing anything; the placement
   //--- loop creates no object for it. See the note there.
   if(n > 0)                                    // spacer between blocks only
      PanelPush(txt, clr, n, "", InpPanelColor);

   PanelPush(txt, clr, n,
             (anchor > 0)
             ? StringFormat("%-6s from %s", title, TimeToString(anchor, fmt))
             : StringFormat("%-6s from -", title),
             InpPanelColor);

   for(int i = 0; i < rows; i++)
     {
      color col = InpPanelColor;
      string row = PanelRow(tfs[i], anchor, col);
      PanelPush(txt, clr, n, row, col);
     }
  }

//+------------------------------------------------------------------+
//| The solid block behind the rows.                                 |
//|                                                                  |
//| A rectangle label rather than a rectangle: this is screen        |
//| furniture pinned to a corner, not something anchored to a price  |
//| and a time that would slide away as the chart scrolls.           |
//|                                                                  |
//| Drawn in front of the candles, not behind them. BACK would put   |
//| it under the price data, which is exactly the thing it is meant  |
//| to hide. It stays under the ROWS because it is created first and |
//| same-layer objects paint in creation order.                      |
//+------------------------------------------------------------------+
void PanelBox(const string prefix, const ENUM_BASE_CORNER corner, const int x,
              const string &txt[], const int n, const int top,
              const int size, const int lineH)
  {
   string name = prefix + "BG";

   if(!InpPanelBox || n <= 0)
     {
      ObjectDelete(0, name);
      return;
     }

   int w = PanelWidth(txt, n, size);

   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);

   ObjectSetInteger(0, name, OBJPROP_CORNER,      corner);
   //--- The rows are laid out from x and top, so the block starts one padding
   //--- earlier on each axis and carries two of them in each size.
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,   (int)MathMax(0, x - KP_PAD));
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,   (int)MathMax(0, top - KP_PAD));
   ObjectSetInteger(0, name, OBJPROP_XSIZE,       w + 2 * KP_PAD);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,       n * lineH + 2 * KP_PAD);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,     InpPanelBg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR,       InpPanelBorder);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,       1);
   ObjectSetInteger(0, name, OBJPROP_BACK,        false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,  false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED,    false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,      true);
  }

//+------------------------------------------------------------------+
//| Put one panel on the chart: its block, its rows, and the tail of |
//| the last layout that this one no longer uses.                    |
//|                                                                  |
//| Everything that differs between the panels is an argument, so    |
//| the count, segment and schedule blocks cannot drift into         |
//| behaving differently - only into standing side by side.          |
//|                                                                  |
//| x and top are given rather than worked out here, because the two |
//| blocks are placed against EACH OTHER: they share a top edge, and |
//| the segment panel's x is the count panel's x plus the width the  |
//| count panel measured. Only the caller knows both.                |
//|                                                                  |
//| Rewritten in place rather than swept and rebuilt: the rows are   |
//| fixed names, so setting their text costs nothing and there is no |
//| window in which the panel is missing. Rows past the last one     |
//| used are deleted, which is what clears a block switched off.     |
//+------------------------------------------------------------------+
void PanelDraw(const string prefix, const ENUM_BASE_CORNER corner,
               const int x, const int top,
               const string &txt[], const color &clr[], const int n,
               const int size, const bool fresh)
  {
   int lineH = PanelLineH(size);

   //--- Y grows away from the chosen corner, so from a lower corner the rows
   //--- stack upwards and have to be laid out bottom first to read in order.
   bool up = (corner == CORNER_LEFT_LOWER || corner == CORNER_RIGHT_LOWER);

   //--- A fresh load or an input change rebuilds the objects from scratch, so
   //--- the block is created BEFORE the rows again. Same-layer objects paint in
   //--- creation order, so a block created after them would cover them.
   if(fresh)
      ObjectsDeleteAll(0, prefix, -1, -1);

   PanelBox(prefix, corner, x, txt, n, top, size, lineH);

   for(int r = 0; r < n; r++)
     {
      string name = prefix + IntegerToString(r);
      int    slot = up ? (n - 1 - r) : r;

      //--- Spacers are layout, not content. A label with empty text is not an
      //--- invisible label: MT5 falls back to its default caption and draws the
      //--- word "Label", one per gap between blocks. The row still occupies its
      //--- slot, so the gap and the block height are unchanged - there is just
      //--- no object. Deleted rather than skipped, to clear any left behind by
      //--- a build that did create them.
      if(txt[r] == "")
        {
         ObjectDelete(0, name);
         continue;
        }

      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);

      ObjectSetInteger(0, name, OBJPROP_CORNER,     corner);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  top + slot * lineH);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR,     AnchorFor(corner));
      ObjectSetString (0, name, OBJPROP_TEXT,       txt[r]);
      //--- fixed pitch, or the columns will not line up between rows
      ObjectSetString (0, name, OBJPROP_FONT,       "Consolas");
      ObjectSetInteger(0, name, OBJPROP_COLOR,      clr[r]);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   size);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
     }

   //--- Whatever the last layout left behind. Deleting only the tail means a
   //--- steady panel is never torn down and rebuilt, so it does not flicker.
   for(int r = n; r < KP_MAX_ROWS; r++)
      ObjectDelete(0, prefix + IntegerToString(r));
  }

//+------------------------------------------------------------------+
//| The open the day block counts from.                              |
//|                                                                  |
//| The chart's own anchor when that anchor is a custom session      |
//| time, so the panel agrees with the marks drawn on the chart      |
//| instead of quietly counting from a different open; the plain day |
//| open otherwise, since every other anchor mode belongs to one of  |
//| the blocks above the day block.                                  |
//+------------------------------------------------------------------+
datetime PanelDayOpen(bool &sess)
  {
   sess = (InpCountAnchor == KIHON_ANCHOR_TIME);

   return(sess ? KihonAnchor(_Symbol, InpCountAnchor, InpAnchorHour, InpAnchorMin)
               : iTime(_Symbol, PERIOD_D1, 0));
  }

//+------------------------------------------------------------------+
//| Is this timeframe's candle a kihon suchi candle right now.       |
//|                                                                  |
//| It can only be one relative to a count, and a count needs an     |
//| anchor, so the calendar anchors are tried here - but that is the |
//| whole of their part in this. They decide WHETHER the block opens |
//| and nothing else: what it then counts starts at the candle, and  |
//| the block never shows a figure measured from a day, week or      |
//| month open. Those counts are the panel beside it, in full.       |
//|                                                                  |
//| Read from the anchors themselves rather than from that panel, so |
//| this block says the same thing whether or not the row that would |
//| have shown the hit is switched on. A count you have hidden is    |
//| still a count.                                                   |
//+------------------------------------------------------------------+
bool SegIsKihon(const ENUM_TIMEFRAMES tf, const bool withDay)
  {
   //--- sess is not read: which open the day count started at changes whether
   //--- this is a hit, not what the block then says about it.
   bool     sess = false;
   datetime day  = PanelDayOpen(sess);

   datetime anch[3];

   anch[0] = KihonPeriodOpen(false);
   anch[1] = iTime(_Symbol, PERIOD_W1, 0);
   anch[2] = day;

   int n = withDay ? 3 : 2;

   for(int i = 0; i < n; i++)
     {
      int c = KihonCount(_Symbol, tf, anch[i]);
      //--- c can be 0 (history still loading) or -1 (refused as too far), and
      //--- neither is a hit. Only a real count can be on a number.
      if(c > 0 && KihonIs(c, InpKihonCompound))
         return(true);                          // one is enough to open it
     }

   return(false);
  }

//+------------------------------------------------------------------+
//| One segment block: the kihon candle's own header, then the finer |
//| counts taken from inside it. Nothing at all when that timeframe  |
//| is not on a number.                                              |
//|                                                                  |
//| The segment starts at the DEVELOPING candle's open. Under        |
//| inclusive counting the developing candle carries the count, so a |
//| count of 9 means the candle in front of you is the ninth one -   |
//| the hit is now, not in the past, and the minutes to count are    |
//| the ones running.                                                |
//|                                                                  |
//| Which finer rows it gets is decided by what fits - see g_ksFine. |
//+------------------------------------------------------------------+

//--- The ladder counted INSIDE a kihon candle, coarse to fine like every block
//--- in the panel. A row is shown only when at least one kihon number fits
//--- inside the candle, which is what puts M15 under an H4 and not under an H1:
//--- sixteen M15 candles fit in an H4, so 9 is in reach and the row can say
//--- something, where the four that fit in an H1 could never read anything but
//--- "9 in 5" for the whole hour. It is the same rule that keeps the day anchor
//--- off the H4 count above, applied at the other end of the nesting - do not
//--- count what cannot reach a number.
//---
//--- What survives it: inside an H4, M15 to 16, M5 to 48 and M1 to 240, so the
//--- rows run to 9, 42 and 226. Inside an H1, M5 to 12 and M1 to 60, so 9 and
//--- 51. The short ones are the point rather than a shortcoming - what they
//--- measure is how far into the kihon candle the market has come, and the
//--- numbers that fit inside it are the only ones that can mean anything there.
const ENUM_TIMEFRAMES g_ksFine[3] = { PERIOD_M15, PERIOD_M5, PERIOD_M1 };

bool SegAdd(const ENUM_TIMEFRAMES tf, const bool withDay, const bool gap,
            string &txt[], color &clr[], int &n)
  {
   if(!SegIsKihon(tf, withDay))
      return(false);

   datetime from = iTime(_Symbol, tf, 0);      // the kihon candle itself

   if(gap)
      PanelPush(txt, clr, n, "", InpPanelColor);

   //--- Same shape as a block title in the panel beside it - what, then the
   //--- open everything under it counts from - because that is exactly what it
   //--- is. Here the open is a candle's rather than a calendar period's, which
   //--- is the only difference between the two blocks. In the hit colour: the
   //--- candle it names IS the hit, and the rows below it colour themselves on
   //--- their own counts.
   PanelPush(txt, clr, n,
             StringFormat("%-6s from %s", TfNameOf(tf),
                          (from > 0) ? TimeToString(from, TIME_MINUTES) : "-"),
             InpPanelHit);

   //--- Compared in seconds rather than by position in the list, so a broker's
   //--- non-standard period lands where its length puts it. This is the one
   //--- place a row is still dropped for not fitting, and the test is
   //--- reachability inside the candle rather than the chart's period: a row
   //--- that cannot reach the first kihon number could only ever count down.
   int span = PeriodSeconds(tf);

   for(int i = 0; i < ArraySize(g_ksFine); i++)
     {
      int fine = PeriodSeconds(g_ksFine[i]);
      if(fine <= 0 || span / fine < KihonNumbers[0])
         continue;                              // cannot reach even the first

      color  col = InpPanelColor;
      string row = PanelRow(g_ksFine[i], from, col);
      PanelPush(txt, clr, n, row, col);
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| The schedule panel: when this week's kihon suchi candles fall,   |
//| and which of today's are still in front.                         |
//|                                                                  |
//| The two blocks beside it answer where the count has got to. This |
//| one answers when it arrives, which is a different question and   |
//| the one a plan is made against: a count reading 14 tells you 17  |
//| is due, but not that 17 opens at 16:00, and 16:00 is the part    |
//| that can go in a diary.                                          |
//|                                                                  |
//| Every time in the block is the OPEN of the candle carrying the   |
//| number, written as weekday, date and time of day.                |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Time of day, on whichever clock the block is set to.             |
//|                                                                  |
//| Midnight is 12:00 AM and noon is 12:00 PM - the one place the    |
//| 12-hour clock catches people out, and the reason this is a       |
//| function rather than a format string. Hour 0 and hour 12 both    |
//| reduce to 12; it is the AM/PM that separates them.               |
//|                                                                  |
//| The hour is padded to two columns rather than zero-filled, so    |
//| " 7:00 AM" lines up under "12:00 PM" without reading as 07.      |
//+------------------------------------------------------------------+
string SchedClock(const int hour, const int minute)
  {
   if(!InpSchedAmPm)
      return(StringFormat("%02d:%02d", hour, minute));

   int h = hour % 12;
   if(h == 0)
      h = 12;

   return(StringFormat("%2d:%02d %s", h, minute, (hour < 12) ? "AM" : "PM"));
  }

//--- A datetime's time of day on that same clock, for the block headings.
string SchedClockOf(const datetime t)
  {
   MqlDateTime st;
   TimeToStruct(t, st);
   return(SchedClock(st.hour, st.min));
  }

//+------------------------------------------------------------------+
//| A candle open written the way a diary entry is: weekday, date,   |
//| time of day.                                                     |
//|                                                                  |
//| The month is in it and the year is not. Most of the block is     |
//| inside this week, where the weekday alone would do - but the D1  |
//| rows are not, and they are the ones that need it: D1 9 is a week |
//| and a half out and D1 33 over a month, so a bare "Tue 06" under  |
//| a heading that says this week reads as the 6th of a month that   |
//| has already gone. Three characters to make the column say what   |
//| it means.                                                        |
//|                                                                  |
//| The year stays out. Nothing here reaches one: the furthest row   |
//| in the block is D1 33, around seven trading weeks ahead.         |
//|                                                                  |
//| The hour is written on whichever clock the block is set to. It   |
//| sits here rather than in the kihon section it used to live in,   |
//| because it now reads an input and MQL5 wants that declared       |
//| above the function using it.                                     |
//+------------------------------------------------------------------+
string SchedWhen(const datetime t)
  {
   if(t <= 0)
      return("-");

   MqlDateTime st;
   TimeToStruct(t, st);

   //--- Clamped rather than trusted. day_of_week is always 0..6 from a valid
   //--- time, but this indexes a fixed array and an out-of-range read here
   //--- would be a crash rather than a wrong weekday.
   int dow = (st.day_of_week >= 0 && st.day_of_week <= 6) ? st.day_of_week : 0;

   return(StringFormat("%s %02d/%02d %s",
                       g_schDow[dow], st.day, st.mon,
                       SchedClock(st.hour, st.min)));
  }

//+------------------------------------------------------------------+
//| How far the trade server runs ahead of UTC, in seconds.          |
//|                                                                  |
//| TimeTradeServer rather than TimeCurrent, and the distinction is  |
//| the whole reason this has a comment. TimeCurrent is the time of  |
//| the last quote, so on a closed market it is stuck at Friday's    |
//| close - and the block read on Sunday would work the offset out   |
//| as two days. TimeTradeServer is calculated rather than quoted    |
//| and keeps running through the weekend, which is exactly when a   |
//| week's timetable is worth looking at.                            |
//|                                                                  |
//| Read fresh each time rather than cached at load. A broker on a   |
//| zone that keeps daylight saving shifts by an hour twice a year,  |
//| and an indicator left on a chart across that weekend would go on |
//| showing the old offset until someone reloaded it.                |
//|                                                                  |
//| Rounded to the minute. The two clocks are read a moment apart    |
//| and no broker offset has ever been a matter of seconds.          |
//+------------------------------------------------------------------+
long SchedServerOffset()
  {
   long d = (long)TimeTradeServer() - (long)TimeGMT();

   //--- Rounded half away from zero, so a -7199 does not become -119 minutes.
   long m = (d >= 0) ? (d + 30) / 60 : (d - 30) / 60;

   return(m * 60);
  }

//--- A server time in the display zone: back to UTC, then out to the offset.
datetime SchedTzShift(const datetime srv)
  {
   if(!InpSchedTz || srv <= 0)
      return(srv);

   return((datetime)((long)srv - SchedServerOffset()
                     + (long)MathRound(InpSchedTzHours * 3600.0)));
  }

//--- The offset written the way a timezone is - "UTC+10", "UTC+5:30" - so the
//--- block says which clock it is in rather than leaving it to be guessed.
string SchedTzTag()
  {
   if(!InpSchedTz)
      return("server");

   long m = (long)MathRound(InpSchedTzHours * 60.0);
   string sign = (m < 0) ? "-" : "+";
   if(m < 0)
      m = -m;

   return((m % 60 == 0)
          ? StringFormat("UTC%s%d", sign, (int)(m / 60))
          : StringFormat("UTC%s%d:%02d", sign, (int)(m / 60), (int)(m % 60)));
  }

//--- A heading's own time, converted and written the same way the rows are.
//--- TIME_MINUTES goes through the block's own clock so a heading cannot read
//--- 24-hour over a column of AM/PM; TIME_DATE has no hour in it to convert.
string SchedTzStamp(const datetime srv, const int fmt)
  {
   if(srv <= 0)
      return("-");

   datetime t = SchedTzShift(srv);

   return((fmt == TIME_MINUTES) ? SchedClockOf(t) : TimeToString(t, fmt));
  }

//--- Width of the time column: "~Thu 24/09 12:00 AM" on the 12-hour clock and
//--- "~Thu 24/09 00:00" on the 24-hour one, plus a bracketed server time of
//--- the same shape when that is asked for.
//---
//--- Both flags for the bracket, because it is only ever written when there is
//--- a conversion to write it beside. Widening on InpSchedTzBoth alone would
//--- pad every row out to a column nothing is ever put in.
int SchedStampWidth()
  {
   int w = InpSchedAmPm ? 19 : 16;

   if(InpSchedTzBoth && InpSchedTz)
      w += InpSchedAmPm ? 11 : 8;

   return(w);
  }

//--- Left-justify to a width StringFormat cannot take as a variable.
string SchedPad(const string s, const int w)
  {
   string r = s;
   for(int i = StringLen(s); i < w; i++)
      r += " ";
   return(r);
  }

//+------------------------------------------------------------------+
//| One schedule row: which timeframe, which number, when that       |
//| candle opens, and whether it has been and gone.                  |
//|                                                                  |
//| Counting is inclusive, so candle k sits at shift (c - k) for as  |
//| long as k <= c, and the time comes off the bar itself - exact,   |
//| with the session breaks and the holidays already in it. Past the |
//| count there is no bar to read, so the time is projected forward  |
//| from the developing candle and flagged with a ~.                 |
//|                                                                  |
//| The timeframe is named only on the first row of its group. The   |
//| rows under it are the same timeframe, and repeating it down the  |
//| column makes the part that changes - the number and the time -   |
//| the quieter half of the row.                                     |
//|                                                                  |
//| state is written back for the caller to colour on: 0 gone by, 1  |
//| running now, 2 still ahead.                                      |
//+------------------------------------------------------------------+
string SchedRow(const ENUM_TIMEFRAMES tf, const int k, const int c,
                const bool head, int &state)
  {
   state = 2;

   string stamp, tail;

   if(c <= 0)
     {
      //--- "no data" is history still arriving and has to hold the panel's
      //--- gate open so the row is rewritten the moment it resolves. "too far"
      //--- is a refusal that will not change; the week anchor is nowhere near
      //--- KIHON_SPAN_CAP, so it is here for completeness rather than because
      //--- anything in this block can reach it.
      if(c == 0)
         g_pUnknown = true;

      stamp = (c == 0) ? " no data" : " too far";
      tail  = "";
     }
   else
     {
      datetime when = 0;

      if(k <= c)
        {
         state = (k == c) ? 1 : 0;
         when  = iTime(_Symbol, tf, c - k);
        }
      else
         when = SchedProject(_Symbol, iTime(_Symbol, tf, 0), k - c,
                             PeriodSeconds(tf));

      stamp = ((state == 2) ? "~" : " ") + SchedWhen(SchedTzShift(when));

      //--- The broker's own clock beside it, time of day only. The date is
      //--- already on the converted stamp and a second one would double the
      //--- width of the column to say the same thing twice - the two differ
      //--- by hours, so they disagree about the date at most once a day.
      if(InpSchedTzBoth && InpSchedTz)
         stamp += " (" + SchedClockOf(when) + ")";

      tail  = (state == 0) ? "done" : ((state == 1) ? "NOW" : "due");
     }

   //--- The stamp is padded to the width of a full one - "~Thu 24/09 00:00",
   //--- or that plus " (00:00)" when the server time rides along - so the
   //--- status column behind it lines up whether the row carries a time or one
   //--- of the two excuses for not having one.
   return(StringFormat("%s %-3s %3d %s %-4s",
                       (tf == (ENUM_TIMEFRAMES)_Period) ? ">" : " ",
                       head ? TfNameOf(tf) : "", k,
                       SchedPad(stamp, SchedStampWidth()), tail));
  }

//+------------------------------------------------------------------+
//| One timeframe's group in the week list: its numbers in order,    |
//| every one of them, whether it has passed or not.                 |
//|                                                                  |
//| All of them because this is a timetable and not a countdown. The |
//| number that went at 08:00 is how you read the one due at 16:00 - |
//| what the market did at the last one is the only evidence there   |
//| is about what the next one is worth.                             |
//+------------------------------------------------------------------+
bool SchedWeekAdd(const ENUM_TIMEFRAMES tf, const datetime anchor,
                  const bool gap, string &txt[], color &clr[], int &n)
  {
   int last = InpKihonCompound ? KIHON_COUNT : KIHON_SIMPLE;

   //--- Counted before anything is written, so a group that will not fit is
   //--- dropped whole rather than cut off halfway down its numbers.
   int rows = 0;
   for(int i = 0; i < last; i++)
      if(KihonNumbers[i] >= SCH_FIRST && KihonNumbers[i] <= SCH_LAST)
         rows++;

   if(rows <= 0 || n + rows + (gap ? 1 : 0) > KP_MAX_ROWS)
      return(false);

   if(gap)
      PanelPush(txt, clr, n, "", InpPanelColor);

   int  c    = KihonCount(_Symbol, tf, anchor);
   bool head = true;
   bool lit  = false;

   for(int i = 0; i < last; i++)
     {
      int k = KihonNumbers[i];
      if(k < SCH_FIRST || k > SCH_LAST)
         continue;

      int    state = 2;
      string row   = SchedRow(tf, k, c, head, state);

      //--- Lime for the number the count is standing on, orange for the next
      //--- one due, and nothing else. A column in which every future row
      //--- shouted would have no next in it, and the ones behind are quiet on
      //--- purpose: they are context, not the reading.
      color col = InpPanelColor;
      if(state == 1)
         col = InpPanelHit;
      else
         if(state == 2 && !lit)
           {
            col = InpPanelNear;
            lit = true;
           }

      PanelPush(txt, clr, n, row, col);
      head = false;
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| One timeframe's group in the today list: the numbers it has not  |
//| reached yet whose candle still opens before the day is out.      |
//|                                                                  |
//| Strictly ahead. A number the count is standing on belongs to the |
//| segment block, which has far more to say about it than a line in |
//| a timetable could, and a number already gone is not upcoming.    |
//| What is left is the part of the day that has not happened.       |
//|                                                                  |
//| The day ends at the anchor plus twenty-four hours rather than at |
//| the next D1 open, which does not exist yet to be read. On a      |
//| session anchor that puts the window one session ahead, which is  |
//| the span the Sess block in the panel counts.                     |
//|                                                                  |
//| That end is also what bounds the group, whichever number window  |
//| is in force: a row is here because its candle opens today, not   |
//| because it was near enough in the list, so the group is at most  |
//| eight rows even with the window opened right up - M15 reaches 76 |
//| in a day and nothing finer is counted.                           |
//+------------------------------------------------------------------+
bool SchedDayAdd(const ENUM_TIMEFRAMES tf, const datetime anchor,
                 const bool gap, string &txt[], color &clr[], int &n)
  {
   int c = KihonCount(_Symbol, tf, anchor);
   if(c <= 0)
     {
      if(c == 0)
         g_pUnknown = true;                    // history still arriving
      return(false);
     }

   //--- Gathered before anything is written, for the same reason the week
   //--- group counts first: the group goes in whole or not at all.
   int      keep[KIHON_COUNT];
   int      rows = 0;
   int      last = InpKihonCompound ? KIHON_COUNT : KIHON_SIMPLE;
   datetime end  = (datetime)((long)anchor + 86400);
   datetime cur  = iTime(_Symbol, tf, 0);
   int      secs = PeriodSeconds(tf);

   for(int i = 0; i < last; i++)
     {
      int k = KihonNumbers[i];
      if(k < SCH_FIRST || k <= c)
         continue;                             // below the window, or gone by
      if(!InpSchedDayAll && k > SCH_LAST)
         break;                                // ascending, so nothing after it

      datetime when = SchedProject(_Symbol, cur, k - c, secs);
      if(when <= 0 || when >= end)
         continue;                             // opens after today is out

      keep[rows++] = k;
     }

   if(rows <= 0 || n + rows + (gap ? 1 : 0) > KP_MAX_ROWS)
      return(false);

   if(gap)
      PanelPush(txt, clr, n, "", InpPanelColor);

   for(int i = 0; i < rows; i++)
     {
      int    state = 2;
      string row   = SchedRow(tf, keep[i], c, i == 0, state);

      //--- Orange on the first only: it is the next thing due on this
      //--- timeframe, and the rest of the group is what follows it.
      PanelPush(txt, clr, n, row, (i == 0) ? InpPanelNear : InpPanelColor);
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| The schedule panel's rows, both sections.                        |
//|                                                                  |
//| A section that finds nothing to say still prints its heading and |
//| "none" underneath it, the way the segment panel does: a block    |
//| that vanished would take its own explanation with it, and by     |
//| late on a Friday the today list is empty for perfectly good      |
//| reasons that an absence cannot state.                            |
//+------------------------------------------------------------------+
void SchedBuild(string &txt[], color &clr[], int &n)
  {
   n = 0;

   if(!g_showSched)
      return;

   if(InpSchedWeek)
     {
      datetime wk = iTime(_Symbol, PERIOD_W1, 0);

      //--- The window as it actually stands, not as it is written above. With
      //--- the compounds switched off 33 is not in the list, so the heading
      //--- would be promising a row the block cannot produce; asking the
      //--- active list for its last number at or below 33 gives 26 instead.
      PanelPush(txt, clr, n,
                StringFormat("%-6s %d-%d from %s  %s", "Week", SCH_FIRST,
                             KihonAtOrBelow(SCH_LAST, InpKihonCompound),
                             SchedTzStamp(wk, TIME_DATE), SchedTzTag()),
                InpPanelColor);

      bool any = false;
      for(int i = 0; i < ArraySize(g_schWeek); i++)
         if(SchedWeekAdd(g_schWeek[i], wk, any, txt, clr, n))
            any = true;

      if(!any)
         PanelPush(txt, clr, n, " none", InpPanelColor);
     }

   if(InpSchedDay)
     {
      //--- The same open the day block counts from, so the two cannot disagree
      //--- about where today started. See PanelDayOpen.
      bool     sess = false;
      datetime day  = PanelDayOpen(sess);

      if(n > 0)
         PanelPush(txt, clr, n, "", InpPanelColor);

      PanelPush(txt, clr, n,
                StringFormat("%-6s ahead from %s  %s", sess ? "Sess" : "Day",
                             SchedTzStamp(day, TIME_MINUTES), SchedTzTag()),
                InpPanelColor);

      bool any = false;
      for(int i = 0; i < ArraySize(g_schDay); i++)
         if(SchedDayAdd(g_schDay[i], day, any, txt, clr, n))
            any = true;

      if(!any)
         PanelPush(txt, clr, n, " none", InpPanelColor);
     }
  }

//+------------------------------------------------------------------+
//| The count panel: a ladder of calendar periods, each counted in   |
//| the candles that divide it.                                      |
//|                                                                  |
//| Year in months, weeks and days; month in days, H4s and H1s; week |
//| the same down to M30; day in H1 down to M1. Each has its own     |
//| anchor, so a row is always counting something its timeframe can  |
//| actually fill - a week counted in H1 reads 26 on Wednesday       |
//| morning, where a week counted from the day open would read 1.    |
//|                                                                  |
//| What you are reading for is agreement across the blocks. One row |
//| on a kihon number is a small turn due; the day, the week and the |
//| month all landing on one at the same candle is a bigger one.     |
//|                                                                  |
//| All three panels are built here, in one pass, and placed against |
//| each other rather than against the chart. The segment block and  |
//| the schedule block are read off the same anchors as the ladder,  |
//| so building them apart would let one of them show a hit for a    |
//| minute another had already counted past.                         |
//+------------------------------------------------------------------+
void UpdatePanel()
  {
   //--- The gate. Every count in the panel steps on a minute boundary, so
   //--- rebuilding between them writes the same 260-odd object properties over
   //--- again. m1 == 0 means M1 history is not there yet, which is not a state
   //--- worth latching, so it falls through and tries again.
   datetime m1 = iTime(_Symbol, PERIOD_M1, 0);
   int      ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);

   if(!g_pDirty && !g_pUnknown && m1 != 0 && m1 == g_pLast && ch == g_pHeight)
      return;

   g_pHeight  = ch;

   //--- A fresh load or an input change rebuilds the objects from scratch
   //--- rather than rewriting them in place. PanelDraw does the sweep, and
   //--- needs telling, because it also has to recreate the block first.
   bool fresh = g_pDirty;

   g_pLast    = m1;
   g_pDirty   = false;
   //--- Cleared before the rows are built; PanelRow sets it again for any row
   //--- that could not be counted, which holds the gate open for the next pass.
   g_pUnknown = false;

   string txt[KP_MAX_ROWS];
   color  clr[KP_MAX_ROWS];
   int    n = 0;

   if(g_showPanel)
     {
      if(InpShowYear)
         PanelAdd("Year", KihonPeriodOpen(true), TIME_DATE,
                  g_kpYear, txt, clr, n);

      if(InpShowMonth)
         PanelAdd("Month", KihonPeriodOpen(false), TIME_DATE,
                  g_kpMonth, txt, clr, n);

      if(InpShowWeek)
         PanelAdd("Week", iTime(_Symbol, PERIOD_W1, 0), TIME_DATE,
                  g_kpWeek, txt, clr, n);

      //--- The day block follows the chart's own anchor when that anchor is a
      //--- custom session time; see PanelDayOpen.
      if(InpShowDay)
        {
         bool     sess    = false;
         datetime dayOpen = PanelDayOpen(sess);

         PanelAdd(sess ? "Sess" : "Day", dayOpen, TIME_MINUTES,
                  g_kpDay, txt, clr, n);

         //--- The nested M1 count. Running M1 across a whole day gives a number
         //--- that is past 257 by breakfast and says nothing after that, so it
         //--- restarts at every kihon suchi H1 candle instead - hour 1, then 9,
         //--- then 17. The label carries the hour it restarted at, because the
         //--- count on its own cannot tell you which phase of the day it is
         //--- measuring. Its own row rather than a member of the day list: the
         //--- rest of that block counts the day, this one counts the segment.
         int      seg  = 0;
         datetime from = KihonSegmentStart(_Symbol, PERIOD_H1, dayOpen,
                                           InpKihonCompound, seg);
         color    col  = InpPanelColor;
         string   row  = PanelRow(PERIOD_M1, from, col,
                                  "M1@" + ((seg > 0) ? IntegerToString(seg) : "-"));

         PanelPush(txt, clr, n, row, col);
        }
     }

   //--- The segment panel. Its rows exist only while an H4 or an H1 is standing
   //--- on a kihon number, which is a handful of minutes in a session, so the
   //--- section keeps its title and says "none" the rest of the time rather
   //--- than vanishing off the chart and taking its own explanation with it.
   string stx[KP_MAX_ROWS];
   color  scl[KP_MAX_ROWS];
   int    sn = 0;

   if(g_showSeg)
     {
      PanelPush(stx, scl, sn, "Kihon Suchi segments", InpPanelColor);

      //--- H4 is read against the month and the week only. A trading day holds
      //--- six H4 candles, so a day-anchored H4 count stops at 6 and could
      //--- never be on a number - checking it would cost a count to learn
      //--- nothing. H1 gets the day as well, where it runs to 24 and the first
      //--- three numbers are all in reach.
      bool any = false;
      if(InpSegH4 && SegAdd(PERIOD_H4, false, false, stx, scl, sn))
         any = true;
      //--- The gap goes in only when an H4 block came first, so a lone H1
      //--- block is not pushed away from the title by an empty row.
      if(InpSegH1 && SegAdd(PERIOD_H1, true, any, stx, scl, sn))
         any = true;

      if(!any)
         PanelPush(stx, scl, sn, " none", InpPanelColor);
     }

   //--- The schedule panel. Built in this same pass for the same reason the
   //--- segment panel is: it reads the week and day opens over again, and a
   //--- block built on its own clock could show a time the panel beside it had
   //--- already counted past.
   string schTxt[KP_MAX_ROWS];
   color  schClr[KP_MAX_ROWS];
   int    schN = 0;

   SchedBuild(schTxt, schClr, schN);

   //--- All three panels, same code, same pass, same text size: they are one
   //--- instrument in three blocks, and three sizes would read as three.
   int size  = (int)MathMax(6, MathMin(20, InpPanelSize));
   int lineH = PanelLineH(size);

   //--- The top edge all three blocks share. Centring works from whichever edge
   //--- the corner names, so it lands in the middle from an upper or a lower
   //--- corner alike. Clamped at the padding so a block taller than the chart
   //--- starts on screen rather than above it.
   //---
   //--- Centred on the TALLEST of the three, not on the count panel. It used to
   //--- be the count panel's own height, on the reasonable grounds that it was
   //--- the long one and the short block beside it should line up with its top
   //--- rather than float in the middle of it. The schedule panel is longer
   //--- still - five timeframes of four numbers before the today list even
   //--- starts - so centring on anything shorter would push its foot off the
   //--- bottom of the chart. They share one top edge either way, which is what
   //--- keeps them reading as one instrument; only where that edge falls has
   //--- changed, and only when the block that moved it is switched on.
   int rows = n;
   if(sn > rows)
      rows = sn;
   if(schN > rows)
      rows = schN;

   int top  = InpPanelY;
   if(InpPanelMiddle && ch > 0)
      top = (int)MathMax(KP_PAD, (ch - rows * lineH) / 2);

   //--- Beside, not below: one block's width plus its two paddings, plus the
   //--- gap. From a left corner X measures rightward and the segment panel
   //--- lands to the right of the count panel; from a right corner X measures
   //--- leftward and it lands to the left of it. Either way it is on the far
   //--- side of the count panel from the chart edge, which is the only side
   //--- with room, and the arithmetic is the same for both.
   int segX = InpPanelX;
   if(n > 0)
      segX += PanelWidth(txt, n, size) + 2 * KP_PAD
              + (int)MathMax(0, InpSegGap);

   //--- And once more along, past the segment panel. Measured the same way, so
   //--- a segment block that widens when an H4 hit opens it pushes the
   //--- schedule along instead of being covered by it. With the segment panel
   //--- switched off sn is 0 and the schedule takes the place it would have
   //--- stood in, rather than leaving a hole.
   int schX = segX;
   if(sn > 0)
      schX += PanelWidth(stx, sn, size) + 2 * KP_PAD
              + (int)MathMax(0, InpSchedGap);

   PanelDraw(PO3_KPANEL, InpPanelCorner, InpPanelX, top,
             txt, clr, n, size, fresh);

   PanelDraw(PO3_KSEG, InpPanelCorner, segX, top,
             stx, scl, sn, size, fresh);

   PanelDraw(PO3_KSCHED, InpPanelCorner, schX, top,
             schTxt, schClr, schN, size, fresh);
  }

//+------------------------------------------------------------------+
//| Redraw the levels if price has crossed a grid cell or a new bar  |
//| opened. Shared by the tick and timer paths so a quiet market     |
//| still rolls the levels onto the new bar.                         |
//+------------------------------------------------------------------+
void RefreshLevels()
  {
   if(g_n <= 0)
      return;

   double   price = iClose(_Symbol, _Period, 0);
   datetime last  = iTime (_Symbol, _Period, 0);
   if(price <= 0.0 || last == 0)
      return;

   long m0 = (long)MathFloor(price * InpScale / (double)g_finest + 1e-9);

   datetime labelTime = last + (datetime)(PeriodSeconds() * InpLabelShift);

   if(g_dirty || m0 != g_anchor)
     {
      Rebuild(price, labelTime);
      g_anchor   = m0;
      g_lastTime = last;
      g_dirty    = false;
     }
   else
      if(last != g_lastTime)
        {
         //--- A new bar changes nothing but where the labels sit, so slide
         //--- them along; the lines are horizontal and do not care.
         for(int i = 0; i < g_lvlLabN; i++)
            ObjectSetInteger(0, g_lvlLab[i], OBJPROP_TIME, labelTime);
         g_lastTime = last;
         ChartRedraw();
        }
  }

//+------------------------------------------------------------------+
//|  UNRAIDED LIQUIDITY - swing highs and lows price has not yet     |
//|  traded back through, the resting orders a sweep is expected     |
//|  to take. Each is a line from the tip of its wick to the right   |
//|  edge; when price takes the level out, the line goes.            |
//|                                                                  |
//|  A swing is found the way a fractal is: a high is a swing high   |
//|  when it stands above the InpLiqLeft candles before it and the   |
//|  InpLiqRight candles after it (6 and 6 by default; a Williams    |
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
//|  swing failed. A wick raid is read off the live candle, so a     |
//|  line goes the moment price trades through; a close raid waits   |
//|  for the candle to close.                                        |
//|                                                                  |
//|  InpLiqTF = PERIOD_CURRENT follows the chart; anything else      |
//|  locks the swings and the raid check to that timeframe. When the |
//|  locked timeframe is higher than the chart's, the line starts at |
//|  the chart candle inside it that printed the wick, not at the    |
//|  locked candle's open, so it sits on the wick you can see.       |
//|                                                                  |
//|  The LAST RAIDED high and low - of the raided swings, the one    |
//|  whose raid is newest on each side - stay on the chart, dashed,  |
//|  from the wick to the candle that raided them, at the same       |
//|  colour and width (InpLiqLastRaid).                              |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES LiqTF()
  {
   return (InpLiqTF == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : InpLiqTF;
  }

bool LiqIsSwing(const MqlRates &r[], const int i, const bool isHigh,
                const int left, const int right)
  {
   double v = isHigh ? r[i].high : r[i].low;
   for(int j = 1; j <= left; j++)                 // older: strictly beyond
     {
      double o = isHigh ? r[i + j].high : r[i + j].low;
      if(isHigh ? (v <= o) : (v >= o))
         return(false);
     }
   for(int j = 1; j <= right; j++)                // newer: at least as far
     {
      double o = isHigh ? r[i - j].high : r[i - j].low;
      if(isHigh ? (v < o) : (v > o))
         return(false);
     }
   return(true);
  }

//--- For a swing from a higher timeframe, the chart candle inside it that
//--- printed the extreme. Falls back to the swing candle's open when the
//--- chart's own history does not reach back that far.
datetime LiqWickTime(const datetime t, const ENUM_TIMEFRAMES tf, const bool isHigh)
  {
   if(!InpLiqSnap || PeriodSeconds(_Period) >= PeriodSeconds(tf))
      return(t);
   MqlRates c[];
   int m = CopyRates(_Symbol, _Period, t, t + PeriodSeconds(tf) - 1, c);
   if(m <= 0)
      return(t);
   int best = 0;
   for(int k = 1; k < m; k++)
      if(isHigh ? (c[k].high > c[best].high) : (c[k].low < c[best].low))
         best = k;
   return(c[best].time);
  }

//--- The swing's price, written at the wick in the line's colour, for the
//--- unraided lines and the last raided ones alike: above a
//--- high and below a low, so it sits clear of the candles that made the
//--- swing. Same size as the PO3 labels, a lighter face so it reads as a
//--- note on the line rather than a level of its own.
void LiqDrawValue(const string name, const datetime at, const double level, const bool isHigh)
  {
   if(!InpLiqValues || ObjectFind(0, name) >= 0)
      return;
   if(!ObjectCreate(0, name, OBJ_TEXT, 0, at, level))
      return;
   ObjectSetString (0, name, OBJPROP_TEXT,       DoubleToString(level, _Digits));
   ObjectSetString (0, name, OBJPROP_FONT,       InpLiqFont);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   (int)MathMax(5, MathMin(20, InpFontSize)));
   ObjectSetInteger(0, name, OBJPROP_COLOR,      isHigh ? InpLiqHighColor : InpLiqLowColor);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,     isHigh ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BACK,       false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   g_liqChanged = true;
  }

void LiqDraw(const datetime t, const double level, const ENUM_TIMEFRAMES tf, const bool isHigh)
  {
   string name = PO3_LIQ + (isHigh ? "H_" : "L_") + IntegerToString((long)t);
   ArrayResize(g_liqKeep, g_liqKeepN + 2, 64);
   g_liqKeep[g_liqKeepN++] = name;
   if(InpLiqValues)
      g_liqKeep[g_liqKeepN++] = name + "_V";     // pruned with its line
   if(isHigh)
      g_liqHiNear = MathMin(g_liqHiNear, level);
   else
      g_liqLoNear = MathMax(g_liqLoNear, level);

   if(ObjectFind(0, name) >= 0)
      return;                                    // a confirmed swing never moves

   datetime start = LiqWickTime(t, tf, isHigh);
   LiqDrawValue(name + "_V", start, level, isHigh);
   if(!ObjectCreate(0, name, OBJ_TREND, 0, start, level, start + PeriodSeconds(_Period), level))
      return;
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT,  true);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT,   false);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      isHigh ? InpLiqHighColor : InpLiqLowColor);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,      InpLiqWidth);
   ObjectSetInteger(0, name, OBJPROP_STYLE,      InpLiqStyle);
   ObjectSetInteger(0, name, OBJPROP_BACK,       true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   ObjectSetString(0, name, OBJPROP_TOOLTIP,
                   "Unraided " + (isHigh ? "high " : "low ") + DoubleToString(level, _Digits) +
                   "  " + TfNameOf(tf) + "  " + TimeToString(t, TIME_DATE | TIME_MINUTES));
   g_liqChanged = true;
  }

//--- A raided swing: find the candle that first went beyond it, and keep the
//--- swing if that raid is the newest seen on its side. When one candle takes
//--- several levels, the furthest one is kept - it was the last to go.
void LiqNoteRaid(const MqlRates &r[], const int i, const double level, const bool isHigh)
  {
   int j = i - 1;
   for(; j >= 0; j--)
     {
      if(InpLiqRaid == LIQ_RAID_CLOSE && j == 0)
         continue;
      double probe = (InpLiqRaid == LIQ_RAID_WICK) ? (isHigh ? r[j].high : r[j].low) : r[j].close;
      if(isHigh ? (probe > level) : (probe < level))
         break;
     }
   if(j < 0)
      return;
   int side = isHigh ? 0 : 1;
   if(g_rdHas[side])
     {
      if(j > g_rdAge[side])
         return;
      if(j == g_rdAge[side] && (isHigh ? (level <= g_rdLevel[side]) : (level >= g_rdLevel[side])))
         return;
     }
   g_rdHas[side]   = true;
   g_rdSwing[side] = r[i].time;
   g_rdRaid[side]  = r[j].time;
   g_rdLevel[side] = level;
   g_rdAge[side]   = j;
  }

//--- For a raid on a higher timeframe, the chart candle inside it that went
//--- beyond the level (a wick raid), or the one it closed on (a close raid).
datetime LiqRaidTime(const datetime t, const ENUM_TIMEFRAMES tf, const double level, const bool isHigh)
  {
   if(!InpLiqSnap || PeriodSeconds(_Period) >= PeriodSeconds(tf))
      return(t);
   MqlRates c[];
   int m = CopyRates(_Symbol, _Period, t, t + PeriodSeconds(tf) - 1, c);
   if(m <= 0)
      return(t);
   if(InpLiqRaid == LIQ_RAID_CLOSE)
      return(c[m - 1].time);
   for(int k = 0; k < m; k++)
      if(isHigh ? (c[k].high > level) : (c[k].low < level))
         return(c[k].time);
   return(t);
  }

//--- One dash of a raided line.
void LiqDash(const string name, const datetime a, const datetime b, const double level,
             const bool isHigh, const string tip)
  {
   if(!ObjectCreate(0, name, OBJ_TREND, 0, a, level, b, level))
      return;
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT,  false);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT,   false);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      isHigh ? InpLiqHighColor : InpLiqLowColor);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,      InpLiqWidth);
   ObjectSetInteger(0, name, OBJPROP_STYLE,      InpLiqWidth <= 1 ? STYLE_DASH : STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_BACK,       true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   ObjectSetString(0, name, OBJPROP_TOOLTIP,     tip);
  }

//--- The last raided level on one side, from its wick to the candle that
//--- raided it. MT5 draws a dashed style only at width 1, so at width 1 it is
//--- one native dashed line; wider, the dashes are separate solid segments of
//--- InpLiqWidth, cut to ~12 px on and ~8 px off at the chart's zoom (a bar
//--- is 2^CHART_SCALE px wide) and never fewer than one bar each. A long span
//--- - a locked higher timeframe on a low chart - stretches the dashes rather
//--- than drawing more than 150 of them.
//--- Returns true when anything was drawn or removed.
bool LiqDrawRaided(const int side, const ENUM_TIMEFRAMES tf, const int scale)
  {
   bool   isHigh = (side == 0);
   string pre    = PO3_LIQR + (isHigh ? "H_" : "L_");
   string key    = "";
   if(g_rdHas[side])
      key = StringFormat("%I64d_%I64d_%d", (long)g_rdSwing[side], (long)g_rdRaid[side], scale);
   if(key == g_rdKey[side])
      return(false);

   bool had = (g_rdKey[side] != "");
   ObjectsDeleteAll(0, pre, -1, -1);
   g_rdKey[side] = "";
   if(key == "")
      return(had);

   double   level = g_rdLevel[side];
   datetime from  = LiqWickTime(g_rdSwing[side], tf, isHigh);
   datetime to    = LiqRaidTime(g_rdRaid[side], tf, level, isHigh);
   int      s     = iBarShift(_Symbol, _Period, from, false);
   int      e     = iBarShift(_Symbol, _Period, to, false);
   if(s < 0 || e < 0)
      return(had);                               // history not loaded: retry next pass
   string tip = "Raided " + (isHigh ? "high " : "low ") + DoubleToString(level, _Digits) +
                "  " + TfNameOf(tf) + "  " + TimeToString(g_rdSwing[side], TIME_DATE | TIME_MINUTES) +
                " -> " + TimeToString(g_rdRaid[side], TIME_DATE | TIME_MINUTES);

   LiqDrawValue(pre + "V", from, level, isHigh);  // swept with the dashes

   if(InpLiqWidth <= 1 || s <= e)
     {
      datetime end = (s <= e) ? from + PeriodSeconds(_Period) : iTime(_Symbol, _Period, e);
      LiqDash(pre + "0", from, end, level, isHigh, tip);
     }
   else
     {
      double px   = (double)(1 << (int)MathMax(0, MathMin(5, scale)));
      int    dash = (int)MathMax(1, MathRound(12.0 / px));
      int    gap  = (int)MathMax(1, MathRound(8.0 / px));
      int    span = s - e;
      if(span > 150 * (dash + gap))
        {
         double f = (double)span / (150.0 * (dash + gap));
         dash = (int)MathCeil(dash * f);
         gap  = (int)MathCeil(gap * f);
        }
      int n = 0;
      for(int k = s; k > e; k -= dash + gap)
        {
         int b = (int)MathMax(e, k - dash);
         LiqDash(pre + IntegerToString(n++), iTime(_Symbol, _Period, k),
                 iTime(_Symbol, _Period, b), level, isHigh, tip);
        }
     }
   g_rdKey[side] = key;
   return(true);
  }

//--- Walk from the newest candle back, carrying the furthest price traded
//--- since. A swing is unraided when nothing newer has gone beyond it, so one
//--- pass settles every swing at once.
void LiqScan(const MqlRates &r[], const int n, const ENUM_TIMEFRAMES tf, const bool isHigh,
             const int left, const int right)
  {
   double reach = isHigh ? -DBL_MAX : DBL_MAX;

   for(int i = 0; i < n; i++)
     {
      //--- bars 1..right must all be closed, and `left` bars must exist behind
      if(i > right && i + left < n && LiqIsSwing(r, i, isHigh, left, right))
        {
         double level  = isHigh ? r[i].high : r[i].low;
         bool   raided = isHigh ? (reach > level) : (reach < level);
         if(!raided)
            LiqDraw(r[i].time, level, tf, isHigh);
         else if(InpLiqLastRaid)
            LiqNoteRaid(r, i, level, isHigh);
        }

      if(InpLiqRaid == LIQ_RAID_CLOSE && i == 0)
         continue;                               // the live candle has not closed yet
      double probe = (InpLiqRaid == LIQ_RAID_WICK) ? (isHigh ? r[i].high : r[i].low) : r[i].close;
      reach = isHigh ? MathMax(reach, probe) : MathMin(reach, probe);
     }
  }

//--- Rescan and sync the lines, but only when the gate says something can
//--- have changed. The timer calls it too, which is what fills in a locked
//--- timeframe whose history was not loaded on the first call.
//--- Returns true when a line was added or removed.
bool RefreshLiquidity()
  {
   if(!InpShowLiq)
      return(false);                             // nothing drawn; OnDeinit sweeps

   ENUM_TIMEFRAMES tf = LiqTF();
   datetime bar = iTime(_Symbol, tf, 0);
   if(bar == 0)
      return(false);                             // history not ready

   //--- a zoom change re-cuts the dashes, so it opens the gate too
   int scale = (int)ChartGetInteger(0, CHART_SCALE);
   if(!g_liqDirty && bar == g_liqBar && scale == g_liqScale)
     {
      if(InpLiqRaid == LIQ_RAID_CLOSE)
         return(false);                          // a close raid needs a new candle
      double hi = iHigh(_Symbol, tf, 0);
      double lo = iLow (_Symbol, tf, 0);
      if(hi <= 0.0 || (hi <= g_liqHiNear && lo >= g_liqLoNear))
         return(false);
     }

   int left  = (int)MathMax(1, InpLiqLeft);
   int right = (int)MathMax(1, InpLiqRight);
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int n = CopyRates(_Symbol, tf, 0, (int)MathMax(left + right + 2, InpLiqLookback), r);
   if(n < left + right + 2)
      return(false);                             // not loaded yet: keep what is drawn

   g_liqKeepN   = 0;
   g_liqChanged = false;
   g_liqHiNear  = DBL_MAX;
   g_liqLoNear  = -DBL_MAX;
   g_rdHas[0]   = false;
   g_rdHas[1]   = false;
   if(InpLiqHighs)
      LiqScan(r, n, tf, true, left, right);
   if(InpLiqLows)
      LiqScan(r, n, tf, false, left, right);

   //--- Prune against our own list, not every object on the chart.
   for(int i = 0; i < g_liqNamesN; i++)
     {
      bool keep = false;
      for(int k = 0; k < g_liqKeepN && !keep; k++)
         keep = (g_liqKeep[k] == g_liqNames[i]);
      if(!keep)
        {
         ObjectDelete(0, g_liqNames[i]);
         g_liqChanged = true;
        }
     }
   ArrayResize(g_liqNames, g_liqKeepN);
   for(int k = 0; k < g_liqKeepN; k++)
      g_liqNames[k] = g_liqKeep[k];
   g_liqNamesN = g_liqKeepN;

   //--- with InpLiqLastRaid off nothing is noted, so both sides clear
   if(LiqDrawRaided(0, tf, scale))
      g_liqChanged = true;
   if(LiqDrawRaided(1, tf, scale))
      g_liqChanged = true;

   g_liqScale = scale;
   g_liqBar   = bar;
   g_liqDirty = false;
   return(g_liqChanged);
  }

//+------------------------------------------------------------------+
//|  FAIR VALUE GAPS - three-candle imbalances price has not yet     |
//|  traded back through. Each is a box from the middle candle to    |
//|  the right edge; when price fills it, the box goes.              |
//|                                                                  |
//|  Of three candles in a row, a bullish gap is the space between   |
//|  the first candle's high and the third candle's low, when the    |
//|  third's low is above the first's high - the middle candle moved |
//|  so fast that no candle traded that range both ways. A bearish   |
//|  gap mirrors it: the third's high below the first's low.         |
//|                                                                  |
//|  A gap is only confirmed once its third candle has closed, so a  |
//|  box never appears and then vanishes because the live candle     |
//|  wicked back. Mitigation is read off the wicks of the candles    |
//|  after the third, the live one included, so a box goes the       |
//|  moment price reaches it:                                        |
//|    FVG_MIT_FULL   the far edge - the whole gap is filled         |
//|    FVG_MIT_HALF   the middle (the consequent encroachment)       |
//|    FVG_MIT_TOUCH  the near edge - any trade into the gap         |
//|                                                                  |
//|  InpFvgTF = PERIOD_CURRENT follows the chart; anything else      |
//|  locks the gaps and the mitigation check to that timeframe, and  |
//|  the box starts at the locked middle candle's open.              |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES FvgTF()
  {
   return (InpFvgTF == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : InpFvgTF;
  }

//--- The price a wick has to reach for the gap to count as mitigated. A
//--- bullish gap sits below price and is reached by a low at or under this; a
//--- bearish one by a high at or over it.
double FvgTrigger(const double bot, const double top, const bool bull)
  {
   if(InpFvgMit == FVG_MIT_HALF)
      return((bot + top) / 2.0);
   if(InpFvgMit == FVG_MIT_TOUCH)
      return(bull ? top : bot);
   return(bull ? bot : top);
  }

void FvgDraw(const datetime t, const double bot, const double top,
             const bool bull, const ENUM_TIMEFRAMES tf, const datetime edge)
  {
   string name = PO3_FVG + (bull ? "B_" : "S_") + IntegerToString((long)t);
   ArrayResize(g_fvgKeep, g_fvgKeepN + 1, 64);
   g_fvgKeep[g_fvgKeepN++] = name;
   double trig = FvgTrigger(bot, top, bull);
   if(bull)
      g_fvgBullNear = MathMax(g_fvgBullNear, trig);
   else
      g_fvgBearNear = MathMin(g_fvgBearNear, trig);

   //--- a confirmed gap never moves; only its right edge follows the chart
   if(ObjectFind(0, name) >= 0)
     {
      if((datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 1) != edge)
        {
         ObjectSetInteger(0, name, OBJPROP_TIME, 1, edge);
         g_fvgChanged = true;
        }
      return;
     }

   if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, t, top, edge, bot))
      return;
   ObjectSetInteger(0, name, OBJPROP_COLOR,      bull ? InpFvgBullColor : InpFvgBearColor);
   ObjectSetInteger(0, name, OBJPROP_FILL,       true);
   ObjectSetInteger(0, name, OBJPROP_BACK,       true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   ObjectSetString(0, name, OBJPROP_TOOLTIP,
                   (bull ? "Bullish FVG " : "Bearish FVG ") + DoubleToString(bot, _Digits) +
                   " - " + DoubleToString(top, _Digits) +
                   "  " + TfNameOf(tf) + "  " + TimeToString(t, TIME_DATE | TIME_MINUTES));
   g_fvgChanged = true;
  }

//--- Walk from the newest candle back, carrying the lowest low and highest
//--- high traded AFTER each gap's third candle. A gap is unmitigated when
//--- nothing since has reached its trigger, so one pass settles every gap.
//--- m is the middle candle: m - 1 the third (closed, so m >= 2), m + 1 the
//--- first, and 0 .. m - 2 the candles that can mitigate it.
void FvgScan(const MqlRates &r[], const int n, const ENUM_TIMEFRAMES tf, const datetime edge)
  {
   double minGap = MathMax(0, InpFvgMinPts) * _Point;
   double lo = DBL_MAX;
   double hi = -DBL_MAX;

   for(int m = 2; m + 1 < n; m++)
     {
      lo = MathMin(lo, r[m - 2].low);
      hi = MathMax(hi, r[m - 2].high);

      if(InpFvgBull && r[m - 1].low > r[m + 1].high)
        {
         double bot = r[m + 1].high, top = r[m - 1].low;
         if(top - bot >= minGap && lo > FvgTrigger(bot, top, true))
            FvgDraw(r[m].time, bot, top, true, tf, edge);
        }
      if(InpFvgBear && r[m - 1].high < r[m + 1].low)
        {
         double bot = r[m - 1].high, top = r[m + 1].low;
         if(top - bot >= minGap && hi < FvgTrigger(bot, top, false))
            FvgDraw(r[m].time, bot, top, false, tf, edge);
        }
     }
  }

//--- Rescan and sync the boxes, but only when the gate says something can
//--- have changed. The timer calls it too, which fills in a locked timeframe
//--- whose history was not loaded on the first call.
//--- Returns true when a box was added, stretched or removed.
bool RefreshFvg()
  {
   if(!InpShowFvg)
      return(false);                             // nothing drawn; OnDeinit sweeps

   ENUM_TIMEFRAMES tf = FvgTF();
   datetime bar  = iTime(_Symbol, tf, 0);
   datetime last = iTime(_Symbol, _Period, 0);
   if(bar == 0 || last == 0)
      return(false);                             // history not ready
   datetime edge = last + PeriodSeconds(_Period);

   if(!g_fvgDirty && bar == g_fvgBar && edge == g_fvgEdge)
     {
      double hi = iHigh(_Symbol, tf, 0);
      double lo = iLow (_Symbol, tf, 0);
      if(hi <= 0.0 || (lo > g_fvgBullNear && hi < g_fvgBearNear))
         return(false);
     }

   MqlRates r[];
   ArraySetAsSeries(r, true);
   int n = CopyRates(_Symbol, tf, 0, (int)MathMax(4, InpFvgLookback), r);
   if(n < 4)
      return(false);                             // not loaded yet: keep what is drawn

   g_fvgKeepN    = 0;
   g_fvgChanged  = false;
   g_fvgBullNear = -DBL_MAX;
   g_fvgBearNear = DBL_MAX;
   FvgScan(r, n, tf, edge);

   //--- Prune against our own list, not every object on the chart.
   for(int i = 0; i < g_fvgNamesN; i++)
     {
      bool keep = false;
      for(int k = 0; k < g_fvgKeepN && !keep; k++)
         keep = (g_fvgKeep[k] == g_fvgNames[i]);
      if(!keep)
        {
         ObjectDelete(0, g_fvgNames[i]);
         g_fvgChanged = true;
        }
     }
   ArrayResize(g_fvgNames, g_fvgKeepN);
   for(int k = 0; k < g_fvgKeepN; k++)
      g_fvgNames[k] = g_fvgKeep[k];
   g_fvgNamesN = g_fvgKeepN;

   g_fvgBar   = bar;
   g_fvgEdge  = edge;
   g_fvgDirty = false;
   return(g_fvgChanged);
  }

//+------------------------------------------------------------------+
//| The kihon panel buttons: one click shows or hides a block.       |
//|                                                                  |
//| The state starts from the three "Show the ..." inputs. A         |
//| timeframe change reloads the indicator, and a toggle lost on     |
//| every switch would be worse than no toggle, so OnDeinit parks    |
//| the state in a terminal global keyed by chart id and the next    |
//| OnInit adopts it - the session timer's trick. Any other reload,  |
//| an input change included, starts from the inputs again, so       |
//| setting one in the dialog always does what it says.              |
//+------------------------------------------------------------------+
void ToggleInit(const int reason)
  {
   g_gvToggle  = "PO3_Toggle_" + IntegerToString(ChartID());
   g_showPanel = InpShowPanel;
   g_showSeg   = InpShowSeg;
   g_showSched = InpShowSched;

   if(reason == REASON_CHARTCHANGE && GlobalVariableCheck(g_gvToggle))
     {
      int bits    = (int)GlobalVariableGet(g_gvToggle);
      g_showPanel = (bits & 1) != 0;
      g_showSeg   = (bits & 2) != 0;
      g_showSched = (bits & 4) != 0;
     }
   GlobalVariableDel(g_gvToggle);
  }

void ToggleSave(const int reason)
  {
   if(reason == REASON_CHARTCHANGE)
      GlobalVariableSet(g_gvToggle, (double)((g_showPanel ? 1 : 0) |
                                             (g_showSeg   ? 2 : 0) |
                                             (g_showSched ? 4 : 0)));
   else
      GlobalVariableDel(g_gvToggle);
  }

//--- One button. Fixed properties once; state and colours on every call.
//--- Lit in the panel's hit colour while its block is showing, dimmed and
//--- unpressed while it is hidden.
void ButtonDraw(const string key, const string text, const int slot, const bool on)
  {
   string name = PO3_BTN + key;
   int    w    = 76;
   int    h    = 20;
   int    gap  = 4;

   if(ObjectFind(0, name) < 0)
     {
      //--- A button is placed by its top-left corner whatever corner it is
      //--- measured from, so from a right or lower corner the distance has to
      //--- take in its own width or height to keep it on screen.
      bool right = (InpButtonCorner == CORNER_RIGHT_UPPER || InpButtonCorner == CORNER_RIGHT_LOWER);
      bool lower = (InpButtonCorner == CORNER_LEFT_LOWER  || InpButtonCorner == CORNER_RIGHT_LOWER);
      int  x     = InpButtonX + slot * (w + gap) + (right ? w : 0);
      int  y     = InpButtonY + (lower ? h : 0);

      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER,       InpButtonCorner);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE,    x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE,    y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE,        w);
      ObjectSetInteger(0, name, OBJPROP_YSIZE,        h);
      ObjectSetString (0, name, OBJPROP_TEXT,         text);
      ObjectSetString (0, name, OBJPROP_FONT,         "Consolas");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE,     8);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, InpPanelBorder);
      ObjectSetInteger(0, name, OBJPROP_BACK,         false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE,   false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED,     false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,       true);
      ObjectSetString (0, name, OBJPROP_TOOLTIP,      "Show or hide the kihon " + text + " block");
     }
   ObjectSetInteger(0, name, OBJPROP_STATE,   on);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, InpPanelBg);
   ObjectSetInteger(0, name, OBJPROP_COLOR,   on ? InpPanelHit : clrDimGray);
  }

void UpdateButtons()
  {
   if(!InpShowButtons)
     {
      ObjectsDeleteAll(0, PO3_BTN, -1, -1);
      return;
     }
   ButtonDraw("P", "Count",    0, g_showPanel);
   ButtonDraw("S", "Segments", 1, g_showSeg);
   ButtonDraw("C", "Schedule", 2, g_showSched);
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_OBJECT_CLICK || StringFind(sparam, PO3_BTN) != 0)
      return;

   string key = StringSubstr(sparam, StringLen(PO3_BTN));
   if(key == "P")
      g_showPanel = !g_showPanel;
   else if(key == "S")
      g_showSeg = !g_showSeg;
   else if(key == "C")
      g_showSched = !g_showSched;
   else
      return;

   //--- the whole panel is re-laid out: a block switched off hands its place
   //--- along to the one after it
   g_pDirty = true;
   UpdatePanel();
   UpdateButtons();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Ticks are not guaranteed once a minute, so the clock runs off a  |
//| timer instead. Without it the countdown would sit frozen through |
//| a quiet session and read wrong.                                  |
//+------------------------------------------------------------------+
void OnTimer()
  {
   RefreshLevels();
   RefreshLiquidity();
   RefreshFvg();
   UpdateCount();
   UpdatePanel();
   UpdateClock();
   UpdateSession();
   UpdateButtons();
   ChartRedraw();
  }

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
   if(rates_total <= 0)
      return(rates_total);

   //--- Deliberately NOT the panel or the session timer. Both are one-second
   //--- displays driven by OnTimer, and a tick tells them nothing a second of
   //--- wall clock does not - the panel's counts cannot move except on a minute
   //--- boundary. Leaving them here had every tick rewrite them. The clock
   //--- stays: it is anchored to price and rides it between seconds.
   RefreshLevels();
   bool liq = RefreshLiquidity();
   bool fvg = RefreshFvg();
   if(liq || fvg)
      ChartRedraw();
   UpdateCount();
   UpdateClock();

   return(rates_total);
  }
//+------------------------------------------------------------------+
