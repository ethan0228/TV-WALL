[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$InstallRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $InstallRoot 'config.json'
$DetectorPath = Join-Path $InstallRoot 'detect-canva-duration.ps1'
$LogPath = Join-Path $InstallRoot 'tv-wall.log'

function Write-Log {
    param([string]$Message)
    $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

function Stop-KioskBrowser {
    param([string]$ProfilePath)
    $escaped = [Regex]::Escape($ProfilePath)
    Get-CimInstance Win32_Process |
        Where-Object {
            $_.Name -match '^(chrome|msedge)\.exe$' -and
            $_.CommandLine -match "--user-data-dir=`"?$escaped"
        } |
        ForEach-Object {
            & "$env:SystemRoot\System32\taskkill.exe" /PID $_.ProcessId /T /F 2>$null | Out-Null
        }
}

function Start-KioskBrowser {
    param($Config)
    $arguments = @(
        "--user-data-dir=`"$($Config.BrowserProfile)`""
        '--kiosk'
        '--no-first-run'
        '--disable-session-crashed-bubble'
        '--autoplay-policy=no-user-gesture-required'
        '--remote-debugging-address=127.0.0.1'
        "--remote-debugging-port=$($Config.DebugPort)"
        '--remote-allow-origins=http://localhost'
        "`"$($Config.Url)`""
    )
    Start-Process -FilePath $Config.BrowserPath -ArgumentList $arguments -PassThru
}

function Send-PlaybackKey {
    param([string]$ProfilePath)
    $escaped = [Regex]::Escape($ProfilePath)
    $browser = Get-CimInstance Win32_Process |
        Where-Object {
            $_.Name -match '^(chrome|msedge)\.exe$' -and
            $_.CommandLine -match "--user-data-dir=`"?$escaped"
        } |
        Select-Object -First 1

    if ($browser) {
        $shell = New-Object -ComObject WScript.Shell
        if ($shell.AppActivate([int]$browser.ProcessId)) {
            Start-Sleep -Seconds 1
            $shell.SendKeys(' ')
        }
    }
}

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "找不到設定檔：$ConfigPath"
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if (-not (Test-Path -LiteralPath $config.BrowserPath -PathType Leaf)) {
    throw "找不到瀏覽器：$($config.BrowserPath)"
}

try {
    while ($true) {
        Stop-KioskBrowser -ProfilePath $config.BrowserProfile
        Start-Sleep -Seconds 2
        $browser = Start-KioskBrowser -Config $config
        Write-Log "已啟動瀏覽器 PID $($browser.Id)：$($config.Url)"

        Start-Sleep -Seconds 10
        $detected = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $DetectorPath -Port $config.DebugPort -WaitSeconds 30
        if ($LASTEXITCODE -eq 0 -and $detected -match '^\d+$') {
            $sleepSeconds = [int]$detected + 5
            Write-Log "偵測到播放長度 $detected 秒；$sleepSeconds 秒後重新啟動。"
        }
        else {
            $sleepSeconds = [int]$config.FallbackSeconds
            Write-Log "無法偵測播放長度；使用備援 $sleepSeconds 秒。"
        }

        Send-PlaybackKey -ProfilePath $config.BrowserProfile
        Start-Sleep -Seconds $sleepSeconds
    }
}
catch {
    Write-Log "錯誤：$($_.Exception.Message)"
    throw
}
finally {
    Stop-KioskBrowser -ProfilePath $config.BrowserProfile
}
