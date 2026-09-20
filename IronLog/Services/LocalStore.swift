import Foundation
import CryptoKit
import Security

actor LocalStore {
    private let directory: URL
    private let legacyURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
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
    func migrateLegacyStoreIfNeeded(to ownerID: String) {
        let destination = url(ownerID: ownerID)
        guard FileManager.default.fileExists(atPath: legacyURL.path),
              !FileManager.default.fileExists(atPath: destination.path) else { return }
        try? FileManager.default.moveItem(at: legacyURL, to: destination)
    }

    func load(ownerID: String? = nil) -> AppSnapshot {
        let url = url(ownerID: ownerID)
        guard let data = try? Data(contentsOf: url) else { return AppSnapshot() }
        return (try? decoder.decode(AppSnapshot.self, from: data)) ?? AppSnapshot()
    }

    func save(_ snapshot: AppSnapshot, ownerID: String? = nil) {
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url(ownerID: ownerID), options: [.atomic])
    }

    func clear(ownerID: String? = nil) {
        try? FileManager.default.removeItem(at: url(ownerID: ownerID))
    }

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
