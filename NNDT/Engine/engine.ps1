param(
    [switch]$JsonMode,
    [switch]$InfoOnly,
    [string]$TargetMode,
    [switch]$SetupDownloadOokla,
    [switch]$SetupSignEula
)

# ==============================================================================
#   SNDT - SINN NETWORK DIAGNOSTICS TOOL v1.0.0 (PS5.1 compatible backend)
# ==============================================================================

$version  = "1.1.5"
$baseDir  = if ($MyInvocation.MyCommand.Path) { Split-Path $MyInvocation.MyCommand.Path } else { (Get-Location).Path }

# Everything stays inside the tool folder — no traces outside
$cacheDir     = Join-Path $baseDir "Cache"
$vaultFile    = Join-Path $cacheDir ".vault"         # hidden file, hashed MACs
$speedtestExe = Join-Path $baseDir "speedtest.exe"

if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null }

# ============================================================
# HELPERS
# ============================================================
function Send-Json($obj) {
    $json = $obj | ConvertTo-Json -Compress -Depth 10
    [Console]::WriteLine($json)
    [Console]::Out.Flush()
}

function Send-Progress($pct, $msg) {
    Send-Json @{ Type = "Progress"; Pct = [int]$pct; Msg = $msg }
}

# ============================================================
# EULA VAULT (hardware hash, PS5.1 compatible)
# ============================================================
function Get-HardwareHash {
    $macs = @(Get-NetAdapter | Where-Object { $_.Status -eq "Up" } |
              Select-Object -ExpandProperty LinkLayerAddress | Sort-Object)
    $combined = $macs -join ""
    $sha  = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($combined)
    $hash = $sha.ComputeHash($bytes)
    return ([System.BitConverter]::ToString($hash)).Replace("-","").ToLower()
}

$eulaAccepted = $false
$currentHash  = Get-HardwareHash
$ooklaExists  = (Test-Path $speedtestExe)

if (Test-Path $vaultFile) {
    $vault = Get-Content $vaultFile -ErrorAction SilentlyContinue
    if ($vault -contains $currentHash) { $eulaAccepted = $true }
}

# ============================================================
# SETUP ACTIONS
# ============================================================
if ($SetupDownloadOokla) {
    $zipPath = Join-Path $cacheDir "st.zip"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-win64.zip" -OutFile $zipPath -UseBasicParsing
        Expand-Archive -Path $zipPath -DestinationPath $baseDir -Force
        Remove-Item $zipPath -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $baseDir "speedtest.md")  -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $baseDir "speedtest.pdf") -ErrorAction SilentlyContinue
    } catch {}
    exit 0
}

if ($SetupSignEula) {
    $currentHash | Add-Content $vaultFile
    try { (Get-Item $vaultFile).Attributes = 'Hidden' } catch {}
    exit 0
}

# ============================================================
# PING ENGINE (PS5.1 compat: use .NET Ping directly)
# ============================================================
function Invoke-PingTest {
    param($Target, [int]$Count, [string]$Label, [int]$StartPct, [int]$EndPct)

    $pingObj = New-Object System.Net.NetworkInformation.Ping
    $latencies = [System.Collections.ArrayList]@()
    $lost = 0

    for ($i = 1; $i -le $Count; $i++) {
        $pct = $StartPct + [Math]::Round(($i / $Count) * ($EndPct - $StartPct))
        if ($JsonMode -and ($i % 5 -eq 0 -or $i -eq 1 -or $i -eq $Count)) {
            Send-Progress $pct "PINGING $Label... ($i/$Count)"
        }
        try {
            $reply = $pingObj.Send($Target, 1500)
            if ($reply.Status -eq 'Success') { [void]$latencies.Add([long]$reply.RoundtripTime) }
            else { $lost++ }
        } catch { $lost++ }
        Start-Sleep -Milliseconds 20
    }

    $lossP = [Math]::Round(($lost / $Count) * 100, 1)
    $avg   = if ($latencies.Count -gt 0) { [Math]::Round(($latencies | Measure-Object -Average).Average, 1) } else { 999 }
    $jitter = 0
    if ($latencies.Count -gt 1) {
        $diffs = for ($i = 1; $i -lt $latencies.Count; $i++) { [Math]::Abs($latencies[$i] - $latencies[$i-1]) }
        $jitter = [Math]::Round(($diffs | Measure-Object -Average).Average, 1)
    }
    return @{ Avg = $avg; Jitter = $jitter; Loss = $lossP; Received = $latencies.Count; Total = $Count }
}

