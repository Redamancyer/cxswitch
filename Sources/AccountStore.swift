import Foundation
import SwiftUI

@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var accounts: [AccountRecord] = []
    @Published private(set) var activeAccountID: UUID?
    @Published var isBusy = false
    @Published var isRefreshingUsage = false
    @Published private(set) var canCancelBusyOperation = false
    @Published var statusMessage: String?
    @Published var lastError: String?

    private let vault = FileVault()
    private let codex = CodexController()
    private let usageClient = UsageClient()
    private let fileManager = FileManager.default
    private var currentOperationTask: Task<Void, Never>?

    private var legacyStateURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "CXSwitch", directoryHint: .isDirectory)
        return base.appending(path: "accounts.json")
    }

    var activeAccount: AccountRecord? {
        accounts.first { $0.id == activeAccountID }
    }

    init() {
        reloadState()
    }

    func reloadState() {
        loadState()
        identifyActiveAccount()
    }

    func importCurrentAccount() {
        perform("正在导入当前账户…") {
            let data = try self.codex.readCurrentAuth()
            let identity = try AuthDocument.validate(data)
            _ = try self.upsert(data: data, identity: identity, makeActive: true)
            self.statusMessage = "已导入 \(identity.suggestedName)"
        }
    }

    func addAccount() {
        perform("会拉起最近点击的默认浏览器窗口，请在浏览器中完成登陆~", allowsCancellation: true) {
            let data = try await CodexController.loginInTemporaryHome()
            let identity = try AuthDocument.validate(data)
            let accountID = try self.upsert(data: data, identity: identity, makeActive: false)
            self.statusMessage = "已添加 \(identity.suggestedName)，正在更新用量…"
            await self.refreshUsage(
                for: accountID,
                successMessage: { "已添加 \($0)，用量已更新" },
                failureMessage: { "已添加 \($0)，用量更新失败" }
            )
        }
    }

    func switchAccount(to account: AccountRecord) {
        guard account.id != activeAccountID else { return }
        perform("正在切换到 \(account.displayName)…") {
            try await self.codex.quitCodex()

            if let activeAccountID = self.activeAccountID,
               let currentData = try? self.codex.readCurrentAuth() {
                try self.vault.save(currentData, for: activeAccountID)
            }

            guard let targetData = try self.vault.load(for: account.id) else {
                throw CXSwitchError.accountCredentialMissing
            }
            try self.codex.ensureFileCredentialStorage()
            try self.codex.writeCurrentAuth(targetData)

            let writtenAccountID = try self.codex.currentAccountID()
            if let expectedAccountID = account.accountID,
               writtenAccountID != expectedAccountID {
                throw CXSwitchError.processFailed("目标账户凭据校验失败，Codex 未启动。")
            }

            self.activeAccountID = account.id
            self.touch(account.id)
            try self.saveState()
            self.codex.launchCodex()
            self.statusMessage = "已切换到 \(account.displayName)，Codex 已重新启动"
        }
    }

    func refreshUsage() {
        performUsageRefresh(message: "正在更新所有账户用量…")
    }

    private func performUsageRefresh(message: String) {
        guard !isRefreshingUsage else { return }
        isRefreshingUsage = true
        statusMessage = message
        lastError = nil

        Task {
            defer { isRefreshingUsage = false }
            var successCount = 0

            for account in accounts {
                let snapshot: AccountUsageSnapshot
                do {
                    guard let data = try vault.load(for: account.id) else {
                        throw CXSwitchError.accountCredentialMissing
                    }
                    snapshot = try await usageClient.fetch(authData: data)
                    successCount += 1
                } catch {
                    snapshot = AccountUsageSnapshot(
                        fiveHour: nil,
                        weekly: nil,
                        updatedAt: Date(),
                        error: error.localizedDescription
                    )
                }

                if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                    accounts[index].usage = snapshot
                }
            }

            try? saveState()
            let updatedAt = DateFormatter.localizedString(
                from: Date(),
                dateStyle: .none,
                timeStyle: .short
            )
            statusMessage = successCount == accounts.count
                ? "用量已更新：\(updatedAt)"
                : "用量已部分更新：\(successCount)/\(accounts.count)，\(updatedAt)"
        }
    }

    private func refreshUsage(
        for accountID: UUID,
        successMessage: @escaping (String) -> String,
        failureMessage: @escaping (String) -> String
    ) async {
        guard !isRefreshingUsage else { return }
        isRefreshingUsage = true
        lastError = nil
        defer { isRefreshingUsage = false }

        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        let displayName = accounts[index].displayName
        let snapshot: AccountUsageSnapshot

        do {
            guard let data = try vault.load(for: accountID) else {
                throw CXSwitchError.accountCredentialMissing
            }
            snapshot = try await usageClient.fetch(authData: data)
            statusMessage = successMessage(displayName)
        } catch {
            snapshot = AccountUsageSnapshot(
                fiveHour: nil,
                weekly: nil,
                updatedAt: Date(),
                error: error.localizedDescription
            )
            statusMessage = failureMessage(displayName)
        }

        accounts[index].usage = snapshot
        try? saveState()
    }

    func test(_ account: AccountRecord) {
        perform("正在测试 \(account.displayName)…") {
            guard let data = try self.vault.load(for: account.id) else {
                throw CXSwitchError.accountCredentialMissing
            }

            let identity = try await CodexController.testAuthInTemporaryHome(data)
            self.statusMessage = "测试通过：\(identity.suggestedName)，正在更新用量…"
            await self.refreshUsage(
                for: account.id,
                successMessage: { "测试通过：\($0)，用量已更新" },
                failureMessage: { "测试通过：\($0)，用量更新失败" }
            )
        }
    }

    func reauthenticate(_ account: AccountRecord) {
        perform("请在浏览器中重新登录 \(account.displayName)…", allowsCancellation: true) {
            let data = try await CodexController.loginInTemporaryHome()
            let identity = try AuthDocument.validate(data)

            if let accountID = identity.accountID,
               self.accounts.contains(where: { $0.id != account.id && $0.accountID == accountID }) {
                throw CXSwitchError.processFailed("该登录身份已存在于其他账户，未覆盖当前账户。")
            }

            guard let index = self.accounts.firstIndex(where: { $0.id == account.id }) else { return }
            let oldSuggestedName = self.accounts[index].email
                ?? self.accounts[index].accountID
                ?? self.accounts[index].displayName

            try self.vault.save(data, for: account.id)
            self.accounts[index].email = identity.email
            self.accounts[index].accountID = identity.accountID
            self.accounts[index].lastUsedAt = Date()
            if self.accounts[index].displayName == oldSuggestedName {
                self.accounts[index].displayName = identity.suggestedName
            }

            if self.activeAccountID == account.id {
                try self.codex.ensureFileCredentialStorage()
                try self.codex.writeCurrentAuth(data)
            }

            try self.saveState()
            self.statusMessage = "已重新认证 \(self.accounts[index].displayName)"
        }
    }

    func rename(_ account: AccountRecord, to newName: String) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        accounts[index].displayName = trimmed
        try? saveState()
    }

    func setSubscriptionExpiration(for account: AccountRecord, to date: Date?) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index].subscriptionExpiresAt = date
        try? saveState()
    }

    func remove(_ account: AccountRecord) {
        guard account.id != activeAccountID else {
            lastError = "不能删除当前激活账户。请先切换到其他账户。"
            return
        }
        do {
            try vault.delete(for: account.id)
            accounts.removeAll { $0.id == account.id }
            try saveState()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func openSharedCodexHome() {
        NSWorkspace.shared.open(codex.codexHome)
    }

    func openCXSwitchHome() {
        try? vault.prepare()
        NSWorkspace.shared.open(vault.baseDirectory)
    }

    func cancelCurrentOperation() {
        guard canCancelBusyOperation else { return }
        statusMessage = "正在取消…"
        currentOperationTask?.cancel()
    }

    private func perform(
        _ message: String,
        allowsCancellation: Bool = false,
        operation: @escaping @MainActor () async throws -> Void
    ) {
        guard !isBusy else { return }
        isBusy = true
        canCancelBusyOperation = allowsCancellation
        statusMessage = message
        lastError = nil
        let task = Task { @MainActor in
            defer {
                isBusy = false
                canCancelBusyOperation = false
                currentOperationTask = nil
            }
            do {
                try Task.checkCancellation()
                try await operation()
            } catch is CancellationError {
                statusMessage = "已取消账号登录！"
                lastError = nil
            } catch {
                lastError = error.localizedDescription
                statusMessage = nil
            }
        }
        currentOperationTask = task
    }

    private func upsert(data: Data, identity: AuthIdentity, makeActive: Bool) throws -> UUID {
        if let accountID = identity.accountID,
           let index = accounts.firstIndex(where: { $0.accountID == accountID }) {
            try vault.save(data, for: accounts[index].id)
            accounts[index].email = identity.email
            accounts[index].lastUsedAt = Date()
            if makeActive { activeAccountID = accounts[index].id }
            try saveState()
            return accounts[index].id
        } else {
            let account = AccountRecord(
                displayName: identity.suggestedName,
                email: identity.email,
                accountID: identity.accountID
            )
            try vault.save(data, for: account.id)
            accounts.append(account)
            if makeActive { activeAccountID = account.id }
            try saveState()
            return account.id
        }
    }

    private func touch(_ id: UUID) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].lastUsedAt = Date()
    }

    private func identifyActiveAccount() {
        guard
            let data = try? codex.readCurrentAuth(),
            let identity = try? AuthDocument.validate(data)
        else { return }

        if let accountID = identity.accountID,
           let match = accounts.first(where: { $0.accountID == accountID }) {
            activeAccountID = match.id
            try? vault.save(data, for: match.id)
            try? saveState()
        }
    }

    private func loadState() {
        if let state = try? vault.loadState() {
            accounts = state.accounts
            activeAccountID = state.activeAccountID
            return
        }

        guard
            let data = try? Data(contentsOf: legacyStateURL),
            let state = try? JSONDecoder().decode(PersistedState.self, from: data)
        else { return }

        accounts = state.accounts
        activeAccountID = state.activeAccountID
        try? saveState()
    }

    private func saveState() throws {
        let state = PersistedState(accounts: accounts, activeAccountID: activeAccountID)
        try vault.saveState(state)
    }
}
