import Foundation
import CryptoKit
import Security

actor LocalStore {
    enum StoreError: LocalizedError {
        case unreadable
        case futureVersion

        var errorDescription: String? {
            switch self {
            case .unreadable: "Saved data could not be read. Setzo has stopped saving to protect it."
            case .futureVersion: "Saved data is from a newer Setzo version. Update the app before editing it."
            }
        }
    }
    private let directory: URL
    private let legacyURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private(set) var didRecoverFromBackup = false

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        // Keep the installed app's storage location so the rename preserves all accounts and drafts.
        self.directory = directory ?? base.appendingPathComponent("IronLog", isDirectory: true)
        legacyURL = self.directory.appendingPathComponent("store.json")
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    /// Move the single-store layout used by older releases into the currently
    /// authenticated account. This runs only when that account has no scoped
    /// store yet, so a guest snapshot created by a newer release is never
    /// mistaken for cloud-account data.
    func migrateLegacyStoreIfNeeded(to ownerID: String) throws {
        let destination = url(ownerID: ownerID)
        guard FileManager.default.fileExists(atPath: legacyURL.path),
              !FileManager.default.fileExists(atPath: destination.path),
              !FileManager.default.fileExists(atPath: backupURL(for: destination).path) else { return }
        _ = try load(ownerID: nil)
        try FileManager.default.moveItem(at: legacyURL, to: destination)
        let legacyBackup = backupURL(for: legacyURL)
        if FileManager.default.fileExists(atPath: legacyBackup.path) {
            try FileManager.default.moveItem(at: legacyBackup, to: backupURL(for: destination))
        }
    }

    func load(ownerID: String? = nil) throws -> AppSnapshot {
        let url = url(ownerID: ownerID)
        let backup = backupURL(for: url)
        guard FileManager.default.fileExists(atPath: url.path) else {
            guard FileManager.default.fileExists(atPath: backup.path) else { return AppSnapshot() }
            let data = try Data(contentsOf: backup)
            let snapshot = try decode(data)
            try data.write(to: url, options: .atomic)
            didRecoverFromBackup = true
            return snapshot
        }
        let data = try Data(contentsOf: url)
        do {
            return try decode(data)
        } catch StoreError.futureVersion {
            throw StoreError.futureVersion
        } catch {
            guard let backupData = try? Data(contentsOf: backup),
                  let snapshot = try? decode(backupData) else { throw StoreError.unreadable }
            let damaged = url.deletingPathExtension().appendingPathExtension("damaged-\(UUID().uuidString).json")
            try FileManager.default.moveItem(at: url, to: damaged)
            try backupData.write(to: url, options: .atomic)
            didRecoverFromBackup = true
            return snapshot
        }
    }

    func save(_ snapshot: AppSnapshot, ownerID: String? = nil, replacingBackup: Bool = false) throws {
        let destination = url(ownerID: ownerID)
        if FileManager.default.fileExists(atPath: destination.path) {
            let previous = try Data(contentsOf: destination)
            _ = try decode(previous)
            if !replacingBackup {
                try previous.write(to: backupURL(for: destination), options: .atomic)
            }
        }
        let data = try encoder.encode(snapshot)
        // A confirmed deletion must also replace the recovery copy. Writing
        // it first means a failed backup write leaves the existing primary
        // untouched and prevents the deletion from being acknowledged.
        if replacingBackup {
            try data.write(to: backupURL(for: destination), options: .atomic)
        }
        try data.write(to: destination, options: .atomic)
        if replacingBackup { try removeDamagedCopies(for: destination) }
    }

    func clear(ownerID: String? = nil) throws {
        let destination = url(ownerID: ownerID)
        let backup = backupURL(for: destination)
        if FileManager.default.fileExists(atPath: backup.path) { try FileManager.default.removeItem(at: backup) }
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try removeDamagedCopies(for: destination)
    }

    private func removeDamagedCopies(for destination: URL) throws {
        // A prior recovery may have moved a damaged snapshot aside. It still
        // contains the user's data and must go when that owner's data is deleted.
        let prefix = destination.deletingPathExtension().lastPathComponent + ".damaged-"
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        where file.lastPathComponent.hasPrefix(prefix) && file.pathExtension == "json" {
            try FileManager.default.removeItem(at: file)
        }
    }

    private func decode(_ data: Data) throws -> AppSnapshot {
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let version = root["schemaVersion"] as? Int,
           version > AppSnapshot.currentSchemaVersion { throw StoreError.futureVersion }
        return try decoder.decode(AppSnapshot.self, from: data)
    }

    private func backupURL(for url: URL) -> URL { url.appendingPathExtension("bak") }

    private func url(ownerID: String?) -> URL {
        guard let ownerID else { return legacyURL }
        let digest = SHA256.hash(data: Data(ownerID.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directory.appendingPathComponent("store-\(digest).json")
    }
}

enum KeychainStore {
    static func save(_ data: Data, service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        SecItemAdd(item as CFDictionary, nil)
    }

    static func load(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        return result as? Data
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
