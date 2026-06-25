//+------------------------------------------------------------------+
//|                                                       MaTest.mq5  |
//|  Diagnoses the VQZL "average of high initialization failed"       |
//|  alert by calling the SAME iMA/iATR directly and printing the     |
//|  handle + error code. Drag onto the chart that fails.             |
//+------------------------------------------------------------------+
#property script_show_inputs
#property version "1.00"

input int            InpPeriod = 10;          // same as VQZL "Price smoothing period"
input ENUM_MA_METHOD InpMethod = MODE_LWMA;   // same as VQZL "Price smoothing method"

void OnStart()
{
   PrintFormat("Symbol=%s  selected=%d  bars=%d  point=%.5f",
               _Symbol,
               (int)SymbolInfoInteger(_Symbol,SYMBOL_SELECT),
               Bars(_Symbol,PERIOD_CURRENT),
               SymbolInfoDouble(_Symbol,SYMBOL_POINT));

   ResetLastError();
   int hMA = iMA(_Symbol,PERIOD_CURRENT,InpPeriod,0,InpMethod,PRICE_HIGH);
   int eMA = GetLastError();
   PrintFormat("iMA(PRICE_HIGH, period=%d, method=%d): handle=%d  err=%d", InpPeriod,(int)InpMethod,hMA,eMA);

   ResetLastError();
   int hATR = iATR(_Symbol,PERIOD_CURRENT,InpPeriod);
   int eATR = GetLastError();
   PrintFormat("iATR(period=%d): handle=%d  err=%d", InpPeriod,hATR,eATR);

   if(hMA!=INVALID_HANDLE){
      int w=0; while(BarsCalculated(hMA)<1 && w<5000){ Sleep(100); w+=100; }
      PrintFormat("iMA BarsCalculated=%d", BarsCalculated(hMA));
   }
   Print("==== MaTest done - copy these lines from the Experts tab ====");
}
//+------------------------------------------------------------------+
