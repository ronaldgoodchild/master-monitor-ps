# Changelog

Reconstructed from the original development history (February 2026).

## [Unreleased]
- Fix: MasterMonitorPRO.ps1 failed to parse (JavaScript ` ${...}` in the web-dashboard HTML was being expanded by PowerShell); the HTML is now a literal here-string
- Docs, examples, security policy and CI added

## [17.1 Simple] - 2026-02-11
- `MasterMonitor-Simple.ps1`: no database dependency

## [17.0 PRO] - 2026-02-11
- SQLite logging, analytics, Telegram / Pushover / webhook alerts, CSV and HTML export, setup wizard

## [1.0 - 16.0] - 2026-02-10
- Rapid iterations of a single-file NOC dashboard (v3.0 - v14.0 card UI, alarm sound, maintenance mode, uptime log)
