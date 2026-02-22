import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var pollTimer: Timer?
    private let client = UsageClient()
    private var lastUsage: UsageData?
    private var logo: NSImage?

    // Preferences
    private var activeView: String = "five_hour"   // "five_hour" or "seven_day"
    private var displayMode: DisplayMode = .barAndPct
    private var invert: Bool = false

    // Menu items (for updating checkmarks)
    private var miFiveHour: NSMenuItem!
    private var miSevenDay: NSMenuItem!
    private var miUsed: NSMenuItem!
    private var miRemaining: NSMenuItem!
    private var miBarPct: NSMenuItem!
    private var miBarOnly: NSMenuItem!
    private var miPctOnly: NSMenuItem!
    private var miSessionReset: NSMenuItem!
    private var miWeeklyReset: NSMenuItem!
    private var sessionBarView: BarRenderer.UsageBarMenuView!
    private var weeklyBarView: BarRenderer.UsageBarMenuView!

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

        miFiveHour = NSMenuItem(title: "5-Hour Usage", action: #selector(setFiveHour), keyEquivalent: "")
        miFiveHour.target = self
        menu.addItem(miFiveHour)

        miSevenDay = NSMenuItem(title: "Weekly Usage", action: #selector(setSevenDay), keyEquivalent: "")
        miSevenDay.target = self
        menu.addItem(miSevenDay)

        menu.addItem(.separator())

        miUsed = NSMenuItem(title: "Show Used", action: #selector(setUsed), keyEquivalent: "")
        miUsed.target = self
        menu.addItem(miUsed)

        miRemaining = NSMenuItem(title: "Show Remaining", action: #selector(setRemaining), keyEquivalent: "")
        miRemaining.target = self
        menu.addItem(miRemaining)

        menu.addItem(.separator())

        miBarPct = NSMenuItem(title: "Bar + Percentage", action: #selector(setBarPct), keyEquivalent: "")
        miBarPct.target = self
        menu.addItem(miBarPct)

        miBarOnly = NSMenuItem(title: "Bar Only", action: #selector(setBarOnly), keyEquivalent: "")
        miBarOnly.target = self
        menu.addItem(miBarOnly)

        miPctOnly = NSMenuItem(title: "Percentage Only", action: #selector(setPctOnly), keyEquivalent: "")
        miPctOnly.target = self
        menu.addItem(miPctOnly)

        menu.addItem(.separator())

        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateMenuChecks()

        // Show initial state
        setStatusImage(BarRenderer.renderUnauthenticated(logo: logo))

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
                    self.setStatusImage(BarRenderer.renderUnauthenticated(logo: self.logo))
                    self.miSessionReset.title = "Resets in: n/a"
                    self.miWeeklyReset.title = "Resets: n/a"
                    self.sessionBarView.update(percentage: 0)
                    self.weeklyBarView.update(percentage: 0)
                    return
                }

                if usage == nil {
                    if self.lastUsage == nil {
                        self.setStatusImage(BarRenderer.renderUnauthenticated(logo: self.logo))
                    }
                    return
                }

                self.lastUsage = usage
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
            setStatusImage(BarRenderer.renderUnauthenticated(logo: logo))
            return
        }

        // Update menu bars and reset times
        sessionBarView.update(percentage: usage.fiveHourPct)
        weeklyBarView.update(percentage: usage.sevenDayPct)
        miSessionReset.title = "Resets in \(formatResetTime(usage.fiveHourReset))"
        miWeeklyReset.title = "Resets \(formatResetTimeAbsolute(usage.sevenDayReset))"

        // Update toolbar
        let pct = activeView == "five_hour" ? usage.fiveHourPct : usage.sevenDayPct
        let image = BarRenderer.render(utilization: pct, mode: displayMode, invert: invert, logo: logo)
        setStatusImage(image)
    }

    // MARK: - Menu checks

    private func updateMenuChecks() {
        miFiveHour.state = activeView == "five_hour" ? .on : .off
        miSevenDay.state = activeView == "seven_day" ? .on : .off
        miUsed.state = !invert ? .on : .off
        miRemaining.state = invert ? .on : .off
        miBarPct.state = displayMode == .barAndPct ? .on : .off
        miBarOnly.state = displayMode == .barOnly ? .on : .off
        miPctOnly.state = displayMode == .pctOnly ? .on : .off
    }

    // MARK: - Menu actions

    @objc private func setFiveHour() {
        activeView = "five_hour"
        updateMenuChecks()
        updateDisplay()
        savePrefs()
    }

    @objc private func setSevenDay() {
        activeView = "seven_day"
        updateMenuChecks()
        updateDisplay()
        savePrefs()
    }

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

    @objc private func setBarPct() {
        displayMode = .barAndPct
        updateMenuChecks()
        updateDisplay()
        savePrefs()
    }

    @objc private func setBarOnly() {
        displayMode = .barOnly
        updateMenuChecks()
        updateDisplay()
        savePrefs()
    }

    @objc private func setPctOnly() {
        displayMode = .pctOnly
        updateMenuChecks()
        updateDisplay()
        savePrefs()
    }

    @objc private func refreshNow() {
        poll()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Preferences

    private func loadPrefs() {
        let d = UserDefaults.standard
        activeView = d.string(forKey: "activeView") ?? "five_hour"
        invert = d.bool(forKey: "invert")
        if let modeStr = d.string(forKey: "displayMode"), let mode = DisplayMode(rawValue: modeStr) {
            displayMode = mode
        }
    }

    private func savePrefs() {
        let d = UserDefaults.standard
        d.set(activeView, forKey: "activeView")
        d.set(invert, forKey: "invert")
        d.set(displayMode.rawValue, forKey: "displayMode")
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
