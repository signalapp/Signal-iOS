//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import blurhash

@objc
public class BlurHash: NSObject {

    // This should be generous.
    private static let maxLength = 100

    // A custom base 83 encoding is used.
    //
    // See: https://github.com/woltapp/blurhash/blob/master/Algorithm.md
    private static let validCharacterSet = CharacterSet(charactersIn: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~")

    @objc
    public class func isValidBlurHash(_ blurHash: String?) -> Bool {
        guard let blurHash = blurHash else {
            return false
        }
        guard blurHash.count >= 6 && blurHash.count < maxLength else {
            return false
        }
        return blurHash.unicodeScalars.allSatisfy { validCharacterSet.contains($0) }
    }

    @objc(ensureBlurHashForAttachmentStream:)
    public class func ensureBlurHashObjc(for attachmentStream: TSAttachmentStream) -> AnyPromise {
        return AnyPromise(ensureBlurHash(for: attachmentStream))
    }

    public class func ensureBlurHash(for attachmentStream: TSAttachmentStream) -> Promise<Void> {
        let (promise, future) = Promise<Void>.pending()

        DispatchQueue.global().async {
            guard attachmentStream.blurHash == nil else {
                // Attachment already has a blurHash.
                future.resolve()
                return
            }
            guard attachmentStream.isVisualMediaMimeType else {
                // We only generate a blurHash for visual media.
                future.resolve()
                return
            }
            guard attachmentStream.isValidVisualMedia else {
                future.reject(OWSAssertionError("Invalid attachment."))
                return
            }
            // Use the smallest available thumbnail; quality doesn't matter.
            // This is important for perf.
            guard let thumbnail: UIImage = attachmentStream.thumbnailImageSmallSync() else {
                future.reject(OWSAssertionError("Could not load small thumbnail."))
                return
            }
            guard let normalized = normalize(image: thumbnail, backgroundColor: .white) else {
                future.reject(OWSAssertionError("Could not normalize thumbnail."))
                return
            }
            // blurHash uses a DCT transform, so these are AC and DC components.
            // We use 4x3.
            //
            // https://github.com/woltapp/blurhash/blob/master/Algorithm.md
            guard let blurHash = normalized.blurHash(numberOfComponents: (4, 3)) else {
                future.reject(OWSAssertionError("Could not generate blurHash."))
                return
            }
            guard self.isValidBlurHash(blurHash) else {
                future.reject(OWSAssertionError("Generated invalid blurHash."))
                return
            }
            self.databaseStorage.write { transaction in
                attachmentStream.update(withBlurHash: blurHash, transaction: transaction)
            }
            Logger.verbose("Generated blurHash.")
            future.resolve()
        }

        return promise
    }

    // Large enough to reflect max quality of blurHash;
    // Small enough to avoid most perf hotspots around
    // these thumbnails.
    private static let kDefaultSize: CGFloat = 16

    @objc(imageForBlurHash:)
    public class func image(for blurHash: String) -> UIImage? {
        let thumbnailSize = imageSize(for: blurHash)
        guard let image = UIImage(blurHash: blurHash, size: thumbnailSize) else {
            owsFailDebug("Couldn't generate image for blurHash.")
            return nil
        }
        return image
    }

    private class func imageSize(for blurHash: String) -> CGSize {
        return CGSize(width: kDefaultSize, height: kDefaultSize)
    }

    // BlurHashEncode only works with images in a very specific
    // pixel format: RGBA8888.
    private class func normalize(image: UIImage, backgroundColor: UIColor) -> UIImage? {
        guard let cgImage = image.cgImage else {
            owsFailDebug("Invalid image.")
            return nil
        }

        // As long as we're normalizing the image, reduce the size.
        // The blurHash algorithm doesn't need more data.
        // This also places an upper bound on blurHash perf cost.
        let srcSize = image.pixelSize
        guard srcSize.width > 0, srcSize.height > 0 else {
            owsFailDebug("Invalid image size.")
            return nil
        }
        let srcMinDimension: CGFloat = min(srcSize.width, srcSize.height)
        // Make sure the short dimension is N.
        let scale: CGFloat = min(1.0, kDefaultSize / srcMinDimension)
        let dstWidth: Int = Int(round(srcSize.width * scale))
        let dstHeight: Int = Int(round(srcSize.height * scale))
        let dstSize = CGSize(width: dstWidth, height: dstHeight)
        let dstRect = CGRect(origin: .zero, size: dstSize)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        // RGBA8888 pixel format
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil,
                                      width: dstWidth,
                                      height: dstHeight,
                                      bitsPerComponent: 8,
                                      bytesPerRow: dstWidth * 4,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo) else {
                                        return nil
        }
        context.setFillColor(backgroundColor.cgColor)
        context.fill(dstRect)
        context.draw(cgImage, in: dstRect)
        return (context.makeImage().flatMap { UIImage(cgImage: $0) })
    }
}
