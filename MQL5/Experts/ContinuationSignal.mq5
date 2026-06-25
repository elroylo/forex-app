//+------------------------------------------------------------------+
//|                                        ContinuationSignal.mq5     |
//|                  Trend-continuation signal EA with multi-channel  |
//|                  alerts (MT5 push, email, popup, sound, Telegram) |
//+------------------------------------------------------------------+
// v0.2 - iCustom signatures + buffer indices CONFIRMED from indicator
// source (ATR_Adaptive, VQZL, MA_of_RSI). STC is compiled-only; its
// value is buffer 0 (single plot) - verify with BufferProbe if needed.
//
// Built as an EA (not an indicator) because Telegram needs WebRequest(),
// which MT5 blocks inside indicators.
//
// INSTALL (in MT5 -> File -> Open Data Folder -> MQL5):
//   1. Copy from this repo into MQL5\Indicators\ :
//        ATR_Adaptive_DoubleSmoothed.mq5   (compile, F7)
//        VQZL_v2.3.mq5                      (compile, F7)
//        MA_of_RSI.mq5                      (compile, F7; needs Examples\RSI)
//        SchaffTrendCycle.ex5              (already compiled)
//   2. Copy ContinuationSignal.mq5 into MQL5\Experts\ and compile (F7).
//   3. Tools > Options > Expert Advisors: tick "Allow WebRequest for
//      listed URL" and add  https://api.telegram.org . Configure Email
//      (SMTP) for email alerts; set MetaQuotes ID for push.
//   4. Drag the EA onto the chart, fill Telegram token/chat id, enable
//      "Algo Trading".
//+------------------------------------------------------------------+
#property copyright "forex-app"
#property version   "1.00"
#property description "Trend-continuation signals (D1+H4 filter) with MT5 push, email, popup, sound & Telegram alerts."

//==================== INPUTS ====================
input group "=== Higher-timeframe trend filter ==="
input ENUM_TIMEFRAMES InpTrendTF1     = PERIOD_D1;  // Trend TF #1
input ENUM_TIMEFRAMES InpTrendTF2     = PERIOD_H4;  // Trend TF #2
input bool            InpUseTrendTF1   = true;       // Require TF#1 alignment
input bool            InpUseTrendTF2   = true;       // Require TF#2 alignment
input bool            InpUseChartTrend = true;       // Require chart-TF baseline too

input group "=== ATR Adaptive Double Smoothed EMA (baseline) [iCustom] ==="
input string             InpAA_Name   = "ATR_Adaptive_DoubleSmoothed"; // indicator name
input double             InpAA_Period = 25.0;          // Period (this indicator uses a DOUBLE)
input ENUM_APPLIED_PRICE InpAA_Price  = PRICE_CLOSE;   // Price
input int                InpAA_Buffer = 0;             // value buffer (0 = EMA value)
input bool               InpAA_PriceVsLine = true;     // bullish only if price is on the right side of the line

input group "=== MA of RSI (momentum) [iCustom] ==="
input string             InpMARSI_Name   = "MA_of_RSI"; // indicator name
input int                InpRSI_Period   = 6;          // RSI1: Period
input ENUM_APPLIED_PRICE InpRSI_Price    = PRICE_CLOSE;// RSI1: Applied Price
input int                InpRSI_MAPeriod = 3;          // MA Period
input ENUM_MA_METHOD     InpRSI_MAMethod = MODE_SMMA;  // MA Method (Smoothed)
input int                InpMARSI_Buffer = 0;          // value buffer (0 = MA of RSI)
input double             InpRSI_Mid      = 50.0;       // midline

input group "=== VQZL v2.3 (volatility/quality) [iCustom] ==="
input string         InpVQ_Name      = "VQZL_v2.3"; // indicator name
input int            InpVQ_SmoothPer = 10;          // Price smoothing period
input ENUM_MA_METHOD InpVQ_SmoothMet = MODE_LWMA;   // Price smoothing method (Linear weighted)
input double         InpVQ_FilterATR  = 7.5;        // Filter (% of ATR)
input int            InpVQ_Buffer     = 0;          // value buffer (0 = VQZL value)
input double         InpVQ_Zero        = 0.0;       // bullish if value > this (or rising)

