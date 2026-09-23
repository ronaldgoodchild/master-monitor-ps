#Requires -Version 5.1
<#
.SYNOPSIS
    REGTeches NOC Dashboard - Simplified Edition
    
.DESCRIPTION
    Real-time server monitoring with visual alarms and multiple notification channels.
    No database dependencies - works immediately on any Windows system.
    
.NOTES
    Author: REGTeches
    Version: 17.1 Simple
    Features: Real-time monitoring, Multi-channel alerts, System tray, Visual/Audio alarms
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ============================================================================
# CONFIGURATION
# ============================================================================

$Global:ConfigPath = Join-Path $PSScriptRoot "servers.json"

function Get-Config {
    if (-not (Test-Path $Global:ConfigPath)) {
        $defaultConfig = @{
            Servers = @(
                @{
                    Name = "Google DNS"
                    Address = "8.8.8.8"
                    Port = $null
                    Maintenance = $false
                }
                @{
                    Name = "Cloudflare DNS"
                    Address = "1.1.1.1"
                    Port = $null
                    Maintenance = $false
                }
            )
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

$Config = Get-Config

# ============================================================================
# STATE VARIABLES
# ============================================================================

$Global:ServerCards = @{}
$Global:AlertActive = $false
$Global:FlashState = $false
$Global:LastAlertTime = @{}
$Global:AlertCooldownMinutes = 15
$Global:AlarmFile = Join-Path $PSScriptRoot "Nuclear Alarm.wav"
$Global:Player = if (Test-Path $Global:AlarmFile) { 
    New-Object System.Media.SoundPlayer($Global:AlarmFile) 
} else { 
    $null 
}

# ============================================================================
# ENHANCED SERVER CHECK
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
    
    # Ping test (a URL is reduced to its host name). ICMP being blocked is not fatal when a
    # port or HTTP check can still decide whether the service is up.
    $pingHost = if ($Address -like "http*") { try { ([Uri]$Address).Host } catch { $Address } } else { $Address }
    $pingResult = $null
    try { $pingResult = Test-Connection $pingHost -Count 1 -ErrorAction Stop } catch { $result.Error = "Ping failed: $_" }
    try {
        if ($pingResult -or $Port -or $Address -like "http*") {
            if ($pingResult) { $result.ResponseTime = $pingResult.ResponseTime }
            
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
            } elseif ($pingResult) {
                $result.IsOnline = $true
            }
            
            # HTTP/HTTPS check if applicable
            if ($Address -like "http*" -or ($Port -eq 80 -or $Port -eq 443)) {
                try {
                    $url = if ($Address -like "http*") { $Address } else { "http://${Address}" }
                    $httpResponse = Invoke-WebRequest -Uri $url -Method Head -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
                    $result.HttpStatus = $httpResponse.StatusCode
                    $result.IsOnline = ($httpResponse.StatusCode -ge 200 -and $httpResponse.StatusCode -lt 400)
                } catch {
                    $result.HttpStatus = if ($_.Exception.Response) { $_.Exception.Response.StatusCode.value__ } else { 0 }
                    if (-not $result.IsOnline) {
                        $result.Error += " | HTTP check failed"
                    }
                }
            }
        }
    } catch {
        $result.Error = "Ping failed: $_"
    }
    
    return $result
}

# ============================================================================
# NOTIFICATION FUNCTIONS
# ============================================================================

function Should-SendAlert {
    param([string]$Address)
    
    $now = Get-Date
    
    if ($Global:LastAlertTime.ContainsKey($Address)) {
        $elapsed = ($now - $Global:LastAlertTime[$Address]).TotalMinutes
        if ($elapsed -lt $Global:AlertCooldownMinutes) {
            return $false
        }
    }
    
    $Global:LastAlertTime[$Address] = $now
    return $true
}

function Send-EmailAlert {
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

This is an automated alert from REGTeches Server Monitor.
"@
    
    try {
        Send-MailMessage -To $Config.Settings.EmailReceiver -From $Config.Settings.EmailSender `
                         -Subject "[ALERT] $ServerName is DOWN" `
                         -Body $body -UseSsl `
                         -SmtpServer "smtp.gmail.com" -Port 587 -Credential $Cred -ErrorAction Stop
    } catch {
        Write-Host "Email alert failed: $_"
    }
}

function Send-TelegramAlert {
    param($ServerName, $ServerAddr)
    
    $token = $Config.Settings.TelegramBotToken
    $chatId = $Config.Settings.TelegramChatId
    
    if (-not $token -or -not $chatId) { return }
    
    $message = "[ALERT] *Server Down*`n`nServer: $ServerName`nAddress: $ServerAddr`nStatus: OFFLINE`nTime: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    
    $body = @{
        chat_id = $chatId
        text = $message
        parse_mode = "Markdown"
    } | ConvertTo-Json
    
    try {
        Invoke-RestMethod -Uri "https://api.telegram.org/bot$token/sendMessage" `
                          -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "Telegram alert failed: $_"
    }
}

function Send-PushoverAlert {
    param($ServerName, $ServerAddr)
    
    $userKey = $Config.Settings.PushoverUserKey
    $apiToken = $Config.Settings.PushoverAPIToken
    
    if (-not $userKey -or -not $apiToken) { return }
    
    $body = @{
        token = $apiToken
        user = $userKey
        title = "REGTeches Server Alert"
        message = "Server $ServerName at $ServerAddr is OFFLINE"
        priority = 1
        sound = "siren"
    }
    
    try {
        Invoke-RestMethod -Uri "https://api.pushover.net/1/messages.json" `
                          -Method Post -Body $body -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "Pushover alert failed: $_"
    }
}

function Send-WebhookAlert {
    param($ServerName, $ServerAddr)
    
    $webhookUrl = $Config.Settings.WebhookUrl
    
    if (-not $webhookUrl) { return }
    
    $payload = @{
        server_name = $ServerName
        server_address = $ServerAddr
        status = "OFFLINE"
        timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    } | ConvertTo-Json
    
    try {
        Invoke-RestMethod -Uri $webhookUrl -Method Post -Body $payload `
                          -ContentType "application/json" -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "Webhook alert failed: $_"
    }
}

# ============================================================================
# UI DIALOGS
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
    $d.Text = "Alert Settings"
    $d.Size = "450,600"
    $d.StartPosition = "CenterParent"
    $d.AutoScroll = $true
    
    $y = 10
    
    # Email Settings
    $lblEmail = New-Object Windows.Forms.Label
    $lblEmail.Text = "EMAIL ALERTS"
    $lblEmail.Location = "10,$y"
    $lblEmail.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lblEmail.AutoSize = $true
    $d.Controls.Add($lblEmail)
    $y += 30
    
    $l1 = New-Object Windows.Forms.Label
    $l1.Text = "Gmail Address:"
    $l1.Location = "10,$y"
    $d.Controls.Add($l1)
    $y += 20
    
    $t1 = New-Object Windows.Forms.TextBox
    $t1.Location = "10,$y"
    $t1.Width = 400
    $t1.Text = $Config.Settings.EmailSender
    $d.Controls.Add($t1)
    $y += 35
    
    $l2 = New-Object Windows.Forms.Label
    $l2.Text = "App Password:"
    $l2.Location = "10,$y"
    $d.Controls.Add($l2)
    $y += 20
    
    $t2 = New-Object Windows.Forms.TextBox
    $t2.Location = "10,$y"
    $t2.Width = 400
    $t2.PasswordChar = "*"
    $d.Controls.Add($t2)
    $y += 35
    
    $l3 = New-Object Windows.Forms.Label
    $l3.Text = "Receiver Email:"
    $l3.Location = "10,$y"
    $d.Controls.Add($l3)
    $y += 20
    
    $t3 = New-Object Windows.Forms.TextBox
    $t3.Location = "10,$y"
    $t3.Width = 400
    $t3.Text = $Config.Settings.EmailReceiver
    $d.Controls.Add($t3)
    $y += 40
    
    # Telegram Settings
    $lblTelegram = New-Object Windows.Forms.Label
    $lblTelegram.Text = "TELEGRAM ALERTS"
    $lblTelegram.Location = "10,$y"
    $lblTelegram.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lblTelegram.AutoSize = $true
    $d.Controls.Add($lblTelegram)
    $y += 30
    
    $l4 = New-Object Windows.Forms.Label
    $l4.Text = "Bot Token:"
    $l4.Location = "10,$y"
    $d.Controls.Add($l4)
    $y += 20
    
    $t4 = New-Object Windows.Forms.TextBox
    $t4.Location = "10,$y"
    $t4.Width = 400
    $t4.Text = $Config.Settings.TelegramBotToken
    $d.Controls.Add($t4)
    $y += 35
    
    $l5 = New-Object Windows.Forms.Label
    $l5.Text = "Chat ID:"
    $l5.Location = "10,$y"
    $d.Controls.Add($l5)
    $y += 20
    
    $t5 = New-Object Windows.Forms.TextBox
    $t5.Location = "10,$y"
    $t5.Width = 400
    $t5.Text = $Config.Settings.TelegramChatId
    $d.Controls.Add($t5)
    $y += 40
    
    # Pushover Settings
    $lblPushover = New-Object Windows.Forms.Label
    $lblPushover.Text = "PUSHOVER ALERTS"
    $lblPushover.Location = "10,$y"
    $lblPushover.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lblPushover.AutoSize = $true
    $d.Controls.Add($lblPushover)
    $y += 30
    
    $l6 = New-Object Windows.Forms.Label
    $l6.Text = "User Key:"
    $l6.Location = "10,$y"
    $d.Controls.Add($l6)
    $y += 20
    
    $t6 = New-Object Windows.Forms.TextBox
    $t6.Location = "10,$y"
    $t6.Width = 400
    $t6.Text = $Config.Settings.PushoverUserKey
    $d.Controls.Add($t6)
    $y += 35
    
    $l7 = New-Object Windows.Forms.Label
    $l7.Text = "API Token:"
    $l7.Location = "10,$y"
    $d.Controls.Add($l7)
    $y += 20
    
    $t7 = New-Object Windows.Forms.TextBox
    $t7.Location = "10,$y"
    $t7.Width = 400
    $t7.Text = $Config.Settings.PushoverAPIToken
    $d.Controls.Add($t7)
    $y += 40
    
    # Webhook Settings
    $lblWebhook = New-Object Windows.Forms.Label
    $lblWebhook.Text = "WEBHOOK ALERTS"
    $lblWebhook.Location = "10,$y"
    $lblWebhook.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lblWebhook.AutoSize = $true
    $d.Controls.Add($lblWebhook)
    $y += 30
    
    $l8 = New-Object Windows.Forms.Label
    $l8.Text = "Webhook URL:"
    $l8.Location = "10,$y"
    $d.Controls.Add($l8)
    $y += 20
    
    $t8 = New-Object Windows.Forms.TextBox
    $t8.Location = "10,$y"
    $t8.Width = 400
    $t8.Text = $Config.Settings.WebhookUrl
    $d.Controls.Add($t8)
    $y += 40
    
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
        
        [System.Windows.Forms.MessageBox]::Show("Settings saved successfully!", "Success")
    }
}

# ============================================================================
# MAIN FORM
# ============================================================================

$Form = New-Object Windows.Forms.Form
$Form.Text = "REGTeches NOC Dashboard v17.1 Simple"
$Form.Size = "1000,700"
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
$SetM = New-Object Windows.Forms.ToolStripMenuItem("Alert Settings", $null, { Show-SettingsDialog })
$FileM.DropDownItems.AddRange(@($AddM, $SetM))
$Menu.Items.Add($FileM)
$MainGrid.Controls.Add($Menu, 0, 0)

# Alarm Button
$MaintBtn = New-Object Windows.Forms.CheckBox
$MaintBtn.Appearance = "Button"
$MaintBtn.Text = "ALARM ARMED"
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
        $MaintBtn.Text = "ALARM ARMED"
        $MaintBtn.BackColor = [System.Drawing.Color]::DarkGreen
    }
})
$MainGrid.Controls.Add($MaintBtn, 0, 1)

# Tabs
$Tabs = New-Object Windows.Forms.TabControl
$Tabs.Dock = "Fill"

$MapTab = New-Object Windows.Forms.TabPage("Network Map")
$LogTab = New-Object Windows.Forms.TabPage("Live Log")

$Tabs.Controls.AddRange(@($MapTab, $LogTab))
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

# ============================================================================
# SYSTEM TRAY
# ============================================================================

$Global:TrayIcon = New-Object System.Windows.Forms.NotifyIcon
$Global:TrayIcon.Icon = [System.Drawing.SystemIcons]::Application
$Global:TrayIcon.Text = "REGTeches Monitor"
$Global:TrayIcon.Visible = $true

$TrayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$ShowItem = New-Object System.Windows.Forms.ToolStripMenuItem("Show Dashboard")
$ShowItem.Add_Click({ $Form.WindowState = "Normal"; $Form.Activate() })
$TrayMenu.Items.Add($ShowItem)

$QuitItem = New-Object System.Windows.Forms.ToolStripMenuItem("Quit")
$QuitItem.Add_Click({ $Form.Close() })
$TrayMenu.Items.Add($QuitItem)

$Global:TrayIcon.ContextMenuStrip = $TrayMenu
$Global:TrayIcon.Add_DoubleClick({ $Form.WindowState = "Normal"; $Form.Activate() })

# ============================================================================
# CREATE SERVER CARDS
# ============================================================================

foreach ($S in $Config.Servers) {
    $Card = New-Object Windows.Forms.Label
    $Card.Text = "$($S.Name)`n$($S.Address)"
    if ($S.Maintenance) { $Card.Text += "`n[MAINT]" }
    $Card.Size = "240,150"
    $Card.TextAlign = "MiddleCenter"
    $Card.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
    $Card.ForeColor = "White"
    $Card.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $Card.Margin = New-Object System.Windows.Forms.Padding(12)
    $Card.BorderStyle = "FixedSingle"
    
    # Context Menu
    $ctx = New-Object Windows.Forms.ContextMenuStrip
    $itemAddr = $S.Address
    $itemName = $S.Name
    
    $openItem = New-Object Windows.Forms.ToolStripMenuItem("Open Connection", $null, {
        $target = if ($itemAddr -notlike "http*") { "https://$itemAddr" } else { $itemAddr }
        Start-Process $target
    })
    
    $deleteItem = New-Object Windows.Forms.ToolStripMenuItem("Delete", $null, {
        $result = [System.Windows.Forms.MessageBox]::Show("Delete $itemName?", "Confirm", "YesNo", "Question")
        if ($result -eq "Yes") {
            $c = Get-Config
            $c.Servers = $c.Servers | Where-Object { $_.Address -ne $itemAddr }
            Save-Config $c
            [System.Windows.Forms.MessageBox]::Show("Server removed! Please restart the application.", "Success")
        }
    })
    
    $ctx.Items.AddRange(@($openItem, $deleteItem))
    $Card.ContextMenuStrip = $ctx
    
    $Flow.Controls.Add($Card)
    $Global:ServerCards[$S.Address] = $Card
}

# ============================================================================
# MONITORING LOOP
# ============================================================================

$MainTimer = New-Object Windows.Forms.Timer
$MainTimer.Interval = ($Config.Settings.CheckIntervalSeconds * 1000)
$MainTimer.Add_Tick({
    $Panic = $false
    
    foreach ($S in $Config.Servers) {
        # Skip maintenance servers
        if ($S.Maintenance) { continue }
        
        # Check server
        $result = Test-ServerAdvanced $S.Address $S.Port
        
        # Update card
        if ($Global:ServerCards.ContainsKey($S.Address)) {
            $card = $Global:ServerCards[$S.Address]
            if ($result.IsOnline) {
                $card.BackColor = [System.Drawing.Color]::DarkGreen
                $card.Text = "$($S.Name)`n$($S.Address)`n[OK] $([Math]::Round($result.ResponseTime)) ms"
            } else {
                $card.BackColor = [System.Drawing.Color]::Maroon
                $card.Text = "$($S.Name)`n$($S.Address)`n[OFFLINE]"
                $Panic = $true
                
                $timestamp = Get-Date -Format "HH:mm:ss"
                $LogBox.AppendText("[$timestamp] [DOWN] $($S.Name) - $($result.Error)`n")
                $LogBox.ScrollToCaret()
                
                # Send alerts if cooldown allows
                if (Should-SendAlert $S.Address) {
                    Send-EmailAlert $S.Name $S.Address $result.ResponseTime $result.Error
                    Send-TelegramAlert $S.Name $S.Address
                    Send-PushoverAlert $S.Name $S.Address
                    Send-WebhookAlert $S.Name $S.Address
                    $LogBox.AppendText("[$timestamp] [ALERTS] Sent for $($S.Name)`n")
                }
            }
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
        $Global:AlertActive = $false
    }
})

# ============================================================================
# CLEANUP
# ============================================================================

$Form.Add_FormClosing({
    $MainTimer.Stop()
    $FlashTimer.Stop()
    if ($Global:Player) { $Global:Player.Stop() }
    $Global:TrayIcon.Visible = $false
    $Global:TrayIcon.Dispose()
})

# ============================================================================
# START
# ============================================================================

$LogBox.AppendText(@"
========================================
REGTeches Server Monitor v17.1 Simple
========================================

[OK] Real-time monitoring active
[OK] Multi-channel alerts configured
[OK] System tray integration enabled

Monitoring $($Config.Servers.Count) servers...
Check interval: $($Config.Settings.CheckIntervalSeconds) seconds

"@)

$MainTimer.Start()
$Form.ShowDialog()
