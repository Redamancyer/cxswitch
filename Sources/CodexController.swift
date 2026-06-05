import AppKit
import Foundation

private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    func set(_ process: Process) {
        lock.withLock {
            self.process = process
        }
    }

    func clear() {
        lock.withLock {
            process = nil
        }
    }

    func terminate() {
        lock.withLock {
            guard let process, process.isRunning else { return }
            process.terminate()
        }
    }
}

struct CodexController {
    let fileManager = FileManager.default

    var codexHome: URL {
        fileManager.homeDirectoryForCurrentUser.appending(path: ".codex", directoryHint: .isDirectory)
    }

    var authURL: URL {
        codexHome.appending(path: "auth.json")
    }

    var configURL: URL {
        codexHome.appending(path: "config.toml")
    }

    var codexExecutable: URL {
        URL(filePath: "/Applications/Codex.app/Contents/Resources/codex")
    }

    func readCurrentAuth() throws -> Data {
        guard fileManager.fileExists(atPath: authURL.path) else {
            throw CXSwitchError.authMissing(authURL)
        }
        let data = try Data(contentsOf: authURL)
        _ = try AuthDocument.validate(data)
        return data
    }

    func writeCurrentAuth(_ data: Data) throws {
        _ = try AuthDocument.validate(data)
        try fileManager.createDirectory(at: codexHome, withIntermediateDirectories: true)

        let temporary = codexHome.appending(path: ".auth.json.cxswitch-\(UUID().uuidString)")
        try data.write(to: temporary, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)

        if fileManager.fileExists(atPath: authURL.path) {
            _ = try fileManager.replaceItemAt(authURL, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: authURL)
        }
    }

    func ensureFileCredentialStorage() throws {
        try fileManager.createDirectory(at: codexHome, withIntermediateDirectories: true)
        let setting = "cli_auth_credentials_store = \"file\""
        let existing = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let pattern = #"(?m)^\s*cli_auth_credentials_store\s*=.*$"#

        let updated: String
        if let regex = try? NSRegularExpression(pattern: pattern),
           regex.firstMatch(
               in: existing,
               range: NSRange(existing.startIndex..., in: existing)
           ) != nil {
            updated = regex.stringByReplacingMatches(
                in: existing,
                range: NSRange(existing.startIndex..., in: existing),
                withTemplate: setting
            )
        } else {
            let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
            updated = existing + separator + setting + "\n"
        }

        guard updated != existing else { return }
        try updated.write(to: configURL, atomically: true, encoding: .utf8)
    }

    func currentAccountID() throws -> String? {
        let data = try readCurrentAuth()
        return try AuthDocument.validate(data).accountID
    }

    @MainActor
    func quitCodex() async throws {
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == "com.openai.codex"
        }
        running.forEach { _ = $0.terminate() }

        if await waitUntilCodexStops() {
            return
        }

        try terminateRemainingCodexProcesses()
        if await waitUntilCodexStops() {
            return
        }

        throw CXSwitchError.codexStillRunning
    }

    @MainActor
    private func waitUntilCodexStops() async -> Bool {
        for _ in 0..<50 {
            if !isCodexRunning() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }

    @MainActor
    private func isCodexRunning() -> Bool {
        if NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleIdentifier == "com.openai.codex"
        }) {
            return true
        }

        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/pgrep")
        process.arguments = ["-f", "^/Applications/Codex\\.app/"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return true
        }
    }

    private func terminateRemainingCodexProcesses() throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/pkill")
        process.arguments = ["-TERM", "-f", "^/Applications/Codex\\.app/"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
            throw CXSwitchError.processFailed("无法完全关闭 Codex。")
        }
    }

    @MainActor
    func launchCodex() {
        let appURL = URL(filePath: "/Applications/Codex.app")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }

    static func loginInTemporaryHome() async throws -> Data {
        let fileManager = FileManager.default
        let temporaryHome = fileManager.temporaryDirectory
            .appending(path: "cxswitch-login-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: temporaryHome, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryHome) }

        let process = Process()
        process.executableURL = URL(filePath: "/Applications/Codex.app/Contents/Resources/codex")
        process.arguments = [
            "login",
            "-c", "cli_auth_credentials_store=\"file\""
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = temporaryHome.path
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let output = try await run(process, pipe: pipe)
        try Task.checkCancellation()

        guard process.terminationStatus == 0 else {
            let message = String(decoding: output, as: UTF8.self)
            throw CXSwitchError.processFailed(message.isEmpty ? "登录未完成。" : message)
        }

        let authURL = temporaryHome.appending(path: "auth.json")
        guard fileManager.fileExists(atPath: authURL.path) else {
            throw CXSwitchError.authMissing(authURL)
        }
        let data = try Data(contentsOf: authURL)
        _ = try AuthDocument.validate(data)
        return data
    }

    static func testAuthInTemporaryHome(_ data: Data) async throws -> AuthIdentity {
        let identity = try AuthDocument.validate(data)
        let fileManager = FileManager.default
        let temporaryHome = fileManager.temporaryDirectory
            .appending(path: "cxswitch-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: temporaryHome, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryHome) }

        let authURL = temporaryHome.appending(path: "auth.json")
        try data.write(to: authURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authURL.path)

        let process = Process()
        process.executableURL = URL(filePath: "/Applications/Codex.app/Contents/Resources/codex")
        process.arguments = [
            "login",
            "status",
            "-c", "cli_auth_credentials_store=\"file\""
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = temporaryHome.path
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let output = try await run(process, pipe: pipe)
        try Task.checkCancellation()

        guard process.terminationStatus == 0 else {
            let message = String(decoding: output, as: UTF8.self)
            throw CXSwitchError.processFailed(message.isEmpty ? "账户测试失败。" : message)
        }

        return identity
    }

    private static func run(_ process: Process, pipe: Pipe) async throws -> Data {
        let box = ProcessBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                box.set(process)
                process.terminationHandler = { _ in
                    let output = pipe.fileHandleForReading.readDataToEndOfFile()
                    box.clear()
                    continuation.resume(returning: output)
                }

                do {
                    try process.run()
                    if Task.isCancelled {
                        box.terminate()
                    }
                } catch {
                    box.clear()
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            box.terminate()
        }
    }
}
