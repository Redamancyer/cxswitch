import AppKit
import SwiftUI

struct AccountMenuView: View {
    @EnvironmentObject private var store: AccountStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CXSwitch")
                    .font(.title3.weight(.semibold))
                Text("共享本地会话，仅切换账户")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if store.isBusy || store.isRefreshingUsage {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            HStack(spacing: 8) {
                Button("导入当前账户") {
                    store.importCurrentAccount()
                }
                .buttonStyle(FeedbackButtonStyle(kind: .normal))
                .disabled(store.isBusy)

                Button("添加账户") {
                    store.addAccount()
                }
                .buttonStyle(FeedbackButtonStyle(kind: .normal))
                .disabled(store.isBusy)

                Button("更新用量") {
                    store.refreshUsage()
                }
                .buttonStyle(FeedbackButtonStyle(kind: .normal))
                .disabled(store.accounts.isEmpty || store.isBusy || store.isRefreshingUsage)

                if store.canCancelBusyOperation {
                    Button("取消") {
                        store.cancelCurrentOperation()
                    }
                    .buttonStyle(FeedbackButtonStyle(kind: .destructive))
                }

                Spacer()

                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(FeedbackButtonStyle(kind: .destructive))
            }

            Divider()

            if store.accounts.isEmpty {
                ContentUnavailableView(
                    "尚未添加账户",
                    systemImage: "person.crop.circle.badge.plus",
                    description: Text("先导入当前 Codex 账户，再添加其他账户。")
                )
                .frame(height: 130)
            } else {
                if store.accounts.count > 3 {
                    ScrollView {
                        accountList
                    }
                    .frame(height: accountListHeight(for: 3))
                } else {
                    accountList
                }
            }

            if let status = store.statusMessage {
                Label(status, systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let error = store.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

        }
        .padding(14)
        .frame(width: 400)
        .onAppear {
            store.reloadState()
        }
    }

    private var accountList: some View {
        LazyVStack(spacing: 6) {
            ForEach(store.accounts) { account in
                AccountRow(account: account)
            }
        }
    }

    private func accountListHeight(for rowCount: Int) -> CGFloat {
        let rows = CGFloat(rowCount) * 132
        let spacing = CGFloat(max(rowCount - 1, 0)) * 6
        return rows + spacing
    }
}

private struct AccountRow: View {
    @EnvironmentObject private var store: AccountStore
    @State private var isConfirmingSwitch = false
    @State private var isHovered = false
    @State private var isSettingSubscriptionDate = false
    @State private var draftSubscriptionDate = Date()
    let account: AccountRecord

