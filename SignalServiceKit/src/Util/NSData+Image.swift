//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
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
        do {
            let parser = OWSDataParser(data: self as Data)

            let signature = try parser.nextData(length: 8, name: "PNG signature")
            let pngSignature: [UInt8] = [ 137, 80, 78, 71, 13, 10, 26, 10 ]
            guard signature == NSData(bytes: pngSignature, length: pngSignature.count) as Data else {
                Logger.warn("Invalid signature.")
                return nil
            }

            while true {
                let chunkHeader = try parser.nextData(length: 8, name: "PNG chunk header")
                let chunkLength = try chunkHeader[0..<4].asPngUInt32()
                let chunkType = chunkHeader[4..<8]

                // From the APNG specification:
                //
                // To be recognized as an APNG, an `acTL` chunk must appear in the stream before any `IDAT` chunks.
                //
                // https://wiki.mozilla.org/APNG_Specification
                //
                // See also the PNG specification:
                //
                // https://www.w3.org/TR/PNG
                if chunkType == "acTL".data(using: .utf8) {
                    return NSNumber(value: true)
                } else if chunkType == "IDAT".data(using: .utf8) {
                    return NSNumber(value: false)
                }

                // Skip over the rest of the chunk.
                if chunkLength > 0 {
                    try parser.skip(length: UInt(chunkLength), name: "PNG chunk data")
                }
                try parser.skip(length: 4, name: "PNG chunk CRC")
            }
        } catch {
            Logger.warn("Error: \(error)")
            return nil
        }
    }
}

 // MARK: -

extension Data {

    func asPngUInt32() throws -> UInt32 {
        guard count == 4 else {
            throw OWSAssertionError("Unexpected length: \(count)")
        }
        let rawValue: UInt32 = withUnsafeBytes { $0.load(as: UInt32.self) }
        // PNG and all iOS devices use big-endian (MSB) byte order,
        // so this should be redundant, but it will future-proof the code.
        return CFSwapInt32BigToHost(rawValue)
    }

    public var ows_isValidImage: Bool {
        (self as NSData).ows_isValidImage()
    }

    public func ows_isValidImage(mimeType: String?) -> Bool {
        (self as NSData).ows_isValidImage(withMimeType: mimeType)
    }
}
