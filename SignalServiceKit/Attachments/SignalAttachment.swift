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

public class SignalAttachment: NSObject {

    // MARK: Properties

    public let dataSource: DataSource

    public var captionText: String?

    // This flag should be set for text attachments that can be sent as text messages.
    public var isConvertibleToTextMessage = false

    // This flag should be set for attachments that can be sent as contact shares.
    public var isConvertibleToContactShare = false

    // This flag should be set for attachments that should be sent as view-once messages.
    public var isViewOnceAttachment = false

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
    private init(dataSource: DataSource, dataUTI: String) {
        self.dataSource = dataSource
        self.dataUTI = dataUTI
        super.init()

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

    public override var debugDescription: String {
        let fileSize = ByteCountFormatter.string(fromByteCount: Int64(dataSource.dataLength), countStyle: .file)
        return "[SignalAttachment] mimeType: \(mimeType), fileSize: \(fileSize)"
    }

    #if compiler(>=6.2)
    @concurrent
    #endif
    public func preparedForOutput(qualityLevel: ImageQualityLevel) async throws(SignalAttachmentError) -> SignalAttachment {
        // We only bother converting/compressing non-animated images
        guard isImage, !isAnimatedImage else { return self }

        guard !Self.isValidOutputOriginalImage(
            dataSource: dataSource,
            dataUTI: dataUTI,
            imageQuality: qualityLevel
        ) else { return self }

        return try Self.convertAndCompressImage(
            dataSource: dataSource,
            attachment: self,
            imageQuality: qualityLevel
        )
    }

    private func replacingDataSource(with newDataSource: DataSource, dataUTI: String? = nil) -> SignalAttachment {
        let result = SignalAttachment(dataSource: newDataSource, dataUTI: dataUTI ?? self.dataUTI)
        result.captionText = captionText
        result.isConvertibleToTextMessage = isConvertibleToTextMessage
        result.isConvertibleToContactShare = isConvertibleToContactShare
        result.isViewOnceAttachment = isViewOnceAttachment
        result.isVoiceMessage = isVoiceMessage
        result.isBorderless = isBorderless
        result.isLoopingVideo = isLoopingVideo
        return result
    }

    public func buildOutgoingAttachmentInfo(message: TSMessage? = nil) -> OutgoingAttachmentInfo {
        return OutgoingAttachmentInfo(
            dataSource: dataSource,
            contentType: mimeType,
            sourceFilename: filenameOrDefault,
            caption: captionText,
            albumMessageId: message?.uniqueId,
            isBorderless: isBorderless,
            isVoiceMessage: isVoiceMessage,
            isLoopingVideo: isLoopingVideo
        )
    }

    public func buildAttachmentDataSource(
        message: TSMessage? = nil
    ) async throws -> AttachmentDataSource {
        return try await buildOutgoingAttachmentInfo(message: message).asAttachmentDataSource()
    }

    public func staticThumbnail() -> UIImage? {
        if let cachedThumbnail = cachedThumbnail {
            return cachedThumbnail
        }

        return autoreleasepool {
            guard let image: UIImage = {
                if isAnimatedImage {
                    return image()
                } else if isImage {
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
        guard let image = UIImage(data: dataSource.data) else {
            return nil
        }
        cachedImage = image
        return image
    }

    public func videoPreview() -> UIImage? {
        if let cachedVideoPreview = cachedVideoPreview {
            return cachedVideoPreview
        }

        guard let mediaUrl = dataSource.dataUrl else {
            return nil
        }

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
        if isOversizeText {
            return MimeType.textXSignalPlain.rawValue
        }
        return UTType(dataUTI)?.preferredMIMEType ?? MimeType.applicationOctetStream.rawValue
    }

    // Use the filename if known. If not, e.g. if the attachment was copy/pasted, we'll generate a filename
    // like: "signal-2017-04-24-095918.zip"
    public var filenameOrDefault: String {
        if let filename = dataSource.sourceFilename?.filterFilename() {
            return filename.filterFilename()
        } else {
            let kDefaultAttachmentName = "signal"

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
            let dateString = dateFormatter.string(from: Date())

            let withoutExtension = "\(kDefaultAttachmentName)-\(dateString)"
            if let fileExtension = self.fileExtension {
                return "\(withoutExtension).\(fileExtension)"
            }

            return withoutExtension
        }
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
        if isOversizeText {
            return MimeTypeUtil.oversizeTextAttachmentFileExtension
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

    public var isAnimatedImage: Bool {
        let mimeType = mimeType
        if MimeTypeUtil.isSupportedDefinitelyAnimatedMimeType(mimeType) {
            return true
        }
        if MimeTypeUtil.isSupportedMaybeAnimatedMimeType(mimeType) {
            return dataSource.imageMetadata?.isAnimated ?? false
        }
        return false
    }

    public var isVideo: Bool {
        return SignalAttachment.videoUTISet.contains(dataUTI)
    }

    public var isAudio: Bool {
        return SignalAttachment.audioUTISet.contains(dataUTI)
    }

    public var isOversizeText: Bool {
        return dataUTI == MimeTypeUtil.oversizeTextAttachmentUti
    }

    public var isText: Bool {
        let isText = UTType(dataUTI)?.conforms(to: .text) ?? false
        return isText || isOversizeText
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
    public class func attachmentsFromPasteboard() async throws(SignalAttachmentError) -> [SignalAttachment]? {
        guard
            UIPasteboard.general.numberOfItems >= 1,
            let pasteboardUTITypes = UIPasteboard.general.types(forItemSet: nil)
        else {
            return nil
        }

        var attachments = [SignalAttachment]()
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
                if attachment.allowMultipleAttachments() == false {
                    // If this is a non-visual-media attachment, we only allow 1 pasted item at a time.
                    return [attachment]
                }
            }

            // Otherwise, continue with any visual media attachments, dropping
            // any non-visual-media ones based on the first pasteboard item.
            if attachment.allowMultipleAttachments() {
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

    private class func attachmentFromPasteboard(pasteboardUTIs: [String], index: IndexSet, retrySinglePixelImages: Bool) async throws(SignalAttachmentError) -> SignalAttachment? {

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
                guard let data = dataForPasteboardItem(dataUTI: dataUTI, index: index) else {
                    owsFailDebug("Missing expected pasteboard data for UTI: \(dataUTI)")
                    return nil
                }
                let dataSource = DataSourceValue(data, utiType: dataUTI)
                guard let dataSource else {
                    throw .missingData
                }

                // There is a known bug with the iOS pasteboard where it will randomly give a
                // single green pixel, and nothing else. Work around this by refetching the
                // pasteboard after a brief delay (once, then give up).
                if dataSource.imageMetadata?.pixelSize == CGSize(square: 1), retrySinglePixelImages {
                    try? await Task.sleep(nanoseconds: NSEC_PER_MSEC * 50)
                    return try await attachmentFromPasteboard(pasteboardUTIs: pasteboardUTIs, index: index, retrySinglePixelImages: false)
                }

                // If the data source is sticker like AND we're pasting the attachment,
                // we want to make it borderless.
                let isBorderless = dataSource.hasStickerLikeProperties

                return try imageAttachment(dataSource: dataSource, dataUTI: dataUTI, isBorderless: isBorderless)
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

                return try? await SignalAttachment.compressVideoAsMp4(dataSource: dataSource)
            }
        }
        for dataUTI in audioUTISet {
            if pasteboardUTISet.contains(dataUTI) {
                guard let data = dataForPasteboardItem(dataUTI: dataUTI, index: index) else {
                    owsFailDebug("Missing expected pasteboard data for UTI: \(dataUTI)")
                    return nil
                }
                let dataSource = DataSourceValue(data, utiType: dataUTI)
                guard let dataSource else {
                    throw .missingData
                }
                return try audioAttachment(dataSource: dataSource, dataUTI: dataUTI)
            }
        }

        let dataUTI = pasteboardUTISet[pasteboardUTISet.startIndex]
        guard let data = dataForPasteboardItem(dataUTI: dataUTI, index: index) else {
            owsFailDebug("Missing expected pasteboard data for UTI: \(dataUTI)")
            return nil
        }
        let dataSource = DataSourceValue(data, utiType: dataUTI)
        guard let dataSource else {
            throw .missingData
        }
        return try genericAttachment(dataSource: dataSource, dataUTI: dataUTI)
    }

    public class func stickerAttachmentFromPasteboard() throws(SignalAttachmentError) -> SignalAttachment? {
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
                guard let data = dataForPasteboardItem(dataUTI: dataUTI, index: IndexSet(integer: 0)) else {
                    owsFailDebug("Missing expected pasteboard data for UTI: \(dataUTI)")
                    return nil
                }

                let dataSource = DataSourceValue(data, utiType: dataUTI)
                guard let dataSource else {
                    throw .missingData
                }
                if !dataSource.hasStickerLikeProperties {
                    owsFailDebug("Treating non-sticker data as a sticker")
                }
                return try imageAttachment(dataSource: dataSource, dataUTI: dataUTI, isBorderless: true)
            }
        }
        return nil
    }

    /// Returns an attachment from the memoji.
    public class func attachmentFromMemoji(_ memojiGlyph: OWSAdaptiveImageGlyph) throws(SignalAttachmentError) -> SignalAttachment {
        let dataUTI = filterDynamicUTITypes([memojiGlyph.contentType.identifier]).first
        guard let dataUTI else {
            throw .invalidFileFormat
        }
        let dataSource = DataSourceValue(memojiGlyph.imageContent, utiType: dataUTI)
        guard let dataSource else {
            throw .missingData
        }
        return try imageAttachment(
            dataSource: dataSource,
            dataUTI: dataUTI,
            isBorderless: dataSource.hasStickerLikeProperties,
        )
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
    public class func imageAttachment(dataSource: any DataSource, dataUTI: String, isBorderless: Bool = false) throws(SignalAttachmentError) -> SignalAttachment {
        assert(!dataUTI.isEmpty)

        let attachment = SignalAttachment(dataSource: dataSource, dataUTI: dataUTI)

        attachment.isBorderless = isBorderless

        guard inputImageUTISet.contains(dataUTI) else {
            throw .invalidFileFormat
        }

        guard dataSource.dataLength > 0 else {
            owsFailDebug("imageData was empty")
            throw .invalidData
        }

        let imageMetadata = dataSource.imageMetadata
        let isAnimated = imageMetadata?.isAnimated ?? false
        if isAnimated {
            guard dataSource.dataLength <= OWSMediaUtils.kMaxFileSizeAnimatedImage else {
                throw .fileSizeTooLarge
            }

            // Never re-encode animated images (i.e. GIFs) as JPEGs.
            if dataUTI == UTType.png.identifier {
                do {
                    return try attachment.removingImageMetadata()
                } catch {
                    Logger.warn("Failed to remove metadata from animated PNG. Error: \(error)")
                    throw .couldNotRemoveMetadata
                }
            } else {
                return attachment
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

            if isValidOutputOriginalImage(dataSource: dataSource, dataUTI: dataUTI, imageQuality: .maximumForCurrentAppContext) {
                do {
                    return try attachment.removingImageMetadata()
                } catch {}
            }

            return try convertAndCompressImage(
                dataSource: dataSource,
                attachment: attachment,
                imageQuality: .maximumForCurrentAppContext
            )
        }
    }

    // If the proposed attachment already conforms to the
    // file size and content size limits, don't recompress it.
    private class func isValidOutputOriginalImage(
        dataSource: DataSource,
        dataUTI: String,
        imageQuality: ImageQualityLevel
    ) -> Bool {
        // 10-18-2023: Due to an issue with corrupt JPEG IPTC metadata causing a
        // crash in CGImageDestinationCopyImageSource, stop using the original
        // JPEGs and instead go through the recompresing step.
        // This is an iOS bug (FB13285956) still present in iOS 17 and should
        // be revisitied in the future to see if JPEG support can be reenabled.
        guard dataUTI != UTType.jpeg.identifier else { return false }

        guard SignalAttachment.outputImageUTISet.contains(dataUTI) else { return false }
        guard dataSource.dataLength <= imageQuality.maxFileSize else { return false }
        if dataSource.hasStickerLikeProperties { return true }
        guard dataSource.dataLength <= imageQuality.maxOriginalFileSize else { return false }
        return true
    }

    private class func convertAndCompressImage(
        dataSource: DataSource,
        attachment: SignalAttachment,
        imageQuality: ImageQualityLevel,
    ) throws(SignalAttachmentError) -> SignalAttachment {
        var nextImageUploadQuality: ImageQualityTier? = imageQuality.startingTier
        while let imageUploadQuality = nextImageUploadQuality {
            let result = try convertAndCompressImageAttempt(
                dataSource: dataSource,
                attachment: attachment,
                imageQuality: imageQuality,
                imageUploadQuality: imageUploadQuality,
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

    private class func convertAndCompressImageAttempt(
        dataSource: DataSource,
        attachment: SignalAttachment,
        imageQuality: ImageQualityLevel,
        imageUploadQuality: ImageQualityTier,
    ) throws(SignalAttachmentError) -> SignalAttachment? {
        return try autoreleasepool { () throws(SignalAttachmentError) -> SignalAttachment? in
            let maxSize = imageUploadQuality.maxEdgeSize
            let pixelSize = dataSource.imageMetadata?.pixelSize ?? .zero
            var imageProperties = [CFString: Any]()

            let cgImage: CGImage
            if pixelSize.width > maxSize || pixelSize.height > maxSize {
                guard let downsampledCGImage = downsampleImage(dataSource: dataSource, toMaxSize: maxSize) else {
                    throw .couldNotResizeImage
                }

                cgImage = downsampledCGImage
            } else {
                guard let imageSource = cgImageSource(for: dataSource) else {
                    throw .couldNotParseImage
                }

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

            let dataFileExtension: String
            let dataType: UTType

            // We convert everything that's not sticker-like to jpg, because
            // often images with alpha channels don't actually have any
            // transparent pixels (all screenshots fall into this bucket)
            // and there is not a simple, performant way, to check if there
            // are any transparent pixels in an image.
            if dataSource.hasStickerLikeProperties {
                dataFileExtension = "png"
                dataType = .png
            } else {
                dataFileExtension = "jpg"
                dataType = .jpeg
                imageProperties[kCGImageDestinationLossyCompressionQuality] = compressionQuality(for: pixelSize)
            }

            let tempFileUrl = OWSFileSystem.temporaryFileUrl(fileExtension: dataFileExtension)
            guard let destination = CGImageDestinationCreateWithURL(tempFileUrl as CFURL, dataType.identifier as CFString, 1, nil) else {
                owsFailDebug("Failed to create CGImageDestination for attachment")
                throw .couldNotConvertImage
            }
            CGImageDestinationAddImage(destination, cgImage, imageProperties as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                owsFailDebug("Failed to write downsampled attachment to disk")
                throw .couldNotConvertImage
            }

            let outputDataSource: DataSource
            do {
                outputDataSource = try DataSourcePath(fileUrl: tempFileUrl, shouldDeleteOnDeallocation: false)
            } catch {
                owsFailDebug("Failed to create data source for downsampled image \(error)")
                throw .couldNotConvertImage
            }

            // Preserve the original filename
            let outputFilename: String?
            if let sourceFilename = dataSource.sourceFilename {
                let sourceFilenameWithoutExtension = (sourceFilename as NSString).deletingPathExtension
                outputFilename = (sourceFilenameWithoutExtension as NSString).appendingPathExtension(dataFileExtension) ?? sourceFilenameWithoutExtension
            } else {
                outputFilename = nil
            }
            outputDataSource.sourceFilename = outputFilename

            if outputDataSource.dataLength <= imageQuality.maxFileSize, outputDataSource.dataLength <= OWSMediaUtils.kMaxFileSizeImage {
                let recompressedAttachment = attachment.replacingDataSource(with: outputDataSource, dataUTI: dataType.identifier)
                return recompressedAttachment
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

    private class func cgImageSource(for dataSource: DataSource) -> CGImageSource? {
        if dataSource.imageMetadata?.imageFormat == ImageFormat.webp {
            // CGImageSource doesn't know how to handle webp, so we have
            // to pass it through YYImage. This is costly and we could
            // perhaps do better, but webp images are usually small.
            guard let yyImage = UIImage.sd_image(with: dataSource.data) else {
                owsFailDebug("Failed to initialized YYImage")
                return nil
            }
            guard let imageData = yyImage.pngData() else {
                owsFailDebug("Failed to get png data for YYImage")
                return nil
            }
            return CGImageSourceCreateWithData(imageData as CFData, nil)
        } else if let dataUrl = dataSource.dataUrl {
            // If we can init with a URL, we prefer to. This way, we can avoid loading
            // the full image into memory. We need to set kCGImageSourceShouldCache to
            // false to ensure that CGImageSource doesn't try and read the file immediately.
            return CGImageSourceCreateWithURL(dataUrl as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        } else {
            return CGImageSourceCreateWithData(dataSource.data as CFData, nil)
        }
    }

    // NOTE: For unknown reasons, resizing images with UIGraphicsBeginImageContext()
    // crashes reliably in the share extension after screen lock's auth UI has been presented.
    // Resizing using a CGContext seems to work fine.
    private class func downsampleImage(dataSource: DataSource, toMaxSize maxSize: CGFloat) -> CGImage? {
        autoreleasepool {
            guard let imageSource: CGImageSource = cgImageSource(for: dataSource) else {
                owsFailDebug("Failed to create CGImageSource for attachment")
                return nil
            }

            // Perform downsampling
            let downsampleOptions = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxSize
            ] as [CFString: Any] as CFDictionary
            guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
                owsFailDebug("Failed to downsample attachment")
                return nil
            }

            return downsampledImage
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

    /// Remove nonessential chunks from PNG data.
    /// - Returns: Cleaned PNG data.
    /// - Throws: `SignalAttachmentError.couldNotRemoveMetadata` if the PNG parser fails.
    private static func removeMetadata(fromPng pngData: Data) throws(SignalAttachmentError) -> Data {
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

    private func removingImageMetadata() throws(SignalAttachmentError) -> SignalAttachment {
        owsAssertDebug(isImage)

        if dataUTI == UTType.png.identifier {
            let cleanedData = try Self.removeMetadata(fromPng: dataSource.data)
            guard let dataSource = DataSourceValue(cleanedData, utiType: dataUTI) else {
                throw .couldNotRemoveMetadata
            }
            return replacingDataSource(with: dataSource)
        }

        guard let source = CGImageSourceCreateWithData(dataSource.data as CFData, nil) else {
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

        guard let dataSource = DataSourceValue(mutableData as Data, utiType: dataUTI) else {
            throw .couldNotRemoveMetadata
        }

        return self.replacingDataSource(with: dataSource)
    }

    // MARK: Video Attachments

    // Factory method for video attachments.
    public class func videoAttachment(dataSource: DataSource, dataUTI: String) throws(SignalAttachmentError) -> SignalAttachment {
        return try newAttachment(
            dataSource: dataSource,
            dataUTI: dataUTI,
            validUTISet: videoUTISet,
            maxFileSize: OWSMediaUtils.kMaxFileSizeVideo,
        )
    }

    public class func copyToVideoTempDir(url fromUrl: URL) throws -> URL {
        let baseDir = SignalAttachment.videoTempPath.appendingPathComponent(UUID().uuidString, isDirectory: true)
        OWSFileSystem.ensureDirectoryExists(baseDir.path)
        let toUrl = baseDir.appendingPathComponent(fromUrl.lastPathComponent)

        Logger.debug("moving \(fromUrl) -> \(toUrl)")
        try FileManager.default.copyItem(at: fromUrl, to: toUrl)

        return toUrl
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

        let dataSource: DataSourcePath
        do {
            dataSource = try DataSourcePath(fileUrl: exportURL, shouldDeleteOnDeallocation: true)
        } catch {
            // TODO: Remove this; it's dead code.
            owsFailDebug("Failed to build data source for exported video URL")
            throw SignalAttachmentError.couldNotConvertToMpeg4
        }
        dataSource.sourceFilename = mp4Filename

        let endTime = MonotonicDate()
        let formattedDuration = OWSOperation.formattedNs((endTime - startTime).nanoseconds)
        Logger.info("transcoded video in \(formattedDuration)s")

        return try videoAttachment(dataSource: dataSource, dataUTI: UTType.mpeg4Movie.identifier)
    }

    // MARK: Audio Attachments

    // Factory method for audio attachments.
    private class func audioAttachment(dataSource: DataSource, dataUTI: String) throws(SignalAttachmentError) -> SignalAttachment {
        return try newAttachment(
            dataSource: dataSource,
            dataUTI: dataUTI,
            validUTISet: audioUTISet,
            maxFileSize: OWSMediaUtils.kMaxFileSizeAudio,
        )
    }

    // MARK: Generic Attachments

    // Factory method for generic attachments.
    public class func genericAttachment(dataSource: DataSource, dataUTI: String) throws(SignalAttachmentError) -> SignalAttachment {
        return try newAttachment(
            dataSource: dataSource,
            dataUTI: dataUTI,
            validUTISet: nil,
            maxFileSize: OWSMediaUtils.kMaxFileSizeGeneric,
        )
    }

    // MARK: Voice Messages

    public class func voiceMessageAttachment(dataSource: DataSource, dataUTI: String) throws(SignalAttachmentError) -> SignalAttachment {
        let attachment = try audioAttachment(dataSource: dataSource, dataUTI: dataUTI)
        attachment.isVoiceMessage = true
        return attachment
    }

    // MARK: Attachments

    // Factory method for attachments of any kind.
    public class func attachment(dataSource: DataSource, dataUTI: String) throws(SignalAttachmentError) -> SignalAttachment {
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
        dataSource: DataSource,
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

        guard dataSource.dataLength > 0 else {
            owsFailDebug("Empty attachment")
            assert(dataSource.dataLength > 0)
            throw .invalidData
        }

        guard dataSource.dataLength <= maxFileSize else {
            throw .fileSizeTooLarge
        }

        // Attachment is valid
        return attachment
    }
}
