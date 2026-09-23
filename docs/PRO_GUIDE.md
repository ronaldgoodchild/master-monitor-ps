# REGTeches NOC Dashboard PRO v17.0 - PowerShell Edition

## 🚀 What's New in PRO v17.0

This enhanced version includes ALL the advanced features from the Python edition:

### ✅ Core Features
- **Real-time Server Monitoring** with ping and port checks
- **Visual Alert System** with nuclear alarm sound and screen flashing
- **Professional Card-Based UI** with 3 tabs (Network Map, Live Log, Statistics)
- **Maintenance Mode** - Global and per-server maintenance toggles

### 🆕 Advanced Features (NEW!)

#### 1. **SQLite Database Logging**
- Persistent storage of all server checks
- Historical data analysis
- Response time tracking
- Alert history logging

#### 2. **Multiple Notification Channels**
- ✉️ **Email Alerts** (Gmail)
- 📱 **Telegram Bot** integration
- 📲 **Pushover** notifications
- 🔗 **Webhook** support (for Slack, Discord, custom APIs)

#### 3. **Analytics & Reports**
- **Uptime Statistics** (24-hour and 7-day)
- **Response Time Analysis**
- **Failure Pattern Detection** (identify peak failure times)
- **CSV Data Export** (for Excel analysis)
- **Professional HTML Reports** with styling

#### 4. **Enhanced UI**
- **Statistics Dashboard** - Real-time system overview
- **Server Analytics Dialog** - Detailed per-server analysis
- **Server Management** - Easy server configuration
- **Right-Click Context Menus** - Quick access to analytics and exports

## 📋 Requirements

### PowerShell Requirements
- Windows PowerShell 5.1 or higher
- .NET Framework 4.5 or higher

### SQLite Setup
The script needs System.Data.SQLite. Install options:

**Option 1: Automatic (Script will attempt this)**
```powershell
Install-Module -Name PSSQLite -Force -Scope CurrentUser
```

**Option 2: Manual Download**
1. Download System.Data.SQLite from: https://system.data.sqlite.org/downloads/
2. Extract `System.Data.SQLite.dll` to the script directory

### Required Files
1. `MasterMonitorPRO.ps1` - Main script
2. `servers.json` - Server configuration (auto-created on first run)
3. `Nuclear Alarm.wav` - Alarm sound (optional, but recommended)
4. `System.Data.SQLite.dll` - SQLite library

## 🔧 Initial Setup

### Step 1: Create Your Servers Configuration

The script will auto-create `servers.json` on first run. You can also create it manually:

```json
{
  "Servers": [
    {
      "Name": "Main Web Server",
      "Address": "192.168.1.100",
      "Port": 443,
      "Maintenance": false
    },
    {
      "Name": "Database Server",
      "Address": "db.example.com",
      "Port": 3306,
      "Maintenance": false
    },
    {
      "Name": "Backup Server",
      "Address": "192.168.1.50",
      "Port": null,
      "Maintenance": false
    }
  ],
  "Settings": {
    "CheckIntervalSeconds": 30,
    "EmailSender": "",
    "EmailPassword": "",
    "EmailReceiver": "",
    "TelegramBotToken": "",
    "TelegramChatID": "",
    "PushoverUserKey": "",
    "PushoverAPIToken": "",
    "WebhookURL": ""
  }
}
```

### Step 2: Configure Notifications

#### Email Alerts (Gmail)
1. Go to **File → Notification Settings**
2. Enter your Gmail address
3. Generate an App Password:
   - Go to https://myaccount.google.com/apppasswords
   - Select "Mail" and "Windows Computer"
   - Copy the 16-character password
4. Enter receiver email address

#### Telegram Alerts
1. Create a bot:
   - Message @BotFather on Telegram
   - Use `/newbot` command
   - Copy the bot token
2. Get your Chat ID:
   - Message @userinfobot
   - Copy your numeric chat ID
3. Enter both in **File → Notification Settings**

#### Pushover Alerts
1. Sign up at https://pushover.net
2. Get your User Key from the dashboard
3. Create an Application to get API Token
4. Enter both in **File → Notification Settings**

#### Webhook Alerts
Perfect for Slack, Discord, or custom integrations:
- **Slack**: Create an Incoming Webhook in your workspace settings
- **Discord**: Create a webhook in channel settings
- **Custom**: Any endpoint that accepts JSON POST requests

### Step 3: Add the Alarm Sound (Optional)
1. Find a nuclear alarm sound (or any WAV file)
2. Name it `Nuclear Alarm.wav`
3. Place in the same directory as the script

## 🎮 How to Use

### Starting the Application
```powershell
.\MasterMonitorPRO.ps1
```

### Main Interface

#### Network Map Tab 🖥️
- **Green Cards** = Server is online
- **Red Cards** = Server is offline
- **Orange Cards** = Server in maintenance mode
- **Right-click any card** for:
  - Open Connection
  - View Analytics
  - Export Data

#### Live Log Tab 📋
- Real-time monitoring log
- Color-coded messages:
  - Green = Normal operations
  - Red = Server down alerts
  - Cyan = System messages

#### Statistics Tab 📊
- Auto-refreshing system overview
- 24-hour uptime statistics
- Average response times
- Check counts

### Menu Options

#### File Menu
- **Add New Server** - Add a server to monitor
- **Manage Servers** - Toggle maintenance mode, delete servers
- **Notification Settings** - Configure all alert channels
- **Exit** - Close application

