//+------------------------------------------------------------------+
//|                                                 TelegramTest.mq5  |
//|  One-shot: sends a test message to confirm your bot token +      |
//|  chat id + the WebRequest whitelist are all working, BEFORE you  |
//|  rely on live signals. Run it as a script (drag onto a chart).   |
//+------------------------------------------------------------------+
// Requires: Tools > Options > Expert Advisors > "Allow WebRequest for
// listed URL" includes  https://api.telegram.org , and Algo Trading on.
//+------------------------------------------------------------------+
#property script_show_inputs
#property version "1.00"

input string InpTgBotToken = "";  // Bot token (from @BotFather)
input string InpTgChatId   = "";  // Chat id (from @userinfobot)
input string InpMessage    = "Test from MT5 - if you see this, Telegram alerts work.";

string UrlEncode(const string s)
{
   string out=""; uchar b[]; int n=StringToCharArray(s,b,0,StringLen(s),CP_UTF8);
   for(int i=0;i<n;i++){ uchar c=b[i];
      if((c>='0'&&c<='9')||(c>='A'&&c<='Z')||(c>='a'&&c<='z')||c=='-'||c=='_'||c=='.'||c=='~')
         out+=CharToString(c);
      else out+=StringFormat("%%%02X",c); }
   return(out);
}

void OnStart()
{
   if(InpTgBotToken=="" || InpTgChatId==""){ Print("Set the bot token and chat id in the script inputs."); return; }
   string url="https://api.telegram.org/bot"+InpTgBotToken+"/sendMessage";
   string body="chat_id="+InpTgChatId+"&text="+UrlEncode(InpMessage);
   uchar post[]; int len=StringToCharArray(body,post,0,StringLen(body),CP_UTF8); ArrayResize(post,len);
   uchar result[]; string rhead; ResetLastError();
   int code=WebRequest("POST",url,"Content-Type: application/x-www-form-urlencoded\r\n",5000,post,result,rhead);
   if(code==-1)
      PrintFormat("FAILED err=%d -> add https://api.telegram.org under Tools>Options>Expert Advisors (Allow WebRequest) and enable Algo Trading.",GetLastError());
   else
      PrintFormat("Telegram HTTP %d: %s",code,CharArrayToString(result));
}
//+------------------------------------------------------------------+
