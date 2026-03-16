//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import UniformTypeIdentifiers

/// Represents ``PreviewableAttachment``s that are images. This is roughly
/// equivalent to a "previewable image attachment".
///
/// This type (via `finalizeImage`) can be used to produce an image that's
/// acceptable for ``SendableAttachment``/sending via Signal.
public struct NormalizedImage {
    let dataSource: DataSourcePath
    let dataUTI: String

    /// If true, this image must be re-compressed when finalizing it. This is
    /// typically true when an input has large dimensions and must be resized
    /// for compatibility with the editing pipeline.
    let mustCompress: Bool

    /// If true, this data source may have metadata that must be stripped when
    /// finalizing it.
    let mayHaveMetadata: Bool

    /// If true, this image may have transparency that should be maintained when
    /// finalizing it.
    let mayHaveTransparency: Bool

    // MARK: - Resizing

    /// Load and resize an image.
    private static func loadImage(dataSource: DataSourcePath, maxPixelSize: CGFloat) throws(SignalAttachmentError) -> CGImage {
        let imageSource = CGImageSourceCreateWithURL(dataSource.fileUrl as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        guard let imageSource else {
            throw .couldNotParseImage
        }
        guard let result = loadImage(imageSource: imageSource, maxPixelSize: maxPixelSize) else {
            throw .couldNotResizeImage
        }
        return result
    }

    public static func loadImage(imageSource: CGImageSource, maxPixelSize: CGFloat) -> CGImage? {
        // NOTE: For unknown reasons, resizing images with UIGraphicsBeginImageContext()
        // crashes reliably in the share extension after screen lock's auth UI has been presented.
        // Resizing using a CGContext seems to work fine.

        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as [CFString: Any] as CFDictionary

        return CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions)
    }

    private enum ContainerType {
        case jpg
        case png

        var dataType: UTType {
            switch self {
            case .jpg: UTType.jpeg
            case .png: UTType.png
            }
        }

        var fileExtension: String {
            switch self {
            case .jpg: "jpg"
            case .png: "png"
            }
        }
    }

    /// Save an image to disk.
    private static func saveImage(_ image: CGImage, containerType: ContainerType) throws(SignalAttachmentError) -> DataSourcePath {
        let tempFileUrl = OWSFileSystem.temporaryFileUrl(
            fileExtension: containerType.fileExtension,
            isAvailableWhileDeviceLocked: false,
        )
        let destination = CGImageDestinationCreateWithURL(tempFileUrl as CFURL, containerType.dataType.identifier as CFString, 1, nil)
        guard let destination else {
            throw .couldNotConvertImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw .couldNotConvertImage
        }
        return DataSourcePath(fileUrl: tempFileUrl, ownership: .owned)
    }

    // MARK: - Normalize

    /// Construct a normalized image from an image.
    public static func forImage(
        _ image: UIImage,
        sourceFilename: String? = nil,
        mayHaveTransparency: Bool = false,
    ) throws -> Self {
        let containerType = ContainerType.png
        guard let imageData = image.pngData() else {
            throw SignalAttachmentError.couldNotConvertImage
        }
        Logger.info("creating forImage")
        let dataSource = try DataSourcePath(writingTempFileData: imageData, fileExtension: containerType.fileExtension)
        dataSource.sourceFilename = Self.replaceFileExtension(sourceFilename: sourceFilename, newFileExtension: containerType.fileExtension)
        return try forDataSource(
            dataSource,
            dataUTI: containerType.dataType.identifier,
            mustCompress: !mayHaveTransparency,
            mayHaveMetadata: false,
            mayHaveTransparency: mayHaveTransparency,
        )
    }

