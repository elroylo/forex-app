//+------------------------------------------------------------------+
//|                                                  MA_of_RSI.mq5   |
//|                                                                  |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2022, FxAutomated.com"
#property link      "http://www.fxautomated.com"
#property version   "1.00"
#property indicator_separate_window
#property indicator_buffers 4
#property indicator_plots   2
#property indicator_level1 15
#property indicator_level2 80
#property indicator_label1  "MA of Custom RSI"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrLimeGreen
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1
#property indicator_label2  "RSI Line"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrGray
#property indicator_style2  STYLE_DOT
#property indicator_width2  1
#property indicator_minimum 0
#property indicator_maximum 100


// Input parameters
input int        RSI1_Period = 1;               // RSI1: Period
input ENUM_APPLIED_PRICE RSI1_Applied_Price = PRICE_CLOSE; // RSI1: Applied Price
input int        MA_Period = 10;                // MA Period
input ENUM_MA_METHOD MA_Method = MODE_LWMA;      // MA Method
double     RSI1_Oversold = 15;            // Oversold Level
double     RSI1_Overbought = 80;          // Overbought Level

// Indicator buffers
double maBuffer[];
double rsiBuffer[];
double oversoldBuffer[];
double overboughtBuffer[];

// Handles
int rsi1Handle;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   // Set indicator buffers
   SetIndexBuffer(0, maBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, rsiBuffer, INDICATOR_DATA);
   SetIndexBuffer(2, oversoldBuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(3, overboughtBuffer, INDICATOR_CALCULATIONS);
   
   // Set indicator properties
   IndicatorSetString(INDICATOR_SHORTNAME, "MA of Custom RSI(" + string(RSI1_Period) + ")");
   IndicatorSetInteger(INDICATOR_DIGITS, 2);
   
   // Set levels for overbought and oversold
   IndicatorSetDouble(INDICATOR_LEVELVALUE, 0, RSI1_Oversold);
   IndicatorSetDouble(INDICATOR_LEVELVALUE, 1, RSI1_Overbought);
   IndicatorSetInteger(INDICATOR_LEVELS, 2);
   IndicatorSetInteger(INDICATOR_LEVELSTYLE, 0, STYLE_DOT);
   IndicatorSetInteger(INDICATOR_LEVELSTYLE, 1, STYLE_DOT);
   IndicatorSetInteger(INDICATOR_LEVELCOLOR, 0, clrSilver);
   IndicatorSetInteger(INDICATOR_LEVELCOLOR, 1, clrSilver);
   
   // Set indicator range
   IndicatorSetDouble(INDICATOR_MINIMUM, 0);
   IndicatorSetDouble(INDICATOR_MAXIMUM, 100);
   
   // Get custom RSI handle :cite[1]:cite[9]
   rsi1Handle = iCustom(_Symbol, _Period, "Examples\\RSI", RSI1_Period, RSI1_Applied_Price);
   if(rsi1Handle == INVALID_HANDLE)
   {
      Print("Error creating custom RSI handle: ", GetLastError());
      return INIT_FAILED;
   }
   
   // Set index labels
   PlotIndexSetString(0, PLOT_LABEL, "MA of RSI(" + string(RSI1_Period) + ")");
   PlotIndexSetString(1, PLOT_LABEL, "RSI(" + string(RSI1_Period) + ")");
   
   // Initialize level buffers
   ArrayInitialize(oversoldBuffer, RSI1_Oversold);
   ArrayInitialize(overboughtBuffer, RSI1_Overbought);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
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
   // Check if we have enough data
   if(rates_total < MA_Period + RSI1_Period) 
      return 0;
   
   // Set arrays as series
   ArraySetAsSeries(maBuffer, true);
   ArraySetAsSeries(rsiBuffer, true);
   ArraySetAsSeries(oversoldBuffer, true);
   ArraySetAsSeries(overboughtBuffer, true);
   ArraySetAsSeries(time, true);
   
   // Calculate starting index
   int start;
   if(prev_calculated == 0)
   {
      start = rates_total - 1;
      // Initialize buffers
      ArrayInitialize(maBuffer, 0.0);
      ArrayInitialize(rsiBuffer, 0.0);
   }
   else
   {
      start = prev_calculated - 1;
   }
   
   // Get RSI values from custom indicator :cite[1]:cite[3]
   double tempRSI[];
   ArraySetAsSeries(tempRSI, true);
   
   // Copy buffer 0 from custom RSI (main RSI line) :cite[1]:cite[9]
   if(CopyBuffer(rsi1Handle, 0, 0, rates_total, tempRSI) <= 0)
   {
      Print("Error copying RSI buffer: ", GetLastError());
      return 0;
   }
   
   // Calculate MA of RSI for each bar
   for(int i = start; i >= 0; i--)
   {
      // Store RSI value
      rsiBuffer[i] = tempRSI[i];
      
      // Check if we have enough data for MA calculation
      if(i > rates_total - MA_Period)
      {
         maBuffer[i] = 0;
         continue;
      }
      
      // Calculate MA of RSI :cite[6]
      maBuffer[i] = CalculateMA(tempRSI, i, MA_Period, MA_Method);
      
      // Set level values
      oversoldBuffer[i] = RSI1_Oversold;
      overboughtBuffer[i] = RSI1_Overbought;
   }
   
   return rates_total;
}

//+------------------------------------------------------------------+
//| Helper function to calculate MA values                           |
//+------------------------------------------------------------------+
double CalculateMA(double &data[], int index, int period, ENUM_MA_METHOD method)
{
   // For series arrays, index 0 is the current bar, higher indexes are older bars
   if(index + period - 1 >= ArraySize(data))
      return 0.0;  // Not enough data

   if(method == MODE_SMA)
   {
      double sum = 0;
      for(int i = 0; i < period; i++)
         sum += data[index + i];  // For series arrays, we sum from current to older
      return sum / period;
   }
   else if(method == MODE_EMA)
   {
      // EMA calculation for series arrays
      double ema = data[index + period - 1];  // Oldest value in the period
      double k = 2.0 / (period + 1.0);
      for(int i = period - 2; i >= 0; i--)
         ema = data[index + i] * k + ema * (1 - k);
      return ema;
   }
   else if(method == MODE_LWMA)
   {
      double sum = 0, weights = 0;
      for(int i = 0; i < period; i++)
      {
         double w = period - i;
         sum += data[index + i] * w;
         weights += w;
      }
      return sum / weights;
   }
   else if(method == MODE_SMMA)
   {
      // SMMA calculation for series arrays
      double smma = 0;
      for(int i = 0; i < period; i++)
        smma += data[index + i];
      smma /= period;
      
      for(int i = 1; i < period; i++)
        smma = (smma * (period - 1) + data[index + i]) / period;
      
      return smma;
   }
   return 0.0;
}
//+------------------------------------------------------------------+