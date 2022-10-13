//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension NSData {
    /// Determine whether something is an animated PNG.
    ///
    /// Does this by checking that the `acTL` chunk appears before any `IDAT` chunk.
    /// See [the APNG spec][0] for more.
    ///
    /// [0]: https://wiki.mozilla.org/APNG_Specification
    ///
    /// - Returns:
    ///   `true` if the contents appear to be an APNG.
    ///   `false` if the contents are a still PNG.
    ///   `nil` if the contents are invalid.
    @objc
    func isAnimatedPngData() -> NSNumber? {
        let actl = "acTL".data(using: .ascii)
        let idat = "IDAT".data(using: .ascii)

        do {
            let chunker = try PngChunker(data: self as Data)
            while let chunk = try chunker.next() {
                if chunk.type == actl {
                    return NSNumber(value: true)
                } else if chunk.type == idat {
                    return NSNumber(value: false)
                }
            }
        } catch {
            Logger.warn("Error: \(error)")
        }

        return nil
    }
}

 // MARK: -

extension Data {
    public var ows_isValidImage: Bool {
        (self as NSData).ows_isValidImage()
    }

    public func ows_isValidImage(mimeType: String?) -> Bool {
        (self as NSData).ows_isValidImage(withMimeType: mimeType)
    }
}
