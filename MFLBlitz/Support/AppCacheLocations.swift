import Foundation

enum AppCacheLocations {
    nonisolated static var leagueMetadata: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "com.biggsjm.MFLBlitz/private-metadata", directoryHint: .isDirectory)
    }
    nonisolated static var leagueDisplay: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "com.biggsjm.MFLBlitz/private-display-v1.json")
    }

    nonisolated static var players: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "com.biggsjm.MFLBlitz/public-players", directoryHint: .isDirectory)
    }
}
