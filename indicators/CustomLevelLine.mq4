//+------------------------------------------------------------------+
//|                                              CustomLevelLine.mq4 |
//|                                                        Junqi Hou |
//|                                           https://blog.junqi.tw/ |
//+------------------------------------------------------------------+

#property indicator_chart_window
#property indicator_buffers 2
//---- plot Line
#property indicator_label1  "自訂線"
#property indicator_type1   DRAW_LINE
#property indicator_color1  Red
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1
#property indicator_label2  "加錢後自訂線"
#property indicator_type2   DRAW_LINE
#property indicator_color2  Green
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1
//--- indicator buffers
double         LineBuffer[];
double         LineBuffer2[];
//--- inputs
input double   LevelPercentage = 100; // 自訂線的保證金水平
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
double CustomLinePrice; // 爆倉線的位置
double AddCashLinePrice; // 加錢後自訂線的位置
double FixProfitRate; // 損益較正貨幣的匯率
string TextOnTheCustomLine; // 自訂線上方的題示文字
string labelNameCustomLine = "customLineLabel";
string labelNameCustomAddCashLine = "customAddCashLineLabel";

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
    MarginMaintenance = GetMarginMaintenance(LevelPercentage);
    TotalLots = CurrentTotalLots();
    FixProfitRate = GetFixProfitRate();
    if(TotalLots == 0) {
        CustomLinePrice = 0;
        AddCashLinePrice = 0;
    }
    else if(TotalLots > 0) { // 做多
        CustomLinePrice = (MarginMaintenance + 100000.0*TotalLots*FixProfitRate*close[0] - Equity)/(100000.0*TotalLots*FixProfitRate);
        AddCashLinePrice = (MarginMaintenance + 100000.0*TotalLots*FixProfitRate*close[0] - AddCashEquity)/(100000.0*TotalLots*FixProfitRate);

    }
    else {   // (TotalLots < 0)
        TotalLots = -TotalLots; // TotalLots 的值永為正，方便公式計算
        CustomLinePrice = (Equity + 100000.0*TotalLots*FixProfitRate*close[0] - MarginMaintenance)/(100000.0*TotalLots*FixProfitRate);
        AddCashLinePrice = (AddCashEquity + 100000.0*TotalLots*FixProfitRate*close[0] - MarginMaintenance)/(100000.0*TotalLots*FixProfitRate);
    }

// Development only
    if(DebugMode) {
        PrintFormat("CustomLinePrice: %lf", CustomLinePrice);
        PrintFormat("Equity: %lf", Equity);
        PrintFormat("TotalLots: %lf", TotalLots);
        PrintFormat("FixProfitRate: %lf", FixProfitRate);
        PrintFormat("MarginMaintenance: %lf", MarginMaintenance);
    }

    ArrayInitialize(LineBuffer, CustomLinePrice);
    ArrayInitialize(LineBuffer2, AddCashLinePrice);
    UpdateLine(labelNameCustomLine, StringFormat("自訂線 (%.2lf%%)", LevelPercentage), CustomLinePrice);
    UpdateLine(labelNameCustomAddCashLine, StringFormat("加 $%.2lf 後自訂線", AddCash), AddCashLinePrice);
//--- return value of prev_calculated for next call
    return(rates_total);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if (ObjectFind(0, labelNameCustomLine) != -1) {
        // 確保要刪除的對象存在於圖表中
        ObjectDelete(0, labelNameCustomLine);
    }
    if (ObjectFind(0, labelNameCustomAddCashLine) != -1) {
        // 確保要刪除的對象存在於圖表中
        ObjectDelete(0, labelNameCustomAddCashLine);
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
        ResetLastError();
        double fixProfitRate = MarketInfo(FixCurrency, MODE_BID);
        // 進行錯誤處理，因為 FixCurrency 是使用者輸入，有可能有誤
        int lastError = GetLastError();
        if(lastError != 0 || fixProfitRate <= 0) {
            PrintFormat("獲取校正貨幣兌匯率時出現問題！請檢查你的 input 參數格式是否符合您交易商的格式。您的 input 為：\"%s\"；錯誤代碼：%d；MarketInfo 回傳值為 %lf", FixCurrency,lastError, fixProfitRate);
            ResetLastError();
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
            ResetLastError();
        }
        else {
            ObjectSetText(labelName, labelText, 10, "Arial", clrWhite);
        }
    }
    ObjectSetText(labelName, labelText, 10, "Arial", clrWhite);
    ObjectMove(0, labelName, 0, Time[TextMoveToLeft], price); // 這會移動標籤到新價格上
}
//+------------------------------------------------------------------+
double GetMarginMaintenance(double levelPercentage)
{
    return AccountInfoDouble(ACCOUNT_MARGIN) * levelPercentage * 0.01;
}
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