    /// Construct a normalized image from arbitrary input.
    ///
    /// - Parameter mayHaveMetadata: If true, indicates that the image might
    /// have metadata that must be stripped for the finalized image. If false,
    /// `dataSource` may pass through as the finalizd image (assuming it meets
    /// all the other validation criteria).
    ///
    /// - Parameter mayHaveTransparency: If true, sticker-like images will be
    /// finalized in a format that supports transparency (e.g., PNG). If false,
    /// all images (include sticker-like images) will be finalized in a format
    /// that doesn't support transparency (e.g., JPG).
    static func forDataSource(
        _ dataSource: DataSourcePath,
        dataUTI: String,
        mustCompress: Bool = false,
        mayHaveMetadata: Bool = true,
        mayHaveTransparency: Bool = true,
    ) throws -> Self {
        // When preparing an attachment, we always prepare it in the max quality
        // for the current context. The user can choose during sending whether they
        // want the final send to be in standard or high quality. We will do the
        // final convert and compress before uploading.

        let imageQuality = ImageQualityLevel.maximumForCurrentAppContext()
        let imageMetadata = try? dataSource.imageSource().imageMetadata()

        // If the original has the right dimensions and a valid format, it might be
        // valid, and it's fine to use it as an intermediate normalized image. If
        // the file size is too large, we'll compress it when finalizing.
        let originalMightBeValid = { () -> Bool in
            guard SignalAttachment.outputImageUTISet.contains(dataUTI) else {
                return false
            }
            guard let imageMetadata, imageMetadata.pixelSize.largerAxis <= imageQuality.startingTier.maxEdgeSize else {
                return false
            }
            return true
        }()

        Logger.info("creating forDataSource (originalMightBeValid: \(originalMightBeValid))")

        let normalizedDataSource: DataSourcePath
        let normalizedDataUTI: String

        var mustCompress = mustCompress
        var mayHaveMetadata = mayHaveMetadata
        // We convert everything that's not sticker-like to JPG because images with
        // alpha channels often don't actually have any transparent pixels (all
        // screenshots fall into this bucket) and there is not a simple, performant
        // way to check if there are any transparent pixels in an image.
        let mayHaveTransparency = mayHaveTransparency && imageMetadata?.hasStickerLikeProperties == true

        if originalMightBeValid {
            // If we might be able to use the original, we'll leave it as is for now.
            normalizedDataSource = dataSource
            normalizedDataUTI = dataUTI
        } else {
            // If we can't use the original, we convert it to a lossless intermediate
            // representation for use throughout the remainder of the image pipeline.
            (normalizedDataSource, normalizedDataUTI) = try normalizingDataSource(
                dataSource,
                imageQuality: imageQuality,
            )
            mayHaveMetadata = false
            mustCompress = mustCompress || !mayHaveTransparency
        }
        return Self(
            dataSource: normalizedDataSource,
            dataUTI: normalizedDataUTI,
            mustCompress: mustCompress,
            mayHaveMetadata: mayHaveMetadata,
            mayHaveTransparency: mayHaveTransparency,
        )
    }

    /// Produce an intermediate representation for an image.
    ///
    /// This is used for images with unusual formats or unusually large dimensions.
    ///
    /// We always store these images as PNGs because it's a lossless format. In
    /// `finalizeImage`, we'll convert it to JPEG (unless it's a sticker).
    private static func normalizingDataSource(
        _ dataSource: DataSourcePath,
        imageQuality: ImageQualityLevel,
    ) throws(SignalAttachmentError) -> (dataSource: DataSourcePath, dataUTI: String) {
        let tier = imageQuality.startingTier
        return try autoreleasepool { () throws(SignalAttachmentError) -> (dataSource: DataSourcePath, dataUTI: String) in
            let containerType = ContainerType.png
            let cgImage = try loadImage(dataSource: dataSource, maxPixelSize: tier.maxEdgeSize)
            let outputDataSource = try saveImage(cgImage, containerType: containerType)
            outputDataSource.sourceFilename = Self.replaceFileExtension(
                sourceFilename: dataSource.sourceFilename,
                newFileExtension: containerType.fileExtension,
            )
            return (outputDataSource, containerType.dataType.identifier)
        }
    }

    // MARK: - Compress

    struct FinalizedImage {
        let dataSource: DataSourcePath
        let dataUTI: String
    }

    func finalizeImage(imageQuality: ImageQualityLevel) throws -> FinalizedImage {
        Logger.info("finalizing (mustCompress: \(mustCompress))")
        if !mustCompress {
            // When constructing a NormalizedImage, we check if the original image
            // could ever be valid (i.e., against the maximum possible quality). When
            // finalizing, the user may have selected a lower quality, and that may
            // mean that the original is no longer valid.
            let isOriginalStillValid = try { () -> Bool in
                let fileSize = try dataSource.readLength()
                guard fileSize <= imageQuality.maxFileSize else {
                    return false
                }
                let imageMetadata = try? dataSource.imageSource().imageMetadata()
                guard let imageMetadata, imageMetadata.pixelSize.largerAxis <= imageQuality.startingTier.maxEdgeSize else {
                    return false
                }
                return fileSize <= imageQuality.maxOriginalFileSize || imageMetadata.hasStickerLikeProperties
            }()
            Logger.info("finalizing (isOriginalStillValid: \(isOriginalStillValid))")
            if isOriginalStillValid {
                Logger.info("finalizing (mayHaveMetadata: \(mayHaveMetadata))")
                if !mayHaveMetadata {
                    return FinalizedImage(dataSource: dataSource, dataUTI: dataUTI)
                }
                let strippedDataSource = try stripImage()
                Logger.info("finalizing (strippedDataSource != nil: \(strippedDataSource != nil))")
                if let strippedDataSource {
                    return FinalizedImage(dataSource: strippedDataSource, dataUTI: dataUTI)
                }
            }
        }
        return try compressImageToQuality(imageQuality)
    }

