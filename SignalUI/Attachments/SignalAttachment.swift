//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import AVFoundation
import Foundation
import MobileCoreServices
import SDWebImage
public import SignalServiceKit

public enum SignalAttachmentError: Error {
    case missingData
    case fileSizeTooLarge
    case invalidData
    case couldNotParseImage
    case couldNotConvertImage
    case couldNotConvertToMpeg4
    case couldNotRemoveMetadata
    case invalidFileFormat
    case couldNotResizeImage
}

// MARK: -

extension SignalAttachmentError: LocalizedError, UserErrorDescriptionProvider {
    public var errorDescription: String? {
        localizedDescription
    }

    public var localizedDescription: String {
        switch self {
        case .missingData:
            return OWSLocalizedString("ATTACHMENT_ERROR_MISSING_DATA", comment: "Attachment error message for attachments without any data")
        case .fileSizeTooLarge:
            return OWSLocalizedString("ATTACHMENT_ERROR_FILE_SIZE_TOO_LARGE", comment: "Attachment error message for attachments whose data exceed file size limits")
        case .invalidData:
            return OWSLocalizedString("ATTACHMENT_ERROR_INVALID_DATA", comment: "Attachment error message for attachments with invalid data")
        case .couldNotParseImage:
            return OWSLocalizedString("ATTACHMENT_ERROR_COULD_NOT_PARSE_IMAGE", comment: "Attachment error message for image attachments which cannot be parsed")
        case .couldNotConvertImage:
            return OWSLocalizedString("ATTACHMENT_ERROR_COULD_NOT_CONVERT_TO_JPEG", comment: "Attachment error message for image attachments which could not be converted to JPEG")
        case .invalidFileFormat:
            return OWSLocalizedString("ATTACHMENT_ERROR_INVALID_FILE_FORMAT", comment: "Attachment error message for attachments with an invalid file format")
        case .couldNotConvertToMpeg4:
            return OWSLocalizedString("ATTACHMENT_ERROR_COULD_NOT_CONVERT_TO_MP4", comment: "Attachment error message for video attachments which could not be converted to MP4")
        case .couldNotRemoveMetadata:
            return OWSLocalizedString("ATTACHMENT_ERROR_COULD_NOT_REMOVE_METADATA", comment: "Attachment error message for image attachments in which metadata could not be removed")
        case .couldNotResizeImage:
            return OWSLocalizedString("ATTACHMENT_ERROR_COULD_NOT_RESIZE_IMAGE", comment: "Attachment error message for image attachments which could not be resized")
        }
    }
}

// MARK: -

// Represents a possible attachment to upload.
//
// Signal attachments are subject to validation and, in some cases, file
// format conversion.
//
// This class gathers that logic. It offers factory methods for attachments
// that do the necessary work.
//
// TODO: Perhaps do conversion off the main thread?

public class SignalAttachment: CustomDebugStringConvertible {

    // MARK: Properties

    public let dataSource: DataSourcePath

    // Attachment types are identified using UTIs.
    //
    // See: https://developer.apple.com/library/content/documentation/Miscellaneous/Reference/UTIRef/Articles/System-DeclaredUniformTypeIdentifiers.html
    public let dataUTI: String

    // To avoid redundant work of repeatedly compressing/uncompressing
    // images, we cache the UIImage associated with this attachment if
    // possible.
    private var cachedImage: UIImage?
    private var cachedThumbnail: UIImage?
    private var cachedVideoPreview: UIImage?

    public var isVoiceMessage = false

    public static let maxAttachmentsAllowed: Int = 32

    // MARK: Constructor

