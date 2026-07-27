[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$InstallRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $InstallRoot 'config.json'
$DetectorPath = Join-Path $InstallRoot 'detect-canva-duration.ps1'
$LogPath = Join-Path $InstallRoot 'tv-wall.log'
$AppVersion = '1.2.1'
$StartedAt = Get-Date

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
    $browserProcesses = Get-CimInstance Win32_Process |
        Where-Object {
            $_.Name -match '^(chrome|msedge)\.exe$' -and
            $_.CommandLine -match "--user-data-dir=`"?$escaped"
        }

    foreach ($browserProcess in $browserProcesses) {
        $desktopProcess = Get-Process -Id $browserProcess.ProcessId -ErrorAction SilentlyContinue
        if ($desktopProcess -and $desktopProcess.MainWindowHandle -ne 0) {
            $shell = New-Object -ComObject WScript.Shell
            if ($shell.AppActivate([int]$browserProcess.ProcessId)) {
                Start-Sleep -Milliseconds 750
                $shell.SendKeys('{SPACE}')
                Write-Log "已將播放指令送至瀏覽器視窗 PID $($browserProcess.ProcessId)。"
                return $true
            }
        }
    }

    Write-Log '找不到可接收播放指令的瀏覽器主視窗。'
    return $false
}

function Sync-Control {
    param(
        $Config,
        [string]$Status = 'playing',
        [string]$ErrorMessage = ''
    )

    if (-not $Config.ControlUrl -or -not $Config.DeviceApiKey) {
        return $false
    }

    try {
        $previousUrl = [string]$Config.Url
        $response = Invoke-RestMethod `
            -Uri "$($Config.ControlUrl.TrimEnd('/'))/api/agent/heartbeat" `
            -Method Post `
            -Headers @{ Authorization = "Bearer $($Config.DeviceApiKey)" } `
            -Body @{
                status = $Status
                current_url = $Config.Url
                app_version = $AppVersion
                os_version = [Environment]::OSVersion.VersionString
                uptime_seconds = [Math]::Floor(((Get-Date) - $StartedAt).TotalSeconds)
                error_message = $ErrorMessage
            } `
            -TimeoutSec 10

        if ($response.configuration) {
            $Config.Enabled = [bool]$response.configuration.enabled
            $Config.Url = [string]$response.configuration.playbackUrl
            $Config.FallbackSeconds = [int]$response.configuration.fallbackSeconds
            return $Config.Url -ne $previousUrl
        }
    }
    catch {
        Write-Log "管理後台連線失敗：$($_.Exception.Message)"
    }
    return $false
}

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "找不到設定檔：$ConfigPath"
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if ($null -eq $config.Enabled) {
    $config | Add-Member -NotePropertyName Enabled -NotePropertyValue $true
}
if (-not (Test-Path -LiteralPath $config.BrowserPath -PathType Leaf)) {
    throw "找不到瀏覽器：$($config.BrowserPath)"
}

try {
    while ($true) {
        $null = Sync-Control -Config $config -Status 'loading'
        if (-not $config.Enabled) {
            Stop-KioskBrowser -ProfilePath $config.BrowserProfile
            Write-Log '此節點已由管理後台停用，等待重新啟用。'
            while (-not $config.Enabled) {
                Start-Sleep -Seconds 30
                $null = Sync-Control -Config $config -Status 'disabled'
            }
            Write-Log '節點已由管理後台重新啟用。'
        }

        Stop-KioskBrowser -ProfilePath $config.BrowserProfile
        Start-Sleep -Seconds 2
        $browser = Start-KioskBrowser -Config $config
        Write-Log "已啟動瀏覽器 PID $($browser.Id)：$($config.Url)"

        Start-Sleep -Seconds 8
        $null = Send-PlaybackKey -ProfilePath $config.BrowserProfile
        Start-Sleep -Seconds 2
        $detected = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $DetectorPath -Port $config.DebugPort -WaitSeconds 30
        if ($LASTEXITCODE -eq 0 -and $detected -match '^\d+$') {
            $sleepSeconds = [int]$detected + 5
            Write-Log "偵測到播放長度 $detected 秒；$sleepSeconds 秒後重新啟動。"
        }
        else {
            $sleepSeconds = [int]$config.FallbackSeconds
            Write-Log "無法偵測播放長度；使用備援 $sleepSeconds 秒。"
        }

        if ($LASTEXITCODE -ne 0) {
            $null = Send-PlaybackKey -ProfilePath $config.BrowserProfile
        }

        $remaining = $sleepSeconds
        while ($remaining -gt 0) {
            $step = [Math]::Min(30, $remaining)
            Start-Sleep -Seconds $step
            $remaining -= $step
            $configurationChanged = Sync-Control -Config $config -Status 'playing'
            if (-not $config.Enabled -or $configurationChanged) {
                break
            }
        }
    }
}
catch {
    Write-Log "錯誤：$($_.Exception.Message)"
    $null = Sync-Control -Config $config -Status 'error' -ErrorMessage $_.Exception.Message
    throw
}
finally {
    $null = Sync-Control -Config $config -Status 'offline'
    Stop-KioskBrowser -ProfilePath $config.BrowserProfile
}