    /// Strip metadata from a passthrough image.
    private func stripImage() throws -> DataSourcePath? {
        // If we can't strip it, we can fall back to compressing it.
        let strippedData = try? Self.removeImageMetadata(fromData: dataSource.readData(), dataUti: dataUTI)
        guard let strippedData else {
            return nil
        }
        // If we can strip it but can't write it to disk, we have bigger problems.
        guard let fileExtension = MimeTypeUtil.fileExtensionForUtiType(dataUTI) else {
            throw SignalAttachmentError.couldNotRemoveMetadata
        }
        let dataSource = try DataSourcePath(writingTempFileData: strippedData, fileExtension: fileExtension)
        dataSource.sourceFilename = Self.replaceFileExtension(
            sourceFilename: dataSource.sourceFilename,
            newFileExtension: fileExtension,
        )
        return dataSource
    }

    /// Compress the image to the largest tier that fits the specified quality.
    private func compressImageToQuality(_ imageQuality: ImageQualityLevel) throws -> FinalizedImage {
        var nextTier: ImageQualityTier? = imageQuality.startingTier
        while let currentTier = nextTier {
            Logger.info("compressing to tier \(currentTier.rawValue)")
            let result = try autoreleasepool { () throws -> FinalizedImage? in
                let result = try compressImageToTier(currentTier)
                let outputFileSize = try result.dataSource.readLength()
                if outputFileSize <= imageQuality.maxFileSize {
                    return result
                }
                return nil
            }
            if let result {
                return result
            }
            // If the image output is larger than the file size limit, continue to try
            // again by progressively reducing the image upload quality.
            nextTier = currentTier.reduced
        }
        throw SignalAttachmentError.fileSizeTooLarge
    }

    /// Compress the image to the specified tier.
    private func compressImageToTier(_ tier: ImageQualityTier) throws(SignalAttachmentError) -> FinalizedImage {
        let cgImage = try Self.loadImage(dataSource: dataSource, maxPixelSize: tier.maxEdgeSize)

        let containerType: ContainerType
        var imageProperties = [CFString: Any]()

        if self.mayHaveTransparency {
            containerType = .png
        } else {
            containerType = .jpg
            let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
            imageProperties[kCGImageDestinationLossyCompressionQuality] = Self.compressionQuality(for: imageSize)
        }

        let outputDataSource = try Self.saveImage(cgImage, containerType: containerType)
        outputDataSource.sourceFilename = Self.replaceFileExtension(
            sourceFilename: dataSource.sourceFilename,
            newFileExtension: containerType.fileExtension,
        )
        return FinalizedImage(
            dataSource: outputDataSource,
            dataUTI: containerType.dataType.identifier,
        )
    }

    private static func compressionQuality(for pixelSize: CGSize) -> CGFloat {
        // For very large images, we can use a higher
        // jpeg compression without seeing artifacting
        if pixelSize.largerAxis >= 3072 { return 0.55 }
        return 0.6
    }

    private static func replaceFileExtension(sourceFilename: String?, newFileExtension fileExtension: String) -> String? {
        guard let sourceFilename else {
            return nil
        }
        let sourceFilenameWithoutExtension = (sourceFilename as NSString).deletingPathExtension
        let sourceFilenameWithExtension = (sourceFilenameWithoutExtension as NSString).appendingPathExtension(fileExtension)
        return sourceFilenameWithExtension ?? sourceFilenameWithoutExtension
    }

    // MARK: - Stripping

    private static let preservedMetadata: [CFString] = [
        "\(kCGImageMetadataPrefixTIFF):\(kCGImagePropertyTIFFOrientation)" as CFString,
        "\(kCGImageMetadataPrefixIPTCCore):\(kCGImagePropertyIPTCImageOrientation)" as CFString,
    ]