    var isActive: Bool { store.activeAccountID == account.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "person.crop.circle")
                    .font(.title2)
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayName)
                        .font(.title3)
                        .fontWeight(isActive ? .semibold : .regular)
                        .foregroundStyle(.primary)
                    if let email = account.email, email != account.displayName {
                        Text(email)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isActive {
                    Text("当前")
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else if isConfirmingSwitch {
                    Button("退出 Codex 并切换") {
                        isConfirmingSwitch = false
                        store.switchAccount(to: account)
                    }
                    .buttonStyle(FeedbackButtonStyle(kind: .prominent))
                    .controlSize(.small)
                    .disabled(store.isBusy)

                    Button("取消") {
                        isConfirmingSwitch = false
                    }
                    .buttonStyle(FeedbackButtonStyle(kind: .normal))
                    .controlSize(.small)
                    .disabled(store.isBusy)
                } else {
                    Button("切换") {
                        isConfirmingSwitch = true
                    }
                    .buttonStyle(FeedbackButtonStyle(kind: .prominent))
                    .controlSize(.small)
                    .disabled(store.isBusy)
                }
            }

            UsageSummaryView(usage: account.usage)
                .environment(\.isAccountRowHovered, isHovered)

            HStack {
                Button("测试") {
                    store.test(account)
                }
                .buttonStyle(FeedbackButtonStyle(kind: .normal))
                .controlSize(.small)
                .disabled(store.isBusy)

                Button("重新认证") {
                    store.reauthenticate(account)
                }
                .buttonStyle(FeedbackButtonStyle(kind: .normal))
                .controlSize(.small)
                .disabled(store.isBusy)

                Button("删除", role: .destructive) {
                    store.remove(account)
                }
                .buttonStyle(FeedbackButtonStyle(kind: .destructive))
                .controlSize(.small)
                .disabled(store.isBusy || isActive)

                Spacer()

                Text("订阅到期：")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button(subscriptionExpirationText) {
                    draftSubscriptionDate = account.subscriptionExpiresAt ?? Date()
                    isSettingSubscriptionDate = true
                }
                .buttonStyle(FeedbackButtonStyle(kind: .normal))
                .controlSize(.small)
                .popover(isPresented: $isSettingSubscriptionDate) {
                    SubscriptionExpirationEditor(
                        date: $draftSubscriptionDate,
                        hasExistingDate: account.subscriptionExpiresAt != nil,
                        onClear: {
                            store.setSubscriptionExpiration(for: account, to: nil)
                            isSettingSubscriptionDate = false
                        },
                        onSave: {
                            store.setSubscriptionExpiration(for: account, to: draftSubscriptionDate)
                            isSettingSubscriptionDate = false
                        }
                    )
                }
            }
        }
        .padding(9)
        .padding(.vertical, 4)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 9))
        .animation(.snappy(duration: 0.12), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            if !isActive {
                Button("删除", role: .destructive) {
                    store.remove(account)
                }
            }
        }
    }

    private var rowBackground: Color {
        isHovered ? Color.gray.opacity(0.32) : Color.secondary.opacity(0.10)
    }

    private var subscriptionExpirationText: String {
        guard let date = account.subscriptionExpiresAt else { return "----/--/--" }
        return formatSubscriptionDate(date)
    }
}

private struct SubscriptionExpirationEditor: View {
    @Binding var date: Date
    let hasExistingDate: Bool
    let onClear: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker("订阅到期", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)

            HStack {
                Button("清空") {
                    onClear()
                }
                .buttonStyle(FeedbackButtonStyle(kind: .normal))
                .disabled(!hasExistingDate)

                Spacer()

                Button("完成") {
                    onSave()
                }
                .buttonStyle(FeedbackButtonStyle(kind: .prominent))
            }
        }
        .padding(12)
        .frame(width: 280)
    }
}

private struct UsageSummaryView: View {
    @Environment(\.isAccountRowHovered) private var isRowHovered
    let usage: AccountUsageSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let error = usage?.error {
                Label("用量更新失败：\(trimmed(error))", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            } else if let usage {
                HStack(spacing: 8) {
                    UsagePill(title: "5小时", window: usage.fiveHour)
                        .frame(width: 150)
                    UsagePill(title: "每周", window: usage.weekly)
                        .frame(maxWidth: .infinity)
                }

            } else {
                Text("用量尚未更新")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary.opacity(0.70))
            }
        }
    }

    private func trimmed(_ message: String) -> String {
        let compact = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return compact.count > 80 ? String(compact.prefix(80)) + "…" : compact
    }
}

private struct UsagePill: View {
    @Environment(\.isAccountRowHovered) private var isRowHovered
    let title: String
    let window: UsageWindowSnapshot?

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(isRowHovered ? Color.gray.opacity(0.26) : Color.secondary.opacity(0.10))

            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.green.opacity(1.0),
                                    Color.green.opacity(isRowHovered ? 0.86 : 0.76)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    Capsule()
                        .fill(Color.white.opacity(isRowHovered ? 0.34 : 0.28))
                        .frame(height: max(proxy.size.height * 0.22, 1))
                        .padding(.horizontal, 1)
                        .padding(.top, 1)
                }
                .frame(width: proxy.size.width * progress)
                .shadow(color: Color.black.opacity(0.10), radius: 0.8, x: 0, y: 0.6)
            }
            .clipShape(Capsule())

            HStack(spacing: 4) {
                Text(title)
                    .foregroundStyle(.secondary)
                Text(remainingText)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text(resetText)
                    .foregroundStyle(Color.secondary.opacity(0.70))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progress: CGFloat {
        guard let window else { return 0 }
        return CGFloat(min(max(window.remainingPercent / 100, 0), 1))
    }

    private var remainingText: String {
        guard let window else { return "未知" }
        return "\(Int(window.remainingPercent.rounded()))%"
    }

    private var resetText: String {
        guard let resetAt = window?.resetAt else { return "" }
        return "重置 \(formatShortTime(resetAt))"
    }
}

