//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

extension Emoji {
    private static let availableCache = AtomicDictionary<Emoji, Bool>()
    private static let iosVersionKey = "iosVersion"
    private static let cacheUrl = OWSFileSystem.appSharedDataDirectoryURL()
        .appendingPathComponent("Library")
        .appendingPathComponent("Caches")
        .appendingPathComponent("emoji.plist")

    static func warmAvailableCache() {
        owsAssertDebug(!Thread.isMainThread)

        guard CurrentAppContext().hasUI else { return }

        var availableCache = [Emoji: Bool]()
        var uncachedEmoji = [Emoji]()

        let iosVersion = AppVersion.iosVersionString

        // Use an NSMutableDictionary for built-in plist serialization and heterogeneous values.
        var availableMap = NSMutableDictionary()
        do {
            availableMap = try NSMutableDictionary(contentsOf: Self.cacheUrl, error: ())
        } catch {
            Logger.info("Re-building emoji availability cache. Cache could not be loaded. \(error)")
            uncachedEmoji = Emoji.allCases
        }

        let lastIosVersion = availableMap[iosVersionKey] as? String
        if lastIosVersion == iosVersion {
            Logger.debug("Loading emoji availability cache (expect \(Emoji.allCases.count) items, found \(availableMap.count - 1)).")
            for emoji in Emoji.allCases {
                if let available = availableMap[emoji.rawValue] as? Bool {
                    availableCache[emoji] = available
                } else {
                    Logger.warn("Emoji unexpectedly missing from cache: \(emoji).")
                    uncachedEmoji.append(emoji)
                }
            }
        } else if uncachedEmoji.isEmpty {
            Logger.info("Re-building emoji availability cache. iOS version upgraded from \(lastIosVersion ?? "(none)") -> \(iosVersion)")
            uncachedEmoji = Emoji.allCases
        }

        if !uncachedEmoji.isEmpty {
            Logger.info("Checking emoji availability for \(uncachedEmoji.count) uncached emoji")
            uncachedEmoji.forEach {
                let available = isEmojiAvailable($0)
                availableMap[$0.rawValue] = available
                availableCache[$0] = available
            }

            availableMap[iosVersionKey] = iosVersion
            do {
                // Use FileManager.createDirectory directly because OWSFileSystem.ensureDirectoryExists
                // can modify the protection, and this is a system-managed directory.
                try FileManager.default.createDirectory(at: Self.cacheUrl.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try availableMap.write(to: Self.cacheUrl)
            } catch {
                Logger.warn("Failed to save emoji availability cache; it will be recomputed next time! \(error)")
            }
        }

        Logger.info("Warmed emoji availability cache with \(availableCache.lazy.filter { $0.value }.count) available emoji for iOS \(iosVersion)")

        Self.availableCache.set(availableCache)
    }

    private static func isEmojiAvailable(_ emoji: Emoji) -> Bool {
        owsAssertDebug(CurrentAppContext().hasUI)

        return emoji.rawValue.isUnicodeStringAvailable
    }

    /// Indicates whether the given emoji is available on this iOS
    /// version. We cache the availability in memory.
    var available: Bool {
        owsAssertDebug(CurrentAppContext().hasUI)

        guard let available = Self.availableCache[self] else {
            let available = Self.isEmojiAvailable(self)
            Self.availableCache[self] = available
            return available
        }
        return available
    }
}

private extension String {
    /// A known undefined unicode character for comparison
    private static let unknownUnicodeStringPng = "\u{1fff}".unicodeStringPngRepresentation

    // Based on https://stackoverflow.com/a/41393387
    // Check if an emoji is available on the current iOS version
    // by verifying its image is different than the "unknown"
    // reference image
    var isUnicodeStringAvailable: Bool {
        guard isSingleEmoji else { return false }
        return String.unknownUnicodeStringPng != unicodeStringPngRepresentation
    }

    var unicodeStringPngRepresentation: Data? {
        let attributes = [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 8)]
        let size = (self as NSString).size(withAttributes: attributes)

        UIGraphicsBeginImageContext(size)
        defer { UIGraphicsEndImageContext() }
        (self as NSString).draw(at: CGPoint(x: 0, y: 0), withAttributes: attributes)

        guard let unicodeImage = UIGraphicsGetImageFromCurrentImageContext() else { return nil }
        return unicodeImage.pngData()
    }
}
