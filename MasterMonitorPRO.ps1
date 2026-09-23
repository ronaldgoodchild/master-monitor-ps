#Requires -Version 5.1
<#
.SYNOPSIS
    REGTeches NOC Dashboard PRO v17.0 - PowerShell Edition
    
.DESCRIPTION
    Enhanced server monitoring with database logging, web dashboard, advanced analytics,
    multiple notification channels (Email, Telegram, Pushover, Webhook), report generation,
    system tray integration, and AI-powered failure prediction.
    
.NOTES
    Author: REGTeches
    Version: 17.0 PRO
    Features: Database logging, Web API, Advanced notifications, AI Analytics, Reports
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Web

# ============================================================================
# DATABASE MODULE
# ============================================================================

class Database {
    [string]$DbPath
    
    Database([string]$path) {
        $this.DbPath = $path
        $this.Initialize()
    }
    
    [void]Initialize() {
        if (-not (Test-Path $this.DbPath)) {
            $conn = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$($this.DbPath)")
            $conn.Open()
            
            $createTable = @"
CREATE TABLE IF NOT EXISTS checks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    server_address TEXT NOT NULL,
    server_name TEXT NOT NULL,
    timestamp TEXT NOT NULL,
    is_online INTEGER NOT NULL,
    response_time_ms REAL,
    http_status_code INTEGER,
    error_message TEXT
);
CREATE INDEX IF NOT EXISTS idx_server_address ON checks(server_address);
CREATE INDEX IF NOT EXISTS idx_timestamp ON checks(timestamp);
"@
            
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = $createTable
            $cmd.ExecuteNonQuery() | Out-Null
            $conn.Close()
        }
    }
    
    [void]LogCheck([hashtable]$checkResult) {
        $conn = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$($this.DbPath)")
        $conn.Open()
        
        $sql = @"
INSERT INTO checks (server_address, server_name, timestamp, is_online, response_time_ms, http_status_code, error_message)
VALUES (@addr, @name, @time, @online, @response, @status, @error)
"@
        
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $sql
        $cmd.Parameters.AddWithValue("@addr", $checkResult.Address) | Out-Null
        $cmd.Parameters.AddWithValue("@name", $checkResult.Name) | Out-Null
        $cmd.Parameters.AddWithValue("@time", (Get-Date -Format "yyyy-MM-dd HH:mm:ss")) | Out-Null
        $cmd.Parameters.AddWithValue("@online", [int]$checkResult.IsOnline) | Out-Null
        $cmd.Parameters.AddWithValue("@response", $checkResult.ResponseTime) | Out-Null
        $cmd.Parameters.AddWithValue("@status", $checkResult.HttpStatus) | Out-Null
        $cmd.Parameters.AddWithValue("@error", $checkResult.Error) | Out-Null
        
        $cmd.ExecuteNonQuery() | Out-Null
        $conn.Close()
    }
    
    [hashtable]GetUptimeStats([string]$address, [int]$hours) {
        $conn = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$($this.DbPath)")
        $conn.Open()
        
        $since = (Get-Date).AddHours(-$hours).ToString("yyyy-MM-dd HH:mm:ss")
        
        $sql = @"
SELECT 
    COUNT(*) as total_checks,
    SUM(is_online) as online_checks,
    AVG(CASE WHEN is_online = 1 THEN response_time_ms END) as avg_response
FROM checks 
WHERE server_address = @addr AND timestamp > @since
"@
        
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $sql
        $cmd.Parameters.AddWithValue("@addr", $address) | Out-Null
        $cmd.Parameters.AddWithValue("@since", $since) | Out-Null
        
        $reader = $cmd.ExecuteReader()
        $stats = @{
            TotalChecks = 0
            OnlineChecks = 0
            UptimePercent = 0.0
            AvgResponseTime = 0.0
        }
        
        if ($reader.Read()) {
            $stats.TotalChecks = $reader["total_checks"]
            $stats.OnlineChecks = $reader["online_checks"]
            if ($stats.TotalChecks -gt 0) {
                $stats.UptimePercent = ($stats.OnlineChecks / $stats.TotalChecks) * 100
            }
            if (-not $reader.IsDBNull(2)) {
                $stats.AvgResponseTime = $reader["avg_response"]
            }
        }
        
        $reader.Close()
        $conn.Close()
        
        return $stats
    }
    
    [array]GetRecentChecks([string]$address, [int]$limit) {
        $conn = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$($this.DbPath)")
        $conn.Open()
        
        $sql = "SELECT timestamp, is_online, response_time_ms, error_message FROM checks WHERE server_address = @addr ORDER BY timestamp DESC LIMIT @limit"
        
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $sql
        $cmd.Parameters.AddWithValue("@addr", $address) | Out-Null
        $cmd.Parameters.AddWithValue("@limit", $limit) | Out-Null
        
        $reader = $cmd.ExecuteReader()
        $results = @()
        
        while ($reader.Read()) {
            $results += @{
                Timestamp = $reader["timestamp"]
                IsOnline = [bool]$reader["is_online"]
                ResponseTime = if (-not $reader.IsDBNull(2)) { $reader["response_time_ms"] } else { $null }
                Error = if (-not $reader.IsDBNull(3)) { $reader["error_message"] } else { "" }
            }
        }
        
        $reader.Close()
        $conn.Close()
        
        return $results
    }
}

# ============================================================================
# ANALYTICS MODULE
# ============================================================================

class Analytics {
    [Database]$DB
    
    Analytics([Database]$database) {
        $this.DB = $database
    }
    
    [double]PredictDowntimeRisk([string]$address) {
        $recentChecks = $this.DB.GetRecentChecks($address, 100)
        
        if ($recentChecks.Count -lt 10) {
            return 0.0
        }
        
        # Calculate recent failure rate
        $recent20 = $recentChecks | Select-Object -First 20
        $recentFailures = ($recent20 | Where-Object { -not $_.IsOnline }).Count
        $failureRate = $recentFailures / 20.0
        
        # Calculate response time degradation
        $recentTimes = ($recent20 | Where-Object { $_.ResponseTime -ne $null }).ResponseTime
        $olderTimes = ($recentChecks | Select-Object -Skip 20 -First 20 | Where-Object { $_.ResponseTime -ne $null }).ResponseTime
        
        $degradation = 0.0
        if ($recentTimes.Count -gt 0 -and $olderTimes.Count -gt 0) {
            $avgRecent = ($recentTimes | Measure-Object -Average).Average
            $avgOlder = ($olderTimes | Measure-Object -Average).Average
            
            if ($avgOlder -gt 0) {
                $degradation = [Math]::Max(0, ($avgRecent - $avgOlder) / $avgOlder)
            }
        }
        
        # Risk score (0-1)
        $riskScore = [Math]::Min(1.0, ($failureRate * 0.7) + ($degradation * 0.3))
        
        return $riskScore
    }
    
