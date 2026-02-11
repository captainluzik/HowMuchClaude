import Foundation
import os

// MARK: - API Response Models

struct QuotaData: Codable, Sendable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

struct ExtraUsageData: Codable, Sendable {
    let isEnabled: Bool?
    let monthlyLimit: Double?
    let usedCredits: Double?
    let utilization: Double?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case utilization
    }
}

struct UsageAPIResponse: Codable, Sendable {
    let fiveHour: QuotaData?
    let sevenDay: QuotaData?
    let sevenDayOauthApps: QuotaData?
    let sevenDayOpus: QuotaData?
    let sevenDaySonnet: QuotaData?
    let sevenDayCowork: QuotaData?
    let extraUsage: ExtraUsageData?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOauthApps = "seven_day_oauth_apps"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayCowork = "seven_day_cowork"
        case extraUsage = "extra_usage"
    }
}

// MARK: - Parsed Quota

struct ParsedQuota: Sendable {
    /// 0...100, percent of quota consumed
    let utilization: Double
    let resetsAt: Date?

    var percentUsed: Double { utilization }
    var percentRemaining: Double { max(0, 100.0 - utilization) }

    var resetsInText: String? {
        guard let resetsAt else { return nil }
        let seconds = resetsAt.timeIntervalSinceNow
        guard seconds > 0 else { return nil }

        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m"
        }
        return "< 1m"
    }
}

struct APIQuotas: Sendable {
    let fiveHour: ParsedQuota?
    let sevenDay: ParsedQuota?
    let sevenDayOpus: ParsedQuota?
    let sevenDaySonnet: ParsedQuota?
    let subscriptionType: String?
    let fetchedAt: Date

    static let empty = APIQuotas(
        fiveHour: nil,
        sevenDay: nil,
        sevenDayOpus: nil,
        sevenDaySonnet: nil,
        subscriptionType: nil,
        fetchedAt: .distantPast
    )

    var isValid: Bool { fiveHour != nil || sevenDay != nil }
}

// MARK: - Token Refresh Response

private struct TokenRefreshResponse: Codable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

// MARK: - Claude API Client

