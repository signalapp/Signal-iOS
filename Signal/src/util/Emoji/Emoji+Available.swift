//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

extension Emoji {
    private static let availableCache = AtomicDictionary<Emoji, Bool>()
    private static let metadataStore = SDSKeyValueStore(collection: "Emoji+metadataStore")
    private static let availableStore = SDSKeyValueStore(collection: "Emoji+availableStore")
    private static let iosVersionKey = "iosVersion"

    static func warmAvailableCache() {
        owsAssertDebug(!Thread.isMainThread)

        var availableCache = [Emoji: Bool]()
        var uncachedEmoji = [Emoji]()

        let iosVersion = AppVersion.iOSVersionString
        var iosVersionNeedsUpdate = false
        var shouldResetCache = false

        SDSDatabaseStorage.shared.read { transaction in
            guard let lastIosVersion = metadataStore.getString(iosVersionKey, transaction: transaction) else {
                Logger.info("Building initial emoji availability cache.")
                iosVersionNeedsUpdate = true
                uncachedEmoji = Emoji.allCases
                shouldResetCache = true
                return
            }

            guard lastIosVersion == iosVersion else {
                Logger.info("Re-building emoji availability cache. iOS version upgraded from \(lastIosVersion) -> \(iosVersion)")
                iosVersionNeedsUpdate = true
                uncachedEmoji = Emoji.allCases
                shouldResetCache = true
                return
            }

            let availableMap = availableStore.allBoolValuesMap(transaction: transaction)
            guard !availableMap.isEmpty else {
                Logger.info("Re-building emoji availability cache. Cache could not be loaded.")
                uncachedEmoji = Emoji.allCases
                shouldResetCache = true
                return
            }

            for emoji in Emoji.allCases {
                if let available = availableMap[emoji.rawValue] {
                    availableCache[emoji] = available
                } else {
                    Logger.warn("Emoji unexpectedly missing from cache: \(emoji).")
                    uncachedEmoji.append(emoji)
                }
            }
        }

        var uncachedAvailability = [Emoji: Bool]()
        if !uncachedEmoji.isEmpty {
            Logger.info("Checking emoji availability for \(uncachedEmoji.count) uncached emoji")
            uncachedEmoji.forEach {
                let available = isEmojiAvailable($0)
                uncachedAvailability[$0] = available
                availableCache[$0] = available
            }
        }

        if uncachedAvailability.count > 0 || iosVersionNeedsUpdate {
            SDSDatabaseStorage.shared.write { transaction in
                if shouldResetCache {
                    availableStore.removeAll(transaction: transaction)
                }
                for (emoji, available) in uncachedAvailability {
                    availableStore.setBool(available, key: emoji.rawValue, transaction: transaction)
                }
                metadataStore.setString(iosVersion, key: iosVersionKey, transaction: transaction)
            }
        }

        Logger.info("Warmed emoji availability cache with \(availableCache.filter { $0.value }.count) available emoji for iOS \(iosVersion)")

        Self.availableCache.set(availableCache)
    }

    private static func isEmojiAvailable(_ emoji: Emoji) -> Bool {
        return emoji.rawValue.isUnicodeStringAvailable
    }

    /// Indicates whether the given emoji is available on this iOS
    /// version. We cache the availability in memory.
    var available: Bool {
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
    // by verifying its image is different than the "unknwon"
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
