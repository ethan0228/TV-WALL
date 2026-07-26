[CmdletBinding()]
param(
    [ValidateRange(1, 65535)]
    [int]$Port = 9222,

    [ValidateRange(1, 120)]
    [int]$WaitSeconds = 30
)

$ErrorActionPreference = 'Stop'
$deadline = (Get-Date).AddSeconds($WaitSeconds)
$target = $null

while (-not $target -and (Get-Date) -lt $deadline) {
    try {
        $targets = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/list" -TimeoutSec 2
        $target = $targets |
            Where-Object { $_.type -eq 'page' -and $_.url -match 'canva\.com/design/' } |
            Select-Object -First 1
    }
    catch {
        # Browser or page is still loading.
    }
    if (-not $target) {
        Start-Sleep -Milliseconds 500
    }
}

if (-not $target -or -not $target.webSocketDebuggerUrl) {
    exit 1
}

$expression = @"
new Promise((resolve) => {
  const deadline = Date.now() + $($WaitSeconds * 1000);
  const parseTime = (text) => {
    const parts = String(text).trim().split(':').map(Number);
    if (!parts.length || parts.some(Number.isNaN)) return 0;
    return parts.reduce((total, part) => total * 60 + part, 0);
  };
  const detect = () => {
    const videoDurations = Array.from(document.querySelectorAll('video'))
      .map((video) => Number(video.duration))
      .filter((duration) => Number.isFinite(duration) && duration > 0);
    const displayedTimes = Array.from(document.querySelectorAll('time'))
      .map((item) => parseTime(item.textContent))
      .filter((duration) => duration > 0);
    const durations = videoDurations.concat(displayedTimes);
    if (durations.length) return resolve(Math.max(...durations));
    if (Date.now() >= deadline) return resolve(null);
    setTimeout(detect, 500);
  };
  detect();
})
"@

$command = @{
    id = 1
    method = 'Runtime.evaluate'
    params = @{
        expression = $expression
        awaitPromise = $true
        returnByValue = $true
    }
} | ConvertTo-Json -Depth 6 -Compress

$socket = New-Object System.Net.WebSockets.ClientWebSocket
$socket.Options.SetRequestHeader('Origin', 'http://localhost')
$cancellationSource = New-Object Threading.CancellationTokenSource
$cancellationSource.CancelAfter([TimeSpan]::FromSeconds($WaitSeconds + 5))
$cancellation = $cancellationSource.Token

try {
    $socket.ConnectAsync([Uri]$target.webSocketDebuggerUrl, $cancellation).GetAwaiter().GetResult()

    $payload = [Text.Encoding]::UTF8.GetBytes($command)
    $sendSegment = New-Object 'System.ArraySegment[byte]' -ArgumentList (,$payload)
    $socket.SendAsync(
        $sendSegment,
        [Net.WebSockets.WebSocketMessageType]::Text,
        $true,
        $cancellation
    ).GetAwaiter().GetResult()

    while ($socket.State -eq [Net.WebSockets.WebSocketState]::Open) {
        $stream = New-Object IO.MemoryStream
        do {
            $buffer = New-Object byte[] 8192
            $receiveSegment = New-Object 'System.ArraySegment[byte]' -ArgumentList (,$buffer)
            $result = $socket.ReceiveAsync($receiveSegment, $cancellation).GetAwaiter().GetResult()
            if ($result.Count -gt 0) {
                $stream.Write($buffer, 0, $result.Count)
            }
        } while (-not $result.EndOfMessage)

        if ($result.MessageType -eq [Net.WebSockets.WebSocketMessageType]::Close) {
            break
        }

        $message = [Text.Encoding]::UTF8.GetString($stream.ToArray()) | ConvertFrom-Json
        if ($message.id -eq 1) {
            $value = $message.result.result.value
            if ($null -ne $value -and [double]$value -gt 0) {
                [Math]::Ceiling([double]$value)
                exit 0
            }
            exit 1
        }
    }
}
catch {
    exit 1
}
finally {
    if ($socket) {
        $socket.Dispose()
    }
    if ($cancellationSource) {
        $cancellationSource.Dispose()
    }
}

exit 1
