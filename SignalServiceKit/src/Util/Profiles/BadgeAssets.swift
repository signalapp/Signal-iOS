//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import ImageIO
import CoreServices

class BadgeAssets: Dependencies {
    private let remoteSourceUrl: URL
    private let localAssetDirectory: URL

    let lock = UnfairLock()
    private var state: State = .initialized
    public var isFetching: Bool { lock.withLock { state == .fetching } }

    enum State: Equatable {
        case initialized
        case fetching
        case fetched
        case failed
        case unavailable
    }

    fileprivate enum Variant: String, CaseIterable {
        case light16
        case light24
        case light36
        case dark16
        case dark24
        case dark36
        case universal160

        var pointSize: CGSize {
            switch self {
            case .light16, .dark16: return CGSize(width: 16, height: 16)
            case .light24, .dark24: return CGSize(width: 24, height: 24)
            case .light36, .dark36: return CGSize(width: 36, height: 36)
            case .universal160: return CGSize(width: 160, height: 160)
            }
        }
    }

    required init(remoteSourceUrl: URL, localAssetDirectory: URL) {
        self.remoteSourceUrl = remoteSourceUrl
        self.localAssetDirectory = localAssetDirectory
    }

    private func fileUrlForSpritesheet() -> URL {
        localAssetDirectory.appendingPathComponent("spritesheet")
    }

    private func fileUrlForVariant(_ variant: Variant) -> URL {
        localAssetDirectory.appendingPathComponent(variant.rawValue)
    }

    // MARK: - Sprite retrieval

    var light16: UIImage? { UIImage(contentsOfFile: fileUrlForVariant(.light16).path) }
    var light24: UIImage? { UIImage(contentsOfFile: fileUrlForVariant(.light24).path) }
    var light36: UIImage? { UIImage(contentsOfFile: fileUrlForVariant(.light36).path) }
    var dark16: UIImage? { UIImage(contentsOfFile: fileUrlForVariant(.dark16).path) }
    var dark24: UIImage? { UIImage(contentsOfFile: fileUrlForVariant(.dark24).path) }
    var dark36: UIImage? { UIImage(contentsOfFile: fileUrlForVariant(.dark36).path) }
    var universal160: UIImage? { UIImage(contentsOfFile: fileUrlForVariant(.universal160).path) }

    // MARK: - Sprite fetching

    func prepareAssetsIfNecessary() {
        let shouldFetch: Bool = lock.withLock {
            // If we're already fetching, or have hit a terminal state, there's nothing left to do
            guard state != .fetching, state != .fetched, state != .unavailable else { return false }

            // If we have all our assets on disk, we're good to go
            let allAssetUrls = [fileUrlForSpritesheet()] + Variant.allCases.map { fileUrlForVariant($0) }
            guard allAssetUrls.contains(where: { OWSFileSystem.fileOrFolderExists(url: $0) == false }) else {
                Logger.debug("All badge assets available")
                state = .fetched
                return false
            }

            guard CurrentAppContext().isMainApp else {
                Logger.info("Skipping badge fetch. Not in main app.")
                state = .unavailable
                return false
            }

            state = .fetching
            return true
        }

        guard shouldFetch else { return }
        OWSFileSystem.ensureDirectoryExists(localAssetDirectory.path)
        firstly(on: .sharedUtility) { () -> Promise<Void> in
            self.fetchSpritesheetIfNecessary()
        }.map(on: .sharedUtility) { _ in
            try self.extractSpritesFromSpritesheetIfNecessary()
        }.catch(on: .sharedUtility) { error in
            owsFailDebug("Failed to fetch badge assets with error: \(error)")
            self.state = .failed
        }
    }

    private func fetchSpritesheetIfNecessary() -> Promise<Void> {
        let spriteUrl = fileUrlForSpritesheet()
        guard !OWSFileSystem.fileOrFolderExists(url: spriteUrl) else {
            return Promise.value(())
        }

        // TODO: Badges — Censorship circumvention
        let urlSession = signalService.urlSessionForMainSignalService()
        return urlSession.downloadTaskPromise(remoteSourceUrl.absoluteString, method: .get).map { result in
            let resultUrl = result.downloadUrl

            guard OWSFileSystem.fileOrFolderExists(url: resultUrl) else {
                throw OWSAssertionError("Sprite url missing")
            }
            guard NSData.ows_isValidImage(at: resultUrl, mimeType: nil) else {
                throw OWSAssertionError("Invalid sprite")
            }
            try OWSFileSystem.moveFile(from: resultUrl, to: spriteUrl)
        }
    }

