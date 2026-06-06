import Foundation

struct AccountRecord: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var displayName: String
    var email: String?
    var accountID: String?
    var createdAt: Date
    var lastUsedAt: Date
    var usage: AccountUsageSnapshot?
    var subscriptionExpiresAt: Date?

    init(
        id: UUID = UUID(),
        displayName: String,
        email: String?,
        accountID: String?,
        createdAt: Date = Date(),
        lastUsedAt: Date = Date(),
        usage: AccountUsageSnapshot? = nil,
        subscriptionExpiresAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.accountID = accountID
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.usage = usage
        self.subscriptionExpiresAt = subscriptionExpiresAt
    }
}

struct AccountUsageSnapshot: Codable, Equatable, Sendable {
    var fiveHour: UsageWindowSnapshot?
    var weekly: UsageWindowSnapshot?
    var updatedAt: Date
    var error: String?
}

struct UsageWindowSnapshot: Codable, Equatable, Sendable {
    var usedPercent: Double
    var remainingPercent: Double
    var resetAt: Date?
    var windowSeconds: Double
}

struct PersistedState: Codable, Sendable {
    var accounts: [AccountRecord]
    var activeAccountID: UUID?

    static let empty = PersistedState(accounts: [], activeAccountID: nil)
}

struct UserPreferences: Codable, Sendable {
    var showsAccountActions: Bool

    static let defaultValue = UserPreferences(showsAccountActions: true)
}

struct AuthIdentity: Equatable, Sendable {
    let email: String?
    let accountID: String?
    let mode: String

    var suggestedName: String {
        email ?? accountID ?? mode
    }
}

enum CXSwitchError: LocalizedError {
    case authMissing(URL)
    case invalidAuth
    case accountCredentialMissing
    case codexStillRunning
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .authMissing(let url):
            "找不到认证文件：\(url.path)"
        case .invalidAuth:
            "认证文件格式无效。"
        case .accountCredentialMissing:
            "所选账户的凭据不存在。"
        case .codexStillRunning:
            "Codex 未能完全退出。请结束正在执行的任务并手动退出 Codex 后重试。"
        case .processFailed(let message):
            message
        }
    }
}
