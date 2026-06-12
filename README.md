# Claude Usage Tray

Windows 系統匣小工具,即時監控 Claude Code 用量。

## 顯示內容

| 項目 | 來源 | 更新頻率 |
|------|------|----------|
| 5 小時額度 %(圖示數字 + 顏色) | Anthropic OAuth usage API | 每 60 秒 |
| 週額度 % 與重置時間 | 同上 | 每 60 秒 |
| 今日 token 數 / 估算成本 | `bun x ccusage`(本地 transcript) | 每 10 分鐘 |

- 圖示顏色:綠 < 50%、橘 50–79%、紅 ≥ 80%、灰 = 讀取失敗
- 5h 額度到 80% / 95% 時各跳一次系統通知
- 滑鼠懸停看摘要;雙擊或右鍵「詳細資訊」看完整數據

## 使用

```powershell
# 啟動(無視窗)
wscript tools\usage-tray\Start-UsageTray.vbs

# 設定開機自動啟動
powershell -ExecutionPolicy Bypass -File tools\usage-tray\Install-Startup.ps1
```

結束:右鍵系統匣圖示 →「結束」。
移除自啟:刪除 `shell:startup` 中的 `Claude Usage Tray.lnk`。

## 相依與注意事項

- 額度 % 讀取 `~/.claude/.credentials.json` 的 OAuth token;token 由 Claude Code 自動刷新,若長時間沒開 Claude Code 導致 token 過期,圖示會變灰,開一次 Claude Code 即可恢復。
- 成本統計需要 `bun`(用 `bun x ccusage` 免安裝執行);沒有 bun 時其餘功能照常,只是不顯示成本。
- 用的是非公開 API(`/api/oauth/usage`),Anthropic 改版時可能需要調整。
