//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import libwebp
import YYImage

// MARK: - PNG Chunker

extension TSAttachmentMigration {
    /// Helps you iterate over PNG chunks from raw data.
    ///
    ///     let chunker = try PngChunker(data: myPngData)
    ///     while let chunk = try chunker.next() {
    ///         let type = String(data: chunk.type, encoding: .ascii)!
    ///         print("Found a chunk of type \(type)")
    ///     }
    ///
    /// Useful for low-level handling of PNGs, not image processing.
    ///
    /// Quick background on PNGs: PNG files always start with the same 8
    /// bytes (the "PNG signature") and then contain several chunks. Chunks
    /// have a type (like `IHDR` for the image metadata header) and 0 or
    /// more bytes of chunk-specific data. Chunks also have two computable
    /// fields: the length of the data and a checksum.
    ///
    /// For more, see the ["Chunk layout" section][0] of the PNG spec.
    ///
    /// [0]: https://www.w3.org/TR/2003/REC-PNG-20031110/#5Chunk-layout
    fileprivate class PngChunker {
        /// The PNG signature, lifted from [the spec][1].
        /// [1]: https://www.w3.org/TR/2003/REC-PNG-20031110/#5PNG-file-signature
        fileprivate static let pngSignature = Data([137, 80, 78, 71, 13, 10, 26, 10])

        /// The smallest possible PNG size is a well-compressed 1x1 image.
        ///
        /// 8 bytes for the PNG signature,
        /// plus 25 bytes for the IHDR chunk (12 for metadata + 13 for data),
        /// plus 22 bytes for the IDAT chunk (12 for metadata + 10 for 1 black pixel),
        /// plus 12 bytes for the IEND chunk (12 for metadata, no data),
        /// = 67 bytes.
        private static let smallestPossiblePngSize = 67

        private let pngSource: TSAttachmentMigration.OWSImageSource

        /// The current index we're looking at. If nil, we're done looking at the data.
        private var cursor: Int?

        /// Initialize a PNG chunker.
        /// - Parameter imageSource: Source for a PNG.
        fileprivate init(source: TSAttachmentMigration.OWSImageSource) throws {
            guard source.byteLength >= Self.smallestPossiblePngSize else {
                throw OWSAssertionError("png too small")
            }
            let prefix = try? source.readData(byteOffset: 0, byteLength: Self.pngSignature.count)
            guard prefix == Self.pngSignature else {
                throw OWSAssertionError("File does not start with png signature")
            }
            pngSource = source
            cursor = Self.pngSignature.count
        }

        /// Get the next PNG chunk.
        /// - Returns: The next chunk, or `nil` if the end of the data has been reached.
        fileprivate func next() throws -> TSAttachmentMigration.PngChunker.Chunk? {
            guard var cursor = cursor, cursor < pngSource.byteLength else {
                return nil
            }

            // Checks that there's enough space for the length (4 bytes) and the type (4 bytes).
            guard cursor + 8 <= pngSource.byteLength else {
                self.cursor = nil
                throw OWSAssertionError("Ended unexpectedly")
            }

            let lengthBytes = try pngSource.readData(byteOffset: cursor, byteLength: 4)
            let length = try Self.asPngUInt32(lengthBytes)
            cursor += 4

            var expectedCrc = CRC32()

            let type = try pngSource.readData(byteOffset: cursor, byteLength: 4)
            guard Self.isValidPngType(type) else {
                self.cursor = nil
                throw OWSAssertionError("Invalid chunk type")
            }
            expectedCrc = expectedCrc.update(with: type)
            cursor += 4

            // Checks that there's enough space for the data (N bytes) and the CRC (4 bytes).
            let lengthAsInt = Int(length)
            guard cursor + lengthAsInt + 4 <= pngSource.byteLength else {
                self.cursor = nil
                throw OWSAssertionError("Ended unexpectedly")
            }
            let data = try pngSource.readData(byteOffset: cursor, byteLength: lengthAsInt)
            expectedCrc = expectedCrc.update(with: data)
            cursor += lengthAsInt

            let crcBytes = try pngSource.readData(byteOffset: cursor, byteLength: 4)
            let actualCrc = try Self.asPngUInt32(crcBytes)
            cursor += 4

            guard actualCrc == expectedCrc.value else {
                self.cursor = nil
                throw OWSAssertionError("Invalid checksum")
            }

            self.cursor = cursor

            return Chunk(
                lengthBytes: lengthBytes,
                type: type,
                data: data,
                crcBytes: crcBytes
            )
        }

        // MARK: - Chunk

        /// A single PNG chunk. Holds the length, type, data, and CRC checksum.
        ///
        /// For details, see the ["Chunk layout" section][0] of the PNG spec.
        ///
        /// [0]: https://www.w3.org/TR/2003/REC-PNG-20031110/#5Chunk-layout
        fileprivate struct Chunk {
            /// The chunk data's length, encoded as a PNG 32-bit big endian number.
            let lengthBytes: Data

            /// The chunk's type, as raw data.
            ///
            /// You may wish to convert this to a string. This is just a normal ASCII conversion:
            ///
            ///     let typeString = String(data: myChunk.type, encoding: .ascii)
            let type: Data

            /// The chunk's data.
            let data: Data

            /// The chunk's CRC32 code, encoded as a PNG 32-bit big endian number.
            let crcBytes: Data

            /// Get all the bytes for this chunk.
            ///
            /// Includes all four sections: the length, type, data, and checksum.
            ///
            /// - Returns: The full chunk in bytes.
            func allBytes() -> Data {
                lengthBytes + type + data + crcBytes
            }
        }
    }
}

