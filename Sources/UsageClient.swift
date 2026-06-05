import Foundation

struct UsageClient: Sendable {
    private let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    func fetch(authData: Data) async throws -> AccountUsageSnapshot {
        let accessToken = try AuthDocument.accessToken(from: authData)
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CXSwitchError.processFailed("无法读取用量接口响应。")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(decoding: data, as: UTF8.self)
            throw CXSwitchError.processFailed(
                message.isEmpty ? "用量更新失败（HTTP \(http.statusCode)）。" : message
            )
        }

        let payload = try JSONDecoder().decode(UsageResponse.self, from: data)
        return payload.snapshot
    }
}

private struct UsageResponse: Decodable {
    let rateLimit: RateLimit?

    var snapshot: AccountUsageSnapshot {
        let windows = [rateLimit?.primaryWindow, rateLimit?.secondaryWindow].compactMap { $0 }
        return AccountUsageSnapshot(
            fiveHour: closestWindow(in: windows, targetSeconds: 18_000),
            weekly: closestWindow(in: windows, targetSeconds: 604_800),
            updatedAt: Date(),
            error: nil
        )
    }

    private enum CodingKeys: String, CodingKey {
        case rateLimit = "rate_limit"
    }

    private func closestWindow(in windows: [UsageWindow], targetSeconds: Double) -> UsageWindowSnapshot? {
        windows
            .filter { $0.limitWindowSeconds > 0 }
            .min { lhs, rhs in
                abs(lhs.limitWindowSeconds - targetSeconds) < abs(rhs.limitWindowSeconds - targetSeconds)
            }?
            .snapshot
    }
}

private struct RateLimit: Decodable {
    let primaryWindow: UsageWindow?
    let secondaryWindow: UsageWindow?

    private enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

private struct UsageWindow: Decodable {
    let usedPercent: Double
    let limitWindowSeconds: Double
    let resetAt: Double?

    var snapshot: UsageWindowSnapshot {
        UsageWindowSnapshot(
            usedPercent: usedPercent,
            remainingPercent: min(max(100 - usedPercent, 0), 100),
            resetAt: resetAt.map(Date.init(timeIntervalSince1970:)),
            windowSeconds: limitWindowSeconds
        )
    }

    private enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAt = "reset_at"
    }
}
