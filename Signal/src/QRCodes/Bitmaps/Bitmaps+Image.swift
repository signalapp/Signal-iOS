//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CoreGraphics
import Foundation
import SignalServiceKit

extension Bitmaps {
    /// A bitmap representation of an image.
    ///
    /// Bitmaps have origin at the bottom-left, matching the default
    /// CoreGraphics context orientation.
    struct Image {
        struct Pixel: Equatable {
            let r: UInt8
            let g: UInt8
            let b: UInt8
            let a: UInt8
        }

        /// Width of the image, in pixels.
        let width: Int

        /// Height of the image, in pixels.
        let height: Int

        /// Number of bytes per row in the image. Note that a row may contain
        /// padding as well as pixel data, in order to maintain byte alignment.
        /// - SeeAlso
        /// https://stackoverflow.com/a/25706554/10901655
        /// - SeeAlso
        /// https://stackoverflow.com/questions/31212402/getting-pixel-data-from-cgimageref-contains-extra-bytes
        let bytesPerRow: Int

        /// The number of bytes used to represent each pixel - one each for the
        /// `{R,G,B,A}` tuple.
        private let bytesPerPixel: Int = 4

        /// The raw bytes of the image. Pixels are represented as `{R,G,B,A}` byte
        /// tuples. Note that these bytes may include alignment padding as well as
        /// pixel bytes.
        private let bytes: [UInt8]

        #if TESTABLE_BUILD
        init(width: Int, height: Int, rawBytes: [UInt8]) {
            self.width = width
            self.height = height
            self.bytesPerRow = 4 * width
            self.bytes = rawBytes
        }
        #endif

        /// Create a bitmap of the given image.
        ///
        /// Bitmaps, like default CoreGraphics contexts, have their origin in
        /// the bottom-left. However, most images (including those coming from
        /// UIKit or CoreImage) have their origin in the upper-left.
        ///
        /// This method assumes the given image has its origin in the upper-left
        /// and inverts it accordingly when creating the bitmap.
        init?(cgImage: CGImage) {
            guard cgImage.width > 0, cgImage.height > 0 else {
                owsFailDebug("Invalid image size! \(cgImage.width), \(cgImage.height)")
                return nil
            }

            guard cgImage.bytesPerRow > 0 else {
                owsFailDebug("Invalid image bytes per row! \(cgImage.bytesPerRow)")
                return nil
            }

            self.width = cgImage.width
            self.height = cgImage.height
            self.bytesPerRow = cgImage.bytesPerRow

            var imageBytes = [UInt8](repeating: 0, count: height * bytesPerRow)

            guard let cgContext = CGContext(
                data: &imageBytes,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                owsFailDebug("Failed to create CGContext!")
                return nil
            }

            // Flip the context so as to match the image orientation.
            cgContext.scaleBy(x: 1, y: -1)
            cgContext.translateBy(x: 0, y: -CGFloat(height))

            cgContext.draw(cgImage, in: cgImage.boundingRect)

            self.bytes = imageBytes
        }

        /// Whether there is a pixel at the given point with non-zero alpha. Returns
        /// `false` if the point is out of bounds.
        func hasVisiblePixel(at point: Point) -> Bool {
            guard let pixel = pixel(at: point) else {
                return false
            }

            return pixel.a > 0
        }

        /// Get the pixel at the given point.
        /// - Returns
        /// The pixel, or `nil` if the point is out of bounds.
        func pixel(at point: Point) -> Pixel? {
            guard point.x < width, point.y < height else {
                return nil
            }

            let pixelRowStartOffset = point.y * bytesPerRow
            let pixelOffsetInRow = point.x * bytesPerPixel

            let pixelStartOffset = pixelRowStartOffset + pixelOffsetInRow

            guard pixelStartOffset + 3 < bytes.count else {
                return nil
            }

            return Pixel(
                r: bytes[pixelStartOffset],
                g: bytes[pixelStartOffset + 1],
                b: bytes[pixelStartOffset + 2],
                a: bytes[pixelStartOffset + 3]
            )
        }
    }
}

private extension CGImage {
    /// Represents the bounds of the full image.
    var boundingRect: CGRect {
        return CGRect(x: 0, y: 0, width: width, height: height)
    }
}