#### Reports Menu
- **Generate Uptime Report** - Text report with 7-day statistics
- **Generate HTML Report** - Professional web report with styling

### Alarm System
- **Green "ALARM ARMED"** = Active monitoring, will alert on failures
- **Orange "ALARM DISARMED"** = Maintenance mode, no alerts sent
- Click to toggle between modes

## 📊 Analytics Features

### Per-Server Analytics
Right-click any server card → **View Analytics** to see:
- 24-hour and 7-day uptime statistics
- Average response times
- Failure pattern analysis:
  - Most common failure hours
  - Most common failure days
  - Hour and day distribution charts

### Failure Pattern Analysis
The system automatically analyzes your downtime data to detect:
- **Peak failure times** - Which hours have the most failures?
- **Problematic days** - Does the server fail more on certain days?
- **Trends** - Historical patterns in your infrastructure

### Exporting Data
- **CSV Export**: Right-click server → Export Data (7 days)
- **HTML Report**: File → Reports → Generate HTML Report
- **Uptime Report**: File → Reports → Generate Uptime Report

## 🗄️ Database

The script creates `monitor.db` with two tables:

### checks table
- Stores every server check
- Includes: timestamp, online status, response time
- Used for analytics and reporting

### alerts table
- Logs all notification attempts
- Tracks which alerts succeeded/failed
- Useful for debugging notification issues

## 🔔 Notification Behavior

### When Alerts are Sent
- Server goes DOWN while alarm is ARMED
- Sends through ALL configured channels simultaneously:
  - Email
  - Telegram
  - Pushover
  - Webhook

### When Alerts are NOT Sent
- Alarm is DISARMED (maintenance mode)
- Server is marked as in Maintenance
- No notification credentials configured

### Alert Cooldown
- Each server has automatic cooldown
- Prevents notification spam
- Logged in database for tracking

## 🎨 Customization

### Change Check Interval
Edit `servers.json`:
```json
"CheckIntervalSeconds": 30
```
(Default is 30 seconds, minimum recommended: 15)

### Change Alarm Sound
Replace `Nuclear Alarm.wav` with any WAV file

### Add Custom Server Fields
You can add custom fields to servers in `servers.json`:
```json
{
  "Name": "My Server",
  "Address": "192.168.1.1",
  "Port": 443,
  "Maintenance": false,
  "Notes": "Production web server",
  "Owner": "IT Department",
  "Location": "Data Center A"
}
```

## 🐛 Troubleshooting

### SQLite Not Working
```powershell
# Install SQLite module manually
Install-Module -Name PSSQLite -Force -Scope CurrentUser -SkipPublisherCheck

# Or download System.Data.SQLite.dll and place in script directory
```

### Email Alerts Not Sending
- Use App Password, not regular Gmail password
- Enable "Less secure app access" if using old Gmail
- Check spam folder
- Verify SMTP settings: smtp.gmail.com, port 587, TLS enabled

### Telegram Not Working
- Verify bot token format: `1234567890:ABCdefGHIjklMNOpqrsTUVwxyz`
- Verify chat ID is numeric: `123456789`
- Message your bot first (bots can't initiate conversations)

### Cards Not Updating
- Check if servers are reachable from your computer
- Verify firewall isn't blocking PowerShell
- Check Event Viewer for errors

### Database Locked Error
- Close all instances of the script
- Delete `monitor.db` (will recreate on next run)

## 📈 Performance Tips

1. **Don't set check interval too low** - 30 seconds is optimal
2. **Use maintenance mode** - Reduces unnecessary checks
3. **Archive old data** - Database grows over time
4. **Monitor response times** - High times indicate network issues

## 🔐 Security Notes

- **Email passwords** stored in plaintext in `servers.json`
- **Consider using** Windows Credential Manager for sensitive data
- **Restrict access** to the script directory
- **Don't commit** `servers.json` to version control

## 📝 Feature Comparison

| Feature | Basic v16 | PRO v17 |
|---------|-----------|---------|
| Server Monitoring | ✅ | ✅ |
| Email Alerts | ✅ | ✅ |
| Visual Alarm | ✅ | ✅ |
| Database Logging | ❌ | ✅ |
| Telegram Alerts | ❌ | ✅ |
| Pushover Alerts | ❌ | ✅ |
| Webhook Support | ❌ | ✅ |
| Analytics Dashboard | ❌ | ✅ |
| Failure Patterns | ❌ | ✅ |
| CSV Export | ❌ | ✅ |
| HTML Reports | ❌ | ✅ |
| Per-Server Maintenance | ❌ | ✅ |
| Response Time Tracking | ❌ | ✅ |
| Statistics Tab | ❌ | ✅ |

## 🆘 Support

For issues or questions:
1. Check the troubleshooting section above
2. Review PowerShell error messages
3. Check `monitor.db` for logged data
4. Verify all configuration in `servers.json`

## 📜 Version History

### v17.0 PRO (Current)
- ✅ SQLite database integration
- ✅ Multi-channel notifications
- ✅ Advanced analytics
- ✅ Professional reporting
- ✅ Per-server maintenance mode
- ✅ Response time tracking
- ✅ Statistics dashboard

### v16.0 (Previous)
- Basic server monitoring
- Email alerts
- Visual alarm system
- Card-based UI

---

**Made by REGTeches** | PowerShell Edition with Python PRO Features