extension TSAttachmentMigration.PngChunker {
    static func asPngUInt32(_ data: Data) throws -> UInt32 {
        var result: UInt32 = 0
        for (i, byte) in data.reversed().enumerated() {
            result += UInt32(byte) * (1 << (8 * i))
        }
        return result
    }

    static func isValidPngType(_ data: Data) -> Bool {
        guard data.count == 4 else { return false }
        func isAsciiLetter(_ byte: UInt8) -> Bool {
            (65...90).contains(byte) || (97...122).contains(byte)
        }
        return data.allSatisfy(isAsciiLetter)
    }
}

// MARK: - Image Validator

extension TSAttachmentMigration {

    struct OWSImageSource {

        let fileHandle: FileHandle
        let byteLength: Int

        init(fileUrl: URL) throws {
            self.byteLength = OWSFileSystem.fileSize(of: fileUrl)?.intValue ?? 0
            self.fileHandle = try FileHandle(forReadingFrom: fileUrl)
        }

        func readData(byteOffset: Int, byteLength: Int) throws -> Data {
            if try fileHandle.offset() != byteOffset {
                fileHandle.seek(toFileOffset: UInt64(byteOffset))
            }
            return try fileHandle.read(upToCount: byteLength) ?? Data()
        }

        func readIntoMemory() throws -> Data {
            if try fileHandle.offset() != 0 {
                fileHandle.seek(toFileOffset: 0)
            }
            return try fileHandle.readToEnd() ?? Data()
        }

        // Class-bound wrapper around FileHandle
        class FileHandleWrapper {
            let fileHandle: FileHandle

            init(_ fileHandle: FileHandle) {
                self.fileHandle = fileHandle
            }
        }

        func cgImageSource() throws -> CGImageSource? {
            let fileHandle = FileHandleWrapper(fileHandle)

            var callbacks = CGDataProviderDirectCallbacks(
                version: 0,
                getBytePointer: nil,
                releaseBytePointer: nil,
                getBytesAtPosition: { info, buffer, offset, byteCount in
                    guard
                        let unmanagedFileHandle = info?.assumingMemoryBound(
                            to: Unmanaged<FileHandleWrapper>.self
                        ).pointee
                    else {
                        return 0
                    }
                    let fileHandle = unmanagedFileHandle.takeUnretainedValue().fileHandle
                    do {
                        if offset != (try fileHandle.offset()) {
                            try fileHandle.seek(toOffset: UInt64(offset))
                        }
                        let data = try fileHandle.read(upToCount: byteCount) ?? Data()
                        data.withUnsafeBytes { bytes in
                            buffer.copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
                        }
                        return data.count
                    } catch {
                        return 0
                    }
                },
                releaseInfo: { info in
                    guard
                        let unmanagedFileHandle = info?.assumingMemoryBound(
                            to: Unmanaged<FileHandleWrapper>.self
                        ).pointee
                    else {
                        return
                    }
                    unmanagedFileHandle.release()
                }
            )

            var unmanagedFileHandle = Unmanaged.passRetained(fileHandle)

            guard let dataProvider = CGDataProvider(
                directInfo: &unmanagedFileHandle,
                size: Int64(byteLength),
                callbacks: &callbacks
            ) else {
                throw OWSAssertionError("Failed to create data provider")
            }
            return CGImageSourceCreateWithDataProvider(dataProvider, nil)
        }

