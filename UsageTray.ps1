# Claude Usage Tray
# 系統匣小工具:顯示 Claude Code 的 5 小時額度 %、週額度 %、今日 token 成本。
# 資料來源:
#   - 額度 %:Anthropic OAuth usage API(讀取 ~/.claude/.credentials.json 的 token)
#   - 今日成本:bun x ccusage(統計本地 transcript)
# 啟動方式:wscript Start-UsageTray.vbs(隱藏視窗),或直接執行本檔。

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# 單一執行個體
$script:mutex = New-Object System.Threading.Mutex($false, "ClaudeUsageTray")
if (-not $script:mutex.WaitOne(0, $false)) { exit }

Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true)]
public static extern bool DestroyIcon(IntPtr hIcon);
'@

$script:state = @{
    FiveHour      = $null   # 0-100
    FiveHourReset = $null   # DateTimeOffset (local)
    SevenDay      = $null
    SevenDayReset = $null
    CostToday     = $null   # USD
    TokensToday   = $null
    LastUpdate    = $null
    ErrorMsg      = $null
    NotifiedLevel = 0       # 已通知的門檻 (0/80/95)
}
$script:costFile      = Join-Path $env:TEMP "claude-usage-tray-cost.json"
$script:costProc      = $null
$script:tickCount     = 0
$script:lastIconHandle = [IntPtr]::Zero

function Get-AccessToken {
    $credPath = Join-Path $env:USERPROFILE ".claude\.credentials.json"
    if (-not (Test-Path $credPath)) { return $null }
    try {
        $cred = Get-Content $credPath -Raw | ConvertFrom-Json
        return $cred.claudeAiOauth.accessToken
    } catch { return $null }
}

function Update-OAuthUsage {
    $token = Get-AccessToken
    if (-not $token) {
        $script:state.ErrorMsg = "找不到 OAuth token(~/.claude/.credentials.json)"
        return
    }
    try {
        $r = Invoke-RestMethod -Uri "https://api.anthropic.com/api/oauth/usage" `
            -Headers @{ "Authorization" = "Bearer $token"; "anthropic-beta" = "oauth-2025-04-20" } `
            -TimeoutSec 10 -ErrorAction Stop
        $script:state.FiveHour      = [math]::Round($r.five_hour.utilization)
        $script:state.FiveHourReset = [DateTimeOffset]::Parse($r.five_hour.resets_at).ToLocalTime()
        $script:state.SevenDay      = [math]::Round($r.seven_day.utilization)
        $script:state.SevenDayReset = [DateTimeOffset]::Parse($r.seven_day.resets_at).ToLocalTime()
        $script:state.LastUpdate    = Get-Date
        $script:state.ErrorMsg      = $null
    } catch {
        $msg = $_.Exception.Message
        if ($msg -match "401") { $msg = "token 過期,開一次 Claude Code 即可刷新" }
        $script:state.ErrorMsg = $msg
    }
}

function Start-CostUpdate {
    # 在背景跑 ccusage,結果寫到 temp 檔,避免卡住 UI 執行緒
    if ($script:costProc -and -not $script:costProc.HasExited) { return }
    $today = Get-Date -Format "yyyyMMdd"
    $cmd = "bun x ccusage daily --json --since $today --until $today > `"$script:costFile`" 2>nul"
    try {
        $script:costProc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $cmd `
            -WindowStyle Hidden -PassThru -ErrorAction Stop
    } catch { }
}

function Read-CostFile {
    if (-not (Test-Path $script:costFile)) { return }
    try {
        $j = Get-Content $script:costFile -Raw | ConvertFrom-Json
        if ($j.totals) {
            $script:state.CostToday   = $j.totals.totalCost
            $script:state.TokensToday = $j.totals.totalTokens
        }
    } catch { }
}