# ============================================================
# SYSTEM INFO
# ============================================================
function Get-SystemInfo {
    try {
        $activeRoute = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction Stop |
                       Sort-Object RouteMetric | Select-Object -First 1
        $adapter = Get-NetAdapter -InterfaceIndex $activeRoute.ifIndex -ErrorAction Stop
        $gateway = $activeRoute.NextHop
        $isWlan  = ($adapter.MediaType -match "Native 802.11|802.11" -or $adapter.Name -match "Wi-Fi|WLAN")

        # Quick pings with .NET
        $pingObj = New-Object System.Net.NetworkInformation.Ping
        $v4Avg = 999
        $v6Avg = 999

        try {
            $v4Samples = @(for ($i=0;$i -lt 4;$i++) { $r=$pingObj.Send("8.8.8.8",1000); if($r.Status -eq 'Success'){$r.RoundtripTime} })
            if ($v4Samples.Count -gt 0) { $v4Avg = [Math]::Round(($v4Samples | Measure-Object -Average).Average,1) }
        } catch {}

        try {
            $v6Samples = @(for ($i=0;$i -lt 4;$i++) { $r=$pingObj.Send("2001:4860:4860::8888",1000); if($r.Status -eq 'Success'){$r.RoundtripTime} })
            if ($v6Samples.Count -gt 0) { $v6Avg = [Math]::Round(($v6Samples | Measure-Object -Average).Average,1) }
        } catch {}

        # =============================================================
        # GATEWAY TYPE DETECTION via MAC OUI comparison
        # Logic: get gateway ARP-MAC + BSSID (Wi-Fi) or adapter MAC (LAN)
        # A router can have multiple MACs but all share the same OUI (first 3 octets)
        # If OUI of connected AP (BSSID) matches OUI of gateway ARP-MAC → Direct
        # If OUI differs → Repeater / Extender is in between
        # =============================================================
        function Get-OUI($mac) {
            # Normalize separators, return first 3 octets uppercase e.g. "AA:BB:CC"
            if (-not $mac) { return $null }
            $clean = $mac.ToUpper() -replace '[^0-9A-F]', ''
            if ($clean.Length -lt 6) { return $null }
            return "$($clean[0..1] -join ''):$($clean[2..3] -join ''):$($clean[4..5] -join '')"
        }

        $gwMac    = $null
        $gwType   = "N/A"
        $gwLatency = $null

        # Step 1: Get gateway MAC via ARP table
        try {
            # Ensure ARP cache has an entry by pinging gateway first
            $pingObj.Send($gateway, 500) | Out-Null
            $arpEntry = Get-NetNeighbor -IPAddress $gateway -ErrorAction SilentlyContinue |
                        Where-Object { $_.LinkLayerAddress -and $_.LinkLayerAddress -ne '00-00-00-00-00-00' } |
                        Select-Object -First 1
            if ($arpEntry) { $gwMac = $arpEntry.LinkLayerAddress }
        } catch {}

        $gwOui = Get-OUI $gwMac

        if ($isWlan) {
            # Step 2a: Wi-Fi — get BSSID of connected access point
            $wi = @(netsh wlan show interfaces 2>$null)
            $bssidLine = ($wi | Where-Object { $_ -match '\bBSSID\b' }) | Select-Object -First 1
            $bssidMac  = $null
            if ($bssidLine -and $bssidLine -match ':\s*([0-9a-fA-F]{2}[:\-][0-9a-fA-F]{2}[:\-][0-9a-fA-F]{2}[:\-][0-9a-fA-F]{2}[:\-][0-9a-fA-F]{2}[:\-][0-9a-fA-F]{2})') {
                $bssidMac = $Matches[1]
            }
            $bssidOui = Get-OUI $bssidMac

            if ($gwOui -and $bssidOui) {
                if ($gwOui -eq $bssidOui) {
                    $gwType = "Direct (Router)"
                } else {
                    $gwType = "Repeater / Extender"
                }
            } elseif ($gwMac) {
                $gwType = "Direct (Router)"  # BSSID unavailable, assume direct
            }

            # Wi-Fi gateway ping (local latency to AP/Router)
            try {
                $gwSamples = @(for ($i=0;$i -lt 6;$i++) { $r=$pingObj.Send($gateway,500); if($r.Status -eq 'Success'){$r.RoundtripTime} })
                if ($gwSamples.Count -gt 0) { $gwLatency = [Math]::Round(($gwSamples | Measure-Object -Average).Average,1) }
            } catch {}
        } else {
            # Step 2b: LAN — wired is always direct
            $gwType = "Direct (LAN)"
        }

        $extV4 = "N/A"; $extV6 = "N/A"
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $extV4 = (Invoke-RestMethod "https://api.ipify.org" -TimeoutSec 5 -UseBasicParsing).Trim()
        } catch {}
        # IPv6: try primary, then fallback endpoint
        try {
            $extV6 = (Invoke-RestMethod "https://api6.ipify.org" -TimeoutSec 8 -UseBasicParsing).Trim()
        } catch {}
        if ($extV6 -eq "N/A" -or $extV6 -eq "") {
            try { $extV6 = (Invoke-RestMethod "https://v6.ident.me" -TimeoutSec 6 -UseBasicParsing).Trim() } catch {}
        }

        $connType = if ($isWlan) {
            # Signal: works in EN + DE (both say "Signal")
            $sigLine = ($wi | Where-Object { $_ -match 'Signal\s*:' }) | Select-Object -First 1
            $sig = if ($sigLine -and $sigLine -match ':\s*(\d+)\s*%') { $Matches[1] } else { "?" }

            # Channel: EN = "Channel", DE = "Kanal"
            $chLine = ($wi | Where-Object { $_ -match '^\s*(Channel|Kanal)\s*:' }) | Select-Object -First 1
            $ch = if ($chLine -and $chLine -match ':\s*(\d+)') { $Matches[1] } else { "?" }

            # Band: EN = "Radio Frequency Band", DE = "Bereich" or "Frequenz"
            $freqLine = ($wi | Where-Object { $_ -match 'Bereich|Frequenz|Frequency.*Band' }) | Select-Object -First 1
            $band = if ($freqLine -and $freqLine -match ':\s*(.+)$') {
                $fStr = $Matches[1].Trim()
                if    ($fStr -match '6')       { "6 GHz" }
                elseif($fStr -match '5')       { "5 GHz" }
                elseif($fStr -match '2[,.]?4') { "2.4 GHz" }
                else { $fStr }
            } elseif ($ch -ne "?") {
                $chNum = [int]$ch
                if    ($chNum -le 14)  { "2.4 GHz" }
                elseif($chNum -le 144) { "5 GHz" }
                else                   { "6 GHz" }
            } else { "?" }

            # SSID
            $ssidLine = ($wi | Where-Object { $_ -match '^\s*SSID\s*:' }) | Select-Object -First 1
            $ssid = if ($ssidLine -and $ssidLine -match ':\s*(.+)$') { $Matches[1].Trim() } else { "" }

            # Radio type: EN = "Radio type", DE = "Funktyp"
            $radioLine = ($wi | Where-Object { $_ -match 'Radio type|Funktyp' }) | Select-Object -First 1
            $radio = if ($radioLine -and $radioLine -match ':\s*(.+)$') { $Matches[1].Trim() } else { "" }

            $radioStr = if ($radio) { " $radio" } else { "" }
            $ssidStr  = if ($ssid)  { " | $ssid" } else { "" }
            "Wi-Fi$radioStr$ssidStr | Signal: $sig% | Ch: $ch | $band"
        } else {
            "LAN Cable | $($adapter.LinkSpeed)"
        }

        return @{
            Adapter      = $adapter.InterfaceDescription
            Gateway      = $gateway
            GatewayType  = $gwType
            GatewayLatency = $gwLatency
            ConnType     = $connType
            PingV4       = $v4Avg
            PingV6       = $v6Avg
            ExtIPv4      = $extV4
            ExtIPv6      = $extV6
            OoklaExists  = $ooklaExists
            EulaAccepted = $eulaAccepted
        }
    } catch {
        return @{
            Adapter="Error reading adapter"; Gateway="N/A"; GatewayType="N/A"; ConnType="Unknown"
            PingV4=999; PingV6=999; ExtIPv4="N/A"; ExtIPv6="N/A"
            OoklaExists=$ooklaExists; EulaAccepted=$eulaAccepted
        }
    }
}

