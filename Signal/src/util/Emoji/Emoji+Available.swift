//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

extension Emoji {
    static let availableSerialQueue = DispatchQueue(label: "EmojiAvailable")
    static var availableCache = [Emoji: Bool]()

    static func warmAvailableCache() {
        Emoji.allCases.forEach { _ = $0.available }
    }

    /// Indicates whether the given emoji is available on this iOS
    /// version. We cache the availability in memory.
    var available: Bool {
        guard let available = Emoji.availableSerialQueue.sync(execute: { Emoji.availableCache[self] }) else {
            let available = rawValue.isUnicodeStringAvailable
            Emoji.availableSerialQueue.sync { Emoji.availableCache[self] = available }
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
