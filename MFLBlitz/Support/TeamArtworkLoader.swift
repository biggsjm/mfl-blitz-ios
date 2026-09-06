import Foundation
import ImageIO

enum TeamArtworkURLPolicy {
    static func allows(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.isEmpty == false
            && url.user == nil && url.password == nil
            && (url.port == nil || url.port == 443)
    }

    /// MFL often keeps artwork under an older season's URL. Preserve it exactly.
    static func candidates(icon: URL?, logo: URL?) -> [URL] {
        var result: [URL] = []
        for url in [icon, logo].compactMap({ $0 }) where allows(url) && !result.contains(url) {
            result.append(url)
        }
        return result
    }
}

protocol TeamArtworkTransport: Sendable {
    func data(from url: URL) async throws -> Data
}

/// Artwork may live outside MFL. Never reuse the authenticated API transport,
/// shared cookies, credentials, or disk cache for these optional image requests.
struct TeamArtworkNetworkTransport: TeamArtworkTransport {
    static let maximumBytes = 2 * 1_024 * 1_024
    private let session: URLSession

    init() {
        session = URLSession(configuration: Self.configuration(), delegate: ArtworkSessionDelegate(), delegateQueue: nil)
    }

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.httpMaximumConnectionsPerHost = 4
        return configuration
    }

    static func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpShouldHandleCookies = false
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        request.setValue("MFLBlitz-Artwork/1.0", forHTTPHeaderField: "User-Agent")
        return request
    }

    func data(from url: URL) async throws -> Data {
        guard TeamArtworkURLPolicy.allows(url) else { throw URLError(.unsupportedURL) }
        let (bytes, response) = try await session.bytes(for: Self.request(for: url))
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              response.mimeType?.lowercased().hasPrefix("image/") == true,
              response.expectedContentLength <= Self.maximumBytes else {
            throw URLError(.badServerResponse)
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < Self.maximumBytes else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }
}

private final class ArtworkSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        // A stale or redirected image falls back to the alternate logo/initials.
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
            ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
    }
}

actor TeamArtworkLoader {
    static let shared = TeamArtworkLoader()
    private let transport: any TeamArtworkTransport
    private let cache = NSCache<NSURL, CachedArtwork>()
    private var inFlight: [URL: Task<CGImage?, Never>] = [:]
    private var failedUntil: [URL: Date] = [:]

    init(transport: any TeamArtworkTransport = TeamArtworkNetworkTransport()) {
        self.transport = transport
        cache.countLimit = 128
        cache.totalCostLimit = 8 * 1_024 * 1_024
    }

    func image(for urls: [URL]) async -> CGImage? {
        for url in urls where TeamArtworkURLPolicy.allows(url) {
            guard !Task.isCancelled else { return nil }
            if let cached = cache.object(forKey: url as NSURL), cached.expiresAt > Date() {
                return cached.image
            }
            if let deadline = failedUntil[url], deadline > Date() { continue }
            if let task = inFlight[url] {
                if let image = await task.value { return image }
                continue
            }
            let transport = transport
            let task = Task {
                guard let data = try? await transport.data(from: url) else { return nil as CGImage? }
                return Self.thumbnail(from: data)
            }
            inFlight[url] = task
            let image = await task.value
            inFlight[url] = nil
            if let image {
                cache.setObject(CachedArtwork(image: image), forKey: url as NSURL,
                                cost: image.bytesPerRow * image.height)
                failedUntil[url] = nil
                return image
            }
            failedUntil = failedUntil.filter { $0.value > Date() }
            if failedUntil.count >= 128 { failedUntil.removeAll() }
            failedUntil[url] = Date().addingTimeInterval(60)
        }
        return nil
    }

    static func thumbnail(from data: Data) -> CGImage? {
        guard !data.isEmpty, data.count <= TeamArtworkNetworkTransport.maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData,
                  [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        // Downsample off the main actor. Use a still first frame for animated GIFs.
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 256,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }
}

private final class CachedArtwork {
    let image: CGImage
    let expiresAt = Date().addingTimeInterval(15 * 60)
    init(image: CGImage) { self.image = image }
}
