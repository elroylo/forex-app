//+------------------------------------------------------------------+
//|                                                  BufferProbe.mq5  |
//|  One-shot diagnostic: prints each custom indicator's buffer       |
//|  values so we can identify the correct buffer index for the EA.   |
//+------------------------------------------------------------------+
// HOW TO USE:
//   1. Put this file in MQL5\Scripts\, compile (F7).
//   2. Make sure the *Name inputs below match the EXACT path/name of
//      your downloaded Market indicators (Market\<Name> usually).
//   3. Drag the script onto a GBPUSD (or your symbol) H4 chart.
//   4. Open the "Experts" tab (or Journal) at the bottom of MT5 and
//      copy ALL the [ ... ] lines it prints back to me.
//
// I read the buffer index from the value magnitudes:
//   - ATR_Adaptive  -> a value near price (e.g. ~1.26 on GBPUSD)
//   - VQZL          -> a small value near 0 (e.g. ~0.001 / -0.002)
//   - STC           -> a value between 0 and 100
//+------------------------------------------------------------------+
#property script_show_inputs
#property version "1.0"

input string             InpAA_Name     = "Market\\ATR_Adaptive_DoubleSmoothed"; // ATR-Adaptive path\name
input int                InpAA_Period   = 25;
input int                InpAA_Price    = PRICE_CLOSE;

input string             InpVQ_Name     = "Market\\VQZL_v2.3";  // VQZL path\name
input int                InpVQ_SmoothPer= 10;
input int                InpVQ_SmoothMet= MODE_LWMA;
input double             InpVQ_FilterATR= 7.5;

input string             InpSTC_Name    = "Market\\SchaffTrendCycle"; // STC path\name
input int                InpSTC_MAShort = 21;
input int                InpSTC_MALong  = 50;
input int                InpSTC_Cycle   = 10;

input int                InpMaxBuffers  = 10;  // how many buffers to probe per indicator

//+------------------------------------------------------------------+
void Probe(const string label,const int handle)
{
   if(handle==INVALID_HANDLE)
   {
      PrintFormat("[%s] INVALID HANDLE - the name/path is wrong or the indicator isn't installed",label);
      return;
   }
   int waited=0;
   while(BarsCalculated(handle)<3 && waited<7000){ Sleep(100); waited+=100; }
   PrintFormat("[%s] handle ok, BarsCalculated=%d  (values shown newest -> oldest: shift1, shift2, shift3)",
               label,BarsCalculated(handle));
   for(int b=0;b<InpMaxBuffers;b++)
   {
      double a[];
      int got=CopyBuffer(handle,b,1,3,a);   // last 3 CLOSED bars
      if(got!=3){ PrintFormat("[%s] buffer %d: (no data) -> stopping",label,b); break; }
      PrintFormat("[%s] buffer %d: %.6f, %.6f, %.6f",label,b,a[2],a[1],a[0]);
   }
}

//+------------------------------------------------------------------+
void OnStart()
{
   PrintFormat("==== BUFFER PROBE  %s  %s ====",_Symbol,EnumToString((ENUM_TIMEFRAMES)_Period));
   Probe("ATR_Adaptive", iCustom(_Symbol,_Period,InpAA_Name,InpAA_Period,InpAA_Price));
   Probe("VQZL",         iCustom(_Symbol,_Period,InpVQ_Name,InpVQ_SmoothPer,InpVQ_SmoothMet,InpVQ_FilterATR));
   Probe("STC",          iCustom(_Symbol,_Period,InpSTC_Name,InpSTC_MAShort,InpSTC_MALong,InpSTC_Cycle));
   Print("==== PROBE DONE - copy the [ ... ] lines above from the Experts/Journal tab ====");
}
//+------------------------------------------------------------------+
