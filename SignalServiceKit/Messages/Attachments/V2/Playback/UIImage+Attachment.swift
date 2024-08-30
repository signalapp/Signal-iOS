//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import YYImage

extension UIImage {

    public static func from(
        _ attachment: AttachmentStream
    ) throws -> UIImage {
        return try .fromEncryptedFile(
            at: attachment.fileURL,
            encryptionKey: attachment.attachment.encryptionKey,
            plaintextLength: attachment.info.unencryptedByteCount,
            mimeType: attachment.mimeType
        )
    }

    public static func from(
        _ attachmentThumbnail: AttachmentBackupThumbnail
    ) throws -> UIImage {
        return try .fromEncryptedFile(
            at: attachmentThumbnail.fileURL,
            encryptionKey: attachmentThumbnail.attachment.encryptionKey,
            plaintextLength: nil,
            mimeType: MimeType.imageJpeg.rawValue
        )
    }

    /// If no plaintext length is provided, the file is assumed to only use pkcs7 padding.
    public static func fromEncryptedFile(
        at fileURL: URL,
        encryptionKey: Data,
        plaintextLength: UInt32?,
        mimeType: String
    ) throws -> UIImage {
        if
            mimeType.caseInsensitiveCompare(MimeType.imageJpeg.rawValue) == .orderedSame,
            /// We can use a CGDataProvider. UIImage tends to load the whole thing into memory _anyway_,
            /// but this at least makes it possible for it to choose not to.
            let jpegImage = try? CGDataProvider.loadFromEncryptedFile(
                at: fileURL,
                encryptionKey: encryptionKey,
                plaintextLength: plaintextLength,
                block: { dataProvider in
                    let (cgImage, orientation) = try dataProvider.toJpegCGImage()
                    return UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
                }
            )
        {
            return jpegImage
        }
        if
            mimeType.caseInsensitiveCompare(MimeType.imagePng.rawValue) == .orderedSame,
            /// We can use a CGDataProvider. UIImage tends to load the whole thing into memory _anyway_,
            /// but this at least makes it possible for it to choose not to.
            let pngImage = try? CGDataProvider.loadFromEncryptedFile(
                at: fileURL,
                encryptionKey: encryptionKey,
                plaintextLength: plaintextLength,
                block: { dataProvider in
                    return UIImage(cgImage: try dataProvider.toPngCGImage())
                }
            )
        {
            return pngImage
        }

        Logger.warn("Loading non-jpeg, non-png image into memory")
        // hmac and digest are validated at download time; no need to revalidate every read.
        let data = try Cryptography.decryptFileWithoutValidating(
            at: fileURL,
            metadata: .init(
                key: encryptionKey,
                plaintextLength: plaintextLength.map(Int.init(_:))
            )
        )
        let image: UIImage?
        if mimeType.caseInsensitiveCompare(MimeType.imageWebp.rawValue) == .orderedSame {
            /// Use YYImage for webp.
            image = YYImage(data: data)
        } else {
            image = UIImage(data: data)
        }

        guard let image else {
            throw OWSAssertionError("Failed to load image")
        }
        return image
    }
}

extension CGDataProvider {

    // Class-bound wrapper around EncryptedFileHandle
    class EncryptedFileHandleWrapper {
        let fileHandle: SignalServiceKit.EncryptedFileHandle

        init(_ fileHandle: SignalServiceKit.EncryptedFileHandle) {
            self.fileHandle = fileHandle
        }
    }

    /// If no plaintext length is provided, the file is assumed to only use pkcs7 padding.
    fileprivate static func loadFromEncryptedFile<T>(
        at fileURL: URL,
        encryptionKey: Data,
        plaintextLength: UInt32?,
        block: (CGDataProvider) throws -> T
    ) throws -> T {
        let fileHandle: EncryptedFileHandle
        if let plaintextLength {
            fileHandle = try Cryptography.encryptedAttachmentFileHandle(
                at: fileURL,
                plaintextLength: plaintextLength,
                encryptionKey: encryptionKey
            )
        } else {
            fileHandle = try Cryptography.encryptedFileHandle(
                at: fileURL,
                encryptionKey: encryptionKey
            )
        }
        let dataProvider = try CGDataProvider.from(fileHandle: fileHandle)
        return try block(dataProvider)
    }

    public static func from(fileHandle: EncryptedFileHandle) throws -> CGDataProvider {
        let fileHandle = EncryptedFileHandleWrapper(fileHandle)

        var callbacks = CGDataProviderDirectCallbacks(
            version: 0,
            getBytePointer: nil,
            releaseBytePointer: nil,
            getBytesAtPosition: { info, buffer, offset, byteCount in
                guard let info else {
                    return 0
                }
                let unmanagedFileHandle = Unmanaged<EncryptedFileHandleWrapper>.fromOpaque(info)
                let fileHandle = unmanagedFileHandle.takeUnretainedValue().fileHandle
                do {
                    if offset != fileHandle.offset() {
                        try fileHandle.seek(toOffset: UInt32(offset))
                    }
                    let data = try fileHandle.read(upToCount: UInt32(byteCount))
                    data.withUnsafeBytes { bytes in
                        buffer.copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
                    }
                    return data.count
                } catch {
                    return 0
                }
            },
            releaseInfo: { info in
                guard let info else {
                    return
                }
                let unmanagedFileHandle = Unmanaged<EncryptedFileHandleWrapper>.fromOpaque(info)
                unmanagedFileHandle.release()
            }
        )

        let unmanagedFileHandle = Unmanaged.passRetained(fileHandle)

        guard let dataProvider = CGDataProvider(
            directInfo: unmanagedFileHandle.toOpaque(),
            size: Int64(fileHandle.fileHandle.plaintextLength),
            callbacks: &callbacks
        ) else {
            throw OWSAssertionError("Failed to create data provider")
        }
        return dataProvider
    }
}

extension CGDataProvider {

    enum ParsingError: Error {
        case failedToParsePng
        case failedToParseJpg
    }

    fileprivate func toPngCGImage() throws -> CGImage {
        guard let cgImage = CGImage(
            pngDataProviderSource: self,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            throw ParsingError.failedToParsePng
        }
        return cgImage
    }

    fileprivate func toJpegCGImage() throws -> (CGImage, UIImage.Orientation) {
        let orientation: UIImage.Orientation = {
            guard let imageSource = CGImageSourceCreateWithDataProvider(self, nil) else {
                return nil
            }
            // Get image orientation
            let options: [CFString: Any] = [
                kCGImageSourceShouldAllowFloat: true
            ]
            let properties = CGImageSourceCopyPropertiesAtIndex(
                imageSource,
                0,
                options as CFDictionary
            ) as? [CFString: Any]
            guard
                let raw = properties?[kCGImagePropertyOrientation] as? Int,
                let raw = UInt32(exactly: raw)
            else {
                return nil
            }
            return CGImagePropertyOrientation(rawValue: raw)?.uiImageOrientation
        }() ?? .up

        guard let cgImage = CGImage(
            jpegDataProviderSource: self,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            throw ParsingError.failedToParseJpg
        }
        return (cgImage, orientation)
    }
}

extension CGImagePropertyOrientation {

    var uiImageOrientation: UIImage.Orientation {
        switch self {
        case .up:
            return .up
        case .down:
            return .down
        case .left:
            return .left
        case .right:
            return .right
        case .upMirrored:
            return .upMirrored
        case .downMirrored:
            return .downMirrored
        case .leftMirrored:
            return .leftMirrored
        case .rightMirrored:
            return .rightMirrored
        }
    }
}