input group "=== Schaff Trend Cycle [iCustom] ==="
input string InpSTC_Name   = "SchaffTrendCycle"; // indicator name
input int    InpSTC_MAShort = 21;   // MAShort
input int    InpSTC_MALong  = 50;   // MALong
input int    InpSTC_Cycle   = 10;   // Cycle
input int    InpSTC_Buffer  = 0;    // value buffer (0 = STC value) - VERIFY if unsure
input double InpSTC_Oversold   = 25.0; // oversold
input double InpSTC_Overbought = 75.0; // overbought
input double InpSTC_Mid          = 50.0; // midline

input group "=== ATR volatility check (native iATR) ==="
input int    InpATR_Period    = 14;    // ATR period
input int    InpATR_Lookback  = 50;    // bars to average ATR
input double InpATR_MinPctAvg  = 60.0; // skip if ATR < this % of its average

input group "=== Signal discipline ==="
input int  InpCooldownBars    = 8;    // no same-direction signal for N bars
input bool InpRequireFresh    = true; // only fire on invalid->valid transition

input group "=== Visuals (chart arrows) ==="
input bool  InpDrawHistory  = true;     // draw past signals on attach
input int   InpHistoryBars  = 600;      // how many bars of history to scan
input color InpBuyColor     = clrLime;  // buy arrow color
input color InpSellColor    = clrRed;   // sell arrow color

input group "=== Alerts ==="
input bool   InpAlertPush     = true;  // MT5 push notification
input bool   InpAlertEmail    = true;  // email (configure SMTP in Options)
input bool   InpAlertPopup    = true;  // popup
input bool   InpAlertSound    = true;  // sound
input string InpSoundFile     = "alert.wav";
input bool   InpAlertTelegram = true;  // Telegram
input string InpTgBotToken    = "";    // Telegram bot token
input string InpTgChatId      = "";    // Telegram chat id

//==================== GLOBALS ====================
int      hAA_TF1=INVALID_HANDLE, hAA_TF2=INVALID_HANDLE, hAA_Chart=INVALID_HANDLE;
int      hVQ=INVALID_HANDLE, hSTC=INVALID_HANDLE, hMARSI=INVALID_HANDLE, hATR=INVALID_HANDLE;
datetime g_lastBarTime=0;
datetime g_lastBuyTime=0, g_lastSellTime=0;
bool     g_prevBuyAll=false, g_prevSellAll=false;
bool     g_historyDone=false;

//+------------------------------------------------------------------+
bool IsValidNum(const double x){ return(MathIsValidNumber(x) && x!=EMPTY_VALUE); }

//--- single buffer value at a given shift (0=forming, 1=last closed) ---
double Val(const int handle,const int buf,const int shift)
{
   double a[];
   if(handle==INVALID_HANDLE) return(EMPTY_VALUE);
   if(CopyBuffer(handle,buf,shift,1,a)!=1) return(EMPTY_VALUE);
   return(a[0]);
}

string TFToStr(const ENUM_TIMEFRAMES tf){ return(StringSubstr(EnumToString(tf),7)); }

//--- ATR-adaptive trend direction on a given timeframe at time t ----
//    returns +1 bullish, -1 bearish, 0 undefined
int TrendDirAt(const int handle,const ENUM_TIMEFRAMES tf,const datetime t)
{
   if(handle==INVALID_HANDLE) return(0);
   int sh = iBarShift(_Symbol,tf,t,false);
   if(sh<1) sh=1;                               // use a closed bar
   double line=Val(handle,InpAA_Buffer,sh);
   double prev=Val(handle,InpAA_Buffer,sh+1);
   if(!IsValidNum(line) || !IsValidNum(prev) || line==0.0 || prev==0.0) return(0);
   double c=iClose(_Symbol,tf,sh);
   bool rising=(line>prev), falling=(line<prev);
   if(rising  && (!InpAA_PriceVsLine || c>line)) return(1);
   if(falling && (!InpAA_PriceVsLine || c<line)) return(-1);
   return(0);
}