function New-PercentIcon {
    param($pct, [bool]$isError)

    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    if ($isError) {
        $bg = [System.Drawing.Color]::Gray
        $text = "!"
    } else {
        if     ($pct -ge 80) { $bg = [System.Drawing.ColorTranslator]::FromHtml("#CD5353") }
        elseif ($pct -ge 50) { $bg = [System.Drawing.ColorTranslator]::FromHtml("#E69554") }
        else                 { $bg = [System.Drawing.ColorTranslator]::FromHtml("#84B585") }
        $text = [string]$pct
    }

    $brush = New-Object System.Drawing.SolidBrush $bg
    $g.FillEllipse($brush, 0, 0, 31, 31)
    $brush.Dispose()

    $fontSize = if ($text.Length -ge 3) { 13 } elseif ($text.Length -eq 2) { 17 } else { 19 }
    $font = New-Object System.Drawing.Font("Segoe UI", $fontSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $fmt = New-Object System.Drawing.StringFormat
    $fmt.Alignment = [System.Drawing.StringAlignment]::Center
    $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
    $white = [System.Drawing.Brushes]::White
    $rect = New-Object System.Drawing.RectangleF(0, 0, 32, 32)
    $g.DrawString($text, $font, $white, $rect, $fmt)
    $font.Dispose(); $fmt.Dispose(); $g.Dispose()

    $h = $bmp.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($h)
    $bmp.Dispose()
    return @{ Icon = $icon; Handle = $h }
}

function Update-Tray {
    param($notify)

    $s = $script:state
    $isError = ($null -eq $s.FiveHour)

    # 圖示(顯示 5h %)
    $r = New-PercentIcon -pct $s.FiveHour -isError $isError
    $notify.Icon = $r.Icon
    if ($script:lastIconHandle -ne [IntPtr]::Zero) {
        [void][Win32.NativeMethods]::DestroyIcon($script:lastIconHandle)
    }
    $script:lastIconHandle = $r.Handle

    # 工具提示(上限 63 字元)
    if ($isError) {
        $tip = "Claude usage 讀取失敗"
    } else {
        $tip = "5h {0}%(重置 {1:HH:mm}) 週 {2}%" -f $s.FiveHour, $s.FiveHourReset, $s.SevenDay
        if ($null -ne $s.CostToday) {
            $tip += (" 今日 `${0:N1}" -f $s.CostToday)
        }
    }
    if ($tip.Length -gt 63) { $tip = $tip.Substring(0, 63) }
    $notify.Text = $tip

    # 超過門檻時跳通知(80% / 95% 各一次,降回 80 以下後重置)
    if (-not $isError) {
        if ($s.FiveHour -ge 95 -and $s.NotifiedLevel -lt 95) {
            $notify.ShowBalloonTip(5000, "Claude 5h 額度", ("已用 {0}%,{1:HH:mm} 重置" -f $s.FiveHour, $s.FiveHourReset), [System.Windows.Forms.ToolTipIcon]::Warning)
            $s.NotifiedLevel = 95
        } elseif ($s.FiveHour -ge 80 -and $s.NotifiedLevel -lt 80) {
            $notify.ShowBalloonTip(5000, "Claude 5h 額度", ("已用 {0}%,{1:HH:mm} 重置" -f $s.FiveHour, $s.FiveHourReset), [System.Windows.Forms.ToolTipIcon]::Info)
            $s.NotifiedLevel = 80
        } elseif ($s.FiveHour -lt 80) {
            $s.NotifiedLevel = 0
        }
    }
}

function Show-Detail {
    $s = $script:state
    if ($null -eq $s.FiveHour) {
        $body = "尚未取得資料。`n$($s.ErrorMsg)"
    } else {
        $lines = @(
            ("5 小時額度:{0}%(重置 {1:HH:mm})" -f $s.FiveHour, $s.FiveHourReset),
            ("週額度:{0}%(重置 {1:M/d HH:mm})" -f $s.SevenDay, $s.SevenDayReset)
        )
        if ($null -ne $s.CostToday) {
            $lines += ("今日 token:{0:N0}(≈ `${1:N2})" -f $s.TokensToday, $s.CostToday)
        }
        $lines += ("更新時間:{0:HH:mm:ss}" -f $s.LastUpdate)
        if ($s.ErrorMsg) { $lines += "上次錯誤:$($s.ErrorMsg)" }
        $body = $lines -join "`n"
    }
    [void][System.Windows.Forms.MessageBox]::Show($body, "Claude Usage", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
}

# ---- 建立系統匣圖示與選單 ----
$notify = New-Object System.Windows.Forms.NotifyIcon
$menu = New-Object System.Windows.Forms.ContextMenuStrip

$miRefresh = $menu.Items.Add("立即更新")
$miDetail  = $menu.Items.Add("詳細資訊")
[void]$menu.Items.Add("-")
$miExit    = $menu.Items.Add("結束")

$miRefresh.add_Click({
    Update-OAuthUsage
    Read-CostFile
    Start-CostUpdate
    Update-Tray $notify
})
$miDetail.add_Click({ Show-Detail })
$miExit.add_Click({
    $notify.Visible = $false
    $notify.Dispose()
    [System.Windows.Forms.Application]::Exit()
})
$notify.add_DoubleClick({ Show-Detail })

$notify.ContextMenuStrip = $menu
$notify.Visible = $true

# ---- 定時更新:額度每 60 秒、成本每 10 分鐘 ----
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 60000
$timer.add_Tick({
    $script:tickCount++
    Update-OAuthUsage
    if ($script:tickCount % 10 -eq 0) { Start-CostUpdate }
    Read-CostFile
    Update-Tray $notify
})

# 初次更新
Update-OAuthUsage
Start-CostUpdate
Update-Tray $notify
$timer.Start()

[System.Windows.Forms.Application]::Run()

# 清理
$timer.Dispose()
if ($script:lastIconHandle -ne [IntPtr]::Zero) {
    [void][Win32.NativeMethods]::DestroyIcon($script:lastIconHandle)
}
$script:mutex.ReleaseMutex()
