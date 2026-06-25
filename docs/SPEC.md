# Forex Continuation-Signal Indicator — Spec

Custom **MetaTrader 5 (MQL5)** indicator that fires **trend-continuation signals only**
(no reversals / counter-trend), **non-repainting**, with multi-channel alerts.

Reference setup the settings were captured from: **GBPUSD.PRO, H4**.

---

## Component indicators & exact settings (from user's live charts)

| # | Indicator | File | Window | Exact inputs |
|---|-----------|------|--------|--------------|
| 1 | ATR Adaptive Double Smoothed EMA (baseline trend filter) | `ATR_Adaptive_DoubleSmoothed.ex5` | Main chart | **Period = 25**, **Price = Close**. Tri-color "Double smoothed EMA" line (up/down/flat). |
| 2 | MA of RSI (momentum trigger) | `MA_of_RSI` | Sub (scale 0–100) | **RSI Period = 6**, **RSI Applied Price = Close**, **MA Period = 3**, **MA Method = Smoothed (SMMA)**. Plots RSI(6) [Lime] + MA [Crimson]. |
| 3 | VQZL v2.3 (volatility/quality filter, noise gate) | `VQZL_v2.3.ex5` | Sub (auto-scale, centered on 0) | **Price smoothing period = 10**, **method = Linear weighted (LWMA)**, **Filter (% of ATR) = 7.5**. Tri-color "Volatility quality" line (green/red/gray). |
| 4 | Schaff Trend Cycle (entry trigger / trend dir) | `SchaffTrendCycle` | Sub | **MAShort = 21**, **MALong = 50**, **Cycle = 10**; ShowArrows=false, UpColor=Blue, DownColor=Red, ShowAlerts/SoundAlerts=false. Drawn levels: **10 / 50 / 90**. |
| 5 | ATR (volatility check + trade mgmt) | `ATR` | Sub (auto-scale) | **ATR period = 14**. |

> ⚠️ **Discrepancy vs original design doc:** doc said MA of RSI uses "EMA3"; the live setting is **Smoothed (SMMA) 3**. Using the live setting.

---

## Signal logic — BUY (SELL = exact mirror)

1. **Baseline / trend:** ATR-Adaptive EMA bullish **AND** MA of RSI > 50 (or sloping up). Price structure bullish.
2. **Confirmation (VQZL):** green/bullish (positive reading or rising), or crosses bearish→bullish. Skip if flat/choppy.
3. **Entry trigger (STC):** crosses **up from oversold** OR crosses **above 50 with momentum**.
4. **Volatility (ATR):** not in extreme low compression (avoid dead market).

## Higher-timeframe filter (continuation-only)
- Trend filter requires **D1 + H4 aligned** in the same direction; **no signal if D1 & H4 disagree**.
- Entry/signal timeframe = chart TF (H4, optionally H1).

## Discipline / anti-spam
- Signal only on a **closed candle**; fully **non-repainting**; historical signals never move/disappear.
- **One alert per valid setup**, no duplicate per candle.
- **Cooldown:** `input int SignalCooldownBars = 8;` — no same-direction signal for N bars after one fires.
- **Fresh-setup gating:** after a signal, no new same-direction alert until conditions go invalid → valid again (not while continuously true).

## Alerts
Channels: **MT5 push, Email, Telegram (Bot API)**, optional popup + sound.
Telegram inputs: **Bot Token**, **Chat ID**. Message format:
```
{BUY|SELL} Signal - {SYMBOL} ({TF})
Daily Trend: {Bullish|Bearish}
H4 Trend: {Bullish|Bearish}
MA of RSI: Confirmed
VQZL: {Bullish|Bearish}
STC: {Cross Up|Cross Down}
ATR: Volatility Confirmed
Entry Price: {price}
Signal Time: {yyyy.MM.dd HH:mm}
```

---

## Decisions (resolved)
1. **Indicator access:** `iCustom()` for all four custom indicators; `ATR(14)` via native `iATR`. The `.mq5` **source** for ATR-Adaptive, VQZL, and MA-of-RSI was provided, so input order + buffer indices are **confirmed** (table below); source files are bundled in `MQL5/Indicators/`. Only `SchaffTrendCycle` is compiled-only (value = buffer 0, single plot).
2. **Timeframe rule:** **D1 + H4 aligned** (+ optional chart-TF baseline), all toggleable via inputs. (The page-1 "H1+H4" variant is still reachable by turning off the D1 filter.)
3. **STC thresholds:** **25 / 75** oversold/overbought, 50 midline.

### iCustom signatures (confirmed from source; STC from screenshot)
| Indicator | iCustom name | Params (in order) | Value buf | Direction |
|---|---|---|---|---|
| ATR Adaptive | `ATR_Adaptive_DoubleSmoothed` | `double Period=25.0`, `Price=PRICE_CLOSE` | 0 | EMA slope (buf1 color 2=up/1=down) |
| MA of RSI | `MA_of_RSI` | `int RSI=6`, `PRICE_CLOSE`, `int MA=3`, `MODE_SMMA` | 0 (buf1 = raw RSI) | line vs 50 |
| VQZL v2.3 | `VQZL_v2.3` | `int Smooth=10`, `MODE_LWMA`, `double Filter=7.5` | 0 | value > 0 = bullish |
| Schaff TC | `SchaffTrendCycle` | `int MAShort=21`, `int MALong=50`, `int Cycle=10` | 0 (assumed) | cross 25/75 & 50 |

`MA_of_RSI` internally calls `Examples\RSI` (standard MT5) and uses a non-standard *windowed* SMMA — so it is read via `iCustom` (buffer 0) for an exact match rather than reimplemented.

## Architecture note — EA, not indicator
Telegram needs `WebRequest()`, which MT5 forbids inside indicators (they run on the UI thread). So this is built as an **Expert Advisor** (`MQL5/Experts/ContinuationSignal.mq5`): same on-chart BUY/SELL arrows (drawn as objects, so history persists), closed-bar evaluation (non-repainting), and all alert channels including Telegram.

## Build/test workflow
No MT5 on the dev machine → Claude writes the `.mq5`; user compiles in MetaEditor and runs on a chart; we iterate from results/screenshots. First run = calibrate the iCustom `*Name` paths + buffer indices together.