    private func extractSpritesFromSpritesheetIfNecessary() throws {
        guard NSData.ows_isValidImage(atPath: fileUrlForSpritesheet().path) else {
            throw OWSAssertionError("Invalid spritesheet source image")
        }

        guard let source = CGImageSourceCreateWithURL(fileUrlForSpritesheet() as CFURL, nil) else {
            throw OWSAssertionError("Couldn't load CGImageSource")
        }
        let imageOptions = [kCGImageSourceShouldCache: kCFBooleanFalse] as CFDictionary
        guard let rawImage = CGImageSourceCreateImageAtIndex(source, 0, imageOptions) else {
            throw OWSAssertionError("Couldn't load image")
        }

        let spriteParser = try DefaultSpriteSheetParser(spritesheet: rawImage)

        try Variant.allCases.forEach { variant in
            let destinationUrl = fileUrlForVariant(variant)
            guard !OWSFileSystem.fileOrFolderExists(url: destinationUrl) else { return }

            guard let spriteImage = spriteParser.copySprite(variant: variant),
                  let imageDestination = CGImageDestinationCreateWithURL(destinationUrl as CFURL, kUTTypePNG, 1, nil) else {
                      throw OWSAssertionError("Couldn't load image")
                  }
            CGImageDestinationAddImage(imageDestination, spriteImage, nil)
            CGImageDestinationFinalize(imageDestination)
        }
    }
}

// MARK: - Sprite parsing

private class DefaultSpriteSheetParser {
    let scale: Int
    let spritesheet: CGImage

    init(spritesheet: CGImage) throws {
        self.spritesheet = spritesheet

        // API contract specifies spritesheets have a constant format. Sheets will always be the same
        // size with sprites in the same location. If this ever changes we'll want to be more intelligent here.
        switch (spritesheet.width, spritesheet.height) {
        case (232, 162): scale = 1
        case (456, 322): scale = 2
        case (680, 482): scale = 3
        default: throw OWSAssertionError("Invalid spritesheet")
        }
    }

    // I've tried various ways of representing these origin points. These could be computed by
    // incrementally padding each sprite's pixel size with 1px margins, but I found that to be
    // confusing and difficult to follow.
    // Since these sprites should never change, I've just hardcoded each origin into a dictionary
    // mapping spriteType -> [1x, 2x, 3x] origins
    static let spriteOrigins: [BadgeAssets.Variant: [CGPoint]] = [
        .universal160:  [CGPoint(x:   1, y:   1), CGPoint(x:   1, y:   1), CGPoint(x:   1, y:   1)],
        .light16:       [CGPoint(x: 163, y:   1), CGPoint(x: 323, y:   1), CGPoint(x: 483, y:   1)],
        .light24:       [CGPoint(x: 163, y:  19), CGPoint(x: 323, y:  35), CGPoint(x: 483, y:  51)],
        .light36:       [CGPoint(x: 189, y:   1), CGPoint(x: 373, y:   1), CGPoint(x: 557, y:   1)],
        .dark16:        [CGPoint(x: 189, y:  39), CGPoint(x: 373, y:  75), CGPoint(x: 557, y: 111)],
        .dark24:        [CGPoint(x: 207, y:  39), CGPoint(x: 407, y:  75), CGPoint(x: 607, y: 111)],
        .dark36:        [CGPoint(x: 163, y:  57), CGPoint(x: 323, y: 109), CGPoint(x: 483, y: 161)],
    ]

    func copySprite(variant: BadgeAssets.Variant) -> CGImage? {
        // First array element is 1x scale, etc.
        let scaleIndex = scale - 1
        let pixelSize = CGSizeScale(variant.pointSize, CGFloat(scale))
        guard let origin = Self.spriteOrigins[variant]?[scaleIndex] else {
            owsFailDebug("Invalid sprite \(variant) \(scale)")
            return nil
        }

        let spriteRect = CGRect(origin: origin, size: pixelSize)
        return spritesheet.cropping(to: spriteRect)
    }
}