//--- ATR "not too low" check at 'shift' -----------------------------
bool AtrOk(const int shift)
{
   double a[];
   if(CopyBuffer(hATR,0,shift,InpATR_Lookback,a)!=InpATR_Lookback) return(false);
   double sum=0; for(int i=0;i<InpATR_Lookback;i++) sum+=a[i];
   double avg=sum/InpATR_Lookback;
   double now=a[InpATR_Lookback-1];
   if(avg<=0) return(false);
   return( now >= avg*(InpATR_MinPctAvg/100.0) );
}

bool HandlesReady()
{
   if(BarsCalculated(hAA_Chart)<2) return(false);
   if(BarsCalculated(hVQ)<2)       return(false);
   if(BarsCalculated(hSTC)<2)      return(false);
   if(BarsCalculated(hMARSI)<2)    return(false);
   if(BarsCalculated(hATR)<2)      return(false);
   return(true);
}

//+------------------------------------------------------------------+
void DrawArrow(const bool isBuy,const datetime t,const double price)
{
   string name="CS_"+(isBuy?"BUY_":"SELL_")+(string)(long)t;
   if(ObjectFind(0,name)>=0) return;             // idempotent (no duplicates)
   ObjectCreate(0,name,OBJ_ARROW,0,t,price);
   ObjectSetInteger(0,name,OBJPROP_ARROWCODE,isBuy?233:234);
   ObjectSetInteger(0,name,OBJPROP_COLOR,isBuy?InpBuyColor:InpSellColor);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,2);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,isBuy?ANCHOR_TOP:ANCHOR_BOTTOM);
}

//+------------------------------------------------------------------+
string UrlEncode(const string s)
{
   string out="";
   uchar bytes[]; int n=StringToCharArray(s,bytes,0,StringLen(s),CP_UTF8);
   for(int i=0;i<n;i++){
      uchar c=bytes[i];
      if((c>='0'&&c<='9')||(c>='A'&&c<='Z')||(c>='a'&&c<='z')||c=='-'||c=='_'||c=='.'||c=='~')
         out+=CharToString(c);
      else
         out+=StringFormat("%%%02X",c);
   }
   return(out);
}

void SendTelegram(const string text)
{
   if(InpTgBotToken=="" || InpTgChatId=="") { Print("Telegram skipped: token/chat id empty"); return; }
   string url="https://api.telegram.org/bot"+InpTgBotToken+"/sendMessage";
   string body="chat_id="+InpTgChatId+"&text="+UrlEncode(text);
   uchar post[]; int len=StringToCharArray(body,post,0,StringLen(body),CP_UTF8);
   ArrayResize(post,len);                         // drop trailing null
   uchar result[]; string rhead;
   ResetLastError();
   int code=WebRequest("POST",url,"Content-Type: application/x-www-form-urlencoded\r\n",5000,post,result,rhead);
   if(code==-1) PrintFormat("Telegram WebRequest failed err=%d. Add https://api.telegram.org to allowed URLs + enable Algo Trading.",GetLastError());
   else if(code!=200) PrintFormat("Telegram HTTP %d: %s",code,CharArrayToString(result));
}

void SendAllAlerts(const bool isBuy,const double price,const datetime t,const string summary)
{
   string dir=isBuy?"BUY":"SELL";
   string head=dir+" Signal - "+_Symbol+" ("+TFToStr((ENUM_TIMEFRAMES)_Period)+")";
   string msg =head+"\n"+summary+
               "\nEntry Price: "+DoubleToString(price,_Digits)+
               "\nSignal Time: "+TimeToString(t,TIME_DATE|TIME_MINUTES);
   if(InpAlertPopup)    Alert(msg);
   if(InpAlertSound)    PlaySound(InpSoundFile);
   if(InpAlertPush)     SendNotification(msg);
   if(InpAlertEmail)    SendMail(head,msg);
   if(InpAlertTelegram) SendTelegram(msg);
}

