// Minimal C++ stand-in for the part of the MQL5 API the bottom-up stack EAs use.
// Only for mq5check.py: it lets g++ parse and type-check an .mq5 file. Nothing here runs.
#pragma once
#include <string>
#include <vector>

typedef std::string string;
typedef long long datetime;
// ulong and uint come from <sys/types.h>

enum ENUM_TIMEFRAMES { PERIOD_M1, PERIOD_M2, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4, PERIOD_D1 };
enum { INIT_SUCCEEDED = 0, INIT_FAILED = 1, INVALID_HANDLE = -1 };
enum ENUM_SYM_D { SYMBOL_BID, SYMBOL_ASK, SYMBOL_POINT, SYMBOL_TRADE_TICK_VALUE, SYMBOL_TRADE_TICK_SIZE,
                  SYMBOL_VOLUME_STEP, SYMBOL_VOLUME_MIN, SYMBOL_VOLUME_MAX };
enum ENUM_SYM_I { SYMBOL_SPREAD, SYMBOL_TRADE_STOPS_LEVEL, SYMBOL_DIGITS };
enum ENUM_ACC_D { ACCOUNT_EQUITY, ACCOUNT_MARGIN_FREE, ACCOUNT_BALANCE };
enum ENUM_POS_S { POSITION_SYMBOL, POSITION_COMMENT };
enum ENUM_POS_I { POSITION_MAGIC, POSITION_TYPE, POSITION_TIME };
enum ENUM_POS_D { POSITION_SL, POSITION_PRICE_OPEN, POSITION_PRICE_CURRENT, POSITION_VOLUME };
enum { POSITION_TYPE_BUY, POSITION_TYPE_SELL };
enum ENUM_ORDER_TYPE { ORDER_TYPE_BUY, ORDER_TYPE_SELL };
enum ENUM_DEAL_I { DEAL_MAGIC, DEAL_ENTRY, DEAL_TIME };
enum ENUM_DEAL_D { DEAL_PROFIT, DEAL_SWAP, DEAL_COMMISSION };
enum { DEAL_ENTRY_IN, DEAL_ENTRY_OUT };

struct MqlRates { datetime time; double open, high, low, close; long tick_volume; int spread; long real_volume; };
struct MqlDateTime { int year, mon, day, hour, min, sec, day_of_week, day_of_year; };

// MQL5 dynamic array ("MqlRates r[];")
template <class T> struct DynArr { std::vector<T> v; T &operator[](int i) { return v[i]; } };

template <class A> int CopyRates(string, ENUM_TIMEFRAMES, datetime, datetime, A &);
template <class A> int CopyBuffer(int, int, int, int, A &);
template <class A> bool ArraySetAsSeries(A &, bool);
template <class A> int ArraySize(A &);
int iIchimoku(string, ENUM_TIMEFRAMES, int, int, int);
int iATR(string, ENUM_TIMEFRAMES, int);
datetime iTime(string, ENUM_TIMEFRAMES, int);
bool IndicatorRelease(int);
bool SymbolSelect(string, bool);
double SymbolInfoDouble(string, ENUM_SYM_D);
long SymbolInfoInteger(string, ENUM_SYM_I);
double AccountInfoDouble(ENUM_ACC_D);
int PositionsTotal();
ulong PositionGetTicket(int);
bool PositionSelectByTicket(ulong);
string PositionGetString(ENUM_POS_S);
long PositionGetInteger(ENUM_POS_I);
double PositionGetDouble(ENUM_POS_D);
bool OrderCalcMargin(ENUM_ORDER_TYPE, string, double, double, double &);
bool HistorySelect(datetime, datetime);
int HistoryDealsTotal();
ulong HistoryDealGetTicket(int);
long HistoryDealGetInteger(ulong, ENUM_DEAL_I);
double HistoryDealGetDouble(ulong, ENUM_DEAL_D);
bool GlobalVariableCheck(string);
double GlobalVariableGet(string);
datetime GlobalVariableSet(string, double);
void GlobalVariablesFlush();
datetime TimeCurrent();
datetime TimeLocal();
bool TimeToStruct(datetime, MqlDateTime &);
double NormalizeDouble(double, int);
double MathMax(double, double);
double MathMin(double, double);
double MathFloor(double);
double MathAbs(double);
string IntegerToString(long);
string DoubleToString(double, int = 8);
string StringFormat(string, ...);
int StringLen(string);
int StringSplit(string, char, DynArr<string> &);
int StringTrimLeft(string &);
int StringTrimRight(string &);
template <class... A> void Print(A...);
bool SendNotification(string);
template <class... A> void Alert(A...);

class CTrade
{
public:
   void SetDeviationInPoints(ulong);
   void SetExpertMagicNumber(ulong);
   bool SetTypeFillingBySymbol(string);
   bool Buy(double, string, double, double, double, string);
   bool Sell(double, string, double, double, double, string);
   bool PositionClose(ulong);
   bool PositionModify(ulong, double, double);
   uint ResultRetcode();
   double ResultPrice();
};