    private static let pngChunkTypesToKeep: Set<Data> = {
        let asAscii: [String] = [
            // [Critical chunks.][0]
            // [0]: https://www.w3.org/TR/PNG/#11Critical-chunks
            "IHDR",
            "PLTE",
            "IDAT",
            "IEND",
            // [Ancillary chunks][1] that might affect rendering.
            // [1]: https://www.w3.org/TR/PNG/#11Ancillary-chunks
            "tRNS",
            "cHRM",
            "gAMA",
            "iCCP",
            "sRGB",
            "bKGD",
            "pHYs",
            "sPLT",
            // [Animated PNG chunks.][2]
            // [2]: https://wiki.mozilla.org/APNG_Specification#Structure
            "acTL",
            "fcTL",
            "fdAT",
        ]
        let asBytes = asAscii.lazy.compactMap { $0.data(using: .ascii) }
        return Set(asBytes)
    }()

    private static func removeImageMetadata(fromData dataValue: Data, dataUti: String) throws(SignalAttachmentError) -> Data {
        if dataUti == UTType.png.identifier {
            return try self.removeImageMetadata(fromPngData: dataValue)
        } else {
            return try self.removeImageMetadata(fromNonPngData: dataValue)
        }
    }

    /// Remove nonessential chunks from PNG data.
    /// - Returns: Cleaned PNG data.
    /// - Throws: `SignalAttachmentError.couldNotRemoveMetadata` if the PNG parser fails.
    static func removeImageMetadata(fromPngData pngData: Data) throws(SignalAttachmentError) -> Data {
        do {
            let chunker = try PngChunker(source: DataImageSource(pngData))
            var result = PngChunker.pngSignature
            while let chunk = try chunker.next() {
                if pngChunkTypesToKeep.contains(chunk.type) {
                    result += chunk.allBytes()
                }
            }
            return result
        } catch {
            Logger.warn("Could not remove PNG metadata: \(error)")
            throw .couldNotRemoveMetadata
        }
    }

    private static func removeImageMetadata(fromNonPngData dataValue: Data) throws(SignalAttachmentError) -> Data {
        guard let source = CGImageSourceCreateWithData(dataValue as CFData, nil) else {
            throw .couldNotRemoveMetadata
        }

        guard let type = CGImageSourceGetType(source) else {
            throw .couldNotRemoveMetadata
        }

        // 10-18-2023: Due to an issue with corrupt JPEG IPTC metadata causing a
        // crash in CGImageDestinationCopyImageSource, stop using the original
        // JPEGs and instead go through the recompresing step. This is an iOS bug
        // (FB13285956) still present in iOS 17 and should be revisited in the
        // future to see if JPEG support can be reenabled.
        guard (type as String) != UTType.jpeg.identifier else {
            Logger.warn("falling back to compression for JPEG")
            throw .couldNotRemoveMetadata
        }

        let count = CGImageSourceGetCount(source)
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData as CFMutableData, type, count, nil) else {
            throw .couldNotRemoveMetadata
        }

        // Build up a metadata with CFNulls in the place of all tags present in the original metadata.
        // (Unfortunately CGImageDestinationCopyImageSource can only merge metadata, not replace it.)
        let metadata = CGImageMetadataCreateMutable()
        let enumerateOptions: NSDictionary = [kCGImageMetadataEnumerateRecursively: false]
        var hadError = false
        for i in 0..<count {
            guard let originalMetadata = CGImageSourceCopyMetadataAtIndex(source, i, nil) else {
                throw .couldNotRemoveMetadata
            }
            CGImageMetadataEnumerateTagsUsingBlock(originalMetadata, nil, enumerateOptions) { path, tag in
                if Self.preservedMetadata.contains(path) {
                    return true
                }
                guard
                    let namespace = CGImageMetadataTagCopyNamespace(tag),
                    let prefix = CGImageMetadataTagCopyPrefix(tag),
                    CGImageMetadataRegisterNamespaceForPrefix(metadata, namespace, prefix, nil),
                    CGImageMetadataSetValueWithPath(metadata, nil, path, kCFNull)
                else {
                    hadError = true
                    return false // stop iteration
                }
                return true
            }
            if hadError {
                throw .couldNotRemoveMetadata
            }
        }

        let copyOptions: NSDictionary = [
            kCGImageDestinationMergeMetadata: true,
            kCGImageDestinationMetadata: metadata,
        ]
        guard CGImageDestinationCopyImageSource(destination, source, copyOptions, nil) else {
            throw .couldNotRemoveMetadata
        }

        return mutableData as Data
    }
}