if ($InfoOnly) {
    $info = Get-SystemInfo
    Send-Json $info
    exit 0
}

# ============================================================
# SCORING
# ============================================================
function Get-Grade($ping, $jitter, $loss) {
    $score = 100
    if ($loss  -ge 5)  { $score -= 60 } elseif ($loss  -ge 2)  { $score -= 40 }
    elseif ($loss  -ge 1)  { $score -= 20 } elseif ($loss  -gt 0)  { $score -= 10 }
    if ($ping  -ge 200){ $score -= 35 } elseif ($ping  -ge 100){ $score -= 20 }
    elseif ($ping  -ge 50) { $score -= 10 } elseif ($ping  -ge 30) { $score -= 5 }
    if ($jitter -ge 30){ $score -= 25 } elseif ($jitter -ge 15){ $score -= 15 }
    elseif ($jitter -ge 8)  { $score -= 8 } elseif ($jitter -ge 4)  { $score -= 3 }
    $score = [Math]::Max(0, $score)
    $grade = if ($score -ge 90){'A'} elseif($score -ge 75){'B'} elseif($score -ge 55){'C'} elseif($score -ge 35){'D'} else{'F'}
    return @{ score=$score; grade=$grade }
}

function Get-ScoreText($grade) {
    switch ($grade) {
        'A' { "Excellent. Ideal for competitive gaming and 4K streaming." }
        'B' { "Good. Suitable for most online activities." }
        'C' { "Moderate. Some real-time activities may be affected." }
        'D' { "Poor. Noticeable issues in games and video calls." }
        default { "Critical. Immediate troubleshooting recommended." }
    }
}

