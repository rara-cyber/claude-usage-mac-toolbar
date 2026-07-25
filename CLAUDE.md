# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A macOS menu bar app (Swift + AppKit, no Xcode project) that displays Claude's OAuth-reported usage windows (5-hour rolling "session" + 7-day "weekly") as two stacked bars. Distributed as an unsigned `.app` bundle via GitHub Releases.

Min macOS 13. `LSUIElement` is true (no Dock icon, menu bar only).

## Build / run

```bash
./build.sh                          # compiles Sources/*.swift, builds dist/Claude Usage Bar.app
open "dist/Claude Usage Bar.app"    # run the built app
./dist/Claude\ Usage\ Bar.app/Contents/MacOS/ClaudeUsage   # run with stdout visible
```

There is no test suite, linter, or package manager. The whole build is `swiftc -O -framework AppKit -framework Security Sources/*.swift` plus `iconutil` icon generation and `Info.plist` copy. Releases trigger `.github/workflows/release.yml` which runs `build.sh` on `macos-latest` and uploads the zipped bundle to the GitHub release.

## Architecture

Six Swift files, one responsibility each — read in this order:

- `Sources/main.swift` — bootstraps `NSApplication` as `.accessory` and installs `AppDelegate`.
- `Sources/AppDelegate.swift` — owns the `NSStatusItem`, the menu, the 60s `pollTimer`, and all user preferences (persisted via `UserDefaults`). On each poll it calls `UsageClient.fetchUsage()` on a background queue, hands the result to `UsageHistory.record(...)`, then re-renders the status bar image and the dropdown's two `UsageBarMenuView`s. Backoff: 3 consecutive API failures bump the poll interval from 60s → 300s. Launch-at-login uses `SMAppService.mainApp` (macOS 13+).
- `Sources/UsageClient.swift` — reads the Claude Code OAuth token from the macOS Keychain (`kSecClassGenericPassword`, service `Claude Code-credentials`, account `NSUserName()`) and `GET`s `https://api.anthropic.com/api/oauth/usage` with header `anthropic-beta: oauth-2025-04-20`. Synchronous (uses a `DispatchSemaphore` — only call from a background queue). On request failure it invalidates `cachedToken` and retries once in case Claude Code rotated it.
- `Sources/UsageHistory.swift` — append-only snapshot store at `~/Library/Application Support/ClaudeUsageBar/usage_history.json`, pruned to 7 days. `record(...)` appends and saves; `cachedUsage()` returns the last snapshot so the menu bar renders instantly on cold start instead of sitting blank through the first request. No forecasting — that was removed along with the pace indicator.
- `Sources/PeakHours.swift` — the 5:00–11:00 `America/Los_Angeles` window (`isActive`, `nextBoundary`, `statusLabel`). Anchored to Pacific as a fixed absolute interval; only the *displayed* boundary is converted to the user's local clock. Named time zones handle DST.
- `Sources/BarRenderer.swift` — pure drawing. `renderCircles(...)` produces the @2x 18×18 menu-bar `NSImage` — two stacked horizontal bars, session on top, weekly below — and `renderUnauthenticated()` is the dimmed "no auth" state. The nested `UsageBarMenuView` is the wider bar drawn inside the dropdown menu rows. `colorForUsage(_:threshold:peak:)` is the single color rule: violet (`#A855F7`) during peak hours, else red (`#FF4D40`) at or above the user's warning threshold, else orange (`#C56B4F`). `isTemplate = false` because the bars use real color, not the system tint.

`Resources/Info.plist` is bundled by `build.sh`; `claude-bar-app-icon.png` (1024px) is the source for the generated `AppIcon.icns`. Those are the only two resources — the app draws its menu bar icon, it doesn't load one.

The real icon source is `Resources/app-icon.svg`; the PNG is committed because `build.sh` (and CI) only have `sips`/`iconutil`. After editing the SVG, regenerate with
`rsvg-convert -w 1024 -h 1024 Resources/app-icon.svg -o claude-bar-app-icon.png`.

## Conventions worth knowing

- All UI mutation must happen on the main queue; networking and Keychain reads happen on `DispatchQueue.global(qos: .utility)`.
- Reset times from the API come as ISO8601; both fractional-second and plain variants must be tried (helper pattern is repeated in `AppDelegate` and `UsageHistory`).
- Preferences keys in `UserDefaults`: `invert` (Bool, "show remaining"), `warningThreshold` (Double, one of `warningOptions`), `highlightPeak` (Bool). They live under the bundle ID `online.sian-agency.usagebar` — changing that ID orphans existing preferences.
- No third-party dependencies; do not introduce SwiftPM or CocoaPods — `build.sh` would need to change.
