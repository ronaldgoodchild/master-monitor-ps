#Requires -Version 5.1
<#
.SYNOPSIS
    Setup script for REGTeches NOC Dashboard PRO v17.0
.DESCRIPTION
    Installs required dependencies and sets up the monitoring environment
#>

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "REGTeches NOC Dashboard PRO v17.0 - Setup Wizard" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

# Check PowerShell version
Write-Host "[1/5] Checking PowerShell version..." -ForegroundColor Yellow
$psVersion = $PSVersionTable.PSVersion
Write-Host "    PowerShell Version: $($psVersion.Major).$($psVersion.Minor)" -ForegroundColor White

if ($psVersion.Major -lt 5) {
    Write-Host "    ✗ ERROR: PowerShell 5.1 or higher is required!" -ForegroundColor Red
    Write-Host "    Please upgrade PowerShell and try again." -ForegroundColor Red
    pause
    exit 1
} else {
    Write-Host "    ✓ PowerShell version is compatible" -ForegroundColor Green
}
Write-Host ""

# Check for .NET Framework
Write-Host "[2/5] Checking .NET Framework..." -ForegroundColor Yellow
try {
    $dotNetVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -ErrorAction Stop).Version
    Write-Host "    .NET Version: $dotNetVersion" -ForegroundColor White
    Write-Host "    ✓ .NET Framework is installed" -ForegroundColor Green
} catch {
    Write-Host "    ⚠ Could not verify .NET Framework" -ForegroundColor Yellow
    Write-Host "    The script may still work, but if you encounter issues," -ForegroundColor Yellow
    Write-Host "    please install .NET Framework 4.5 or higher" -ForegroundColor Yellow
}
Write-Host ""

# Install SQLite module
Write-Host "[3/5] Setting up SQLite support..." -ForegroundColor Yellow

$installChoice = Read-Host "Do you want to install System.Data.SQLite module? (Y/N)"

if ($installChoice -eq "Y" -or $installChoice -eq "y") {
    Write-Host "    Installing NuGet package provider..." -ForegroundColor White
    try {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction Stop | Out-Null
        Write-Host "    ✓ NuGet installed" -ForegroundColor Green
    } catch {
        Write-Host "    ⚠ NuGet installation failed: $_" -ForegroundColor Yellow
    }
    
    Write-Host "    Installing PSSQLite module..." -ForegroundColor White
    try {
        Install-Module -Name PSSQLite -Force -Scope CurrentUser -SkipPublisherCheck -ErrorAction Stop
        Write-Host "    ✓ PSSQLite module installed successfully" -ForegroundColor Green
    } catch {
        Write-Host "    ⚠ Module installation failed: $_" -ForegroundColor Yellow
        Write-Host "    You may need to manually download System.Data.SQLite.dll" -ForegroundColor Yellow
        Write-Host "    Download from: https://system.data.sqlite.org/downloads/" -ForegroundColor Yellow
    }
} else {
    Write-Host "    Skipped. You'll need to install SQLite manually if needed." -ForegroundColor Yellow
    Write-Host "    Download from: https://system.data.sqlite.org/downloads/" -ForegroundColor Yellow
}
Write-Host ""

# Check for servers.json
Write-Host "[4/5] Checking configuration file..." -ForegroundColor Yellow
$configPath = Join-Path $PSScriptRoot "servers.json"
$sampleConfigPath = Join-Path $PSScriptRoot "servers_sample.json"

if (Test-Path $configPath) {
    Write-Host "    ✓ servers.json already exists" -ForegroundColor Green
    $overwrite = Read-Host "    Do you want to view the sample configuration? (Y/N)"
    if ($overwrite -eq "Y" -or $overwrite -eq "y") {
        if (Test-Path $sampleConfigPath) {
            notepad $sampleConfigPath
        } else {
            Write-Host "    Sample configuration not found." -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "    Creating default servers.json..." -ForegroundColor White
    
    $defaultConfig = @{
        Servers = @(
            @{
                Name = "Example Server 1"
                Address = "8.8.8.8"
                Port = $null
                Maintenance = $false
            },
            @{
                Name = "Example Server 2"
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
            TelegramChatID = ""
            PushoverUserKey = ""
            PushoverAPIToken = ""
            WebhookURL = ""
        }
    }
    
    $defaultConfig | ConvertTo-Json -Depth 10 | Set-Content $configPath
    Write-Host "    ✓ Created servers.json with example configuration" -ForegroundColor Green
    Write-Host "    Please edit servers.json to add your actual servers" -ForegroundColor Yellow
}
Write-Host ""

# Check for alarm sound
Write-Host "[5/5] Checking alarm sound file..." -ForegroundColor Yellow
$alarmPath = Join-Path $PSScriptRoot "Nuclear Alarm.wav"

if (Test-Path $alarmPath) {
    Write-Host "    ✓ Nuclear Alarm.wav found" -ForegroundColor Green
} else {
    Write-Host "    ⚠ Nuclear Alarm.wav not found" -ForegroundColor Yellow
    Write-Host "    The application will work without it, but you won't have audio alerts." -ForegroundColor Yellow
    Write-Host "    To add alarm sound:" -ForegroundColor White
    Write-Host "    1. Find a WAV file you want to use" -ForegroundColor White
    Write-Host "    2. Rename it to 'Nuclear Alarm.wav'" -ForegroundColor White
    Write-Host "    3. Place it in: $PSScriptRoot" -ForegroundColor White
}
Write-Host ""

# Summary
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Setup Complete!" -ForegroundColor Green
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Edit servers.json to add your servers" -ForegroundColor White
Write-Host "2. Configure notification settings (optional)" -ForegroundColor White
Write-Host "3. Run: .\MasterMonitor_Enhanced.ps1" -ForegroundColor White
Write-Host ""
Write-Host "For detailed instructions, see README_PRO.md" -ForegroundColor Cyan
Write-Host ""

$openConfig = Read-Host "Would you like to open servers.json now? (Y/N)"
if ($openConfig -eq "Y" -or $openConfig -eq "y") {
    notepad $configPath
}

Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
