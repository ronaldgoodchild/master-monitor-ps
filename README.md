# Master Monitor (PowerShell)

A free **server monitoring dashboard in a single PowerShell script**: card-based Windows Forms UI, ping and port checks, loud visual + audio alarms when something drops, maintenance mode, and alerts by email, Telegram, Pushover or webhook. No install, no server - just run the script.

> Part of the REGTeches NOC family. Want a web version or SMS alerts? See [noc-dashboard](https://github.com/ronaldgoodchild/noc-dashboard).

## Two editions

| Script | Version | What it is |
|--------|---------|------------|
| [`MasterMonitor-Simple.ps1`](MasterMonitor-Simple.ps1) | 17.1 Simple | Works immediately on any Windows PC - **no database dependency**. Real-time monitoring, multi-channel alerts, tray icon, visual/audio alarms. |
| [`MasterMonitorPRO.ps1`](MasterMonitorPRO.ps1) | 17.0 PRO | Adds **SQLite history**, uptime statistics (24 h / 7 d), response-time and failure-pattern analysis, CSV export, HTML reports, per-server analytics. |

## Features

- Ping **and** TCP port checks; HTTP(S) URL checks
- Card-based UI: Network Map, Live Log, Statistics tabs
- Nuclear-alarm style **audio + screen-flash alerts** (drop in your own `Nuclear Alarm.wav`)
- **Maintenance mode** - global and per-server
- Alerts via **email (Gmail)**, **Telegram bot**, **Pushover** and **webhooks** (Slack, Discord, custom)
- PRO: SQLite logging, analytics dialogs, CSV/HTML export

Full details in [docs/PRO_GUIDE.md](docs/PRO_GUIDE.md).

## Quick start

```powershell
git clone https://github.com/ronaldgoodchild/master-monitor-ps.git
cd master-monitor-ps
copy servers.example.json servers.json      # then edit your servers
powershell -ExecutionPolicy Bypass -File .\MasterMonitor-Simple.ps1
```

For the PRO edition run `.\Setup-Monitor.ps1` first - it checks prerequisites and helps you install SQLite support (`System.Data.SQLite.dll` from https://system.data.sqlite.org/downloads/ next to the script, or the `PSSQLite` module).

Optional alarm sound: put any WAV file named `Nuclear Alarm.wav` next to the script.

## Security

`servers.json` can hold your email password, Telegram token and Pushover keys **in plain text**. It is git-ignored - never commit or share it. Use a Gmail *app password*, not your real password.

## Contributing

Ideas and pull requests welcome - see [CONTRIBUTING.md](CONTRIBUTING.md) and [ROADMAP.md](ROADMAP.md).

## License

[MIT](LICENSE) (c) 2026 Ronald Goodchild / REGTeches