actor ClaudeAPIClient {

    private nonisolated static let logger = Logger(
        subsystem: "com.howmuchclaude.app",
        category: "ClaudeAPIClient"
    )

    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let refreshURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let scopes = "user:profile user:inference user:sessions:claude_code"
    private static let refreshBufferMs: Double = 5 * 60 * 1000

    private let keychainService: String
    private let timeout: TimeInterval

    private var cachedAccessToken: String?
    private var cachedRefreshToken: String?
    private var cachedExpiresAt: Double?
    private var cachedSubscriptionType: String?
    private var cachedFullData: [String: Any]?

    init(
        keychainService: String = "Claude Code-credentials",
        timeout: TimeInterval = 15
    ) {
        self.keychainService = keychainService
        self.timeout = timeout
    }

    // MARK: - Public API

    func fetchQuotas() async -> APIQuotas {
        do {
            try loadCredentialsIfNeeded()

            if needsTokenRefresh() {
                Self.logger.info("Token expiring soon, refreshing...")
                try await refreshToken()
            }

            guard let accessToken = cachedAccessToken else {
                Self.logger.error("No access token available")
                return .empty
            }

            let response = try await callUsageAPI(accessToken: accessToken)
            let quotas = parseResponse(response)

            let fiveHPct = quotas.fiveHour?.percentUsed ?? -1
            let sevenDPct = quotas.sevenDay?.percentUsed ?? -1
            Self.logger.info("Quotas fetched — 5h: \(fiveHPct, privacy: .public)%, 7d: \(sevenDPct, privacy: .public)%")

            return quotas

        } catch {
            Self.logger.error("Quota fetch failed: \(error.localizedDescription, privacy: .public)")
            return .empty
        }
    }

    // MARK: - Credential Loading

    private func loadCredentialsIfNeeded() throws {
        if cachedAccessToken != nil { return }

        if let keychainData = loadFromKeychain() {
            applyCredentials(keychainData)
            return
        }

        if let fileData = loadFromFile() {
            applyCredentials(fileData)
            return
        }

        throw APIClientError.noCredentials
    }

    private func loadFromKeychain() -> [String: Any]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", keychainService, "-w"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let jsonString = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !jsonString.isEmpty,
                  let jsonData = jsonString.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            else { return nil }

            return json
        } catch {
            return nil
        }
    }

    private func loadFromFile() -> [String: Any]? {
        let path = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".claude/.credentials.json")

        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        return json
    }

    private func applyCredentials(_ json: [String: Any]) {
        guard let oauth = json["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String,
              !accessToken.isEmpty
        else { return }

        cachedAccessToken = accessToken
        cachedRefreshToken = oauth["refreshToken"] as? String
        cachedExpiresAt = oauth["expiresAt"] as? Double
        cachedSubscriptionType = oauth["subscriptionType"] as? String
        cachedFullData = json
    }

    // MARK: - Token Refresh

    private func needsTokenRefresh() -> Bool {
        guard let expiresAt = cachedExpiresAt else { return true }
        let nowMs = Date().timeIntervalSince1970 * 1000
        return nowMs + Self.refreshBufferMs >= expiresAt
    }

    private func refreshToken() async throws {
        guard let refreshToken = cachedRefreshToken else {
            throw APIClientError.noRefreshToken
        }

        var request = URLRequest(url: Self.refreshURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID,
            "scope": Self.scopes,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        guard httpResponse.statusCode >= 200, httpResponse.statusCode < 300 else {
            cachedAccessToken = nil
            throw APIClientError.tokenRefreshFailed(httpResponse.statusCode)
        }

        let refreshResponse = try JSONDecoder().decode(TokenRefreshResponse.self, from: data)

        guard let newAccessToken = refreshResponse.accessToken, !newAccessToken.isEmpty else {
            throw APIClientError.invalidResponse
        }

        cachedAccessToken = newAccessToken
        if let newRefreshToken = refreshResponse.refreshToken {
            cachedRefreshToken = newRefreshToken
        }
        if let expiresIn = refreshResponse.expiresIn {
            cachedExpiresAt = Date().timeIntervalSince1970 * 1000 + Double(expiresIn) * 1000
        }

        saveCredentials()
    }

    private func saveCredentials() {
        guard var fullData = cachedFullData else { return }

        var oauthDict: [String: Any] = [:]
        if let token = cachedAccessToken { oauthDict["accessToken"] = token }
        if let refresh = cachedRefreshToken { oauthDict["refreshToken"] = refresh }
        if let expires = cachedExpiresAt { oauthDict["expiresAt"] = expires }
        if let sub = cachedSubscriptionType { oauthDict["subscriptionType"] = sub }
        fullData["claudeAiOauth"] = oauthDict

        guard let jsonData = try? JSONSerialization.data(
            withJSONObject: fullData,
            options: [.prettyPrinted]
        ),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else { return }

        let deleteProcess = Process()
        deleteProcess.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        deleteProcess.arguments = ["delete-generic-password", "-s", keychainService]
        deleteProcess.standardOutput = Pipe()
        deleteProcess.standardError = Pipe()
        try? deleteProcess.run()
        deleteProcess.waitUntilExit()

        let addProcess = Process()
        addProcess.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        addProcess.arguments = ["add-generic-password", "-s", keychainService, "-w", jsonString]
        addProcess.standardOutput = Pipe()
        addProcess.standardError = Pipe()
        try? addProcess.run()
        addProcess.waitUntilExit()
    }

    // MARK: - Usage API Call

    private func callUsageAPI(accessToken: String) async throws -> UsageAPIResponse {
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue(
            "Bearer \(accessToken.trimmingCharacters(in: .whitespaces))",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("HowMuchClaude", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401, 403:
            cachedAccessToken = nil
            throw APIClientError.authenticationRequired
        default:
            throw APIClientError.httpError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(UsageAPIResponse.self, from: data)
    }

    // MARK: - Response Parsing

    private func parseResponse(_ response: UsageAPIResponse) -> APIQuotas {
        APIQuotas(
            fiveHour: parseQuota(response.fiveHour),
            sevenDay: parseQuota(response.sevenDay),
            sevenDayOpus: parseQuota(response.sevenDayOpus),
            sevenDaySonnet: parseQuota(response.sevenDaySonnet),
            subscriptionType: cachedSubscriptionType,
            fetchedAt: Date()
        )
    }

    private func parseQuota(_ data: QuotaData?) -> ParsedQuota? {
        guard let data, let utilization = data.utilization else { return nil }
        return ParsedQuota(
            utilization: utilization,
            resetsAt: parseISO8601(data.resetsAt)
        )
    }

    private func parseISO8601(_ string: String?) -> Date? {
        guard let string else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

// MARK: - Errors

enum APIClientError: Error, LocalizedError {
    case noCredentials
    case noRefreshToken
    case invalidResponse
    case authenticationRequired
    case tokenRefreshFailed(Int)
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .noCredentials:
            return "No Claude credentials found. Run `claude` CLI to authenticate."
        case .noRefreshToken:
            return "No refresh token. Re-authenticate with `claude` CLI."
        case .invalidResponse:
            return "Invalid API response."
        case .authenticationRequired:
            return "Authentication expired. Re-authenticate with `claude` CLI."
        case .tokenRefreshFailed(let code):
            return "Token refresh failed (HTTP \(code))."
        case .httpError(let code):
            return "API error (HTTP \(code))."
        }
    }
}