//+------------------------------------------------------------------+
//| Evaluate a single CLOSED bar (shift>=1). Fires/draws if valid.   |
//+------------------------------------------------------------------+
void ProcessBar(const int shift,const bool allowAlert)
{
   datetime tBar=iTime(_Symbol,_Period,shift);
   if(tBar==0) return;

   // ---- trend gate (ATR-Adaptive EMA direction) ----
   int t1 = InpUseTrendTF1   ? TrendDirAt(hAA_TF1 ,InpTrendTF1,tBar) : 0;
   int t2 = InpUseTrendTF2   ? TrendDirAt(hAA_TF2 ,InpTrendTF2,tBar) : 0;
   int tc = InpUseChartTrend ? TrendDirAt(hAA_Chart,(ENUM_TIMEFRAMES)_Period,tBar) : 0;

   bool trendBuy  = (!InpUseTrendTF1||t1==1) && (!InpUseTrendTF2||t2==1) && (!InpUseChartTrend||tc==1);
   bool trendSell = (!InpUseTrendTF1||t1==-1)&& (!InpUseTrendTF2||t2==-1)&& (!InpUseChartTrend||tc==-1);

   // ---- momentum: MA of RSI (buffer 0) ----
   double maNow =Val(hMARSI,InpMARSI_Buffer,shift);
   double maPrev=Val(hMARSI,InpMARSI_Buffer,shift+1);
   if(!IsValidNum(maNow)||!IsValidNum(maPrev)) return;
   bool rsiBuy  = (maNow>InpRSI_Mid) || (maNow>maPrev);
   bool rsiSell = (maNow<InpRSI_Mid) || (maNow<maPrev);

   // ---- confirmation: VQZL (value > 0 = bullish, per source) ----
   double vq1=Val(hVQ,InpVQ_Buffer,shift), vq2=Val(hVQ,InpVQ_Buffer,shift+1);
   if(!IsValidNum(vq1)||!IsValidNum(vq2)) return;
   bool vqBuy  = (vq1>InpVQ_Zero) || (vq1>vq2);
   bool vqSell = (vq1<InpVQ_Zero) || (vq1<vq2);

   // ---- trigger: STC cross ----
   double s1=Val(hSTC,InpSTC_Buffer,shift), s2=Val(hSTC,InpSTC_Buffer,shift+1);
   if(!IsValidNum(s1)||!IsValidNum(s2)) return;
   bool stcBuy  = (s2< InpSTC_Oversold   && s1>=InpSTC_Oversold)   || (s2< InpSTC_Mid && s1>=InpSTC_Mid);
   bool stcSell = (s2> InpSTC_Overbought && s1<=InpSTC_Overbought) || (s2> InpSTC_Mid && s1<=InpSTC_Mid);

   // ---- volatility ----
   bool atrOk=AtrOk(shift);

   bool buyAll  = trendBuy  && rsiBuy  && vqBuy  && stcBuy  && atrOk;
   bool sellAll = trendSell && rsiSell && vqSell && stcSell && atrOk;

   // ---- fresh-setup gating ----
   bool buyFresh  = !InpRequireFresh || !g_prevBuyAll;
   bool sellFresh = !InpRequireFresh || !g_prevSellAll;
   g_prevBuyAll=buyAll; g_prevSellAll=sellAll;

   // ---- cooldown ----
   bool buyCool  = (g_lastBuyTime==0)  || ((iBarShift(_Symbol,_Period,g_lastBuyTime) -1) >= InpCooldownBars);
   bool sellCool = (g_lastSellTime==0) || ((iBarShift(_Symbol,_Period,g_lastSellTime)-1) >= InpCooldownBars);

   if(buyAll && buyFresh && buyCool)
   {
      double atrv=Val(hATR,0,shift); double off=IsValidNum(atrv)?atrv*0.5:10*_Point;
      double lo=iLow(_Symbol,_Period,shift);
      DrawArrow(true,tBar,lo-off);
      g_lastBuyTime=tBar;
      if(allowAlert){
         string sum=StringFormat("%s Trend: Bullish\n%s Trend: Bullish\nMA of RSI: Confirmed\nVQZL: Bullish\nSTC: Cross Up\nATR: Volatility Confirmed",
                     TFToStr(InpTrendTF1),TFToStr(InpTrendTF2));
         SendAllAlerts(true,iClose(_Symbol,_Period,shift),tBar,sum);
      }
   }
   else if(sellAll && sellFresh && sellCool)
   {
      double atrv=Val(hATR,0,shift); double off=IsValidNum(atrv)?atrv*0.5:10*_Point;
      double hi=iHigh(_Symbol,_Period,shift);
      DrawArrow(false,tBar,hi+off);
      g_lastSellTime=tBar;
      if(allowAlert){
         string sum=StringFormat("%s Trend: Bearish\n%s Trend: Bearish\nMA of RSI: Confirmed\nVQZL: Bearish\nSTC: Cross Down\nATR: Volatility Confirmed",
                     TFToStr(InpTrendTF1),TFToStr(InpTrendTF2));
         SendAllAlerts(false,iClose(_Symbol,_Period,shift),tBar,sum);
      }
   }
}

