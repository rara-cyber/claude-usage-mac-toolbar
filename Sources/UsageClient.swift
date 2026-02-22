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

    /// Read the OAuth token from macOS Keychain (stored by Claude Code).
    func getToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecAttrAccount as String: NSUserName(),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty
        else {
            cachedToken = nil
            return nil
        }

        cachedToken = token
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
