import Foundation
import Security

struct UsageData {
    let fiveHourPct: Double
    let fiveHourReset: String?
    let sevenDayPct: Double
    let sevenDayReset: String?
}

class UsageClient {
    private static let apiURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private var cachedToken: String?
    private(set) var consecutiveErrors = 0

    var isAuthenticated: Bool { cachedToken != nil }
    var isBackedOff: Bool { consecutiveErrors >= 3 }

    /// Read the OAuth token stored by Claude Code. Prefer the `security` CLI: Claude Code
    /// resets the Keychain item's partition list to `apple-tool:` on every token refresh,
    /// which wipes any "Always Allow" grant our app earns — so a native SecItemCopyMatching
    /// re-prompts for the login password roughly daily. Apple's own `/usr/bin/security` is in
    /// the item's ACL with `don't-require-password`, so it reads the token with no prompt and
    /// survives every refresh. Fall back to the native API only if the CLI can't produce a token.
    func getToken() -> String? {
        if let token = tokenViaSecurityCLI() ?? tokenViaKeychainAPI() {
            cachedToken = token
            return token
        }
        cachedToken = nil
        return nil
    }

    private func tokenViaSecurityCLI() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        task.arguments = ["find-generic-password", "-s", "Claude Code-credentials",
                          "-a", NSUserName(), "-w"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return nil }
        // ponytail: 5s kill-switch; login keychain is normally unlocked, token blob is tiny (<1KB)
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            if task.isRunning { task.terminate() }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        return accessToken(from: data)
    }

    private func tokenViaKeychainAPI() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecAttrAccount as String: NSUserName(),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return accessToken(from: data)
    }

    private func accessToken(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty
        else { return nil }
        return token
    }

    /// Fetch usage from the Anthropic OAuth endpoint. Synchronous (call from background).
    func fetchUsage() -> UsageData? {
        guard let token = cachedToken ?? getToken() else {
            consecutiveErrors = 0
            return nil
        }

        guard let data = request(token: token) else {
            // Try refreshing token on failure (Claude Code may have rotated it)
            cachedToken = nil
            guard let newToken = getToken(), let data = request(token: newToken) else {
                consecutiveErrors += 1
                return nil
            }
            return parse(data)
        }

        return parse(data)
    }

    private func request(token: String) -> Data? {
        var req = URLRequest(url: Self.apiURL)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.timeoutInterval = 10

        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?

        let task = URLSession.shared.dataTask(with: req) { data, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                responseData = data
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        return responseData
    }

    private func parse(_ data: Data) -> UsageData? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            consecutiveErrors += 1
            return nil
        }

        let fiveHour = json["five_hour"] as? [String: Any]
        let sevenDay = json["seven_day"] as? [String: Any]

        consecutiveErrors = 0

        return UsageData(
            fiveHourPct: fiveHour?["utilization"] as? Double ?? 0,
            fiveHourReset: fiveHour?["resets_at"] as? String,
            sevenDayPct: sevenDay?["utilization"] as? Double ?? 0,
            sevenDayReset: sevenDay?["resets_at"] as? String
        )
    }
}