//+------------------------------------------------------------------+
void DrawHistory()
{
   int total=Bars(_Symbol,_Period);
   int n=MathMin(InpHistoryBars,total-3);
   if(n<3) return;
   g_prevBuyAll=false; g_prevSellAll=false; g_lastBuyTime=0; g_lastSellTime=0;
   for(int shift=n; shift>=1; shift--)            // oldest -> newest, no alerts
      ProcessBar(shift,false);
}

//+------------------------------------------------------------------+
int OnInit()
{
   hATR      = iATR(_Symbol,_Period,InpATR_Period);
   hAA_Chart = iCustom(_Symbol,_Period,    InpAA_Name,InpAA_Period,InpAA_Price);
   hAA_TF1   = iCustom(_Symbol,InpTrendTF1,InpAA_Name,InpAA_Period,InpAA_Price);
   hAA_TF2   = iCustom(_Symbol,InpTrendTF2,InpAA_Name,InpAA_Period,InpAA_Price);
   hMARSI    = iCustom(_Symbol,_Period,InpMARSI_Name,InpRSI_Period,InpRSI_Price,InpRSI_MAPeriod,InpRSI_MAMethod);
   hVQ       = iCustom(_Symbol,_Period,InpVQ_Name ,InpVQ_SmoothPer,InpVQ_SmoothMet,InpVQ_FilterATR);
   hSTC      = iCustom(_Symbol,_Period,InpSTC_Name,InpSTC_MAShort,InpSTC_MALong,InpSTC_Cycle);

   if(hATR==INVALID_HANDLE || hAA_Chart==INVALID_HANDLE || hAA_TF1==INVALID_HANDLE ||
      hAA_TF2==INVALID_HANDLE || hMARSI==INVALID_HANDLE || hVQ==INVALID_HANDLE || hSTC==INVALID_HANDLE)
   {
      Print("Failed to create one or more indicator handles. Check the iCustom *Name inputs (the indicators must be compiled and present in MQL5\\Indicators).");
      return(INIT_FAILED);
   }
   g_lastBarTime=0; g_historyDone=false;
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason){ /* keep arrow objects as history */ }

//+------------------------------------------------------------------+
void OnTick()
{
   if(!HandlesReady()) return;

   if(InpDrawHistory && !g_historyDone){ DrawHistory(); g_historyDone=true; }

   datetime t0=iTime(_Symbol,_Period,0);
   if(t0==g_lastBarTime) return;                  // not a new bar yet
   bool first=(g_lastBarTime==0);
   g_lastBarTime=t0;
   if(first) return;                              // skip the attach tick

   ProcessBar(1,true);                            // evaluate the just-closed bar w/ alerts
}
//+------------------------------------------------------------------+
