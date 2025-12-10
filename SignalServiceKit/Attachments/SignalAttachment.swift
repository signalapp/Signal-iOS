//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import AVFoundation
import Foundation
import MobileCoreServices
import SDWebImage

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

    private(set) public var isVoiceMessage = false

    public static let maxAttachmentsAllowed: Int = 32

    // MARK: Constructor

    // This method should not be called directly; use the factory
    // methods instead.
    private init(dataSource: DataSourcePath, dataUTI: String) {
        self.dataSource = dataSource
        self.dataUTI = dataUTI

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didReceiveMemoryWarningNotification),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
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
        if let cachedThumbnail = cachedThumbnail {
            return cachedThumbnail
        }

        return autoreleasepool {
            guard let image: UIImage = {
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
        if let cachedImage = cachedImage {
            return cachedImage
        }
        guard let imageData = try? dataSource.readData(), let image = UIImage(data: imageData) else {
            return nil
        }
        cachedImage = image
        return image
    }

    public func videoPreview() -> UIImage? {
        if let cachedVideoPreview = cachedVideoPreview {
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
    private class var inputImageUTISet: Set<String> {
         // HEIC is valid input, but not valid output. Non-iOS11 clients do not support it.
        let heicSet: Set<String> = Set(["public.heic", "public.heif"])

        return MimeTypeUtil.supportedInputImageUtiTypes
            .union(animatedImageUTISet)
            .union(heicSet)
    }

    // Returns the set of UTIs that correspond to valid _output_ image formats
    // for Signal attachments.
    private class var outputImageUTISet: Set<String> {
        MimeTypeUtil.supportedOutputImageUtiTypes.union(animatedImageUTISet)
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
    private class var audioUTISet: Set<String> {
        MimeTypeUtil.supportedAudioUtiTypes
    }

    // Returns the set of UTIs that correspond to valid image, video and audio formats
    // for Signal attachments.
    private class var mediaUTISet: Set<String> {
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

    public class func pasteboardHasStickerAttachment() -> Bool {
        guard
            UIPasteboard.general.numberOfItems > 0,
            let pasteboardUTITypes = UIPasteboard.general.types(forItemSet: IndexSet(integer: 0))
        else {
            return false
        }

        let stickerSet: Set<String> = ["com.apple.sticker", "com.apple.png-sticker"]
        let pasteboardUTISet = Set<String>(filterDynamicUTITypes(pasteboardUTITypes[0]))
        for utiType in pasteboardUTISet {
            if stickerSet.contains(utiType) {
                return true
            }
        }
        return false
    }

    public class func pasteboardHasPossibleAttachment() -> Bool {
        return UIPasteboard.general.numberOfItems > 0
    }

    // This can be more than just mentions (e.g. also text formatting styles)
    // but the name remains as-is for backwards compatibility.
    public static let bodyRangesPasteboardType = "private.archived-mention-text"

    public class func pasteboardHasText() -> Bool {
        if UIPasteboard.general.numberOfItems < 1 {
            return false
        }
        let itemSet = IndexSet(integer: 0)
        guard let pasteboardUTITypes = UIPasteboard.general.types(forItemSet: itemSet) else {
            return false
        }
        let pasteboardUTISet = Set<String>(filterDynamicUTITypes(pasteboardUTITypes[0]))
        guard pasteboardUTISet.count > 0 else {
            return false
        }

        // The mention text view has a special pasteboard type, if we see it
        // we know that the pasteboard contains text.
        guard !pasteboardUTISet.contains(bodyRangesPasteboardType) else {
            return true
        }

        // The pasteboard can be populated with multiple UTI types
        // with different payloads.  iMessage for example will copy
        // an animated GIF to the pasteboard with the following UTI
        // types:
        //
        // * "public.url-name"
        // * "public.utf8-plain-text"
        // * "com.compuserve.gif"
        //
        // We want to paste the animated GIF itself, not it's name.
        //
        // In general, our rule is to prefer non-text pasteboard
        // contents, so we return true IFF there is a text UTI type
        // and there is no non-text UTI type.
        var hasTextUTIType = false
        var hasNonTextUTIType = false
        for utiType in pasteboardUTISet {
            if let type = UTType(utiType), type.conforms(to: .text) {
                hasTextUTIType = true
            } else if mediaUTISet.contains(utiType) {
                hasNonTextUTIType = true
            }
        }
        if pasteboardUTISet.contains(UTType.url.identifier) {
            // Treat URL as a textual UTI type.
            hasTextUTIType = true
        }
        if hasNonTextUTIType {
            return false
        }
        return hasTextUTIType
    }

    // Discard "dynamic" UTI types since our attachment pipeline
    // requires "standard" UTI types to work properly, e.g. when
    // mapping between UTI type, MIME type and file extension.
    private class func filterDynamicUTITypes(_ types: [String]) -> [String] {
        return types.filter {
            !$0.hasPrefix("dyn")
        }
    }

    /// Returns an attachment from the pasteboard, or nil if no attachment
    /// can be found.
    public class func attachmentsFromPasteboard() async throws -> [PreviewableAttachment]? {
        guard
            UIPasteboard.general.numberOfItems >= 1,
            let pasteboardUTITypes = UIPasteboard.general.types(forItemSet: nil)
        else {
            return nil
        }

        var attachments = [PreviewableAttachment]()
        for (index, utiSet) in pasteboardUTITypes.enumerated() {
            let attachment = try await attachmentFromPasteboard(
                pasteboardUTIs: utiSet,
                index: IndexSet(integer: index),
                retrySinglePixelImages: true,
            )

            guard let attachment else {
                owsFailDebug("Missing attachment")
                continue
            }

            if attachments.isEmpty {
                if attachment.rawValue.allowMultipleAttachments() == false {
                    // If this is a non-visual-media attachment, we only allow 1 pasted item at a time.
                    return [attachment]
                }
            }

            // Otherwise, continue with any visual media attachments, dropping
            // any non-visual-media ones based on the first pasteboard item.
            if attachment.rawValue.allowMultipleAttachments() {
                attachments.append(attachment)
            } else {
                Logger.warn("Dropping non-visual media attachment in paste action")
            }
        }
        return attachments
    }

    private func allowMultipleAttachments() -> Bool {
        return !self.isBorderless
            && (MimeTypeUtil.isSupportedVideoMimeType(self.mimeType)
                || MimeTypeUtil.isSupportedDefinitelyAnimatedMimeType(self.mimeType)
                || MimeTypeUtil.isSupportedImageMimeType(self.mimeType))
    }

    private class func attachmentFromPasteboard(pasteboardUTIs: [String], index: IndexSet, retrySinglePixelImages: Bool) async throws -> PreviewableAttachment? {
        var pasteboardUTISet = Set<String>(filterDynamicUTITypes(pasteboardUTIs))
        guard pasteboardUTISet.count > 0 else {
            return nil
        }

        // If we have the choice between a png and a jpg, always choose
        // the png as it may have transparency. Apple provides both jpg
        //  and png uti types when sending memoji stickers and
        // `inputImageUTISet` is unordered, so without this check there
        // is a 50/50 chance that we'd pick the jpg.
        if pasteboardUTISet.isSuperset(of: [UTType.jpeg.identifier, UTType.png.identifier]) {
            pasteboardUTISet.remove(UTType.jpeg.identifier)
        }

        for dataUTI in inputImageUTISet {
            if pasteboardUTISet.contains(dataUTI) {
                guard
                    let dataValue = dataForPasteboardItem(dataUTI: dataUTI, index: index),
                    let fileExtension = MimeTypeUtil.fileExtensionForUtiType(dataUTI),
                    let dataSource = try? DataSourcePath(writingTempFileData: dataValue, fileExtension: fileExtension)
                else {
                    owsFailDebug("Failed to build data source from pasteboard data for UTI: \(dataUTI)")
                    return nil
                }
                // There is a known bug with the iOS pasteboard where it will randomly give a
                // single green pixel, and nothing else. Work around this by refetching the
                // pasteboard after a brief delay (once, then give up).
                if retrySinglePixelImages, (try? dataSource.imageSource())?.imageMetadata(ignorePerTypeFileSizeLimits: true)?.pixelSize == CGSize(square: 1) {
                    try? await Task.sleep(nanoseconds: NSEC_PER_MSEC * 50)
                    return try await attachmentFromPasteboard(pasteboardUTIs: pasteboardUTIs, index: index, retrySinglePixelImages: false)
                }

                let attachment = try imageAttachment(dataSource: dataSource, dataUTI: dataUTI, canBeBorderless: true)
                return PreviewableAttachment(rawValue: attachment)
            }
        }
        for dataUTI in videoUTISet {
            if pasteboardUTISet.contains(dataUTI) {
                guard
                    let dataValue = dataForPasteboardItem(dataUTI: dataUTI, index: index),
                    let fileExtension = MimeTypeUtil.fileExtensionForUtiType(dataUTI),
                    let dataSource = try? DataSourcePath(writingTempFileData: dataValue, fileExtension: fileExtension)
                else {
                    owsFailDebug("Failed to build data source from pasteboard data for UTI: \(dataUTI)")
                    return nil
                }

                // [15M] TODO: Don't ignore errors for pasteboard videos.
                let attachment = try? await SignalAttachment.compressVideoAsMp4(dataSource: dataSource)
                return attachment.map(PreviewableAttachment.init(rawValue:))
            }
        }
        for dataUTI in audioUTISet {
            if pasteboardUTISet.contains(dataUTI) {
                guard
                    let dataValue = dataForPasteboardItem(dataUTI: dataUTI, index: index),
                    let fileExtension = MimeTypeUtil.fileExtensionForUtiType(dataUTI),
                    let dataSource = try? DataSourcePath(writingTempFileData: dataValue, fileExtension: fileExtension)
                else {
                    owsFailDebug("Failed to build data source from pasteboard data for UTI: \(dataUTI)")
                    return nil
                }
                let attachment = try audioAttachment(dataSource: dataSource, dataUTI: dataUTI)
                return PreviewableAttachment(rawValue: attachment)
            }
        }

        let dataUTI = pasteboardUTISet[pasteboardUTISet.startIndex]
        guard
            let dataValue = dataForPasteboardItem(dataUTI: dataUTI, index: index),
            let fileExtension = MimeTypeUtil.fileExtensionForUtiType(dataUTI),
            let dataSource = try? DataSourcePath(writingTempFileData: dataValue, fileExtension: fileExtension)
        else {
            owsFailDebug("Failed to build data source from pasteboard data for UTI: \(dataUTI)")
            return nil
        }
        let attachment = try genericAttachment(dataSource: dataSource, dataUTI: dataUTI)
        return PreviewableAttachment(rawValue: attachment)
    }

    public class func stickerAttachmentFromPasteboard() throws -> PreviewableAttachment? {
        guard
            UIPasteboard.general.numberOfItems >= 1,
            let pasteboardUTITypes = UIPasteboard.general.types(forItemSet: IndexSet(integer: 0))
        else {
            return nil
        }

        var pasteboardUTISet = Set<String>(filterDynamicUTITypes(pasteboardUTITypes[0]))
        guard pasteboardUTISet.count > 0 else {
            return nil
        }

        // If we have the choice between a png and a jpg, always choose
        // the png as it may have transparency.
        if pasteboardUTISet.isSuperset(of: [UTType.jpeg.identifier, UTType.png.identifier]) {
            pasteboardUTISet.remove(UTType.jpeg.identifier)
        }

        for dataUTI in inputImageUTISet {
            if pasteboardUTISet.contains(dataUTI) {
                guard
                    let dataValue = dataForPasteboardItem(dataUTI: dataUTI, index: IndexSet(integer: 0)),
                    let fileExtension = MimeTypeUtil.fileExtensionForUtiType(dataUTI),
                    let dataSource = try? DataSourcePath(writingTempFileData: dataValue, fileExtension: fileExtension)
                else {
                    owsFailDebug("Missing expected pasteboard data for UTI: \(dataUTI)")
                    return nil
                }
                let result = try imageAttachment(dataSource: dataSource, dataUTI: dataUTI, canBeBorderless: true)
                if !result.isBorderless {
                    owsFailDebug("treating non-sticker data as a sticker")
                    result.isBorderless = true
                }
                return PreviewableAttachment(rawValue: result)
            }
        }
        return nil
    }

    /// Returns an attachment from the memoji.
    public class func attachmentFromMemoji(_ memojiGlyph: OWSAdaptiveImageGlyph) throws -> PreviewableAttachment {
        let dataUTI = filterDynamicUTITypes([memojiGlyph.contentType.identifier]).first
        guard let dataUTI else {
            throw SignalAttachmentError.invalidFileFormat
        }
        let fileExtension = MimeTypeUtil.fileExtensionForUtiType(dataUTI)
        guard let fileExtension else {
            throw SignalAttachmentError.missingData
        }
        let dataSource = try DataSourcePath(writingTempFileData: memojiGlyph.imageContent, fileExtension: fileExtension)
        let attachment = try imageAttachment(dataSource: dataSource, dataUTI: dataUTI, canBeBorderless: true)
        return PreviewableAttachment(rawValue: attachment)
    }

    private class func dataForPasteboardItem(dataUTI: String, index: IndexSet) -> Data? {
        guard let datas = UIPasteboard.general.data(forPasteboardType: dataUTI, inItemSet: index) else {
            owsFailDebug("Missing expected pasteboard data for UTI: \(dataUTI)")
            return nil
        }
        guard let data = datas.first else {
            owsFailDebug("Missing expected pasteboard data for UTI: \(dataUTI)")
            return nil
        }
        return data
    }

    // MARK: Image Attachments

    // Factory method for an image attachment.
    public class func imageAttachment(dataSource: DataSourcePath, dataUTI: String, canBeBorderless: Bool = false) throws -> SignalAttachment {
        assert(!dataUTI.isEmpty)

        guard inputImageUTISet.contains(dataUTI) else {
            throw SignalAttachmentError.invalidFileFormat
        }

        // [15M] TODO: Allow sending empty attachments?
        guard let fileSize = try? dataSource.readLength(), fileSize > 0 else {
            owsFailDebug("imageData was empty")
            throw SignalAttachmentError.invalidData
        }

        guard let imageMetadata = try? dataSource.imageSource().imageMetadata(ignorePerTypeFileSizeLimits: true) else {
            throw SignalAttachmentError.invalidData
        }

        let newDataSource: DataSourcePath
        let newDataUTI: String

        let isAnimated = imageMetadata.isAnimated
        // Never re-encode animated images (i.e. GIFs) as JPEGs.
        if isAnimated {
            guard fileSize <= OWSMediaUtils.kMaxFileSizeAnimatedImage else {
                throw SignalAttachmentError.fileSizeTooLarge
            }

            if dataUTI == UTType.png.identifier {
                let strippedData = try Self.removeImageMetadata(fromPngData: dataSource.readData())
                guard let fileExtension = MimeTypeUtil.fileExtensionForUtiType(dataUTI) else {
                    throw SignalAttachmentError.couldNotRemoveMetadata
                }
                newDataSource = try DataSourcePath(writingTempFileData: strippedData, fileExtension: fileExtension)
                newDataUTI = dataUTI
            } else {
                newDataSource = dataSource
                newDataUTI = dataUTI
            }
        } else {
            if
                let sourceFilename = dataSource.sourceFilename,
                ["heic", "heif"].contains((sourceFilename as NSString).pathExtension.lowercased()),
                dataUTI == UTType.jpeg.identifier as String
            {

                // If a .heic file actually contains jpeg data, update the extension to match.
                //
                // Here's how that can happen:
                // In iOS11, the Photos.app records photos with HEIC UTIType, with the .HEIC extension.
                // Since HEIC isn't a valid output format for Signal, we'll detect that and convert to JPEG,
                // updating the extension as well. No problem.
                // However the problem comes in when you edit an HEIC image in Photos.app - the image is saved
                // in the Photos.app as a JPEG, but retains the (now incongruous) HEIC extension in the filename.

                let baseFilename = (sourceFilename as NSString).deletingPathExtension
                dataSource.sourceFilename = (baseFilename as NSString).appendingPathExtension("jpg") ?? baseFilename
            }

            // When preparing an attachment, we always prepare it in the max quality for the current
            // context. The user can choose during sending whether they want the final send to be in
            // standard or high quality. We will do the final convert and compress before uploading.

            let isOriginalValid = self.isOriginalImageValid(
                forImageQuality: .maximumForCurrentAppContext(),
                fileSize: fileSize,
                dataUTI: dataUTI,
                imageMetadata: imageMetadata,
            )

            // If the original is valid and we can remove the metadata, go that route.
            if isOriginalValid, let strippedData = try? Self.removeImageMetadata(fromData: dataSource.readData(), dataUti: dataUTI) {
                guard let fileExtension = MimeTypeUtil.fileExtensionForUtiType(dataUTI) else {
                    throw SignalAttachmentError.couldNotRemoveMetadata
                }
                newDataSource = try DataSourcePath(writingTempFileData: strippedData, fileExtension: fileExtension)
                newDataUTI = dataUTI
            } else {
                // Otherwise, resize & convert to a PNG or JPG before previewing it.
                let containerType: ContainerType
                (newDataSource, containerType) = try convertAndCompressImage(
                    toImageQuality: .maximumForCurrentAppContext(),
                    dataSource: dataSource,
                    imageMetadata: imageMetadata,
                )
                newDataUTI = containerType.dataType.identifier
            }
        }
        let result = SignalAttachment(dataSource: newDataSource, dataUTI: newDataUTI)
        result.isBorderless = canBeBorderless && imageMetadata.hasStickerLikeProperties
        result.isAnimatedImage = isAnimated
        return result
    }

    // If the proposed attachment already conforms to the
    // file size and content size limits, don't recompress it.
    static func isOriginalImageValid(
        forImageQuality imageQuality: ImageQualityLevel,
        fileSize: UInt64,
        dataUTI: String,
        imageMetadata: ImageMetadata,
    ) -> Bool {
        // 10-18-2023: Due to an issue with corrupt JPEG IPTC metadata causing a
        // crash in CGImageDestinationCopyImageSource, stop using the original
        // JPEGs and instead go through the recompresing step.
        // This is an iOS bug (FB13285956) still present in iOS 17 and should
        // be revisitied in the future to see if JPEG support can be reenabled.
        guard dataUTI != UTType.jpeg.identifier else { return false }

        guard SignalAttachment.outputImageUTISet.contains(dataUTI) else { return false }
        guard fileSize <= imageQuality.maxFileSize else { return false }
        if imageMetadata.hasStickerLikeProperties { return true }
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
        imageMetadata: ImageMetadata,
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
        imageMetadata: ImageMetadata,
    ) throws(SignalAttachmentError) -> (dataSource: DataSourcePath, containerType: ContainerType)? {
        return try autoreleasepool { () throws(SignalAttachmentError) -> (dataSource: DataSourcePath, containerType: ContainerType)? in
            let maxSize = imageUploadQuality.maxEdgeSize
            let pixelSize = imageMetadata.pixelSize
            var imageProperties = [CFString: Any]()

            guard let imageSource = cgImageSource(for: dataSource, imageFormat: imageMetadata.imageFormat) else {
                throw .couldNotParseImage
            }

            let cgImage: CGImage
            if pixelSize.width > maxSize || pixelSize.height > maxSize {
                // NOTE: For unknown reasons, resizing images with UIGraphicsBeginImageContext()
                // crashes reliably in the share extension after screen lock's auth UI has been presented.
                // Resizing using a CGContext seems to work fine.

                // Perform downsampling
                let downsampleOptions = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxSize
                ] as [CFString: Any] as CFDictionary
                guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
                    throw .couldNotResizeImage
                }
                cgImage = downsampledImage
            } else {
                guard let originalImageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, [
                    kCGImageSourceShouldCache: false
                ] as CFDictionary) as? [CFString: Any] else {
                    throw .couldNotParseImage
                }

                // Preserve any orientation properties in the final output image.
                if let tiffOrientation = originalImageProperties[kCGImagePropertyTIFFOrientation] {
                    imageProperties[kCGImagePropertyTIFFOrientation] = tiffOrientation
                }
                if let iptcOrientation = originalImageProperties[kCGImagePropertyIPTCImageOrientation] {
                    imageProperties[kCGImagePropertyIPTCImageOrientation] = iptcOrientation
                }

                guard let image = CGImageSourceCreateImageAtIndex(imageSource, 0, [
                    kCGImageSourceShouldCacheImmediately: true
                ] as CFDictionary) else {
                    throw .couldNotParseImage
                }

                cgImage = image
            }

            // Write to disk and convert to file based data source,
            // so we can keep the image out of memory.

            let containerType: ContainerType

            // We convert everything that's not sticker-like to jpg, because
            // often images with alpha channels don't actually have any
            // transparent pixels (all screenshots fall into this bucket)
            // and there is not a simple, performant way to check if there
            // are any transparent pixels in an image.
            if imageMetadata.hasStickerLikeProperties {
                containerType = .png
            } else {
                containerType = .jpg
                imageProperties[kCGImageDestinationLossyCompressionQuality] = compressionQuality(for: pixelSize)
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

    private class func cgImageSource(for dataSource: DataSourcePath, imageFormat: ImageFormat) -> CGImageSource? {
        if imageFormat == .webp {
            // CGImageSource doesn't know how to handle webp, so we have
            // to pass it through YYImage. This is costly and we could
            // perhaps do better, but webp images are usually small.
            guard let yyImage = UIImage.sd_image(with: try? dataSource.readData()) else {
                owsFailDebug("Failed to initialized YYImage")
                return nil
            }
            guard let imageData = yyImage.pngData() else {
                owsFailDebug("Failed to get png data for YYImage")
                return nil
            }
            return CGImageSourceCreateWithData(imageData as CFData, nil)
        } else {
            // If we can init with a URL, we prefer to. This way, we can avoid loading
            // the full image into memory. We need to set kCGImageSourceShouldCache to
            // false to ensure that CGImageSource doesn't try and read the file immediately.
            return CGImageSourceCreateWithURL(dataSource.fileUrl as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        }
    }

    private static let preservedMetadata: [CFString] = [
        "\(kCGImageMetadataPrefixTIFF):\(kCGImagePropertyTIFFOrientation)" as CFString,
        "\(kCGImageMetadataPrefixIPTCCore):\(kCGImagePropertyIPTCImageOrientation)" as CFString
    ]

    private static let pngChunkTypesToKeep: Set<Data> = {
        let asAscii: [String] = [
            // [Critical chunks.][0]
            // [0]: https://www.w3.org/TR/PNG/#11Critical-chunks
            "IHDR", "PLTE", "IDAT", "IEND",
            // [Ancillary chunks][1] that might affect rendering.
            // [1]: https://www.w3.org/TR/PNG/#11Ancillary-chunks
            "tRNS", "cHRM", "gAMA", "iCCP", "sRGB", "bKGD", "pHYs", "sPLT",
            // [Animated PNG chunks.][2]
            // [2]: https://wiki.mozilla.org/APNG_Specification#Structure
            "acTL", "fcTL", "fdAT"
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
    private static func removeImageMetadata(fromPngData pngData: Data) throws(SignalAttachmentError) -> Data {
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
            kCGImageDestinationMetadata: metadata
        ]
        guard CGImageDestinationCopyImageSource(destination, source, copyOptions, nil) else {
            throw .couldNotRemoveMetadata
        }

        return mutableData as Data
    }

    // MARK: Video Attachments

    // Factory method for video attachments.
    public class func videoAttachment(dataSource: DataSourcePath, dataUTI: String) throws -> SignalAttachment {
        try OWSMediaUtils.validateVideoExtension(ofPath: dataSource.fileUrl.path)
        try OWSMediaUtils.validateVideoAsset(atPath: dataSource.fileUrl.path)
        return try newAttachment(
            dataSource: dataSource,
            dataUTI: dataUTI,
            validUTISet: videoUTISet,
            maxFileSize: OWSMediaUtils.kMaxFileSizeVideo,
        )
    }

    private class var videoTempPath: URL {
        let videoDir = URL(fileURLWithPath: OWSTemporaryDirectory()).appendingPathComponent("video")
        OWSFileSystem.ensureDirectoryExists(videoDir.path)
        return videoDir
    }

    @MainActor
    public static func compressVideoAsMp4(dataSource: DataSourcePath, sessionCallback: (@MainActor (AVAssetExportSession) -> Void)? = nil) async throws -> SignalAttachment {
        return try await compressVideoAsMp4(
            asset: AVAsset(url: dataSource.fileUrl),
            baseFilename: dataSource.sourceFilename,
            sessionCallback: sessionCallback,
        )
    }

    @MainActor
    public static func compressVideoAsMp4(asset: AVAsset, baseFilename: String?, sessionCallback: (@MainActor (AVAssetExportSession) -> Void)? = nil) async throws -> SignalAttachment {
        let startTime = MonotonicDate()

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset640x480) else {
            throw SignalAttachmentError.couldNotConvertToMpeg4
        }

        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.metadataItemFilter = AVMetadataItemFilter.forSharing()

        if let sessionCallback {
            sessionCallback(exportSession)
        }

        let exportURL = videoTempPath.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")

        try await exportSession.exportAsync(to: exportURL, as: .mp4)

        switch exportSession.status {
        case .unknown:
            throw OWSAssertionError("Unknown export status.")
        case .waiting:
            throw OWSAssertionError("Export status: .waiting.")
        case .exporting:
            throw OWSAssertionError("Export status: .exporting.")
        case .completed:
            break
        case .failed:
            if let error = exportSession.error {
                owsFailDebug("Error: \(error)")
                throw error
            } else {
                throw OWSAssertionError("Export failed without error.")
            }
        case .cancelled:
            throw CancellationError()
        @unknown default:
            throw OWSAssertionError("Unknown export status: \(exportSession.status.rawValue)")
        }

        let mp4Filename: String?
        if let baseFilename {
            let baseFilenameWithoutExtension = (baseFilename as NSString).deletingPathExtension
            mp4Filename = (baseFilenameWithoutExtension as NSString).appendingPathExtension("mp4") ?? baseFilenameWithoutExtension
        } else {
            mp4Filename = nil
        }

        let dataSource = DataSourcePath(fileUrl: exportURL, ownership: .owned)
        dataSource.sourceFilename = mp4Filename

        let endTime = MonotonicDate()
        let formattedDuration = OWSOperation.formattedNs((endTime - startTime).nanoseconds)
        Logger.info("transcoded video in \(formattedDuration)s")

        return try videoAttachment(dataSource: dataSource, dataUTI: UTType.mpeg4Movie.identifier)
    }

    // MARK: Audio Attachments

    // Factory method for audio attachments.
    private class func audioAttachment(dataSource: DataSourcePath, dataUTI: String) throws(SignalAttachmentError) -> SignalAttachment {
        return try newAttachment(
            dataSource: dataSource,
            dataUTI: dataUTI,
            validUTISet: audioUTISet,
            maxFileSize: OWSMediaUtils.kMaxFileSizeAudio,
        )
    }

    // MARK: Generic Attachments

    // Factory method for generic attachments.
    public class func genericAttachment(dataSource: DataSourcePath, dataUTI: String) throws(SignalAttachmentError) -> SignalAttachment {
        // [15M] TODO: Enforce this at compile-time rather than runtime.
        owsPrecondition(!videoUTISet.contains(dataUTI))
        owsPrecondition(!inputImageUTISet.contains(dataUTI))
        return try newAttachment(
            dataSource: dataSource,
            dataUTI: dataUTI,
            validUTISet: nil,
            maxFileSize: OWSMediaUtils.kMaxFileSizeGeneric,
        )
    }

    // MARK: Voice Messages

    public class func voiceMessageAttachment(dataSource: DataSourcePath, dataUTI: String) throws(SignalAttachmentError) -> SignalAttachment {
        let attachment = try audioAttachment(dataSource: dataSource, dataUTI: dataUTI)
        attachment.isVoiceMessage = true
        return attachment
    }

    // MARK: Attachments

    // Factory method for attachments of any kind.
    public class func attachment(dataSource: DataSourcePath, dataUTI: String) throws -> SignalAttachment {
        if inputImageUTISet.contains(dataUTI) {
            return try imageAttachment(dataSource: dataSource, dataUTI: dataUTI)
        } else if videoUTISet.contains(dataUTI) {
            return try videoAttachment(dataSource: dataSource, dataUTI: dataUTI)
        } else if audioUTISet.contains(dataUTI) {
            return try audioAttachment(dataSource: dataSource, dataUTI: dataUTI)
        } else {
            return try genericAttachment(dataSource: dataSource, dataUTI: dataUTI)
        }
    }

    // MARK: Helper Methods

    private class func newAttachment(
        dataSource: DataSourcePath,
        dataUTI: String,
        validUTISet: Set<String>?,
        maxFileSize: UInt,
    ) throws(SignalAttachmentError) -> SignalAttachment {
        assert(!dataUTI.isEmpty)

        let attachment = SignalAttachment(dataSource: dataSource, dataUTI: dataUTI)

        if let validUTISet = validUTISet {
            guard validUTISet.contains(dataUTI) else {
                throw .invalidFileFormat
            }
        }

        // [15M] TODO: Allow sending empty attachments?
        guard let fileSize = try? dataSource.readLength(), fileSize > 0 else {
            owsFailDebug("Empty attachment")
            throw .invalidData
        }

        guard fileSize <= maxFileSize else {
            throw .fileSizeTooLarge
        }

        // Attachment is valid
        return attachment
    }
}
