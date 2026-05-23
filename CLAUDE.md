# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A macOS menu bar app (Swift + AppKit, no Xcode project) that displays Claude's OAuth-reported usage windows (5-hour rolling "session" + 7-day "weekly") and forecasts whether you'll hit the cap before reset. Distributed as an unsigned `.app` bundle via GitHub Releases.

Min macOS 13. `LSUIElement` is true (no Dock icon, menu bar only).

## Build / run

```bash
./build.sh                          # compiles Sources/*.swift, builds dist/Claude Usage Bar.app
open "dist/Claude Usage Bar.app"    # run the built app
./dist/Claude\ Usage\ Bar.app/Contents/MacOS/ClaudeUsage   # run with stdout visible
```

There is no test suite, linter, or package manager. The whole build is `swiftc -O -framework AppKit -framework Security Sources/*.swift` plus `iconutil` icon generation and `Info.plist` copy. Releases trigger `.github/workflows/release.yml` which runs `build.sh` on `macos-latest` and uploads the zipped bundle to the GitHub release.

## Architecture

Five Swift files, one responsibility each — read in this order:

- `Sources/main.swift` — bootstraps `NSApplication` as `.accessory` and installs `AppDelegate`.
- `Sources/AppDelegate.swift` — owns the `NSStatusItem`, the menu, the 60s `pollTimer`, and all user preferences (persisted via `UserDefaults`). On each poll it calls `UsageClient.fetchUsage()` on a background queue, hands the result to `UsageHistory.record(...)`, then re-renders the status bar image and the dropdown's two `UsageBarMenuView`s. Backoff: 3 consecutive API failures bump the poll interval from 60s → 300s. Launch-at-login uses `SMAppService.mainApp` (macOS 13+).
- `Sources/UsageClient.swift` — reads the Claude Code OAuth token from the macOS Keychain (`kSecClassGenericPassword`, service `Claude Code-credentials`, account `NSUserName()`) and `GET`s `https://api.anthropic.com/api/oauth/usage` with header `anthropic-beta: oauth-2025-04-20`. Synchronous (uses a `DispatchSemaphore` — only call from a background queue). On request failure it invalidates `cachedToken` and retries once in case Claude Code rotated it.
- `Sources/UsageHistory.swift` — append-only snapshot store at `~/Library/Application Support/ClaudeUsageBar/usage_history.json`, pruned to 7 days. `forecast(for:)` does linear extrapolation: picks the last 1h (session) or 3h (weekly) of snapshots, computes `slope = Δpct / Δhours`, projects to the reset timestamp. Pace thresholds: <80% green, 80–95% yellow, ≥95% red. `currentCycleSnapshots(for:)` filters to snapshots sharing the same reset timestamp AND detects mid-window resets by looking for a >20% drop between consecutive points (everything before the drop is discarded so the forecast doesn't slope-fit across a reset boundary).
- `Sources/BarRenderer.swift` — pure drawing. `render(...)` produces the @2x menu-bar `NSImage` (segmented bar + percentage text + optional logo), `renderUnauthenticated(...)` is the dimmed "no auth" state, and the nested `UsageBarMenuView` is the wider bar drawn inside the dropdown menu rows. Color is orange (`#C56B4F`) until ≥90% then red (`#FF4D40`). `isTemplate = false` because the bar uses real color, not the system tint.

`Resources/Info.plist` and `Resources/icon.png` are bundled by `build.sh`; `claude-bar-app-icon.png` (1024px) is the source for the generated `AppIcon.icns`.

## Conventions worth knowing

- All UI mutation must happen on the main queue; networking and Keychain reads happen on `DispatchQueue.global(qos: .utility)`.
- Reset times from the API come as ISO8601; both fractional-second and plain variants must be tried (helper pattern is repeated in `AppDelegate` and `UsageHistory`).
- Preferences keys in `UserDefaults`: `activeView` (`"five_hour"` | `"seven_day"`), `invert` (Bool, "show remaining"), `displayMode` (`DisplayMode.rawValue`).
- No third-party dependencies; do not introduce SwiftPM or CocoaPods — `build.sh` would need to change.