# ============================================================
# DNS BENCHMARK
# ============================================================
function Invoke-DnsBenchmark($useV6) {
    $dnsTargets = [ordered]@{}
    $recordType = "A"

    if ($useV6) {
        $recordType = "AAAA"
        $dnsTargets["System"]     = "2001:4860:4860::8888"
        $dnsTargets["Cloudflare"] = "2606:4700:4700::1111"
        $dnsTargets["Google"]     = "2001:4860:4860::8888"
        $dnsTargets["Quad9"]      = "2620:fe::fe"
    } else {
        try {
            $ifIndex = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Sort-Object RouteMetric | Select-Object -First 1).ifIndex
            $sysDns  = (Get-DnsClientServerAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses | Select-Object -First 1
        } catch { $sysDns = $null }
        $gw = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Sort-Object RouteMetric | Select-Object -First 1).NextHop
        $dnsTargets["System"]     = if ($sysDns) { $sysDns } elseif ($gw) { $gw } else { "8.8.8.8" }
        $dnsTargets["Cloudflare"] = "1.1.1.1"
        $dnsTargets["Google"]     = "8.8.8.8"
        $dnsTargets["Quad9"]      = "9.9.9.9"
    }

    $domains = @("youtube.com","discord.com","twitch.tv","google.com","netflix.com")
    $results = @()

    foreach ($name in $dnsTargets.Keys) {
        $ip = $dnsTargets[$name]; $total = 0.0; $ok = 0
        foreach ($domain in $domains) {
            try {
                $elapsed = (Measure-Command {
                    Resolve-DnsName -Name $domain -Server $ip -Type $recordType -ErrorAction Stop | Out-Null
                }).TotalMilliseconds
                $total += $elapsed; $ok++
            } catch {}
        }
        $avg = if ($ok -gt 0) { [Math]::Round($total / $ok, 1) } else { 999.0 }
        $results += [PSCustomObject]@{ Name=$name; IP=$ip; AvgTimeMs=$avg }
    }
    return ($results | Sort-Object AvgTimeMs)
}

