[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$TaskName = 'TV-WALL'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-InteractiveUserProfile {
    $sessionId = (Get-Process -Id $PID).SessionId
    $explorer = Get-CimInstance Win32_Process -Filter "Name = 'explorer.exe'" |
        Where-Object { $_.SessionId -eq $sessionId } |
        Select-Object -First 1
    if (-not $explorer) {
        throw '找不到目前桌面登入使用者。'
    }
    $owner = Invoke-CimMethod -InputObject $explorer -MethodName GetOwner
    $account = if ($owner.Domain) { "$($owner.Domain)\$($owner.User)" } else { $owner.User }
    $ntAccount = New-Object Security.Principal.NTAccount($account)
    $sid = $ntAccount.Translate([Security.Principal.SecurityIdentifier]).Value
    $profile = Get-CimInstance Win32_UserProfile |
        Where-Object { $_.SID -eq $sid } |
        Select-Object -First 1
    if (-not $profile) {
        throw "找不到 $account 的使用者設定檔。"
    }
    [pscustomobject]@{ Account = $account; ProfilePath = $profile.LocalPath }
}

if (-not (Test-IsAdministrator)) {
    throw '請以系統管理員身分開啟 PowerShell，再執行此移除程式。'
}

$target = Get-InteractiveUserProfile
$installRoot = Join-Path $target.ProfilePath 'AppData\Local\TV-WALL'
$profileRoot = Join-Path $installRoot 'BrowserProfile'

Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

if (Test-Path -LiteralPath $installRoot) {
    $escaped = [Regex]::Escape($profileRoot)
    Get-CimInstance Win32_Process |
        Where-Object {
            $_.Name -match '^(chrome|msedge)\.exe$' -and
            $_.CommandLine -match "--user-data-dir=`"?$escaped"
        } |
        ForEach-Object {
            & "$env:SystemRoot\System32\taskkill.exe" /PID $_.ProcessId /T /F 2>$null | Out-Null
        }
    Remove-Item -LiteralPath $installRoot -Recurse -Force
}

Write-Host "已移除 $($target.Account) 的 TV-WALL。"
