# Claude Usage Bar

<p align="center">
  <img src="claude-bar-app-icon.png" width="128" height="128" alt="Claude Usage Bar icon">
</p>

<p align="center">
  <strong>A tiny macOS menu bar app that shows your Claude usage at a glance.</strong><br>
  100% local. No cloud. No account needed. Just works.
</p>

<p align="center">
  <a href="https://github.com/rara-cyber/claude-usage-mac-toolbar/releases/latest">Download Latest Release</a>
</p>

---

![Screenshot](screenshot.png)

## Features

- **Two bars, always visible** — the 5-hour rolling session window on top, the 7-day weekly cap below, drawn as a compact 18×18 menu bar icon
- **Show used or remaining** — flip the whole display between "42% used" and "58% remaining"
- **Warning threshold** — pick the point (70–95%) where the bars turn red, so the warning matches how close to the cap *you* care about
- **Peak hour highlighting** — bars turn violet during Anthropic's heaviest-load window (5–11 AM Pacific), shown on your local clock
- **Instant cold start** — the last reading is persisted and drawn immediately, so the icon is never blank while the first request is in flight
- **Launch at Login** — one-click toggle
- **About & FAQ** — built-in help window

## Privacy First

- **100% local** — all data stays on your machine. Nothing is sent anywhere except the single API call to check your usage
- **No account or API key needed** — reads the OAuth token that Claude Code already stores in your macOS Keychain
- **Local history** — usage snapshots are saved to `~/Library/Application Support/ClaudeUsageBar/` and auto-pruned after 7 days
- **No telemetry, no analytics, no tracking**

## Menu Options

| Option | Description |
|--------|-------------|
| **Session / Weekly** | The two usage bars, each with its reset countdown |
| **Peak hours** | Whether the 5–11 AM Pacific window is active, and when it next flips |
| **Highlight Peak Hours** | Toggle the violet peak-hour coloring |
| **Show Used / Show Remaining** | Flip between "42% used" and "58% remaining" |
| **Warning Threshold** | 70 / 75 / 80 / 85 / 90 / 95% — where the bars turn red (default 85%) |
| **Refresh Now** | Force an immediate poll (`⌘R`) |
| **About & FAQ** | Built-in help window |
| **Launch at Login** | Start automatically at login |

## How It Works

The app polls the usage API every 60 seconds and records a snapshot locally. If the API errors
three times in a row it backs off to every 5 minutes until the next success. The bar color
reflects your actual usage severity — orange normally, red at or above your warning threshold,
violet during peak hours — while the bar *length* follows whichever metric you chose to display.

## Install

### Download

Grab the latest `.app` from the [Releases page](https://github.com/rara-cyber/claude-usage-mac-toolbar/releases/latest).

Move it to `/Applications` and open it. That's it.

### Build from source

```bash
git clone https://github.com/rara-cyber/claude-usage-mac-toolbar.git
cd claude-usage-mac-toolbar
./build.sh
open "dist/Claude Usage Bar.app"
```

Requires Xcode Command Line Tools (`xcode-select --install`). Requires macOS 13 or later.

## Prerequisites

You need to be signed into [Claude Code](https://claude.ai/claude-code) on your Mac. The app reads the existing OAuth token from your macOS Keychain — no manual configuration required.

## License

MIT. This is a fork of an earlier MIT-licensed menu bar app, substantially rewritten; see
[LICENSE](LICENSE) for the full notice and both copyright holders.

## Disclaimer

This app is **not affiliated with, endorsed by, or associated with Anthropic** in any way. It is an independent utility made from developer to developer.

---

Built by [SIÁN Agency](https://www.sian-agency.online) — minimal, modern, purposeful tools for people who ship.