# ============================================================
# MAIN TEST RUNNER (GUI Mode)
# ============================================================
if ($JsonMode -and $TargetMode) {

    $targetMap = @{
        'a' = @{ host="8.8.8.8";       label="MULTI-TARGET"; mode="full" }
        'b' = @{ host="8.8.8.8";       label="FAST CHECK";   mode="fast" }
        '1' = @{ host="8.8.8.8";       label="GOOGLE DNS" }
        '2' = @{ host="1.1.1.1";       label="CLOUDFLARE DNS" }
        '3' = @{ host="youtube.com";   label="YOUTUBE CDN" }
        '4' = @{ host="discord.com";   label="DISCORD" }
        '5' = @{ host="twitch.tv";     label="TWITCH" }
        '6' = @{ host="eu.battle.net"; label="BLIZZARD EU" }
        '7' = @{ host="dynamodb.eu-central-1.amazonaws.com"; label="AWS EU" }
    }

    $cfg = $targetMap[$TargetMode]
    if (-not $cfg) {
        Send-Json @{ Type="Result"; Score="F"; ScoreText="Unknown mode '$TargetMode'." }
        exit 1
    }

    # Determine protocol
    Send-Progress 3 "DETECTING PROTOCOL..."
    $useV6   = $false
    $pingObj = New-Object System.Net.NetworkInformation.Ping
    try {
        $p4s = @(for($i=0;$i -lt 4;$i++){$r=$pingObj.Send("8.8.8.8",1000);if($r.Status -eq 'Success'){$r.RoundtripTime}})
        $p4  = if($p4s.Count -gt 0){($p4s|Measure-Object -Average).Average}else{999}
    } catch { $p4 = 999 }
    try {
        $p6s = @(for($i=0;$i -lt 4;$i++){$r=$pingObj.Send("2001:4860:4860::8888",1000);if($r.Status -eq 'Success'){$r.RoundtripTime}})
        $p6  = if($p6s.Count -gt 0){($p6s|Measure-Object -Average).Average}else{999}
    } catch { $p6 = 999 }
    if ($p6 -lt 999 -and $p6 -le ($p4 + 5)) { $useV6 = $true }
    $protocol = if ($useV6) { "IPv6" } else { "IPv4" }

    # ROUTER TEST
    $gateway = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Sort-Object RouteMetric | Select-Object -First 1).NextHop
    Send-Progress 8 "TESTING LOCAL GATEWAY..."
    $routerStats = Invoke-PingTest -Target $gateway -Count 80 -Label "GATEWAY" -StartPct 8 -EndPct 25

    # INTERNET TEST
    $pingCount   = if ($cfg.mode -eq "fast") { 100 } elseif ($cfg.mode -eq "full") { 200 } else { 120 }
    $targetHost  = $cfg.host
    $internetStats = Invoke-PingTest -Target $targetHost -Count $pingCount -Label $cfg.label -StartPct 25 -EndPct 75

    # DNS BENCHMARK
    Send-Progress 77 "RUNNING DNS BENCHMARK..."
    $dnsResults = Invoke-DnsBenchmark $useV6
    $bestDns    = $dnsResults | Where-Object { $_.AvgTimeMs -lt 999 } | Select-Object -First 1
    $sysDns     = $dnsResults | Where-Object { $_.Name -eq "System" } | Select-Object -First 1
    $dnsSummary = if ($bestDns -and $sysDns -and $bestDns.Name -ne "System" -and ($sysDns.AvgTimeMs - $bestDns.AvgTimeMs) -ge 3) {
        "> $($bestDns.Name) ($($bestDns.IP)) is $([Math]::Round($sysDns.AvgTimeMs - $bestDns.AvgTimeMs, 1)) ms faster than your System DNS."
    } elseif ($bestDns -and $bestDns.Name -eq "System") {
        "> Your System DNS is already fully optimized."
    } else { "> DNS performance differences are negligible." }

    # SPEEDTEST
    $dlMbit = $null; $ulMbit = $null; $bbDiff = $null
    if ($eulaAccepted -and (Test-Path $speedtestExe)) {
        Send-Progress 82 "RUNNING BANDWIDTH TEST..."
        try {
            $raw   = & $speedtestExe --accept-license --accept-gdpr -f json 2>$null
            $speed = $raw | ConvertFrom-Json
            $dlMbit = [Math]::Round($speed.download.bandwidth / 125000, 1)
            $ulMbit = [Math]::Round($speed.upload.bandwidth / 125000, 1)
            $idlePing = $speed.ping.latency
            $loadPing = $speed.download.latency.iqm
            if ($idlePing -gt 0 -and $loadPing -gt 0) { $bbDiff = [Math]::Round($loadPing - $idlePing, 1) }
        } catch {}
    }

    # TRACEROUTE (skip for fast mode)
    $traceResult = "Skipped"
    if ($cfg.mode -ne "fast" -and $TargetMode -ne 'b') {
        Send-Progress 93 "MAPPING ROUTE..."
        try {
            $traceRaw = tracert -h 15 $targetHost 2>$null
            $hops = @($traceRaw | Select-String "^\s*\d+" | ForEach-Object { $_.ToString().Trim() })
            $traceResult = $hops -join "`n"
        } catch { $traceResult = "Traceroute failed." }
    }

    Send-Progress 99 "CALCULATING SCORE..."
    $gradeResult = Get-Grade $internetStats.Avg $internetStats.Jitter $internetStats.Loss

    Send-Json @{
        Type          = "Result"
        Protocol      = $protocol
        Score         = $gradeResult.grade
        ScoreText     = (Get-ScoreText $gradeResult.grade)
        Latency       = $internetStats.Avg
        Jitter        = $internetStats.Jitter
        Loss          = $internetStats.Loss
        RouterLat     = $routerStats.Avg
        RouterJit     = $routerStats.Jitter
        RouterLoss    = $routerStats.Loss
        Download      = $dlMbit
        Upload        = $ulMbit
        Bufferbloat   = $bbDiff
        DnsResults    = $dnsResults
        DnsSummary    = $dnsSummary
        TracerouteRaw = $traceResult
    }
    exit 0
}

# ============================================================
# CONSOLE FALLBACK (no GUI params)
# ============================================================
Write-Host "SNDT v$version - Please launch via the SNDT GUI (Start.bat)." -ForegroundColor Yellow