        fileprivate static func ows_isValidImage(dimension imageSize: CGSize, depthBytes: CGFloat, isAnimated: Bool) -> Bool {
            if imageSize.width < 1 || imageSize.height < 1 || depthBytes < 1 {
                // Invalid metadata.
                return false
            }

            // We only support (A)RGB and (A)Grayscale, so worst case is 4.
            let worstCaseComponentsPerPixel = CGFloat(4)
            let bytesPerPixel = worstCaseComponentsPerPixel * depthBytes

            let expectedBytesPerPixel: CGFloat = 4
            let maxValidImageDimension: CGFloat = CGFloat(isAnimated ? TSAttachmentMigration.kMaxAnimatedImageDimensions : TSAttachmentMigration.kMaxStillImageDimensions)
            let maxBytes = maxValidImageDimension * maxValidImageDimension * expectedBytesPerPixel
            let actualBytes = imageSize.width * imageSize.height * bytesPerPixel
            if actualBytes > maxBytes {
                Logger.warn("invalid dimensions width: \(imageSize.width), height \(imageSize.height), bytesPerPixel: \(bytesPerPixel)")
                return false
            }

            return true
        }

        // Parse the GIF header to prevent the "GIF of death" issue.
        //
        // See: https://blog.flanker017.me/cve-2017-2416-gif-remote-exec/
        // See: https://www.w3.org/Graphics/GIF/spec-gif89a.txt
        //
        // This behavior was ported over from objective-c and ends up effectively just checking for GIF headers and then that the size isn't zero.
        // It appears to be a somewhat broken attempt to workaround the above CVE which was fixed so long ago we don't ship to iOS builds with the
        // problem anymore.
        var ows_hasValidGifSize: Bool {
            let signatureLength = 3
            let versionLength = 3
            let widthLength = 2
            let heightLength = 2
            let prefixLength = signatureLength + versionLength
            let bufferLength = signatureLength + versionLength + widthLength + heightLength

            guard byteLength >= bufferLength else {
                return false
            }

            let gif87aPrefix = Data([0x47, 0x49, 0x46, 0x38, 0x37, 0x61])
            let gif89aPrefix = Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])
            let prefix = try? self.readData(byteOffset: 0, byteLength: prefixLength)
            guard prefix == gif87aPrefix || prefix == gif89aPrefix else {
                return false
            }
            guard let subRange = try? self.readData(byteOffset: prefixLength, byteLength: 4) else {
                return false
            }
            return subRange != Data(count: 4)
        }

        fileprivate func ows_guessHighEfficiencyImageFormat() -> ImageFormat {
            // A HEIF image file has the first 16 bytes like
            // 0000 0018 6674 7970 6865 6963 0000 0000
            // so in this case the 5th to 12th bytes shall make a string of "ftypheic"
            let heifHeaderStartsAt = 4
            let heifBrandStartsAt = 8
            // We support "heic", "mif1" or "msf1". Other brands are invalid for us for now.
            // The length is 4 + 1 because the brand must be terminated with a null.
            // Include the null in the comparison to prevent a bogus brand like "heicfake"
            // from being considered valid.
            let heifSupportedBrandLength = 5
            let totalHeaderLength = heifBrandStartsAt - heifHeaderStartsAt + heifSupportedBrandLength
            guard byteLength >= heifBrandStartsAt + heifSupportedBrandLength else {
                return .unknown
            }

            // These are the brands of HEIF formatted files that are renderable by CoreGraphics
            let heifBrandHeaderHeic = Data("ftypheic\0".utf8)
            let heifBrandHeaderHeif = Data("ftypmif1\0".utf8)
            let heifBrandHeaderHeifStream = Data("ftypmsf1\0".utf8)

            // Pull the string from the header and compare it with the supported formats
            let header = try? readData(byteOffset: heifHeaderStartsAt, byteLength: totalHeaderLength)

            if header == heifBrandHeaderHeic {
                return .heic
            } else if header == heifBrandHeaderHeif || header == heifBrandHeaderHeifStream {
                return .heif
            } else {
                return .unknown
            }
        }

        fileprivate func ows_guessImageFormat() -> ImageFormat {
            guard byteLength >= 2 else {
                return .unknown
            }

            switch try? readData(byteOffset: 0, byteLength: 2) {
            case Data([0x47, 0x49]):
                return .gif
            case Data([0x89, 0x50]):
                return .png
            case Data([0xff, 0xd8]):
                return .jpeg
            case Data([0x42, 0x4d]):
                return .bmp
            case Data([0x4d, 0x4d]), // Motorola byte order TIFF
                Data([0x49, 0x49]): // Intel byte order TIFF
                return .tiff
            case Data([0x52, 0x49]):
                // First two letters of RIFF tag.
                return .webp
            default:
                return ows_guessHighEfficiencyImageFormat()
            }
        }

        fileprivate static func applyImageOrientation(_ orientation: CGImagePropertyOrientation, to imageSize: CGSize) -> CGSize {
            // NOTE: UIImageOrientation and CGImagePropertyOrientation values
            //       DO NOT match.
            switch orientation {
            case .up, .upMirrored, .down, .downMirrored:
                return imageSize
            case .left, .leftMirrored, .right, .rightMirrored:
                return CGSize(width: imageSize.height, height: imageSize.width)
            }
        }

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
        func isAnimatedPngData() -> NSNumber? {
            let actl = "acTL".data(using: .ascii)
            let idat = "IDAT".data(using: .ascii)

            do {
                let chunker = try PngChunker(source: self)
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

        // MARK: - Image Metadata

        func imageMetadata(
            mimeTypeForValidation declaredMimeType: String?
        ) -> TSAttachmentMigration.ImageMetadata? {
            guard byteLength < TSAttachmentMigration.kMaxFileSizeGeneric else {
                return nil
            }

            let imageFormat = ows_guessImageFormat()
            guard imageFormat.isValid(source: self) else {
                Logger.warn("Image does not have valid format.")
                return nil
            }

            guard imageFormat.mimeType != nil else {
                Logger.warn("Image does not have MIME type.")
                return nil
            }

            let isAnimated: Bool
            switch imageFormat {
            case .gif:
                // This treats all GIFs as animated. We could reflect the actual image content.
                isAnimated = true
            case .webp:
                let webpMetadata = metadataForWebp
                guard webpMetadata.isValid else {
                    Logger.warn("Image does not have valid webpMetadata.")
                    return nil
                }
                isAnimated = webpMetadata.frameCount > 1
            case .png:
                guard let isAnimatedPng = isAnimatedPngData() else {
                    Logger.warn("Could not determine if png is animated.")
                    return nil
                }
                isAnimated = isAnimatedPng.boolValue
            default:
                isAnimated = false
            }

            guard imageFormat.isValid(source: self) else {
                Logger.warn("Image does not have valid format.")
                return nil
            }

            if isAnimated, byteLength > TSAttachmentMigration.kMaxFileSizeAnimatedImage {
                Logger.warn("Oversize image.")
                return nil
            } else if !isAnimated, byteLength > TSAttachmentMigration.kMaxFileSizeImage {
                Logger.warn("Oversize image.")
                return nil
            }

            let metadata = imageMetadata(withIsAnimated: isAnimated, imageFormat: imageFormat)

            guard metadata.isValid else {
                return nil
            }

            return metadata
        }

        fileprivate func imageMetadata(
            withIsAnimated isAnimated: Bool,
            imageFormat: TSAttachmentMigration.ImageFormat
        ) -> TSAttachmentMigration.ImageMetadata {
            if imageFormat == .webp {
                let imageSize = sizeForWebpData
                guard Self.ows_isValidImage(dimension: imageSize, depthBytes: 1, isAnimated: isAnimated) else {
                    Logger.warn("Image does not have valid dimensions: \(imageSize)")
                    return .invalid()
                }
                return .init(isValid: true, imageFormat: imageFormat, pixelSize: imageSize, hasAlpha: true, isAnimated: isAnimated)
            }

            guard let imageSource = try? self.cgImageSource() else {
                Logger.warn("Could not build imageSource.")
                return .invalid()
            }
            return Self.imageMetadata(withImageSource: imageSource, imageFormat: imageFormat, isAnimated: isAnimated)
        }

        fileprivate static func imageMetadata(
            withImageSource imageSource: CGImageSource,
            imageFormat: TSAttachmentMigration.ImageFormat,
            isAnimated: Bool
        ) -> TSAttachmentMigration.ImageMetadata {
            let options = [kCGImageSourceShouldCache as String: false]
            guard let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, options as CFDictionary) as? [String: AnyObject] else {
                Logger.warn("Missing imageProperties.")
                return .invalid()
            }

            guard let widthNumber = imageProperties[kCGImagePropertyPixelWidth as String] as? NSNumber else {
                Logger.warn("widthNumber was unexpectedly nil")
                return .invalid()
            }
            guard let heightNumber = imageProperties[kCGImagePropertyPixelHeight as String] as? NSNumber else {
                Logger.warn("heightNumber was unexpectedly nil")
                return .invalid()
            }

            var pixelSize = CGSize(width: widthNumber.doubleValue, height: heightNumber.doubleValue)
            if let orientationNumber = imageProperties[kCGImagePropertyOrientation as String] as? NSNumber {
                guard let orientation = CGImagePropertyOrientation(rawValue: orientationNumber.uint32Value) else {
                    Logger.warn("orientation number was invalid")
                    return .invalid()
                }
                pixelSize = applyImageOrientation(orientation, to: pixelSize)
            }

            let hasAlpha = imageProperties[kCGImagePropertyHasAlpha as String] as? NSNumber ?? false

            // The number of bits in each color sample of each pixel. The value of this key is a CFNumberRef.
            guard let depthNumber = imageProperties[kCGImagePropertyDepth as String] as? NSNumber else {
                Logger.warn("depthNumber was unexpectedly nil")
                return .invalid()
            }
            let depthBits = depthNumber.uintValue
            // This should usually be 1.
            let depthBytes = ceil(Double(depthBits) / 8.0)

            // The color model of the image such as "RGB", "CMYK", "Gray", or "Lab". The value of this key is CFStringRef.
            guard let colorModel = (imageProperties[kCGImagePropertyColorModel as String] as? NSString) as String? else {
                Logger.warn("colorModel was unexpectedly nil")
                return .invalid()
            }
            guard colorModel == kCGImagePropertyColorModelRGB as String || colorModel == kCGImagePropertyColorModelGray as String else {
                Logger.warn("Invalid colorModel: \(colorModel)")
                return .invalid()
            }

            guard ows_isValidImage(dimension: pixelSize, depthBytes: depthBytes, isAnimated: isAnimated) else {
                Logger.warn("Image does not have valid dimensions: \(pixelSize).")
                return .invalid()
            }

            return .init(isValid: true, imageFormat: imageFormat, pixelSize: pixelSize, hasAlpha: hasAlpha.boolValue, isAnimated: isAnimated)
        }

        // MARK: - WEBP

        fileprivate var sizeForWebpData: CGSize {
            let webpMetadata = metadataForWebp
            guard webpMetadata.isValid else {
                return .zero
            }
            return .init(width: CGFloat(webpMetadata.canvasWidth), height: CGFloat(webpMetadata.canvasHeight))
        }

        fileprivate var metadataForWebp: TSAttachmentMigration.WebpMetadata {
            guard let data = try? self.readIntoMemory() else {
                return WebpMetadata(isValid: false, canvasWidth: 0, canvasHeight: 0, frameCount: 0)
            }
            return data.withUnsafeBytes {
                $0.withMemoryRebound(to: UInt8.self) { buffer in
                    var webPData = WebPData(bytes: buffer.baseAddress, size: buffer.count)
                    guard let demuxer = WebPDemux(&webPData) else {
                        return WebpMetadata(isValid: false, canvasWidth: 0, canvasHeight: 0, frameCount: 0)
                    }
                    defer {
                        WebPDemuxDelete(demuxer)
                    }

                    let canvasWidth = WebPDemuxGetI(demuxer, WEBP_FF_CANVAS_WIDTH)
                    let canvasHeight = WebPDemuxGetI(demuxer, WEBP_FF_CANVAS_HEIGHT)
                    let frameCount = WebPDemuxGetI(demuxer, WEBP_FF_FRAME_COUNT)
                    let result = WebpMetadata(isValid: canvasWidth > 0 && canvasHeight > 0 && frameCount > 0,
                                              canvasWidth: canvasWidth,
                                              canvasHeight: canvasHeight,
                                              frameCount: frameCount)
                    return result
                }
            }
        }
    }
}
