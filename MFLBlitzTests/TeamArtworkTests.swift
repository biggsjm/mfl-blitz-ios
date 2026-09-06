import Foundation
import ImageIO
import Testing
@testable import MFLBlitz

private actor ArtworkFixtureTransport: TeamArtworkTransport {
    let responses: [URL: Data]
    private(set) var requests: [URL] = []

    init(responses: [URL: Data]) { self.responses = responses }

    func data(from url: URL) async throws -> Data {
        requests.append(url)
        try await Task.sleep(for: .milliseconds(10))
        guard let data = responses[url] else { throw URLError(.fileDoesNotExist) }
        return data
    }
}

struct TeamArtworkTests {
    private let icon = URL(string: "https://www45.myfantasyleague.com/fflnetdynamic2015/14025_franchise_icon0004.jpg")!
    private let logo = URL(string: "https://images.example.com/team.png")!

    @Test("Artwork keeps MFL's exact older-season URLs and prefers the compact icon")
    func candidates() {
        #expect(TeamArtworkURLPolicy.candidates(icon: icon, logo: logo) == [icon, logo])
        #expect(TeamArtworkURLPolicy.candidates(icon: icon, logo: icon) == [icon])
        #expect(TeamArtworkURLPolicy.candidates(icon: nil, logo: logo) == [logo])
        #expect(TeamArtworkURLPolicy.candidates(icon: nil, logo: nil).isEmpty)
    }

    @Test("Insecure, relative, credential-bearing and nonstandard-port artwork is skipped", arguments: [
        "http://images.example.com/logo.gif", "file:///tmp/logo.png", "data:image/png;base64,AAAA",
        "/relative/logo.jpg", "https://user:password@images.example.com/logo.jpg", "https://images.example.com:8443/logo.jpg"
    ])
    func unsafeURLs(value: String) async throws {
        let url = try #require(URL(string: value))
        #expect(!TeamArtworkURLPolicy.allows(url))
        #expect(TeamArtworkURLPolicy.candidates(icon: url, logo: logo) == [logo])
        let transport = ArtworkFixtureTransport(responses: [:])
        let loader = TeamArtworkLoader(transport: transport)
        #expect(await loader.image(for: [url]) == nil)
        #expect(await transport.requests.isEmpty)
    }

    @Test("Image requests have no cookie jar, credential store, disk cache or authentication headers")
    func isolatedNetworking() {
        let configuration = TeamArtworkNetworkTransport.configuration()
        #expect(configuration.httpCookieStorage == nil)
        #expect(!configuration.httpShouldSetCookies)
        #expect(configuration.httpCookieAcceptPolicy == .never)
        #expect(configuration.urlCredentialStorage == nil)
        #expect(configuration.urlCache == nil)
        let request = TeamArtworkNetworkTransport.request(for: icon)
        #expect(!request.httpShouldHandleCookies)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Referer") == nil)
        #expect(request.httpBody == nil)
    }

    @Test("Concurrent team marks share a request and reuse the decoded image")
    func caching() async throws {
        let transport = ArtworkFixtureTransport(responses: [icon: try fixtureImage()])
        let loader = TeamArtworkLoader(transport: transport)
        async let first = loader.image(for: [icon])
        async let second = loader.image(for: [icon])
        let images = await (first, second)
        #expect(images.0 != nil && images.1 != nil)
        #expect(await loader.image(for: [icon]) != nil)
        #expect(await transport.requests == [icon])
    }

    @Test("A missing icon uses the alternate logo; broken images retain initials without repeat requests")
    func fallbacks() async throws {
        let transport = ArtworkFixtureTransport(responses: [logo: try fixtureImage()])
        let loader = TeamArtworkLoader(transport: transport)
        #expect(await loader.image(for: [icon, logo]) != nil)
        #expect(await loader.image(for: [icon, logo]) != nil)
        #expect(await transport.requests == [icon, logo])

        let broken = ArtworkFixtureTransport(responses: [icon: Data("<html>Not an image</html>".utf8)])
        let brokenLoader = TeamArtworkLoader(transport: broken)
        #expect(await brokenLoader.image(for: [icon]) == nil)
        #expect(await brokenLoader.image(for: [icon]) == nil)
        #expect(await broken.requests == [icon])
        #expect(await brokenLoader.image(for: []) == nil)
    }

    @Test("JPEG, PNG and GIF artwork is downsampled with its aspect ratio intact", arguments: ["public.jpeg", "public.png", "com.compuserve.gif"])
    func rasterFormats(type: String) throws {
        let image = try #require(TeamArtworkLoader.thumbnail(from: fixtureImage(type: type)))
        #expect(image.width == 256)
        #expect(image.height == 128)
        #expect(TeamArtworkLoader.thumbnail(from: Data()) == nil)
        #expect(TeamArtworkLoader.thumbnail(from: Data(repeating: 0, count: TeamArtworkNetworkTransport.maximumBytes + 1)) == nil)
    }

    private func fixtureImage(type: String = "public.png") throws -> Data {
        let context = try #require(CGContext(data: nil, width: 512, height: 256, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.3, green: 0.7, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 512, height: 256))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, type as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