    // This method should not be called directly; use the factory
    // methods instead.
    init(dataSource: DataSourcePath, dataUTI: String) {
        self.dataSource = dataSource
        self.dataUTI = dataUTI

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didReceiveMemoryWarningNotification),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
        )
    }

    @objc
    private func didReceiveMemoryWarningNotification() {
        cachedImage = nil
        cachedThumbnail = nil
        cachedVideoPreview = nil
    }

    // MARK: Methods

    public var debugDescription: String {
        return "[SignalAttachment mimeType: \(mimeType)]"
    }

    public func staticThumbnail() -> UIImage? {
        if let cachedThumbnail {
            return cachedThumbnail
        }

        return autoreleasepool {
            guard
                let image: UIImage = {
                    if isImage {
                        return image()
                    } else if isVideo {
                        return videoPreview()
                    } else if isAudio {
                        return nil
                    } else {
                        return nil
                    }
                }() else { return nil }

            // We want to limit the *smaller* dimension to 60 points,
            // so figure out what the larger dimension would need to
            // be limited to if we preserved our aspect ratio. This
            // ensures crisp thumbnails when we center crop in a
            // 60x60 or smaller container.
            let pixelSize = image.pixelSize
            let maxDimensionPixels = ((60 * UIScreen.main.scale) / pixelSize.smallerAxis).clamp01() * pixelSize.largerAxis

            let thumbnail = image.resized(maxDimensionPixels: maxDimensionPixels)
            cachedThumbnail = thumbnail
            return thumbnail
        }
    }

    public var renderingFlag: AttachmentReference.RenderingFlag {
        if isVoiceMessage {
            return .voiceMessage
        } else if isBorderless {
            return .borderless
        } else if isLoopingVideo || MimeTypeUtil.isSupportedDefinitelyAnimatedMimeType(mimeType) {
            return .shouldLoop
        } else {
            return .default
        }
    }

    public func image() -> UIImage? {
        if let cachedImage {
            return cachedImage
        }
        guard let imageData = try? dataSource.readData(), let image = UIImage(data: imageData) else {
            return nil
        }
        cachedImage = image
        return image
    }

    public func videoPreview() -> UIImage? {
        if let cachedVideoPreview {
            return cachedVideoPreview
        }

        let mediaUrl = dataSource.fileUrl

        do {
            let filePath = mediaUrl.path
            guard FileManager.default.fileExists(atPath: filePath) else {
                owsFailDebug("asset at \(filePath) doesn't exist")
                return nil
            }

            let asset = AVURLAsset(url: mediaUrl)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            let cgImage = try generator.copyCGImage(at: CMTimeMake(value: 0, timescale: 1), actualTime: nil)
            let image = UIImage(cgImage: cgImage)

            cachedVideoPreview = image
            return image

        } catch {
            return nil
        }
    }

    public var isBorderless = false
    public var isLoopingVideo = false

    // Returns the MIME type for this attachment or nil if no MIME type
    // can be identified.
    public var mimeType: String {
        if isVoiceMessage {
            // Legacy iOS clients don't handle "audio/mp4" files correctly;
            // they are written to disk as .mp4 instead of .m4a which breaks
            // playback.  So we send voice messages as "audio/aac" to work
            // around this.
            //
            // TODO: Remove this Nov. 2016 or after.
            return "audio/aac"
        }

        if let filename = dataSource.sourceFilename?.filterFilename() {
            let fileExtension = (filename as NSString).pathExtension
            if !fileExtension.isEmpty {
                if let mimeType = MimeTypeUtil.mimeTypeForFileExtension(fileExtension) {
                    // UTI types are an imperfect means of representing file type;
                    // file extensions are also imperfect but far more reliable and
                    // comprehensive so we always prefer to try to deduce MIME type
                    // from the file extension.
                    return mimeType
                }
            }
        }
        return UTType(dataUTI)?.preferredMIMEType ?? MimeType.applicationOctetStream.rawValue
    }

    // Returns the file extension for this attachment or nil if no file extension
    // can be identified.
    public var fileExtension: String? {
        if let filename = dataSource.sourceFilename?.filterFilename() {
            let fileExtension = (filename as NSString).pathExtension
            if !fileExtension.isEmpty {
                return fileExtension.filterFilename()
            }
        }
        guard let fileExtension = MimeTypeUtil.fileExtensionForUtiType(dataUTI) else {
            return nil
        }
        return fileExtension
    }

    // Returns the set of UTIs that correspond to valid _input_ image formats
    // for Signal attachments.
    //
    // Image attachments may be converted to another image format before
    // being uploaded.
    public static let inputImageUTISet: Set<String> = {
        // We support additional types for input images because we can transcode
        // these to a format that's always supported by the receiver.
        var additionalTypes = [UTType]()
        if #available(iOS 18.2, *) {
            additionalTypes.append(.jpegxl)
        }
        additionalTypes.append(.heif)
        additionalTypes.append(.heic)
        additionalTypes.append(.webP)

        return outputImageUTISet.union(additionalTypes.map(\.identifier))
    }()

    // Returns the set of UTIs that correspond to valid _output_ image formats
    // for Signal attachments.
    private class var outputImageUTISet: Set<String> {
        MimeTypeUtil.supportedImageUtiTypes.union(animatedImageUTISet)
    }

    private class var outputVideoUTISet: Set<String> {
        [UTType.mpeg4Movie.identifier]
    }

    // Returns the set of UTIs that correspond to valid animated image formats
    // for Signal attachments.
    private class var animatedImageUTISet: Set<String> {
        MimeTypeUtil.supportedAnimatedImageUtiTypes
    }

    // Returns the set of UTIs that correspond to valid video formats
    // for Signal attachments.
    public class var videoUTISet: Set<String> {
        MimeTypeUtil.supportedVideoUtiTypes
    }

    // Returns the set of UTIs that correspond to valid audio formats
    // for Signal attachments.
    public class var audioUTISet: Set<String> {
        MimeTypeUtil.supportedAudioUtiTypes
    }

    // Returns the set of UTIs that correspond to valid image, video and audio formats
    // for Signal attachments.
    public class var mediaUTISet: Set<String> {
        return audioUTISet.union(videoUTISet).union(animatedImageUTISet).union(inputImageUTISet)
    }

    public var isImage: Bool {
        return SignalAttachment.outputImageUTISet.contains(dataUTI)
    }

    /// Only valid when `isImage` is true.
    ///
    /// If `isAnimatedImage` is true, then `isImage` must be true. In other
    /// words, all animated images are images (but not all images are animated).
    public var isAnimatedImage = false

    public var isVideo: Bool {
        return SignalAttachment.videoUTISet.contains(dataUTI)
    }

    public var isVisualMedia: Bool {
        return self.isImage || self.isVideo
    }

    public var isAudio: Bool {
        return SignalAttachment.audioUTISet.contains(dataUTI)
    }

    public var isUrl: Bool {
        UTType(dataUTI)?.conforms(to: .url) ?? false
    }

    // MARK: Image Attachments

    // If the proposed attachment already conforms to the
    // file size and content size limits, don't recompress it.
    static func isOriginalImageValid(
        forImageQuality imageQuality: ImageQualityLevel,
        fileSize: UInt64,
        dataUTI: String,
        imageMetadata: ImageMetadata?,
    ) -> Bool {
        // 10-18-2023: Due to an issue with corrupt JPEG IPTC metadata causing a
        // crash in CGImageDestinationCopyImageSource, stop using the original
        // JPEGs and instead go through the recompresing step.
        // This is an iOS bug (FB13285956) still present in iOS 17 and should
        // be revisitied in the future to see if JPEG support can be reenabled.
        guard dataUTI != UTType.jpeg.identifier else { return false }

        guard SignalAttachment.outputImageUTISet.contains(dataUTI) else { return false }
        guard fileSize <= imageQuality.maxFileSize else { return false }
        if let imageMetadata, imageMetadata.hasStickerLikeProperties { return true }
        guard fileSize <= imageQuality.maxOriginalFileSize else { return false }
        return true
    }

    public enum ContainerType {
        case jpg
        case png

        public var dataType: UTType {
            switch self {
            case .jpg: UTType.jpeg
            case .png: UTType.png
            }
        }

        var mimeType: String {
            self.dataType.preferredMIMEType!
        }

        public var fileExtension: String {
            switch self {
            case .jpg: "jpg"
            case .png: "png"
            }
        }
    }

    static func convertAndCompressImage(
        toImageQuality imageQuality: ImageQualityLevel,
        dataSource: DataSourcePath,
        imageMetadata: ImageMetadata?,
    ) throws(SignalAttachmentError) -> (dataSource: DataSourcePath, containerType: ContainerType) {
        var nextImageUploadQuality: ImageQualityTier? = imageQuality.startingTier
        while let imageUploadQuality = nextImageUploadQuality {
            let result = try convertAndCompressImageAttempt(
                toImageQuality: imageQuality,
                imageUploadQuality: imageUploadQuality,
                dataSource: dataSource,
                imageMetadata: imageMetadata,
            )
            if let result {
                return result
            }
            // If the image output is larger than the file size limit, continue to try
            // again by progressively reducing the image upload quality.
            nextImageUploadQuality = imageUploadQuality.reduced
        }
        throw .fileSizeTooLarge
    }

    private static func convertAndCompressImageAttempt(
        toImageQuality imageQuality: ImageQualityLevel,
        imageUploadQuality: ImageQualityTier,
        dataSource: DataSourcePath,
        imageMetadata: ImageMetadata?,
    ) throws(SignalAttachmentError) -> (dataSource: DataSourcePath, containerType: ContainerType)? {
        return try autoreleasepool { () throws(SignalAttachmentError) -> (dataSource: DataSourcePath, containerType: ContainerType)? in
            let maxSize = imageUploadQuality.maxEdgeSize

            let imageSource = CGImageSourceCreateWithURL(dataSource.fileUrl as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
            guard let imageSource else {
                throw .couldNotParseImage
            }

            // NOTE: For unknown reasons, resizing images with UIGraphicsBeginImageContext()
            // crashes reliably in the share extension after screen lock's auth UI has been presented.
            // Resizing using a CGContext seems to work fine.

            let downsampleOptions = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxSize,
            ] as [CFString: Any] as CFDictionary
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
                throw .couldNotResizeImage
            }

            // Write to disk and convert to file based data source,
            // so we can keep the image out of memory.

            let containerType: ContainerType
            var imageProperties = [CFString: Any]()

            // We convert everything that's not sticker-like to jpg, because
            // often images with alpha channels don't actually have any
            // transparent pixels (all screenshots fall into this bucket)
            // and there is not a simple, performant way to check if there
            // are any transparent pixels in an image.
            if let imageMetadata, imageMetadata.hasStickerLikeProperties {
                containerType = .png
            } else {
                containerType = .jpg
                imageProperties[kCGImageDestinationLossyCompressionQuality] = compressionQuality(
                    for: CGSize(width: cgImage.width, height: cgImage.height),
                )
            }

            let tempFileUrl = OWSFileSystem.temporaryFileUrl(fileExtension: containerType.fileExtension)
            guard let destination = CGImageDestinationCreateWithURL(tempFileUrl as CFURL, containerType.dataType.identifier as CFString, 1, nil) else {
                owsFailDebug("Failed to create CGImageDestination for attachment")
                throw .couldNotConvertImage
            }
            CGImageDestinationAddImage(destination, cgImage, imageProperties as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                owsFailDebug("Failed to write downsampled attachment to disk")
                throw .couldNotConvertImage
            }

            let outputDataSource = DataSourcePath(fileUrl: tempFileUrl, ownership: .owned)
            let outputFileSize: UInt64
            do {
                outputFileSize = try outputDataSource.readLength()
            } catch {
                owsFailDebug("Failed to create data source for downsampled image \(error)")
                throw .couldNotConvertImage
            }

            // Preserve the original filename
            let outputFilename: String?
            if let sourceFilename = dataSource.sourceFilename {
                let sourceFilenameWithoutExtension = (sourceFilename as NSString).deletingPathExtension
                outputFilename = (sourceFilenameWithoutExtension as NSString).appendingPathExtension(containerType.fileExtension) ?? sourceFilenameWithoutExtension
            } else {
                outputFilename = nil
            }
            outputDataSource.sourceFilename = outputFilename

            if outputFileSize <= imageQuality.maxFileSize, outputFileSize <= OWSMediaUtils.kMaxFileSizeImage {
                return (dataSource: outputDataSource, containerType: containerType)
            }

            return nil
        }
    }

    private class func compressionQuality(for pixelSize: CGSize) -> CGFloat {
        // For very large images, we can use a higher
        // jpeg compression without seeing artifacting
        if pixelSize.largerAxis >= 3072 { return 0.55 }
        return 0.6
    }

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

    static func removeImageMetadata(fromData dataValue: Data, dataUti: String) throws(SignalAttachmentError) -> Data {
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
            throw .missingData
        }

        guard let type = CGImageSourceGetType(source) else {
            throw .invalidFileFormat
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

    // MARK: Video Attachments
}
