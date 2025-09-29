//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import blurhash
import Foundation

final public class BlurHash {

    // This should be generous.
    private static let maxLength = 100

    // A custom base 83 encoding is used.
    //
    // See: https://github.com/woltapp/blurhash/blob/master/Algorithm.md
    private static let validCharacterSet = CharacterSet(charactersIn: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~")

    public class func isValidBlurHash(_ blurHash: String?) -> Bool {
        guard let blurHash = blurHash else {
            return false
        }
        guard blurHash.count >= 6 && blurHash.count < maxLength else {
            return false
        }
        return blurHash.unicodeScalars.allSatisfy { validCharacterSet.contains($0) }
    }

    public class func computeBlurHashSync(for image: UIImage) throws -> String {
        // Use a small thumbnail size; quality doesn't matter. This is important for perf.
        var thumbnail: UIImage
        let maxDimensionPixels: CGFloat = 200
        if image.pixelSize.width > maxDimensionPixels || image.pixelSize.height > maxDimensionPixels {
            thumbnail = try OWSMediaUtils.thumbnail(forImage: image, maxDimensionPixels: maxDimensionPixels)
        } else {
            thumbnail = image
        }
        guard let normalized = normalize(image: thumbnail, backgroundColor: .white) else {
            throw OWSAssertionError("Could not normalize thumbnail.")
        }
        // blurHash uses a DCT transform, so these are AC and DC components.
        // We use 4x3.
        //
        // https://github.com/woltapp/blurhash/blob/master/Algorithm.md
        guard let blurHash = normalized.blurHash(numberOfComponents: (4, 3)) else {
            throw OWSAssertionError("Could not generate blurHash.")
        }
        guard self.isValidBlurHash(blurHash) else {
            throw OWSAssertionError("Generated invalid blurHash.")
        }
        return blurHash
    }

    // Large enough to reflect max quality of blurHash;
    // Small enough to avoid most perf hotspots around
    // these thumbnails.
    private static let kDefaultSize: CGFloat = 16

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
