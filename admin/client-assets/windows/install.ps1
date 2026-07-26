[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^https://')]
    [string]$Url,

    [ValidateRange(15, 86400)]
    [int]$FallbackSeconds = 200,

    [string]$ControlUrl = '',

    [string]$DeviceApiKey = ''
)

$ErrorActionPreference = 'Stop'
$TaskName = 'TV-WALL'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-InteractiveUser {
    $sessionId = (Get-Process -Id $PID).SessionId
    $explorer = Get-CimInstance Win32_Process -Filter "Name = 'explorer.exe'" |
        Where-Object { $_.SessionId -eq $sessionId } |
        Select-Object -First 1

    if (-not $explorer) {
        throw '找不到目前桌面登入使用者。請由要使用 TV-WALL 的帳號登入後再執行安裝。'
    }

    $owner = Invoke-CimMethod -InputObject $explorer -MethodName GetOwner
    if ($owner.ReturnValue -ne 0) {
        throw '無法辨識目前桌面登入使用者。'
    }

    $account = if ($owner.Domain) { "$($owner.Domain)\$($owner.User)" } else { $owner.User }
    $ntAccount = New-Object Security.Principal.NTAccount($account)
    $sid = $ntAccount.Translate([Security.Principal.SecurityIdentifier]).Value
    $profile = Get-CimInstance Win32_UserProfile |
        Where-Object { $_.SID -eq $sid } |
        Select-Object -First 1

    if (-not $profile -or -not $profile.LocalPath) {
        throw "找不到 $account 的使用者設定檔。"
    }

    [pscustomobject]@{
        Account = $account
        Sid = $sid
        ProfilePath = $profile.LocalPath
    }
}

function Find-Browser {
    param([string]$ProfilePath)

    $localAppData = Join-Path $ProfilePath 'AppData\Local'
    $candidates = @(
        @(
            (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
            (Join-Path $localAppData 'Google\Chrome\Application\chrome.exe'),
            (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
            (Join-Path $localAppData 'Microsoft\Edge\Application\msedge.exe')
        ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }
    )

    if (-not $candidates) {
        throw '找不到 Google Chrome 或 Microsoft Edge。請先安裝其中一個瀏覽器。'
    }
    return $candidates[0]
}

if (-not (Test-IsAdministrator)) {
    throw '請以系統管理員身分開啟 PowerShell，再執行此安裝程式。'
}

try {
    $uri = [Uri]$Url
    if (-not $uri.IsAbsoluteUri -or $uri.Scheme -ne 'https') {
        throw
    }
}
catch {
    throw '播放網址必須是有效的 https:// 網址。'
}

if ($ControlUrl -or $DeviceApiKey) {
    if (-not $ControlUrl -or -not $DeviceApiKey) {
        throw '管理後台網址與裝置 API 金鑰必須一起提供。'
    }
    try {
        $controlUri = [Uri]$ControlUrl
        if (-not $controlUri.IsAbsoluteUri -or $controlUri.Scheme -ne 'https') {
            throw
        }
    }
    catch {
        throw '管理後台網址必須是有效的 https:// 網址。'
    }
}

$target = Get-InteractiveUser
$browserPath = Find-Browser -ProfilePath $target.ProfilePath
$installRoot = Join-Path $target.ProfilePath 'AppData\Local\TV-WALL'
$profileRoot = Join-Path $installRoot 'BrowserProfile'
$configPath = Join-Path $installRoot 'config.json'
$launcherPath = Join-Path $installRoot 'chrome-kiosk.ps1'

$requiredFiles = @('chrome-kiosk.ps1', 'detect-canva-duration.ps1', 'uninstall.ps1')
foreach ($file in $requiredFiles) {
    $source = Join-Path $PSScriptRoot $file
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "安裝檔不完整，缺少：$file"
    }
}

New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
foreach ($file in $requiredFiles) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $installRoot -Force
}

[ordered]@{
    Url = $Url
    FallbackSeconds = $FallbackSeconds
    BrowserPath = $browserPath
    BrowserProfile = $profileRoot
    DebugPort = 9222
    ControlUrl = $ControlUrl.TrimEnd('/')
    DeviceApiKey = $DeviceApiKey
    Enabled = $true
} | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding UTF8

$accessRule = '{0}:(OI)(CI)M' -f $target.Account
& "$env:SystemRoot\System32\icacls.exe" $installRoot /grant $accessRule /T /C | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "無法授予 $($target.Account) TV-WALL 目錄權限。"
}

$arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$launcherPath`""
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arguments
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $target.Account
$principal = New-ScheduledTaskPrincipal -UserId $target.Account -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew

Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'TV-WALL browser kiosk player' | Out-Null
Start-ScheduledTask -TaskName $TaskName

Write-Host "安裝完成：$($target.Account)"
Write-Host "瀏覽器：$browserPath"
Write-Host "播放網址：$Url"
if ($ControlUrl) {
    Write-Host "管理後台：$($ControlUrl.TrimEnd('/'))"
}
Write-Host "Windows 登入後會自動啟動 TV-WALL。"
