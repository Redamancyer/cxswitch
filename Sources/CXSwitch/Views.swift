import AppKit
import SwiftUI

struct AccountMenuView: View {
    @EnvironmentObject private var store: AccountStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CXSwitch")
                        .font(.title3.weight(.semibold))
                    Text("共享本地会话，仅切换账户")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
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

                Button("添加账户") {
                    store.addAccount()
                }
                .buttonStyle(FeedbackButtonStyle(kind: .prominent))

                Button("更新用量") {
                    store.refreshUsage()
                }
                .buttonStyle(FeedbackButtonStyle(kind: .normal))
                .disabled(store.accounts.isEmpty || store.isRefreshingUsage)

                Spacer()

                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(FeedbackButtonStyle(kind: .destructive))
            }
            .disabled(store.isBusy)

            Divider()

            if store.accounts.isEmpty {
                ContentUnavailableView(
                    "尚未添加账户",
                    systemImage: "person.crop.circle.badge.plus",
                    description: Text("先导入当前 Codex 账户，再添加其他账户。")
                )
                .frame(height: 130)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(store.accounts) { account in
                            AccountRow(account: account)
                        }
                    }
                }
                .frame(height: min(CGFloat(store.accounts.count) * 168, 420))
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
        .frame(width: 430)
        .onAppear {
            store.reloadState()
        }
    }
}

private struct AccountRow: View {
    @EnvironmentObject private var store: AccountStore
    @State private var isConfirmingSwitch = false
    @State private var isHovered = false
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
        isHovered ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.10)
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
                    UsagePill(title: "每周", window: usage.weekly)
                    Spacer()
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
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(remainingText)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Text(resetText)
                .foregroundStyle(Color.secondary.opacity(0.70))
        }
        .font(.subheadline)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background((isRowHovered ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.10)), in: Capsule())
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
        switch kind {
        case .normal:
            .primary
        case .prominent:
            .white
        case .destructive:
            .red
        }
    }

    private var backgroundColor: Color {
        switch kind {
        case .normal:
            if configuration.isPressed { return Color.accentColor.opacity(0.24) }
            return isHovered ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.12)
        case .prominent:
            if configuration.isPressed { return Color.accentColor.opacity(0.78) }
            return isHovered ? Color.accentColor.opacity(0.88) : Color.accentColor
        case .destructive:
            if configuration.isPressed { return Color.red.opacity(0.24) }
            return isHovered ? Color.red.opacity(0.16) : Color.red.opacity(0.10)
        }
    }

    private var borderColor: Color {
        switch kind {
        case .normal:
            if configuration.isPressed { return Color.accentColor.opacity(0.60) }
            return isHovered ? Color.accentColor.opacity(0.50) : Color.secondary.opacity(0.22)
        case .prominent:
            return Color.accentColor.opacity(configuration.isPressed || isHovered ? 0.95 : 0.70)
        case .destructive:
            return Color.red.opacity(configuration.isPressed || isHovered ? 0.70 : 0.35)
        }
    }
}
