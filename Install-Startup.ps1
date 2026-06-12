# 在「啟動」資料夾建立捷徑,讓 Usage Tray 開機自動啟動。
# 移除:刪除 shell:startup 裡的 "Claude Usage Tray.lnk" 即可。

$vbs = Join-Path $PSScriptRoot "Start-UsageTray.vbs"
$startup = [Environment]::GetFolderPath("Startup")
$lnkPath = Join-Path $startup "Claude Usage Tray.lnk"

$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($lnkPath)
$lnk.TargetPath = "wscript.exe"
$lnk.Arguments = "`"$vbs`""
$lnk.WorkingDirectory = $PSScriptRoot
$lnk.Description = "Claude Code usage tray monitor"
$lnk.Save()

Write-Host "已建立開機自啟捷徑:$lnkPath"