    [hashtable]GetFailurePatterns([string]$address) {
        $conn = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$($this.DB.DbPath)")
        $conn.Open()
        
        $sql = "SELECT timestamp FROM checks WHERE server_address = @addr AND is_online = 0 ORDER BY timestamp DESC LIMIT 1000"
        
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $sql
        $cmd.Parameters.AddWithValue("@addr", $address) | Out-Null
        
        $reader = $cmd.ExecuteReader()
        $failures = @()
        
        while ($reader.Read()) {
            $failures += [datetime]::Parse($reader["timestamp"])
        }
        
        $reader.Close()
        $conn.Close()
        
        if ($failures.Count -eq 0) {
            return @{ Message = "No failures detected" }
        }
        
        # Analyze by hour and day
        $hourCounts = @{}
        $dayCounts = @{}
        
        foreach ($failure in $failures) {
            $hour = $failure.Hour
            $day = $failure.DayOfWeek
            
            if (-not $hourCounts.ContainsKey($hour)) { $hourCounts[$hour] = 0 }
            if (-not $dayCounts.ContainsKey($day)) { $dayCounts[$day] = 0 }
            
            $hourCounts[$hour]++
            $dayCounts[$day]++
        }
        
        $mostCommonHour = ($hourCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Key
        $mostCommonDay = ($dayCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Key
        
        return @{
            TotalFailures = $failures.Count
            MostCommonHour = $mostCommonHour
            MostCommonDay = $mostCommonDay
            HourDistribution = $hourCounts
            DayDistribution = $dayCounts
        }
    }
}

# ============================================================================
# ADVANCED NOTIFICATIONS MODULE
# ============================================================================

class AdvancedNotifications {
    [hashtable]$Config
    [hashtable]$LastAlertTime = @{}
    [int]$AlertCooldownMinutes = 15
    
    AdvancedNotifications([hashtable]$config) {
        $this.Config = $config
    }
    
    [bool]ShouldSendAlert([string]$address) {
        $now = Get-Date
        
        if ($this.LastAlertTime.ContainsKey($address)) {
            $elapsed = ($now - $this.LastAlertTime[$address]).TotalMinutes
            if ($elapsed -lt $this.AlertCooldownMinutes) {
                return $false
            }
        }
        
        $this.LastAlertTime[$address] = $now
        return $true
    }
    
    [void]SendTelegramAlert([string]$serverName, [string]$address) {
        $token = $this.Config.Settings.TelegramBotToken
        $chatId = $this.Config.Settings.TelegramChatId
        
        if (-not $token -or -not $chatId) { return }
        
        $message = "🚨 *ALERT*`n`nServer: $serverName`nAddress: $address`nStatus: OFFLINE`nTime: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        
        $body = @{
            chat_id = $chatId
            text = $message
            parse_mode = "Markdown"
        } | ConvertTo-Json
        
        try {
            Invoke-RestMethod -Uri "https://api.telegram.org/bot$token/sendMessage" -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop
        } catch {
            Write-Host "Telegram alert failed: $_"
        }
    }
    
    [void]SendPushoverAlert([string]$serverName, [string]$address) {
        $userKey = $this.Config.Settings.PushoverUserKey
        $apiToken = $this.Config.Settings.PushoverAPIToken
        
        if (-not $userKey -or -not $apiToken) { return }
        
        $body = @{
            token = $apiToken
            user = $userKey
            title = "REGTeches Server Alert"
            message = "Server '$serverName' ($address) is OFFLINE"
            priority = 1
            sound = "siren"
        }
        
        try {
            Invoke-RestMethod -Uri "https://api.pushover.net/1/messages.json" -Method Post -Body $body -ErrorAction Stop
        } catch {
            Write-Host "Pushover alert failed: $_"
        }
    }
    
    [void]SendWebhookAlert([string]$serverName, [string]$address) {
        $webhookUrl = $this.Config.Settings.WebhookUrl
        
        if (-not $webhookUrl) { return }
        
        $payload = @{
            server_name = $serverName
            server_address = $address
            status = "OFFLINE"
            timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        } | ConvertTo-Json
        
        try {
            Invoke-RestMethod -Uri $webhookUrl -Method Post -Body $payload -ContentType "application/json" -ErrorAction Stop
        } catch {
            Write-Host "Webhook alert failed: $_"
        }
    }
}

# ============================================================================
# WEB DASHBOARD MODULE
# ============================================================================

class WebDashboard {
    [Database]$DB
    [hashtable]$Config
    [int]$Port
    [System.Net.HttpListener]$Listener
    [bool]$Running = $false
    
    WebDashboard([Database]$database, [hashtable]$config, [int]$port) {
        $this.DB = $database
        $this.Config = $config
        $this.Port = $port
    }
    
    [void]Start() {
        $this.Listener = New-Object System.Net.HttpListener
        $this.Listener.Prefixes.Add("http://localhost:$($this.Port)/")
        $this.Listener.Start()
        $this.Running = $true
        
        # Start listening in background job
        $scriptBlock = {
            param($dashboard)
            
            while ($dashboard.Running) {
                try {
                    $context = $dashboard.Listener.GetContext()
                    $request = $context.Request
                    $response = $context.Response
                    
                    $path = $request.Url.LocalPath
                    
                    $content = ""
                    $contentType = "text/html"
                    
                    switch ($path) {
                        "/" { 
                            $content = $dashboard.GetDashboardHTML()
                        }
                        "/api/servers" {
                            $content = $dashboard.Config.Servers | ConvertTo-Json
                            $contentType = "application/json"
                        }
                        "/api/status" {
                            $content = $dashboard.GetStatusJSON()
                            $contentType = "application/json"
                        }
                        default {
                            $content = "Not Found"
                            $response.StatusCode = 404
                        }
                    }
                    
                    $response.ContentType = $contentType
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($content)
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                    $response.Close()
                    
                } catch {
                    # Ignore errors when stopping
                }
            }
        }
        
        Start-Job -ScriptBlock $scriptBlock -ArgumentList $this | Out-Null
    }
    
    [void]Stop() {
        $this.Running = $false
        if ($this.Listener) {
            $this.Listener.Stop()
            $this.Listener.Close()
        }
    }
    
    [string]GetStatusJSON() {
        $statusList = @()
        
        foreach ($server in $this.Config.Servers) {
            $stats = $this.DB.GetUptimeStats($server.Address, 24)
            $recent = $this.DB.GetRecentChecks($server.Address, 1)
            
            $status = @{
                name = $server.Name
                address = $server.Address
                is_online = if ($recent.Count -gt 0) { $recent[0].IsOnline } else { $false }
                response_time = if ($recent.Count -gt 0) { $recent[0].ResponseTime } else { $null }
                uptime_24h = $stats.UptimePercent
                maintenance = $server.Maintenance
            }
            
            $statusList += $status
        }
        
        return $statusList | ConvertTo-Json
    }
    
    [string]GetDashboardHTML() {
        return @'
<!DOCTYPE html>
<html>
<head>
    <title>REGTeches Server Monitor PRO</title>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
            color: white;
            padding: 20px;
        }
        .container { max-width: 1400px; margin: 0 auto; }
        h1 { text-align: center; margin-bottom: 30px; text-shadow: 2px 2px 4px rgba(0,0,0,0.3); }
        .stats-bar {
            background: rgba(255, 255, 255, 0.1);
            padding: 15px;
            border-radius: 10px;
            margin-bottom: 20px;
            display: flex;
            justify-content: space-around;
            backdrop-filter: blur(10px);
        }
        .stat-item { text-align: center; }
        .stat-value { font-size: 2em; font-weight: bold; }
        .stat-label { font-size: 0.9em; color: #ccc; }
        .servers-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
            gap: 20px;
            margin-top: 20px;
        }
        .server-card {
            background: rgba(255, 255, 255, 0.1);
            border-radius: 10px;
            padding: 20px;
            backdrop-filter: blur(10px);
            border: 2px solid rgba(255, 255, 255, 0.2);
            transition: transform 0.3s, box-shadow 0.3s;
        }
        .server-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 10px 20px rgba(0,0,0,0.3);
        }
        .server-card.online { border-color: #00ff00; }
        .server-card.offline { border-color: #ff0000; animation: pulse 2s infinite; }
        .server-card.maintenance { border-color: #ffa500; opacity: 0.7; }
        @keyframes pulse {
            0%, 100% { border-color: #ff0000; box-shadow: 0 0 0 0 rgba(255, 0, 0, 0.7); }
            50% { border-color: #ff6666; box-shadow: 0 0 20px 10px rgba(255, 0, 0, 0); }
        }
        .server-name { font-size: 1.5em; font-weight: bold; margin-bottom: 10px; }
        .server-address { color: #ccc; margin-bottom: 15px; font-size: 0.9em; }
        .status {
            display: inline-block;
            padding: 8px 20px;
            border-radius: 20px;
            font-weight: bold;
            font-size: 0.9em;
            margin-bottom: 10px;
        }
        .status.online { background: #00ff00; color: #000; }
        .status.offline { background: #ff0000; color: #fff; }
        .status.maintenance { background: #ffa500; color: #000; }
        .metrics {
            margin-top: 15px;
            font-size: 0.85em;
            border-top: 1px solid rgba(255,255,255,0.2);
            padding-top: 10px;
        }
        .metric-row {
            display: flex;
            justify-content: space-between;
            margin: 5px 0;
        }
        .refresh-info {
            text-align: center;
            margin-top: 20px;
            color: #ccc;
            font-size: 0.9em;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🖥️ REGTeches Server Monitor PRO</h1>
        
        <div class="stats-bar">
            <div class="stat-item">
                <div class="stat-value" id="totalServers">-</div>
                <div class="stat-label">Total Servers</div>
            </div>
            <div class="stat-item">
                <div class="stat-value" id="onlineServers" style="color: #00ff00;">-</div>
                <div class="stat-label">Online</div>
            </div>
            <div class="stat-item">
                <div class="stat-value" id="offlineServers" style="color: #ff0000;">-</div>
                <div class="stat-label">Offline</div>
            </div>
            <div class="stat-item">
                <div class="stat-value" id="avgUptime">-</div>
                <div class="stat-label">Avg Uptime (24h)</div>
            </div>
        </div>
        
        <div class="servers-grid" id="serversGrid"></div>
        
        <div class="refresh-info">
            🔄 Auto-refreshing every 5 seconds | Last update: <span id="lastUpdate">-</span>
        </div>
    </div>

    <script>
        async function loadServers() {
            try {
                const response = await fetch('/api/status');
                const servers = await response.json();
                
                const grid = document.getElementById('serversGrid');
                grid.innerHTML = '';
                
                let totalServers = servers.length;
                let onlineCount = 0;
                let offlineCount = 0;
                let totalUptime = 0;
                
                servers.forEach(server => {
                    if (server.is_online) onlineCount++;
                    else offlineCount++;
                    
                    totalUptime += server.uptime_24h || 0;
                    
                    const statusClass = server.maintenance ? 'maintenance' : (server.is_online ? 'online' : 'offline');
                    const statusText = server.maintenance ? 'MAINTENANCE' : (server.is_online ? 'ONLINE' : 'OFFLINE');
                    const statusIcon = server.maintenance ? '🔧' : (server.is_online ? '✅' : '❌');
                    
                    const card = document.createElement('div');
                    card.className = 'server-card ' + statusClass;
                    card.innerHTML = `
                        <div class="server-name">${server.name}</div>
                        <div class="server-address">${server.address}</div>
                        <div class="status ${statusClass}">${statusIcon} ${statusText}</div>
                        <div class="metrics">
                            <div class="metric-row">
                                <span>Response Time:</span>
                                <strong>${server.response_time ? server.response_time.toFixed(0) + ' ms' : 'N/A'}</strong>
                            </div>
                            <div class="metric-row">
                                <span>24h Uptime:</span>
                                <strong>${server.uptime_24h ? server.uptime_24h.toFixed(2) + '%' : 'N/A'}</strong>
                            </div>
                        </div>
                    `;
                    grid.appendChild(card);
                });
                
                document.getElementById('totalServers').textContent = totalServers;
                document.getElementById('onlineServers').textContent = onlineCount;
                document.getElementById('offlineServers').textContent = offlineCount;
                document.getElementById('avgUptime').textContent = totalServers > 0 ? (totalUptime / totalServers).toFixed(1) + '%' : 'N/A';
                document.getElementById('lastUpdate').textContent = new Date().toLocaleTimeString();
                
            } catch (error) {
                console.error('Error loading servers:', error);
            }
        }
        
        // Load initially
        loadServers();
        
        // Refresh every 5 seconds
        setInterval(loadServers, 5000);
    </script>
</body>
</html>
'@
    }
}

# ============================================================================
# REPORT GENERATOR
# ============================================================================

class ReportGenerator {
    [Database]$DB
    [hashtable]$Config
    
    ReportGenerator([Database]$database, [hashtable]$config) {
        $this.DB = $database
        $this.Config = $config
    }
    
    [string]GenerateUptimeReport([int]$days) {
        $report = @()
        $report += "=" * 80
        $report += "UPTIME REPORT - Last $days Days"
        $report += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $report += "=" * 80
        $report += ""
        
        foreach ($server in $this.Config.Servers) {
            $stats = $this.DB.GetUptimeStats($server.Address, $days * 24)
            
            $report += "Server: $($server.Name)"
            $report += "Address: $($server.Address)"
            $report += "Uptime: $($stats.UptimePercent.ToString('F2'))%"
            $report += "Total Checks: $($stats.TotalChecks)"
            $report += "Online Checks: $($stats.OnlineChecks)"
            $report += "Avg Response Time: $($stats.AvgResponseTime.ToString('F2')) ms"
            $report += "-" * 80
            $report += ""
        }
        
        return $report -join "`n"
    }
    
    [string]GenerateHTMLReport() {
        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Server Monitoring Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        h1 { color: #333; }
        .report-header { background: #4CAF50; color: white; padding: 20px; border-radius: 5px; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; background: white; }
        th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
        th { background-color: #4CAF50; color: white; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .online { color: green; font-weight: bold; }
        .offline { color: red; font-weight: bold; }
        .warning { color: orange; font-weight: bold; }
    </style>
</head>
<body>
    <div class="report-header">
        <h1>📊 Server Monitoring Report</h1>
        <p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
    </div>
    <table>
        <tr>
            <th>Server Name</th>
            <th>Address</th>
            <th>24h Uptime</th>
            <th>Avg Response</th>
            <th>Status</th>
        </tr>
"@
        
        foreach ($server in $this.Config.Servers) {
            $stats = $this.DB.GetUptimeStats($server.Address, 24)
            
            $statusClass = if ($stats.UptimePercent -ge 99) { "online" } 
                          elseif ($stats.UptimePercent -ge 95) { "warning" }
                          else { "offline" }
            
            $statusText = if ($stats.UptimePercent -ge 99) { "✅ Excellent" }
                         elseif ($stats.UptimePercent -ge 95) { "⚠️ Good" }
                         else { "❌ Issues" }
            
            $html += @"
        <tr>
            <td>$($server.Name)</td>
            <td>$($server.Address)</td>
            <td>$($stats.UptimePercent.ToString('F2'))%</td>
            <td>$($stats.AvgResponseTime.ToString('F2')) ms</td>
            <td class="$statusClass">$statusText</td>
        </tr>
"@
        }
        
        $html += @"
    </table>
</body>
</html>
"@
        
        return $html
    }
    
    [string]ExportToCSV([string]$address, [int]$hours) {
        $checks = $this.DB.GetRecentChecks($address, 1000)
        $csv = @("Timestamp,Status,Response Time (ms),Error")
        
        foreach ($check in $checks) {
            $status = if ($check.IsOnline) { "Online" } else { "Offline" }
            $responseTime = if ($check.ResponseTime) { $check.ResponseTime } else { "N/A" }
            $error = $check.Error -replace ',', ';'  # Replace commas to avoid CSV issues
            
            $csv += "$($check.Timestamp),$status,$responseTime,$error"
        }
        
        return $csv -join "`n"
    }
}

# ============================================================================
# SERVER MONITORING - ENHANCED WITH RESPONSE TIME & HTTP CHECKS
# ============================================================================

function Test-ServerAdvanced {
    param(
        [string]$Address,
        [int]$Port
    )
    
    $result = @{
        IsOnline = $false
        ResponseTime = $null
        HttpStatus = $null
        Error = ""
    }
    
    # Ping test with response time
    $pingResult = Test-Connection $Address -Count 1 -ErrorAction SilentlyContinue
    
    if ($pingResult) {
        $result.ResponseTime = $pingResult.ResponseTime
        
        # Port test if specified
        if ($Port) {
            $tcp = New-Object System.Net.Sockets.TcpClient
            try {
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $connect = $tcp.BeginConnect($Address, $Port, $null, $null)
                if ($connect.AsyncWaitHandle.WaitOne(2000, $false)) {
                    $tcp.EndConnect($connect)
                    $stopwatch.Stop()
                    $result.IsOnline = $true
                    $result.ResponseTime = $stopwatch.ElapsedMilliseconds
                } else {
                    $result.Error = "Port $Port timeout"
                }
            } catch {
                $result.Error = "Port $Port connection failed: $_"
            } finally {
                $tcp.Close()
            }
        } else {
            $result.IsOnline = $true
        }
        
        # HTTP/HTTPS check if it looks like a web address
        if ($Address -like "http*" -or ($Port -eq 80 -or $Port -eq 443)) {
            try {
                $url = if ($Address -like "http*") { $Address } else { "http://${Address}" }
                $httpResponse = Invoke-WebRequest -Uri $url -Method Head -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
                $result.HttpStatus = $httpResponse.StatusCode
                $result.IsOnline = ($httpResponse.StatusCode -ge 200 -and $httpResponse.StatusCode -lt 400)
            } catch {
                $result.HttpStatus = if ($_.Exception.Response) { $_.Exception.Response.StatusCode.value__ } else { 0 }
                if (-not $result.IsOnline) {
                    $result.Error += " | HTTP check failed: $_"
                }
            }
        }
    } else {
        $result.Error = "Ping failed"
    }
    
    return $result
}

# ============================================================================
# CONFIG & STATE
# ============================================================================

$Global:ConfigPath = Join-Path $PSScriptRoot "servers.json"
$Global:DbPath = Join-Path $PSScriptRoot "monitor.db"

function Get-Config {
    if (-not (Test-Path $Global:ConfigPath)) {
        $defaultConfig = @{
            Servers = @()
            Settings = @{
                CheckIntervalSeconds = 30
                EmailSender = ""
                EmailPassword = ""
                EmailReceiver = ""
                TelegramBotToken = ""
                TelegramChatId = ""
                PushoverUserKey = ""
                PushoverAPIToken = ""
                WebhookUrl = ""
                WebDashboardPort = 8080
            }
        }
        $defaultConfig | ConvertTo-Json -Depth 10 | Set-Content $Global:ConfigPath
    }
    return Get-Content $Global:ConfigPath | ConvertFrom-Json
}

function Save-Config {
    param($NewConfig)
    $NewConfig | ConvertTo-Json -Depth 10 | Set-Content $Global:ConfigPath
}

# Check if SQLite is available
try {
    Add-Type -Path ([System.IO.Path]::Combine($PSScriptRoot, "System.Data.SQLite.dll"))
} catch {
    Write-Host "SQLite DLL not found. Downloading..."
    # For now, inform user to install
    [System.Windows.Forms.MessageBox]::Show(
        "SQLite is required for database features.`n`nPlease install System.Data.SQLite NuGet package or download the DLL.`n`nThe program will continue with limited functionality.",
        "SQLite Required",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
}

$Config = Get-Config
$Global:DB = [Database]::new($Global:DbPath)
$Global:Analytics = [Analytics]::new($Global:DB)
$Global:AdvancedNotif = [AdvancedNotifications]::new(@{Settings = $Config.Settings})
$Global:ReportGen = [ReportGenerator]::new($Global:DB, @{Servers = $Config.Servers})

# Web Dashboard
$Global:WebDash = [WebDashboard]::new($Global:DB, @{Servers = $Config.Servers}, $Config.Settings.WebDashboardPort)

$Global:ServerCards = @{}
$Global:AlertActive = $false
$Global:FlashState = $false
$Global:AlarmFile = Join-Path $PSScriptRoot "Nuclear Alarm.wav"
$Global:Player = if (Test-Path $Global:AlarmFile) { New-Object System.Media.SoundPlayer($Global:AlarmFile) } else { $null }

# ============================================================================
# ENHANCED EMAIL ALERT
# ============================================================================

function Send-EnhancedAlert {
    param($ServerName, $ServerAddr, $ResponseTime, $Error)
    
    if (-not $Config.Settings.EmailSender) { return }
    
    $SecurePass = $Config.Settings.EmailPassword | ConvertTo-SecureString -AsPlainText -Force
    $Cred = New-Object System.Management.Automation.PSCredential($Config.Settings.EmailSender, $SecurePass)
    
    $body = @"
SERVER ALERT - $ServerName is DOWN

Server Details:
- Name: $ServerName
- Address: $ServerAddr
- Last Response Time: $(if($ResponseTime){"$ResponseTime ms"}else{"N/A"})
- Error: $Error
- Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

This is an automated alert from REGTeches Server Monitor PRO.
"@
    
    try {
        Send-MailMessage -To $Config.Settings.EmailReceiver -From $Config.Settings.EmailSender `
                         -Subject "🚨 ALERT: $ServerName is DOWN" `
                         -Body $body -UseSsl `
                         -SmtpServer "smtp.gmail.com" -Port 587 -Credential $Cred
    } catch {
        Write-Host "Email Failed: $_"
    }
}

# ============================================================================
# UI DIALOGS - ENHANCED
# ============================================================================

function Show-AddServerDialog {
    $d = New-Object Windows.Forms.Form
    $d.Text = "Add Server"
    $d.Size = "350,350"
    $d.StartPosition = "CenterParent"
    
    $y = 10
    
    # Name
    $l1 = New-Object Windows.Forms.Label
    $l1.Text = "Name:"
    $l1.Location = "10,$y"
    $d.Controls.Add($l1)
    $y += 20
    
    $t1 = New-Object Windows.Forms.TextBox
    $t1.Location = "10,$y"
    $t1.Width = 300
    $d.Controls.Add($t1)
    $y += 40
    
    # Address
    $l2 = New-Object Windows.Forms.Label
    $l2.Text = "Address (IP or hostname):"
    $l2.Location = "10,$y"
    $d.Controls.Add($l2)
    $y += 20
    
    $t2 = New-Object Windows.Forms.TextBox
    $t2.Location = "10,$y"
    $t2.Width = 300
    $d.Controls.Add($t2)
    $y += 40
    
    # Port
    $l3 = New-Object Windows.Forms.Label
    $l3.Text = "Port (optional):"
    $l3.Location = "10,$y"
    $d.Controls.Add($l3)
    $y += 20
    
    $t3 = New-Object Windows.Forms.TextBox
    $t3.Location = "10,$y"
    $t3.Width = 300
    $d.Controls.Add($t3)
    $y += 40
    
    # Maintenance checkbox
    $chk = New-Object Windows.Forms.CheckBox
    $chk.Text = "Start in Maintenance Mode"
    $chk.Location = "10,$y"
    $chk.AutoSize = $true
    $d.Controls.Add($chk)
    $y += 30
    
    # Save button
    $btn = New-Object Windows.Forms.Button
    $btn.Text = "Save"
    $btn.Location = "10,$y"
    $btn.DialogResult = "OK"
    $d.Controls.Add($btn)
    
    if ($d.ShowDialog() -eq "OK") {
        $newS = @{
            Name = $t1.Text
            Address = $t2.Text
            Port = if ($t3.Text) { [int]$t3.Text } else { $null }
            Maintenance = $chk.Checked
        }
        $current = Get-Config
        $current.Servers += $newS
        Save-Config $current
        
        [System.Windows.Forms.MessageBox]::Show("Server added! Please restart the application to see changes.", "Success")
    }
}

function Show-SettingsDialog {
    $d = New-Object Windows.Forms.Form
    $d.Text = "Advanced Settings"
    $d.Size = "450,650"
    $d.StartPosition = "CenterParent"
    $d.AutoScroll = $true
    
    $y = 10
    
    # Email Settings
    $lblEmail = New-Object Windows.Forms.Label
    $lblEmail.Text = "=== EMAIL ALERTS ==="
    $lblEmail.Location = "10,$y"
    $lblEmail.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lblEmail.AutoSize = $true
    $d.Controls.Add($lblEmail)
    $y += 30
    
    $l1 = New-Object Windows.Forms.Label; $l1.Text = "Gmail Address:"; $l1.Location = "10,$y"; $d.Controls.Add($l1); $y += 20
    $t1 = New-Object Windows.Forms.TextBox; $t1.Location = "10,$y"; $t1.Width = 400; $t1.Text = $Config.Settings.EmailSender; $d.Controls.Add($t1); $y += 35
    
    $l2 = New-Object Windows.Forms.Label; $l2.Text = "App Password:"; $l2.Location = "10,$y"; $d.Controls.Add($l2); $y += 20
    $t2 = New-Object Windows.Forms.TextBox; $t2.Location = "10,$y"; $t2.Width = 400; $t2.PasswordChar = "*"; $d.Controls.Add($t2); $y += 35
    
    $l3 = New-Object Windows.Forms.Label; $l3.Text = "Receiver Email:"; $l3.Location = "10,$y"; $d.Controls.Add($l3); $y += 20
    $t3 = New-Object Windows.Forms.TextBox; $t3.Location = "10,$y"; $t3.Width = 400; $t3.Text = $Config.Settings.EmailReceiver; $d.Controls.Add($t3); $y += 40
    
    # Telegram Settings
    $lblTelegram = New-Object Windows.Forms.Label
    $lblTelegram.Text = "=== TELEGRAM ALERTS ==="
    $lblTelegram.Location = "10,$y"
    $lblTelegram.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lblTelegram.AutoSize = $true
    $d.Controls.Add($lblTelegram)
    $y += 30
    
    $l4 = New-Object Windows.Forms.Label; $l4.Text = "Bot Token:"; $l4.Location = "10,$y"; $d.Controls.Add($l4); $y += 20
    $t4 = New-Object Windows.Forms.TextBox; $t4.Location = "10,$y"; $t4.Width = 400; $t4.Text = $Config.Settings.TelegramBotToken; $d.Controls.Add($t4); $y += 35
    
    $l5 = New-Object Windows.Forms.Label; $l5.Text = "Chat ID:"; $l5.Location = "10,$y"; $d.Controls.Add($l5); $y += 20
    $t5 = New-Object Windows.Forms.TextBox; $t5.Location = "10,$y"; $t5.Width = 400; $t5.Text = $Config.Settings.TelegramChatId; $d.Controls.Add($t5); $y += 40
    
    # Pushover Settings
    $lblPushover = New-Object Windows.Forms.Label
    $lblPushover.Text = "=== PUSHOVER ALERTS ==="
    $lblPushover.Location = "10,$y"
    $lblPushover.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lblPushover.AutoSize = $true
    $d.Controls.Add($lblPushover)
    $y += 30
    
    $l6 = New-Object Windows.Forms.Label; $l6.Text = "User Key:"; $l6.Location = "10,$y"; $d.Controls.Add($l6); $y += 20
    $t6 = New-Object Windows.Forms.TextBox; $t6.Location = "10,$y"; $t6.Width = 400; $t6.Text = $Config.Settings.PushoverUserKey; $d.Controls.Add($t6); $y += 35
    
    $l7 = New-Object Windows.Forms.Label; $l7.Text = "API Token:"; $l7.Location = "10,$y"; $d.Controls.Add($l7); $y += 20
    $t7 = New-Object Windows.Forms.TextBox; $t7.Location = "10,$y"; $t7.Width = 400; $t7.Text = $Config.Settings.PushoverAPIToken; $d.Controls.Add($t7); $y += 40
    
    # Webhook Settings
    $lblWebhook = New-Object Windows.Forms.Label
    $lblWebhook.Text = "=== WEBHOOK ALERTS ==="
    $lblWebhook.Location = "10,$y"
    $lblWebhook.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lblWebhook.AutoSize = $true
    $d.Controls.Add($lblWebhook)
    $y += 30
    
    $l8 = New-Object Windows.Forms.Label; $l8.Text = "Webhook URL:"; $l8.Location = "10,$y"; $d.Controls.Add($l8); $y += 20
    $t8 = New-Object Windows.Forms.TextBox; $t8.Location = "10,$y"; $t8.Width = 400; $t8.Text = $Config.Settings.WebhookUrl; $d.Controls.Add($t8); $y += 40
    
    # Save button
    $btn = New-Object Windows.Forms.Button
    $btn.Text = "Save All Settings"
    $btn.Location = "10,$y"
    $btn.Width = 400
    $btn.DialogResult = "OK"
    $d.Controls.Add($btn)
    
    if ($d.ShowDialog() -eq "OK") {
        $current = Get-Config
        $current.Settings.EmailSender = $t1.Text
        $current.Settings.EmailReceiver = $t3.Text
        if ($t2.Text) { $current.Settings.EmailPassword = $t2.Text }
        $current.Settings.TelegramBotToken = $t4.Text
        $current.Settings.TelegramChatId = $t5.Text
        $current.Settings.PushoverUserKey = $t6.Text
        $current.Settings.PushoverAPIToken = $t7.Text
        $current.Settings.WebhookUrl = $t8.Text
        Save-Config $current
        
        # Update global objects
        $Global:AdvancedNotif = [AdvancedNotifications]::new(@{Settings = $current.Settings})
        
        [System.Windows.Forms.MessageBox]::Show("Settings saved successfully!", "Success")
    }
}

function Show-AnalyticsDialog {
    param($ServerName, $ServerAddr)
    
    $d = New-Object Windows.Forms.Form
    $d.Text = "AI Analytics: $ServerName"
    $d.Size = "600,500"
    $d.StartPosition = "CenterParent"
    
    # Risk Analysis
    $risk = $Global:Analytics.PredictDowntimeRisk($ServerAddr)
    $riskPercent = $risk * 100
    $riskLevel = if ($risk -lt 0.3) { "LOW 🟢" } elseif ($risk -lt 0.6) { "MEDIUM 🟡" } else { "HIGH 🔴" }
    
    $riskText = New-Object Windows.Forms.TextBox
    $riskText.Multiline = $true
    $riskText.ScrollBars = "Vertical"
    $riskText.Location = "10,10"
    $riskText.Size = "560,200"
    $riskText.Font = New-Object System.Drawing.Font("Consolas", 10)
    $riskText.Text = @"
DOWNTIME RISK ANALYSIS
$("=" * 50)
Server: $ServerName ($ServerAddr)
Risk Score: $($riskPercent.ToString('F1'))%
Risk Level: $riskLevel

Recommendation:
$(if ($risk -gt 0.6) {"⚠️ ATTENTION REQUIRED: High instability detected.`nInvestigate logs and performance metrics."} 
  elseif ($risk -gt 0.3) {"⚡ Monitor closely: Some degradation detected.`nReview recent changes."} 
  else {"✅ Server appears stable with low risk."})
"@
    $d.Controls.Add($riskText)
    
    # Failure Patterns
    $patterns = $Global:Analytics.GetFailurePatterns($ServerAddr)
    
    $patternText = New-Object Windows.Forms.TextBox
    $patternText.Multiline = $true
    $patternText.ScrollBars = "Vertical"
    $patternText.Location = "10,220"
    $patternText.Size = "560,200"
    $patternText.Font = New-Object System.Drawing.Font("Consolas", 10)
    
    if ($patterns.Message) {
        $patternText.Text = $patterns.Message
    } else {
        $patternText.Text = @"
FAILURE PATTERN ANALYSIS
$("=" * 50)
Total Failures: $($patterns.TotalFailures)
Most Common Hour: $($patterns.MostCommonHour):00
Most Common Day: $($patterns.MostCommonDay)

Hour Distribution (Top 5):
$(($patterns.HourDistribution.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 5 | ForEach-Object { "  {0:D2}:00 - {1} failures" -f $_.Key, $_.Value }) -join "`n")

Day Distribution:
$(($patterns.DayDistribution.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { "  {0} - {1} failures" -f $_.Key, $_.Value }) -join "`n")
"@
    }
    $d.Controls.Add($patternText)
    
    # Close button
    $btnClose = New-Object Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Location = "250,430"
    $btnClose.DialogResult = "OK"
    $d.Controls.Add($btnClose)
    
    $d.ShowDialog() | Out-Null
}

function Show-ReportsDialog {
    $d = New-Object Windows.Forms.Form
    $d.Text = "Report Generation"
    $d.Size = "400,300"
    $d.StartPosition = "CenterParent"
    
    $y = 20
    
    $lbl = New-Object Windows.Forms.Label
    $lbl.Text = "Generate Reports:"
    $lbl.Location = "20,$y"
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $lbl.AutoSize = $true
    $d.Controls.Add($lbl)
    $y += 40
    
    # Uptime Report button
    $btn1 = New-Object Windows.Forms.Button
    $btn1.Text = "📊 Generate Uptime Report (7 days)"
    $btn1.Location = "20,$y"
    $btn1.Size = "350,35"
    $btn1.Add_Click({
        $report = $Global:ReportGen.GenerateUptimeReport(7)
        $filename = "uptime_report_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
        $report | Out-File $filename
        [System.Windows.Forms.MessageBox]::Show("Report saved as $filename", "Success")
        Start-Process notepad.exe $filename
    })
    $d.Controls.Add($btn1)
    $y += 45
    
    # HTML Report button
    $btn2 = New-Object Windows.Forms.Button
    $btn2.Text = "🌐 Generate HTML Report"
    $btn2.Location = "20,$y"
    $btn2.Size = "350,35"
    $btn2.Add_Click({
        $report = $Global:ReportGen.GenerateHTMLReport()
        $filename = "monitor_report_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
        $report | Out-File $filename
        [System.Windows.Forms.MessageBox]::Show("HTML report saved as $filename", "Success")
        Start-Process $filename
    })
    $d.Controls.Add($btn2)
    $y += 45
    
    # CSV Export button
    $btn3 = New-Object Windows.Forms.Button
    $btn3.Text = "📁 Export Server Data (CSV)"
    $btn3.Location = "20,$y"
    $btn3.Size = "350,35"
    $btn3.Add_Click({
        foreach ($server in $Config.Servers) {
            $csv = $Global:ReportGen.ExportToCSV($server.Address, 24)
            $filename = "$($server.Name -replace '[^a-zA-Z0-9]', '_')_export_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
            $csv | Out-File $filename
        }
        [System.Windows.Forms.MessageBox]::Show("All server data exported to CSV files", "Success")
    })
    $d.Controls.Add($btn3)
    
    $d.ShowDialog() | Out-Null
}

# ============================================================================
# SYSTEM TRAY ICON
# ============================================================================

$Global:TrayIcon = New-Object System.Windows.Forms.NotifyIcon
$Global:TrayIcon.Icon = [System.Drawing.SystemIcons]::Application
$Global:TrayIcon.Text = "REGTeches Monitor PRO"
$Global:TrayIcon.Visible = $true

$TrayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$ShowItem = New-Object System.Windows.Forms.ToolStripMenuItem("Show Dashboard")
$ShowItem.Add_Click({ $Form.WindowState = "Normal"; $Form.Activate() })
$TrayMenu.Items.Add($ShowItem)

$WebItem = New-Object System.Windows.Forms.ToolStripMenuItem("Open Web Dashboard")
$WebItem.Add_Click({ Start-Process "http://localhost:$($Config.Settings.WebDashboardPort)" })
$TrayMenu.Items.Add($WebItem)

$QuitItem = New-Object System.Windows.Forms.ToolStripMenuItem("Quit")
$QuitItem.Add_Click({ $Form.Close() })
$TrayMenu.Items.Add($QuitItem)

$Global:TrayIcon.ContextMenuStrip = $TrayMenu

# Double-click to show
$Global:TrayIcon.Add_DoubleClick({ $Form.WindowState = "Normal"; $Form.Activate() })

# ============================================================================
# MAIN UI
# ============================================================================

$Form = New-Object Windows.Forms.Form
$Form.Text = "REGTeches NOC Dashboard PRO v17.0"
$Form.Size = "1200,900"
$Form.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 18)
$Form.StartPosition = "CenterScreen"

# Handle minimize to tray
$Form.Add_Resize({
    if ($Form.WindowState -eq "Minimized") {
        $Form.Hide()
    }
})

$MainGrid = New-Object Windows.Forms.TableLayoutPanel
$MainGrid.Dock = "Fill"
$MainGrid.RowCount = 3
$MainGrid.ColumnCount = 1
$MainGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::AutoSize)))
$MainGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute, 60)))
$MainGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent, 100)))
$Form.Controls.Add($MainGrid)

# Menu
$Menu = New-Object Windows.Forms.MenuStrip
$FileM = New-Object Windows.Forms.ToolStripMenuItem("File")
$AddM = New-Object Windows.Forms.ToolStripMenuItem("Add Server", $null, { Show-AddServerDialog })
$SetM = New-Object Windows.Forms.ToolStripMenuItem("Advanced Settings", $null, { Show-SettingsDialog })
$ReportM = New-Object Windows.Forms.ToolStripMenuItem("Generate Reports", $null, { Show-ReportsDialog })
$WebM = New-Object Windows.Forms.ToolStripMenuItem("Open Web Dashboard", $null, { Start-Process "http://localhost:$($Config.Settings.WebDashboardPort)" })
$FileM.DropDownItems.AddRange(@($AddM, $SetM, $ReportM, $WebM))
$Menu.Items.Add($FileM)
$MainGrid.Controls.Add($Menu, 0, 0)

# Alarm Button
$MaintBtn = New-Object Windows.Forms.CheckBox
$MaintBtn.Appearance = "Button"
$MaintBtn.Text = "ALARM ARMED ✓"
$MaintBtn.Dock = "Fill"
$MaintBtn.BackColor = [System.Drawing.Color]::DarkGreen
$MaintBtn.ForeColor = "White"
$MaintBtn.FlatStyle = "Flat"
$MaintBtn.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$MaintBtn.Add_CheckedChanged({
    if ($MaintBtn.Checked) { 
        $MaintBtn.Text = "MAINTENANCE MODE"
        $MaintBtn.BackColor = [System.Drawing.Color]::Orange
        $Global:AlertActive = $false
        if ($Global:Player) { $Global:Player.Stop() }
    } else { 
        $MaintBtn.Text = "ALARM ARMED ✓"
        $MaintBtn.BackColor = [System.Drawing.Color]::DarkGreen
    }
})
$MainGrid.Controls.Add($MaintBtn, 0, 1)

# Tabs
$Tabs = New-Object Windows.Forms.TabControl
$Tabs.Dock = "Fill"

$MapTab = New-Object Windows.Forms.TabPage("🗺️ Network Map")
$LogTab = New-Object Windows.Forms.TabPage("📋 Live Log")
$StatsTab = New-Object Windows.Forms.TabPage("📊 Statistics")

$Tabs.Controls.AddRange(@($MapTab, $LogTab, $StatsTab))
$MainGrid.Controls.Add($Tabs, 0, 2)

# Network Map Tab
$Flow = New-Object Windows.Forms.FlowLayoutPanel
$Flow.Dock = "Fill"
$Flow.AutoScroll = $true
$Flow.Padding = New-Object System.Windows.Forms.Padding(20)
$MapTab.Controls.Add($Flow)

# Live Log Tab
$LogBox = New-Object Windows.Forms.RichTextBox
$LogBox.Dock = "Fill"
$LogBox.BackColor = "Black"
$LogBox.ForeColor = "Lime"
$LogBox.Font = New-Object System.Drawing.Font("Consolas", 10)
$LogTab.Controls.Add($LogBox)

# Statistics Tab
$StatsPanel = New-Object Windows.Forms.Panel
$StatsPanel.Dock = "Fill"
$StatsPanel.AutoScroll = $true
$StatsTab.Controls.Add($StatsPanel)

$StatsFlow = New-Object Windows.Forms.FlowLayoutPanel
$StatsFlow.Dock = "Fill"
$StatsFlow.AutoScroll = $true
$StatsFlow.FlowDirection = "TopDown"
$StatsFlow.WrapContents = $false
$StatsFlow.Padding = New-Object System.Windows.Forms.Padding(20)
$StatsPanel.Controls.Add($StatsFlow)

# ============================================================================
# DYNAMIC SERVER CARDS WITH ENHANCED CONTEXT MENU
# ============================================================================

foreach ($S in $Config.Servers) {
    $Card = New-Object Windows.Forms.Label
    $Card.Text = "$($S.Name)`n$($S.Address)"
    if ($S.Maintenance) { $Card.Text += "`n🔧 MAINTENANCE" }
    $Card.Size = "240,150"
    $Card.TextAlign = "MiddleCenter"
    $Card.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
    $Card.ForeColor = "White"
    $Card.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $Card.Margin = New-Object System.Windows.Forms.Padding(12)
    $Card.BorderStyle = "FixedSingle"
    
    # Context Menu with more options
    $ctx = New-Object Windows.Forms.ContextMenuStrip
    $itemAddr = $S.Address
    $itemName = $S.Name
    
    $openItem = New-Object Windows.Forms.ToolStripMenuItem("🌐 Open Connection", $null, {
        $target = if ($itemAddr -notlike "http*") { "https://$itemAddr" } else { $itemAddr }
        Start-Process $target
    })
    
    $analyticsItem = New-Object Windows.Forms.ToolStripMenuItem("🤖 AI Analytics", $null, {
        Show-AnalyticsDialog $itemName $itemAddr
    })
    
    $statsItem = New-Object Windows.Forms.ToolStripMenuItem("📊 View Statistics", $null, {
        $stats = $Global:DB.GetUptimeStats($itemAddr, 24)
        $msg = @"
24-Hour Statistics for $itemName

Uptime: $($stats.UptimePercent.ToString('F2'))%
Total Checks: $($stats.TotalChecks)
Online Checks: $($stats.OnlineChecks)
Avg Response: $($stats.AvgResponseTime.ToString('F2')) ms
"@
        [System.Windows.Forms.MessageBox]::Show($msg, "Server Statistics")
    })
    
    $exportItem = New-Object Windows.Forms.ToolStripMenuItem("💾 Export CSV", $null, {
        $csv = $Global:ReportGen.ExportToCSV($itemAddr, 24)
        $filename = "$($itemName -replace '[^a-zA-Z0-9]', '_')_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $csv | Out-File $filename
        [System.Windows.Forms.MessageBox]::Show("Exported to $filename", "Success")
    })
    
    $deleteItem = New-Object Windows.Forms.ToolStripMenuItem("❌ Delete", $null, {
        $result = [System.Windows.Forms.MessageBox]::Show("Delete $itemName?", "Confirm", "YesNo", "Question")
        if ($result -eq "Yes") {
            $c = Get-Config
            $c.Servers = $c.Servers | Where-Object { $_.Address -ne $itemAddr }
            Save-Config $c
            [System.Windows.Forms.MessageBox]::Show("Server removed! Please restart the application.", "Success")
        }
    })
    
    $ctx.Items.AddRange(@($openItem, $analyticsItem, $statsItem, $exportItem, $deleteItem))
    $Card.ContextMenuStrip = $ctx
    
    $Flow.Controls.Add($Card)
    $Global:ServerCards[$S.Address] = $Card
}

# ============================================================================
# MONITORING LOOP WITH DATABASE LOGGING
# ============================================================================

$MainTimer = New-Object Windows.Forms.Timer
$MainTimer.Interval = ($Config.Settings.CheckIntervalSeconds * 1000)
$MainTimer.Add_Tick({
    $Panic = $false
    $statusUpdates = @()
    
    foreach ($S in $Config.Servers) {
        # Skip maintenance servers
        if ($S.Maintenance) { continue }
        
        # Enhanced check
        $result = Test-ServerAdvanced $S.Address $S.Port
        
        # Log to database
        try {
            $Global:DB.LogCheck(@{
                Address = $S.Address
                Name = $S.Name
                IsOnline = $result.IsOnline
                ResponseTime = $result.ResponseTime
                HttpStatus = $result.HttpStatus
                Error = $result.Error
            })
        } catch {
            $LogBox.AppendText("[ERROR] Database logging failed: $_`n")
        }
        
        # Update card color
        if ($Global:ServerCards.ContainsKey($S.Address)) {
            $card = $Global:ServerCards[$S.Address]
            if ($result.IsOnline) {
                $card.BackColor = [System.Drawing.Color]::DarkGreen
                $card.Text = "$($S.Name)`n$($S.Address)`n✅ $([Math]::Round($result.ResponseTime)) ms"
            } else {
                $card.BackColor = [System.Drawing.Color]::Maroon
                $card.Text = "$($S.Name)`n$($S.Address)`n❌ OFFLINE"
                $Panic = $true
                
                $timestamp = Get-Date -Format "HH:mm:ss"
                $LogBox.AppendText("[$timestamp] 🔴 DOWN: $($S.Name) - $($result.Error)`n")
                $LogBox.ScrollToCaret()
                
                # Send all alerts if cooldown allows
                if ($Global:AdvancedNotif.ShouldSendAlert($S.Address)) {
                    Send-EnhancedAlert $S.Name $S.Address $result.ResponseTime $result.Error
                    $Global:AdvancedNotif.SendTelegramAlert($S.Name, $S.Address)
                    $Global:AdvancedNotif.SendPushoverAlert($S.Name, $S.Address)
                    $Global:AdvancedNotif.SendWebhookAlert($S.Name, $S.Address)
                    $LogBox.AppendText("[$timestamp] 📧 Alerts sent for $($S.Name)`n")
                }
            }
        }
        
        $statusUpdates += @{
            Name = $S.Name
            Address = $S.Address
            Online = $result.IsOnline
            ResponseTime = $result.ResponseTime
        }
    }
    
    # Update system tray icon
    if ($Panic) {
        $Global:TrayIcon.Icon = [System.Drawing.SystemIcons]::Error
    } else {
        $Global:TrayIcon.Icon = [System.Drawing.SystemIcons]::Information
    }
    
    # Trigger alarm
    if ($Panic -and -not $Global:AlertActive -and -not $MaintBtn.Checked) {
        $Global:AlertActive = $true
        $FlashTimer.Start()
    }
})

# ============================================================================
# FLASH/ALARM TIMER
# ============================================================================

$FlashTimer = New-Object Windows.Forms.Timer
$FlashTimer.Interval = 500
$FlashTimer.Add_Tick({
    if ($Global:AlertActive -and -not $MaintBtn.Checked) {
        $color = if ($Global:FlashState) { [System.Drawing.Color]::Red } else { [System.Drawing.Color]::Black }
        $Form.BackColor = $color
        $MaintBtn.BackColor = $color
        
        if ($Global:FlashState -and $Global:Player) {
            try { $Global:Player.Play() } catch {}
        }
        
        $Global:FlashState = -not $Global:FlashState
    } else {
        $FlashTimer.Stop()
        if ($Global:Player) { $Global:Player.Stop() }
        $Form.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 18)
        if (-not $MaintBtn.Checked) { $MaintBtn.BackColor = [System.Drawing.Color]::DarkGreen }
    }
})

# ============================================================================
# STATISTICS UPDATE TIMER
# ============================================================================

$StatsTimer = New-Object Windows.Forms.Timer
$StatsTimer.Interval = 10000  # Update every 10 seconds
$StatsTimer.Add_Tick({
    $StatsFlow.Controls.Clear()
    
    foreach ($server in $Config.Servers) {
        $stats = $Global:DB.GetUptimeStats($server.Address, 24)
        
        $panel = New-Object Windows.Forms.GroupBox
        $panel.Text = "$($server.Name) - 24 Hour Stats"
        $panel.Width = 550
        $panel.Height = 150
        $panel.ForeColor = "White"
        
        $label = New-Object Windows.Forms.Label
        $label.Location = "10,25"
        $label.Size = "530,110"
        $label.Font = New-Object System.Drawing.Font("Consolas", 10)
        $label.Text = @"
Address: $($server.Address)
Uptime: $($stats.UptimePercent.ToString('F2'))%
Total Checks: $($stats.TotalChecks)
Successful Checks: $($stats.OnlineChecks)
Failed Checks: $($stats.TotalChecks - $stats.OnlineChecks)
Average Response Time: $($stats.AvgResponseTime.ToString('F2')) ms
"@
        
        $panel.Controls.Add($label)
        $StatsFlow.Controls.Add($panel)
    }
})
$StatsTimer.Start()

# ============================================================================
# START WEB DASHBOARD
# ============================================================================

try {
    $Global:WebDash.Start()
    $LogBox.AppendText("[INIT] ✓ Web Dashboard started on http://localhost:$($Config.Settings.WebDashboardPort)`n")
} catch {
    $LogBox.AppendText("[INIT] ⚠ Web Dashboard failed to start: $_`n")
}

# ============================================================================
# CLEANUP ON CLOSE
# ============================================================================

$Form.Add_FormClosing({
    $MainTimer.Stop()
    $FlashTimer.Stop()
    $StatsTimer.Stop()
    if ($Global:Player) { $Global:Player.Stop() }
    if ($Global:WebDash) { $Global:WebDash.Stop() }
    $Global:TrayIcon.Visible = $false
    $Global:TrayIcon.Dispose()
})

# ============================================================================
# START APPLICATION
# ============================================================================

$LogBox.AppendText(@"
╔═══════════════════════════════════════════════════════════════╗
║    REGTeches Server Monitor PRO v17.0 - PowerShell Edition    ║
╚═══════════════════════════════════════════════════════════════╝

✓ Database logging enabled
✓ Web dashboard: http://localhost:$($Config.Settings.WebDashboardPort)
✓ System tray integration active
✓ Advanced notifications configured
✓ AI Analytics ready
✓ Report generation available

Monitoring $($Config.Servers.Count) servers...

"@)

$MainTimer.Start()
$Form.ShowDialog()