private func formatShortTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.dateStyle = Calendar.current.isDateInToday(date) ? .none : .short
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

private func formatSubscriptionDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.dateStyle = .short
    formatter.timeStyle = .none
    return formatter.string(from: date)
}

struct SettingsView: View {
    @EnvironmentObject private var store: AccountStore

    var body: some View {
        Form {
            Section("共享数据") {
                Text("所有账户共用同一个 ~/.codex。切换时仅替换 auth.json，不修改会话、配置、插件、Skills、Memories 或 SQLite 状态。")
                Button("在 Finder 中打开 ~/.codex") {
                    store.openSharedCodexHome()
                }
                .buttonStyle(FeedbackButtonStyle(kind: .normal))
                Button("在 Finder 中打开 ~/.cxswitch") {
                    store.openCXSwitchHome()
                }
                .buttonStyle(FeedbackButtonStyle(kind: .normal))
            }

            Section("安全提示") {
                Text("切换会先退出 Codex，并保存当前账户刷新后的凭据。不要在任务运行中切换。使用新账户继续旧会话时，会话上下文将发送到新账户对应的工作区。")
            }

            Section {
                Button("退出 CXSwitch") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(FeedbackButtonStyle(kind: .destructive))
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 520, height: 360)
    }
}

private struct AccountRowHoveredKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var isAccountRowHovered: Bool {
        get { self[AccountRowHoveredKey.self] }
        set { self[AccountRowHoveredKey.self] = newValue }
    }
}

private enum FeedbackButtonKind {
    case normal
    case prominent
    case destructive
}

private struct FeedbackButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let kind: FeedbackButtonKind

    func makeBody(configuration: Configuration) -> some View {
        FeedbackButtonBody(configuration: configuration, kind: kind, isEnabled: isEnabled)
    }
}

private struct FeedbackButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let kind: FeedbackButtonKind
    let isEnabled: Bool
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .foregroundStyle(foregroundColor)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(borderColor, lineWidth: isHovered ? 1.5 : 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : (isHovered ? 1.03 : 1))
            .brightness(configuration.isPressed ? -0.06 : 0)
            .opacity(isEnabled ? 1 : 0.42)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
            .animation(.snappy(duration: 0.12), value: isHovered)
            .animation(.snappy(duration: 0.12), value: isEnabled)
            .onHover { hovering in
                isHovered = hovering
            }
    }

    private var foregroundColor: Color {
        if isHovered && isEnabled {
            return .white
        }
        switch kind {
        case .normal:
            return .primary
        case .prominent:
            return .white
        case .destructive:
            return .red
        }
    }

    private var backgroundColor: Color {
        if isHovered && isEnabled && kind != .destructive && !configuration.isPressed {
            return Color.accentColor
        }
        switch kind {
        case .normal:
            if configuration.isPressed { return Color.accentColor.opacity(0.24) }
            return Color.secondary.opacity(0.12)
        case .prominent:
            if configuration.isPressed { return Color.accentColor.opacity(0.78) }
            return Color.accentColor
        case .destructive:
            if configuration.isPressed { return Color.red.opacity(0.24) }
            return isHovered && isEnabled ? Color.red : Color.red.opacity(0.10)
        }
    }

    private var borderColor: Color {
        if isHovered && isEnabled && kind != .destructive {
            return Color.accentColor.opacity(0.95)
        }
        switch kind {
        case .normal:
            if configuration.isPressed { return Color.accentColor.opacity(0.60) }
            return Color.secondary.opacity(0.22)
        case .prominent:
            return Color.accentColor.opacity(configuration.isPressed ? 0.95 : 0.70)
        case .destructive:
            return Color.red.opacity(configuration.isPressed || isHovered ? 0.70 : 0.35)
        }
    }
}
