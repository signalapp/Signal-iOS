// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import ImageIO

public extension Data {
    var isValidImage: Bool {
        let imageFormat: ImageFormat = self.guessedImageFormat
        let isAnimated: Bool = (imageFormat == .gif)
        let maxFileSize: UInt = (isAnimated ?
            OWSMediaUtils.kMaxFileSizeAnimatedImage :
            OWSMediaUtils.kMaxFileSizeImage
        )
        
        return (
            count < maxFileSize &&
            isValidImage(mimeType: nil, format: imageFormat) &&
            hasValidImageDimensions(isAnimated: isAnimated)
        )
    }
    
    var guessedImageFormat: ImageFormat {
        let twoBytesLength: Int = 2
        
        guard count > twoBytesLength else { return .unknown }

        var bytes: [UInt8] = [UInt8](repeating: 0, count: twoBytesLength)
        self.copyBytes(to: &bytes, from: (self.startIndex..<self.startIndex.advanced(by: twoBytesLength)))

        switch (bytes[0], bytes[1]) {
            case (0x47, 0x49): return .gif
            case (0x89, 0x50): return .png
            case (0xff, 0xd8): return .jpeg
            case (0x42, 0x4d): return .bmp
            case (0x4D, 0x4D): return .tiff // Motorola byte order TIFF
            case (0x49, 0x49): return .tiff // Intel byte order TIFF
            case (0x52, 0x49): return .webp // First two letters of WebP
                
            default: return .unknown
        }
    }
    
    // Parse the GIF header to prevent the "GIF of death" issue.
    //
    // See: https://blog.flanker017.me/cve-2017-2416-gif-remote-exec/
    // See: https://www.w3.org/Graphics/GIF/spec-gif89a.txt
    var hasValidGifSize: Bool {
        let signatureLength: Int = 3
        let versionLength: Int = 3
        let widthLength: Int = 2
        let heightLength: Int = 2
        let prefixLength: Int = (signatureLength + versionLength)
        let bufferLength: Int = (signatureLength + versionLength + widthLength + heightLength)
        
        guard count > bufferLength else { return false }

        var bytes: [UInt8] = [UInt8](repeating: 0, count: bufferLength)
        self.copyBytes(to: &bytes, from: (self.startIndex..<self.startIndex.advanced(by: bufferLength)))

        let gif87APrefix: [UInt8] = [0x47, 0x49, 0x46, 0x38, 0x37, 0x61]
        let gif89APrefix: [UInt8] = [0x47, 0x49, 0x46, 0x38, 0x39, 0x61]
        
        guard bytes.starts(with: gif87APrefix) || bytes.starts(with: gif89APrefix) else {
            return false
        }
        
        let width: UInt = (UInt(bytes[prefixLength]) | (UInt(bytes[prefixLength + 1]) << 8))
        let height: UInt = (UInt(bytes[prefixLength + 2]) | (UInt(bytes[prefixLength + 3]) << 8))

        // We need to ensure that the image size is "reasonable"
        // We impose an arbitrary "very large" limit on image size
        // to eliminate harmful values
        let maxValidSize: UInt = (1 << 18)

        return (width > 0 && width < maxValidSize && height > 0 && height < maxValidSize)
    }
    
    func hasValidImageDimensions(isAnimated: Bool) -> Bool {
        guard
            let dataPtr: CFData = CFDataCreate(kCFAllocatorDefault, self.bytes, self.count),
            let imageSource = CGImageSourceCreateWithData(dataPtr, nil)
        else { return false }

        return Data.hasValidImageDimension(source: imageSource, isAnimated: isAnimated)
    }
    
    func isValidImage(mimeType: String?, format: ImageFormat) -> Bool {
        // Don't trust the file extension; iOS (e.g. UIKit, Core Graphics) will happily
        // load a .gif with a .png file extension
        //
        // Instead, use the "magic numbers" in the file data to determine the image format
        //
        // If the image has a declared MIME type, ensure that agrees with the
        // deduced image format
        switch format {
            case .unknown: return false
            case .png: return (mimeType == nil || mimeType == OWSMimeTypeImagePng)
            case .jpeg: return (mimeType == nil || mimeType == OWSMimeTypeImageJpeg)
                
            case .gif:
                guard hasValidGifSize else { return false }
                
                return (mimeType == nil || mimeType == OWSMimeTypeImageGif)
                
            case .tiff:
                return (
                    mimeType == nil ||
                    mimeType == OWSMimeTypeImageTiff1 ||
                    mimeType == OWSMimeTypeImageTiff2
                )

            case .bmp:
                return (
                    mimeType == nil ||
                    mimeType == OWSMimeTypeImageBmp1 ||
                    mimeType == OWSMimeTypeImageBmp2
                )
                
            case .webp:
                return (mimeType == nil || mimeType == OWSMimeTypeImageWebp)
        }
    }
    
    static func hasValidImageDimension(source: CGImageSource, isAnimated: Bool) -> Bool {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return false }
        guard let width = properties[kCGImagePropertyPixelWidth] as? Double else { return false }
        guard let height = properties[kCGImagePropertyPixelHeight] as? Double else { return false }

        // The number of bits in each color sample of each pixel. The value of this key is a CFNumberRef
        guard let depthBits = properties[kCGImagePropertyDepth] as? UInt else { return false }
        
        // This should usually be 1.
        let depthBytes: CGFloat = ceil(CGFloat(depthBits) / 8.0)

        // The color model of the image such as "RGB", "CMYK", "Gray", or "Lab"
        // The value of this key is CFStringRef
        guard
            let colorModel = properties[kCGImagePropertyColorModel] as? String,
            (
                colorModel != (kCGImagePropertyColorModelRGB as String) ||
                colorModel != (kCGImagePropertyColorModelGray as String)
            )
        else { return false }

        // We only support (A)RGB and (A)Grayscale, so worst case is 4.
        let worseCastComponentsPerPixel: CGFloat = 4
        let bytesPerPixel: CGFloat = (worseCastComponentsPerPixel * depthBytes)

        let expectedBytePerPixel: CGFloat = 4
        let maxValidImageDimension: CGFloat = CGFloat(isAnimated ?
            OWSMediaUtils.kMaxAnimatedImageDimensions :
            OWSMediaUtils.kMaxStillImageDimensions
        )
        let maxBytes: CGFloat = (maxValidImageDimension * maxValidImageDimension * expectedBytePerPixel)
        let actualBytes: CGFloat = (width * height * bytesPerPixel)
        
        return (actualBytes <= maxBytes)
    }
}
