import Foundation

public struct MFLStoredResponse: Codable, Sendable {
    public let key: String
    public let data: Data
    public let fetchedAt: Date

    public init(key: String, data: Data, fetchedAt: Date = Date()) {
        self.key = key; self.data = data; self.fetchedAt = fetchedAt
    }

    func isFresh(key: String, ttl: TimeInterval, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(fetchedAt)
        return self.key == key && age.isFinite && age >= 0 && age < ttl
    }
}

/// Optional, best-effort response storage. Public players and session-scoped
/// league metadata use separate stores. Cookies and private actions never enter either.
public protocol MFLPersistentResponseCache: Sendable {
    func read() async -> MFLStoredResponse?
    func write(_ value: MFLStoredResponse) async
    func remove() async
}

public actor MFLDiskResponseCache: MFLPersistentResponseCache {
    private let fileURL: URL
    private let protected: Bool
    private static let maximumFileSize = 32 * 1_024 * 1_024

    public init(fileURL: URL, protected: Bool = false) { self.fileURL = fileURL; self.protected = protected }

    public func read() -> MFLStoredResponse? {
        guard let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= Self.maximumFileSize,
              let data = try? Data(contentsOf: fileURL),
              let value = try? JSONDecoder().decode(MFLStoredResponse.self, from: data) else { return nil }
        return value
    }

    public func write(_ value: MFLStoredResponse) {
        // Another client may have finished a newer download while this one
        // was suspended. Do not replace it with an older response.
        if let current = read(), current.key == value.key,
           current.fetchedAt <= Date(), current.fetchedAt > value.fetchedAt { return }
        guard let data = try? JSONEncoder().encode(value), data.count <= Self.maximumFileSize else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var options: Data.WritingOptions = .atomic
            #if os(iOS)
            if protected { options.insert(.completeFileProtection) }
            #endif
            try data.write(to: fileURL, options: options)
            if protected {
                var location = fileURL
                var resources = URLResourceValues()
                resources.isExcludedFromBackup = true
                try location.setResourceValues(resources)
            }
        } catch {
            // Storage is an optimization. A full/unavailable cache must not
            // prevent fresh league data from loading.
        }
    }

    public func remove() { try? FileManager.default.removeItem(at: fileURL) }
}
