import AppKit
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var pollTimer: Timer?
    private let client = UsageClient()
    private var lastUsage: UsageData?
    private var logo: NSImage?

    // Preferences
    private var invert: Bool = false
    private var warningThreshold: Double = 85

    private let warningOptions: [Double] = [70, 75, 80, 85, 90, 95]
    private var miWarningItems: [NSMenuItem] = []

    // Menu items (for updating checkmarks)
    private var miUsed: NSMenuItem!
    private var miRemaining: NSMenuItem!
    private var miSessionReset: NSMenuItem!
    private var miWeeklyReset: NSMenuItem!
    private var sessionBarView: BarRenderer.UsageBarMenuView!
    private var weeklyBarView: BarRenderer.UsageBarMenuView!
    private let usageHistory = UsageHistory()
    private var faqWindow: NSWindow?
    private var miLaunchAtLogin: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadPrefs()
        loadLogo()

        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageOnly

        // Build menu
        let menu = NSMenu()

        // Session usage
        let sessionBarItem = NSMenuItem()
        sessionBarView = BarRenderer.UsageBarMenuView(title: "Session")
        sessionBarItem.view = sessionBarView
        menu.addItem(sessionBarItem)

        miSessionReset = NSMenuItem(title: "Resets in: ...", action: nil, keyEquivalent: "")
        miSessionReset.isEnabled = false
        menu.addItem(miSessionReset)

        menu.addItem(.separator())

        // Weekly usage
        let weeklyBarItem = NSMenuItem()
        weeklyBarView = BarRenderer.UsageBarMenuView(title: "Weekly")
        weeklyBarItem.view = weeklyBarView
        menu.addItem(weeklyBarItem)

        miWeeklyReset = NSMenuItem(title: "Resets: ...", action: nil, keyEquivalent: "")
        miWeeklyReset.isEnabled = false
        menu.addItem(miWeeklyReset)

        menu.addItem(.separator())

        miUsed = NSMenuItem(title: "Show Used", action: #selector(setUsed), keyEquivalent: "")
        miUsed.target = self
        menu.addItem(miUsed)

        miRemaining = NSMenuItem(title: "Show Remaining", action: #selector(setRemaining), keyEquivalent: "")
        miRemaining.target = self
        menu.addItem(miRemaining)

        menu.addItem(.separator())

        // Warning threshold submenu
        let warningSub = NSMenu()
        miWarningItems.removeAll()
        for value in warningOptions {
            let item = NSMenuItem(title: "\(Int(value))%",
                                  action: #selector(setWarningThreshold(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.tag = Int(value)
            warningSub.addItem(item)
            miWarningItems.append(item)
        }
        let warningParent = NSMenuItem(title: "Warning Threshold",
                                       action: nil, keyEquivalent: "")
        warningParent.submenu = warningSub
        menu.addItem(warningParent)

        menu.addItem(.separator())

        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let faqItem = NSMenuItem(title: "About & FAQ", action: #selector(showFAQ), keyEquivalent: "")
        faqItem.target = self
        menu.addItem(faqItem)

        miLaunchAtLogin = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        miLaunchAtLogin.target = self
        menu.addItem(miLaunchAtLogin)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateMenuChecks()

        // Render the last persisted snapshot immediately so the icon is not
        // blank during the first poll's network round-trip.
        if let cached = usageHistory.cachedUsage() {
            lastUsage = cached
            updateDisplay()
        } else {
            setStatusImage(BarRenderer.renderUnauthenticated())
        }

        // Poll immediately, then every 60s
        poll()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    // MARK: - Logo

    private func loadLogo() {
        // Try bundle Resources first, then next to executable
        let candidates = [
            Bundle.main.path(forResource: "icon", ofType: "png"),
            Bundle.main.path(forResource: "claude-logo", ofType: "png"),
            executableRelativePath("icon.png"),
            executableRelativePath("../Resources/icon.png"),
            executableRelativePath("claude-logo.png"),
        ]

        for path in candidates {
            if let path = path, FileManager.default.fileExists(atPath: path),
               let img = NSImage(contentsOfFile: path) {
                logo = img
                return
            }
        }
    }

    private func executableRelativePath(_ relative: String) -> String? {
        guard let execURL = Bundle.main.executableURL else { return nil }
        return execURL.deletingLastPathComponent().appendingPathComponent(relative).path
    }

    // MARK: - Status bar rendering

    private func setStatusImage(_ image: NSImage) {
        statusItem.button?.image = image
        statusItem.button?.imagePosition = .imageOnly
    }

    // MARK: - Polling

    private func poll() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let usage = self.client.fetchUsage()

            DispatchQueue.main.async {
                if usage == nil && !self.client.isAuthenticated {
                    self.setStatusImage(BarRenderer.renderUnauthenticated())
                    self.miSessionReset.title = "Resets in: n/a"
                    self.miWeeklyReset.title = "Resets: n/a"
                    self.sessionBarView.update(percentage: 0, invert: self.invert, warningThreshold: self.warningThreshold)
                    self.weeklyBarView.update(percentage: 0, invert: self.invert, warningThreshold: self.warningThreshold)
                    return
                }

                if usage == nil {
                    if self.lastUsage == nil {
                        self.setStatusImage(BarRenderer.renderUnauthenticated())
                    }
                    return
                }

                self.lastUsage = usage
                self.usageHistory.record(usage!)
                self.updateDisplay()

                // Adjust timer interval on backoff
                self.pollTimer?.invalidate()
                let interval: TimeInterval = self.client.isBackedOff ? 300 : 60
                self.pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                    self?.poll()
                }
            }
        }
    }

    private func updateDisplay() {
        guard let usage = lastUsage else {
            setStatusImage(BarRenderer.renderUnauthenticated())
            return
        }

        // Update menu bars and reset times
        sessionBarView.update(percentage: usage.fiveHourPct, invert: invert, warningThreshold: warningThreshold)
        weeklyBarView.update(percentage: usage.sevenDayPct, invert: invert, warningThreshold: warningThreshold)
        miSessionReset.title = "Resets in \(formatResetTime(usage.fiveHourReset))"
        miWeeklyReset.title = "Resets \(formatResetTimeAbsolute(usage.sevenDayReset))"

        // Update toolbar — two stacked bars, session + weekly
        let image = BarRenderer.renderCircles(
            sessionPct: usage.fiveHourPct,
            weeklyPct: usage.sevenDayPct,
            invert: invert,
            warningThreshold: warningThreshold
        )
        setStatusImage(image)
    }

    // MARK: - Menu checks

    private func updateMenuChecks() {
        miUsed.state = !invert ? .on : .off
        miRemaining.state = invert ? .on : .off

        for item in miWarningItems {
            item.state = Double(item.tag) == warningThreshold ? .on : .off
        }

        if #available(macOS 13.0, *) {
            miLaunchAtLogin.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } else {
            miLaunchAtLogin.isHidden = true
        }
    }

    // MARK: - Menu actions

    @objc private func setUsed() {
        invert = false
        updateMenuChecks()
        updateDisplay()
        savePrefs()
    }

    @objc private func setRemaining() {
        invert = true
        updateMenuChecks()
        updateDisplay()
        savePrefs()
    }

    @objc private func setWarningThreshold(_ sender: NSMenuItem) {
        warningThreshold = Double(sender.tag)
        updateMenuChecks()
        updateDisplay()
        savePrefs()
    }

    @objc private func refreshNow() {
        poll()
    }

    @objc private func toggleLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                } else {
                    try SMAppService.mainApp.register()
                }
            } catch {
                // Silently ignore — may fail if app is not in /Applications
            }
            updateMenuChecks()
        }
    }

    @objc private func showFAQ() {
        if let w = faqWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        w.title = "Claude Usage Bar — FAQ"
        w.center()
        w.isReleasedWhenClosed = false

        let scroll = NSScrollView(frame: w.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: 0))
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 16, height: 16)
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true

        text.textStorage?.setAttributedString(faqContent())

        scroll.documentView = text
        w.contentView = scroll
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        faqWindow = w
    }

    private func faqContent() -> NSAttributedString {
        let result = NSMutableAttributedString()

        let titleFont = NSFont.systemFont(ofSize: 18, weight: .bold)
        let headingFont = NSFont.systemFont(ofSize: 14, weight: .semibold)
        let bodyFont = NSFont.systemFont(ofSize: 13, weight: .regular)
        let titleColor = NSColor.labelColor
        let bodyColor = NSColor.secondaryLabelColor

        func addTitle(_ str: String) {
            result.append(NSAttributedString(string: str + "\n\n", attributes: [
                .font: titleFont, .foregroundColor: titleColor
            ]))
        }

        func addHeading(_ str: String) {
            result.append(NSAttributedString(string: str + "\n", attributes: [
                .font: headingFont, .foregroundColor: titleColor
            ]))
        }

        func addBody(_ str: String) {
            result.append(NSAttributedString(string: str + "\n\n", attributes: [
                .font: bodyFont, .foregroundColor: bodyColor
            ]))
        }

        addTitle("Claude Usage Bar — FAQ")

        addHeading("How does authentication work?")
        addBody("""
            This app reads the OAuth token that Claude Code stores in your \
            macOS Keychain. It never asks for your password or API key directly. \
            If you're signed into Claude Code, the app picks up the token \
            automatically. If the token rotates, the app detects this and \
            refreshes on the next poll.
            """)

        addHeading("Where is my data stored?")
        addBody("""
            Everything stays on your computer. Usage history is saved to:\n\
            ~/Library/Application Support/ClaudeUsageBar/usage_history.json\n\n\
            Preferences (display mode, active view) are stored in the standard \
            macOS UserDefaults. No data is sent to any server — the only network \
            request is the usage API call to api.anthropic.com.
            """)

        addHeading("How often does it refresh?")
        addBody("""
            Every 60 seconds. If the API returns errors 3 times in a row, it \
            backs off to every 5 minutes. You can also click "Refresh Now" at \
            any time. The last successful reading is always shown in the menu bar.
            """)

        addHeading("What are the two usage windows?")
        addBody("""
            Session (5-hour) — a rolling window that resets every 5 hours. \
            This reflects your short-term burst usage.\n\n\
            Weekly (7-day) — resets once per week on a fixed schedule. This \
            is your overall usage cap for the billing period.
            """)

        // About section
        result.append(NSAttributedString(string: "\n", attributes: [.font: bodyFont]))

        let separatorAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont, .foregroundColor: NSColor.separatorColor
        ]
        result.append(NSAttributedString(string: "————————————————————————————————\n\n", attributes: separatorAttrs))

        addHeading("About")
        addBody("""
            Built by SIÁN Agency — minimal, modern, purposeful tools for \
            people who ship.\n\n\
            https://www.sian-agency.online\n\
            hello@sian-agency.online\n\n\
            This app is not affiliated with, endorsed by, or associated with \
            Anthropic in any way. It is an independent utility made from \
            developer to developer.
            """)

        return result
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Preferences

    private func loadPrefs() {
        let d = UserDefaults.standard
        invert = d.bool(forKey: "invert")
        let stored = d.double(forKey: "warningThreshold")
        warningThreshold = stored > 0 ? stored : 85
    }

    private func savePrefs() {
        let d = UserDefaults.standard
        d.set(invert, forKey: "invert")
        d.set(warningThreshold, forKey: "warningThreshold")
    }

    // MARK: - Helpers

    private func formatResetTime(_ resets: String?) -> String {
        guard let resets = resets else { return "unknown" }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Try with fractional seconds first, then without
        guard let resetDate = formatter.date(from: resets) ?? {
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: resets)
        }() else {
            return "unknown"
        }

        let delta = resetDate.timeIntervalSinceNow
        if delta <= 0 { return "< 1m" }

        let hours = Int(delta) / 3600
        let minutes = (Int(delta) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func formatResetTimeAbsolute(_ resets: String?) -> String {
        guard let resets = resets else { return "unknown" }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let resetDate = formatter.date(from: resets) ?? {
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: resets)
        }() else {
            return "unknown"
        }

        let df = DateFormatter()
        df.dateFormat = "EEE, HH:mm"
        return df.string(from: resetDate)
    }
}
