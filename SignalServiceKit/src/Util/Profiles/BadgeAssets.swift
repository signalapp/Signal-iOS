//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import ImageIO
import CoreServices

@objc
public class BadgeAssets: NSObject {
    private let scale: Int
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
        case universal64
        case universal112
        case universal160

        var pointSize: CGSize {
            switch self {
            case .light16, .dark16: return CGSize(width: 16, height: 16)
            case .light24, .dark24: return CGSize(width: 24, height: 24)
            case .light36, .dark36: return CGSize(width: 36, height: 36)
            case .universal64: return CGSize(width: 64, height: 64)
            case .universal112: return CGSize(width: 112, height: 112)
            case .universal160: return CGSize(width: 160, height: 160)
            }
        }
    }

    required init(scale: Int, remoteSourceUrl: URL, localAssetDirectory: URL) {
        self.scale = scale
        self.remoteSourceUrl = remoteSourceUrl
        self.localAssetDirectory = localAssetDirectory
    }

    private func fileUrlForSpritesheet() -> URL {
        localAssetDirectory.appendingPathComponent("spritesheet")
    }

    private func fileUrlForVariant(_ variant: Variant) -> URL {
        localAssetDirectory.appendingPathComponent(variant.rawValue)
    }

    // MARK: - Sprite fetching

    func prepareAssetsIfNecessary() -> Promise<Void> {
        let shouldFetch: Bool = lock.withLock {
            // If we're already fetching, or have hit a terminal state, there's nothing left to do
            guard state != .fetching, state != .fetched, state != .unavailable else { return false }

            guard !CurrentAppContext().isNSE else {
                Logger.info("Badge assets unavailable. Currently running in the NSE")
                state = .unavailable
                return false
            }

            // If we have all our assets on disk, we're good to go
            let allAssetUrls = [fileUrlForSpritesheet()] + Variant.allCases.map { fileUrlForVariant($0) }
            guard allAssetUrls.contains(where: { OWSFileSystem.fileOrFolderExists(url: $0) == false }) else {
                Logger.debug("All badge assets available")
                state = .fetched
                return false
            }

            guard CurrentAppContext().isMainApp else {
                // The share extension can display badges that we've fetched, but we'll save fetching badges
                // we don't have for the main app.
                Logger.info("Skipping badge fetch. Not in main app.")
                state = .unavailable
                return false
            }

            state = .fetching
            return true
        }

        guard shouldFetch else { return Promise.value(()) }
        OWSFileSystem.ensureDirectoryExists(localAssetDirectory.path)
        return firstly(on: DispatchQueue.sharedUtility) { () -> Promise<Void> in
            self.fetchSpritesheetIfNecessary()
        }.done(on: DispatchQueue.sharedUtility) { _ in
            try self.extractSpritesFromSpritesheetIfNecessary()
            self.lock.withLock { self.state = .fetched }
        }.catch(on: DispatchQueue.sharedUtility) { error in
            owsFailDebug("Failed to fetch badge assets with error: \(error)")
            self.lock.withLock { self.state = .failed }
        }
    }

    private func fetchSpritesheetIfNecessary() -> Promise<Void> {
        let spriteUrl = fileUrlForSpritesheet()
        guard !OWSFileSystem.fileOrFolderExists(url: spriteUrl) else {
            return Promise.value(())
        }

        // TODO: Badges — Censorship circumvention
        let urlSession = signalService.urlSessionForUpdates2()
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

        let spriteParser = DefaultSpriteSheetParser(spritesheet: rawImage, scale: scale)

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
// MARK: - Sprite retrieval
extension BadgeAssets {

    // TODO: Badges — Lazy initialization? Double check backing memory is all purgable
    @objc
    public var light16: UIImage? { imageForVariant(.light16) }
    @objc
    public var light24: UIImage? { imageForVariant(.light24) }
    @objc
    public var light36: UIImage? { imageForVariant(.light36) }
    @objc
    public var dark16: UIImage? { imageForVariant(.dark16) }
    @objc
    public var dark24: UIImage? { imageForVariant(.dark24) }
    @objc
    public var dark36: UIImage? { imageForVariant(.dark36) }
    @objc
    public var universal64: UIImage? { imageForVariant(.universal64) }
    @objc
    public var universal112: UIImage? { imageForVariant(.universal112) }
    @objc
    public var universal160: UIImage? { imageForVariant(.universal160) }

    private func imageForVariant(_ variant: Variant) -> UIImage? {
        let currentState = lock.withLock { state }
        guard currentState == .fetched else {
            Logger.debug("Current badge state is \(currentState). Badge asset unavailable")
            return nil
        }

        let fileUrl = fileUrlForVariant(variant)
        guard let imageSource = CGImageSourceCreateWithURL(fileUrl as CFURL, nil) else { return nil }

        let imageOptions = [kCGImageSourceShouldCache: kCFBooleanFalse] as CFDictionary
        guard let rawImage = CGImageSourceCreateImageAtIndex(imageSource, 0, imageOptions) else {
            owsFailDebug("Couldn't load image")
            return nil
        }

        let imageScale: CGFloat
        switch CGSize(width: rawImage.width, height: rawImage.height) {
        case CGSizeScale(variant.pointSize, 1.0): imageScale = 1.0
        case CGSizeScale(variant.pointSize, 2.0): imageScale = 2.0
        case CGSizeScale(variant.pointSize, 3.0): imageScale = 3.0
        default:
            owsFailDebug("Bad scale")
            return nil
        }

        return UIImage(cgImage: rawImage, scale: imageScale, orientation: .up)
    }
}

// MARK: - Sprite parsing

private class DefaultSpriteSheetParser {
    let scale: Int
    let spritesheet: CGImage

    init(spritesheet: CGImage, scale: Int) {
        self.scale = scale
        self.spritesheet = spritesheet
    }

    // I've tried various ways of representing these origin points. These could be computed by
    // incrementally padding each sprite's pixel size with 1px margins, but I found that to be
    // confusing and difficult to follow.
    // Since these sprites should never change, I've just hardcoded each origin into a dictionary
    // mapping spriteType -> [1x, 2x, 3x] origins
    static let spriteOrigins: [BadgeAssets.Variant: [CGPoint]] = [
        .light16: [CGPoint(x: 163, y: 1), CGPoint(x: 323, y: 1), CGPoint(x: 483, y: 1)],
        .light24: [CGPoint(x: 163, y: 19), CGPoint(x: 323, y: 35), CGPoint(x: 483, y: 51)],
        .light36: [CGPoint(x: 189, y: 1), CGPoint(x: 373, y: 1), CGPoint(x: 557, y: 1)],
        .dark16: [CGPoint(x: 189, y: 39), CGPoint(x: 373, y: 75), CGPoint(x: 557, y: 111)],
        .dark24: [CGPoint(x: 207, y: 39), CGPoint(x: 407, y: 75), CGPoint(x: 607, y: 111)],
        .dark36: [CGPoint(x: 163, y: 57), CGPoint(x: 323, y: 109), CGPoint(x: 483, y: 161)],
        .universal64: [CGPoint(x: 163, y: 97), CGPoint(x: 323, y: 193), CGPoint(x: 483, y: 289)],
        .universal112: [CGPoint(x: 233, y: 1), CGPoint(x: 457, y: 1), CGPoint(x: 681, y: 1)],
        .universal160: [CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 1)]
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
