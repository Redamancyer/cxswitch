import Foundation

struct FileVault: Sendable {
    private var fileManager: FileManager { .default }

    var baseDirectory: URL {
        fileManager.homeDirectoryForCurrentUser
            .appending(path: ".cxswitch", directoryHint: .isDirectory)
    }

    var stateURL: URL {
        baseDirectory.appending(path: "accounts.json")
    }

    var preferencesURL: URL {
        baseDirectory.appending(path: "preferences.json")
    }

    private var authDirectory: URL {
        baseDirectory.appending(path: "auth", directoryHint: .isDirectory)
    }

    func prepare() throws {
        try createPrivateDirectory(baseDirectory)
        try createPrivateDirectory(authDirectory)
    }

    func save(_ data: Data, for accountID: UUID) throws {
        _ = try AuthDocument.validate(data)
        try prepare()
        let url = authURL(for: accountID)
        let temporary = authDirectory.appending(path: ".\(accountID.uuidString).json.tmp")
        try data.write(to: temporary, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)

        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: url)
        }
    }

    func load(for accountID: UUID) throws -> Data? {
        let url = authURL(for: accountID)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        _ = try AuthDocument.validate(data)
        return data
    }

    func delete(for accountID: UUID) throws {
        let url = authURL(for: accountID)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func saveState(_ state: PersistedState) throws {
        try prepare()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        let temporary = baseDirectory.appending(path: ".accounts.json.tmp")
        try data.write(to: temporary, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)

        if fileManager.fileExists(atPath: stateURL.path) {
            _ = try fileManager.replaceItemAt(stateURL, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: stateURL)
        }
    }

    func loadState() throws -> PersistedState? {
        guard fileManager.fileExists(atPath: stateURL.path) else { return nil }
        let data = try Data(contentsOf: stateURL)
        return try JSONDecoder().decode(PersistedState.self, from: data)
    }

    func savePreferences(_ preferences: UserPreferences) throws {
        try prepare()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(preferences)
        let temporary = baseDirectory.appending(path: ".preferences.json.tmp")
        try data.write(to: temporary, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)

        if fileManager.fileExists(atPath: preferencesURL.path) {
            _ = try fileManager.replaceItemAt(preferencesURL, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: preferencesURL)
        }
    }

    func loadPreferences() throws -> UserPreferences? {
        guard fileManager.fileExists(atPath: preferencesURL.path) else { return nil }
        let data = try Data(contentsOf: preferencesURL)
        return try JSONDecoder().decode(UserPreferences.self, from: data)
    }

    private func authURL(for accountID: UUID) -> URL {
        authDirectory.appending(path: "\(accountID.uuidString).json")
    }

    private func createPrivateDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
}
