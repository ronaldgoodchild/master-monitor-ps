# Roadmap / ideas

Comment on (or open) an issue first so we don't duplicate work.

## Good first issues
- [x] Add screenshots to the README
- [ ] Add a `-ConfigPath` parameter so several server lists can be monitored
- [ ] Reduce duplicated code between the Simple and PRO editions (shared module)
- [ ] Add Pester tests for config loading and the alert-suppression logic

## Security
- [ ] Store email/Telegram/Pushover secrets with DPAPI (`ConvertFrom-SecureString`) instead of plain JSON

## Features
- [ ] Run as a Windows service / scheduled task without the GUI
- [ ] SSL certificate expiry checks
- [ ] Microsoft Teams / ntfy alert channels
- [ ] Publish to the PowerShell Gallery
