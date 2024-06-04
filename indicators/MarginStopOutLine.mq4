//+------------------------------------------------------------------+
//|                                            MarginStopOutLine.mq4 |
//|                                                        Junqi Hou |
//|                                           https://blog.junqi.tw/ |
//+------------------------------------------------------------------+

#property indicator_chart_window
#property indicator_buffers 2
//---- plot Line
#property indicator_label1  "爆倉線"
#property indicator_type1   DRAW_LINE
#property indicator_color1  Red
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1
#property indicator_label2  "加錢後爆倉線"
#property indicator_type2   DRAW_LINE
#property indicator_color2  Green
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1
//--- indicator buffers
double         LineBuffer[];
double         LineBuffer2[];
//--- inputs
input double   AddCash = 200; // 補錢的數量
input int      TextMoveToLeft = 40; // 文字左移的量
input string   FixCurrency = "USD"; // 不需校正請填 USD；需校正填入損益較正貨幣兌 (基準貨幣USD) eg. GBPUSD
input bool     ReverseFixCurrency = false; // 有時候校正貨幣兌不一定有反向，可以自己翻轉
input bool     DebugMode = false; // 顯示 debug 訊息

//--- variables
double Equity; // 淨值
double AddCashEquity; // 補錢後的淨值
double MarginMaintenance; // 維持保證金
double TotalLots; // 總開倉手數
double MarginCallPrice; // 爆倉線的位置
double AddCashLinePrice; // 加錢後爆倉線的位置
double FixProfitRate; // 損益較正貨幣的匯率
string TextOnTheMarginCallLine; // 爆倉線上方的題示文字
string labelNameMarginCallLine = "marginCallLineLabel";
string labelNameAddCashLine = "addCashLineLabel";

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
    SetIndexBuffer(0,LineBuffer,INDICATOR_DATA);
    SetIndexBuffer(1,LineBuffer2,INDICATOR_DATA);
    return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime& time[],
                const double& open[],
                const double& high[],
                const double& low[],
                const double& close[],
                const long& tick_volume[],
                const long& volume[],
                const int& spread[])
{

    Equity = AccountInfoDouble(ACCOUNT_EQUITY);
    AddCashEquity = Equity + AddCash;
    MarginMaintenance = GetMarginMaintenance();
    TotalLots = CurrentTotalLots();
    FixProfitRate = GetFixProfitRate();
    if(TotalLots == 0) {
        MarginCallPrice = 0;
        AddCashLinePrice = 0;
    }
    else if(TotalLots > 0) { // 做多
        MarginCallPrice = (MarginMaintenance + 100000.0*TotalLots*FixProfitRate*close[0] - Equity)/(100000.0*TotalLots*FixProfitRate);
        AddCashLinePrice = (MarginMaintenance + 100000.0*TotalLots*FixProfitRate*close[0] - AddCashEquity)/(100000.0*TotalLots*FixProfitRate);

    }
    else {   // (TotalLots < 0)
        TotalLots = -TotalLots; // TotalLots 的值永為正，方便公式計算
        MarginCallPrice = (Equity + 100000.0*TotalLots*FixProfitRate*close[0] - MarginMaintenance)/(100000.0*TotalLots*FixProfitRate);
        AddCashLinePrice = (AddCashEquity + 100000.0*TotalLots*FixProfitRate*close[0] - MarginMaintenance)/(100000.0*TotalLots*FixProfitRate);
    }

// Development only
    if(DebugMode) {
        PrintFormat("MarginCallPrice: %lf", MarginCallPrice);
        PrintFormat("Equity: %lf", Equity);
        PrintFormat("TotalLots: %lf", TotalLots);
        PrintFormat("FixProfitRate: %lf", FixProfitRate);
        PrintFormat("MarginMaintenance: %lf", MarginMaintenance);
    }

    ArrayInitialize(LineBuffer, MarginCallPrice);
    ArrayInitialize(LineBuffer2, AddCashLinePrice);
    UpdateLine(labelNameMarginCallLine, "爆倉線", MarginCallPrice);
    UpdateLine(labelNameAddCashLine, StringFormat("加 $%.2lf 後爆倉線", AddCash), AddCashLinePrice);
//--- return value of prev_calculated for next call
    return(rates_total);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if (ObjectFind(0, labelNameMarginCallLine) != -1) {
        // 確保要刪除的對象存在於圖表中
        ObjectDelete(0, labelNameMarginCallLine);
    }
    if (ObjectFind(0, labelNameAddCashLine) != -1) {
        // 確保要刪除的對象存在於圖表中
        ObjectDelete(0, labelNameAddCashLine);
    }
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double CurrentTotalLots()   // 回傳多空相抵後的 Lots
{
    double totalLots = 0;
    int totalOrders = OrdersTotal();
    for(int i = 0; i < totalOrders; i++) {
        if(OrderSelect(i, SELECT_BY_POS)) {
            if(OrderSymbol() == Symbol()) { // 只記錄目前這個圖表的商品的手數
                switch(OrderType()) {
                case OP_BUY: // 做多
                    totalLots += OrderLots();
                    break;
                case OP_SELL: // 做空
                    totalLots -= OrderLots();
                    break;
                    // 若為其它類型的 Order 代表是掛單，尚未成交，不計
                }
            }
        }
        else {
            PrintFormat("OrderSelect err");
        }
    }
    return totalLots;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetFixProfitRate()
{
    if(FixCurrency == "USD")
        return 1;
    else {
        double fixProfitRate = MarketInfo(FixCurrency, MODE_BID);
        // 進行錯誤處理，因為 FixCurrency 是使用者輸入，有可能有誤
        int lastError = GetLastError();
        if(lastError != 0 || fixProfitRate <= 0) {
            PrintFormat("獲取校正貨幣兌匯率時出現問題！請檢查你的 input 參數格式是否符合您交易商的格式。您的 input 為：\"%s\"；錯誤代碼：%d；MarketInfo 回傳值為 %lf", FixCurrency,lastError, fixProfitRate);
            return 1;
        }
        else {   // 沒出錯
            if(ReverseFixCurrency) {
                return 1.0/fixProfitRate;
            }
            else {
                return fixProfitRate;
            }
        }
    }
}
//+------------------------------------------------------------------+
void UpdateLine(string labelName, string labelText, double price)
{

    if(ObjectFind(0, labelName) == -1) {
        if(!ObjectCreate(0, labelName, OBJ_TEXT, 0, Time[TextMoveToLeft], price)) {
            PrintFormat("Text create failed. Error code: ", GetLastError());
        }
        else {
            ObjectSetText(labelName, labelText, 10, "Arial", clrWhite);
        }
    }
    ObjectSetText(labelName, labelText, 10, "Arial", clrWhite);
    ObjectMove(0, labelName, 0, Time[TextMoveToLeft], price); // 這會移動標籤到新價格上
}
//+------------------------------------------------------------------+
double GetMarginMaintenance()
{
    if(AccountInfoInteger(ACCOUNT_MARGIN_SO_MODE) == ACCOUNT_STOPOUT_MODE_PERCENT) {
        return AccountInfoDouble(ACCOUNT_MARGIN) * AccountInfoDouble(ACCOUNT_MARGIN_SO_SO) * 0.01;
    }
    else { // ACCOUNT_STOPOUT_MODE_MONEY
        return AccountInfoDouble(ACCOUNT_MARGIN_SO_SO);
    }

}
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
