import Foundation

enum AppCacheLocations {
    nonisolated static var players: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "com.biggsjm.MFLBlitz/public-players", directoryHint: .isDirectory)
    }
}
