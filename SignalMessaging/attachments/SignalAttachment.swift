//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import MobileCoreServices
import SignalServiceKit
import AVFoundation
import YYImage

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

public extension String {
    var filenameWithoutExtension: String {
        return (self as NSString).deletingPathExtension
    }

    var fileExtension: String? {
        return (self as NSString).pathExtension
    }

    func appendingFileExtension(_ fileExtension: String) -> String {
        guard let result = (self as NSString).appendingPathExtension(fileExtension) else {
            owsFailDebug("Failed to append file extension: \(fileExtension) to string: \(self)")
            return self
        }
        return result
    }
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
// The attachment may be invalid.
//
// Signal attachments are subject to validation and 
// in some cases, file format conversion.
//
// This class gathers that logic.  It offers factory methods
// for attachments that do the necessary work. 
//
// The return value for the factory methods will be nil if the input is nil.
//
// [SignalAttachment hasError] will be true for non-valid attachments.
//
// TODO: Perhaps do conversion off the main thread?
@objc
public class SignalAttachment: NSObject {

    // MARK: Properties

    @objc
    public let dataSource: DataSource

    @objc
    public var captionText: String?

    @objc
    public var data: Data {
        return dataSource.data
    }

    @objc
    public var dataLength: UInt {
        return dataSource.dataLength
    }

    @objc
    public var dataUrl: URL? {
        return dataSource.dataUrl
    }

    @objc
    public var sourceFilename: String? {
        return dataSource.sourceFilename?.filterFilename()
    }

    @objc
    public var isValidImage: Bool {
        return dataSource.isValidImage
    }

    @objc
    public var isValidVideo: Bool {
        return dataSource.isValidVideo
    }

    // This flag should be set for text attachments that can be sent as text messages.
    @objc
    public var isConvertibleToTextMessage = false

    // This flag should be set for attachments that can be sent as contact shares.
    @objc
    public var isConvertibleToContactShare = false

    // This flag should be set for attachments that should be sent as view-once messages.
    @objc
    public var isViewOnceAttachment = false

    // Attachment types are identified using UTIs.
    //
    // See: https://developer.apple.com/library/content/documentation/Miscellaneous/Reference/UTIRef/Articles/System-DeclaredUniformTypeIdentifiers.html
    @objc
    public let dataUTI: String

    public var error: SignalAttachmentError? {
        didSet {
            AssertIsOnMainThread()

            assert(oldValue == nil)
            Logger.verbose("Attachment has error: \(String(describing: error))")
        }
    }

    // To avoid redundant work of repeatedly compressing/uncompressing
    // images, we cache the UIImage associated with this attachment if
    // possible.
    private var cachedImage: UIImage?
    private var cachedThumbnail: UIImage?
    private var cachedVideoPreview: UIImage?

    @objc
    private(set) public var isVoiceMessage = false

    // MARK: Constants

    public static let kMaxFileSizeAnimatedImage = OWSMediaUtils.kMaxFileSizeAnimatedImage
    public static let kMaxFileSizeImage = OWSMediaUtils.kMaxFileSizeImage
    public static let kMaxFileSizeVideo = OWSMediaUtils.kMaxFileSizeVideo
    public static let kMaxFileSizeAudio = OWSMediaUtils.kMaxFileSizeAudio
    public static let kMaxFileSizeGeneric = OWSMediaUtils.kMaxFileSizeGeneric

    // MARK: 

    @objc
    public static let maxAttachmentsAllowed: Int = 32

    // MARK: Constructor

    // This method should not be called directly; use the factory
    // methods instead.
    @objc
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
    func didReceiveMemoryWarningNotification() {
        cachedImage = nil
        cachedThumbnail = nil
        cachedVideoPreview = nil
    }

    // MARK: Methods

    @objc
    public var hasError: Bool {
        return error != nil
    }

    @objc
    public var errorName: String? {
        guard let error = error else {
            // This method should only be called if there is an error.
            owsFailDebug("Missing error")
            return nil
        }

        return "\(error)"
    }

    @objc
    public var localizedErrorDescription: String? {
        guard let error = self.error else {
            // This method should only be called if there is an error.
            owsFailDebug("Missing error")
            return nil
        }
        guard let errorDescription = error.errorDescription else {
            owsFailDebug("Missing error description")
            return nil
        }

        return "\(errorDescription)"
    }

    @objc
    public override var debugDescription: String {
        let fileSize = ByteCountFormatter.string(fromByteCount: Int64(dataLength), countStyle: .file)
        let string = "[SignalAttachment] mimeType: \(mimeType), fileSize: \(fileSize)"

        // Computing resolution from dataUrl could cause DataSourceValue to write to disk, which
        // can be expensive. Only do it in debug.
        #if DEBUG
        if let dataUrl = dataUrl {
            if isVideo {
                let resolution = OWSMediaUtils.videoResolution(url: dataUrl)
                return "\(string), resolution: \(resolution), aspectRatio: \(resolution.aspectRatio)"
            } else if isImage {
                let resolution = NSData.imageSize(forFilePath: dataUrl.path, mimeType: nil)
                return "\(string), resolution: \(resolution), aspectRatio: \(resolution.aspectRatio)"
            }
        }
        #endif

        return string
    }

    @objc
    public class var missingDataErrorMessage: String {
        guard let errorDescription = SignalAttachmentError.missingData.errorDescription else {
            owsFailDebug("Missing error description")
            return ""
        }
        return errorDescription
    }

    public func cloneAttachment() throws -> SignalAttachment {
        guard let sourceUrl = dataUrl else {
            owsFailDebug("Missing data URL for attachment!")
            return SignalAttachment.empty()
        }

        let newUrl = OWSFileSystem.temporaryFileUrl(fileExtension: sourceUrl.pathExtension)
        try FileManager.default.copyItem(at: sourceUrl, to: newUrl)

        let clonedDataSource = try DataSourcePath.dataSource(with: newUrl,
                                                             shouldDeleteOnDeallocation: true)
        clonedDataSource.sourceFilename = sourceFilename

        return self.replacingDataSource(with: clonedDataSource)
    }

    public func preparedForOutput(qualityLevel: ImageQualityLevel) -> SignalAttachment {
        owsAssertDebug(!Thread.isMainThread)

        // We only bother converting/compressing non-animated images
        guard isImage, !isAnimatedImage else { return self }

        guard !Self.isValidOutputOriginalImage(
            dataSource: dataSource,
            dataUTI: dataUTI,
            imageQuality: qualityLevel
        ) else { return self }

        let size = ByteCountFormatter.string(fromByteCount: Int64(dataSource.dataLength), countStyle: .file)
        Logger.verbose("Building output image attachment of type: \(mimeType), size: \(size)")

        return Self.convertAndCompressImage(
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

    @objc
    public func buildOutgoingAttachmentInfo(message: TSMessage? = nil) -> OutgoingAttachmentInfo {
        return OutgoingAttachmentInfo(dataSource: dataSource,
                                      contentType: mimeType,
                                      sourceFilename: filenameOrDefault,
                                      caption: captionText,
                                      albumMessageId: message?.uniqueId,
                                      isBorderless: isBorderless,
                                      isLoopingVideo: isLoopingVideo)
    }

    @objc
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

            let thumbnail = image.resized(withMaxDimensionPixels: maxDimensionPixels)
            cachedThumbnail = thumbnail
            return thumbnail
        }
    }

    @objc
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

    @objc
    public func videoPreview() -> UIImage? {
        if let cachedVideoPreview = cachedVideoPreview {
            return cachedVideoPreview
        }

        guard let mediaUrl = dataUrl else {
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

        } catch let error {
            let localizedDescription: String = error.userErrorDescription
            Logger.verbose("Could not generate video thumbnail: \(localizedDescription)")
            return nil
        }
    }

    @objc
    public var isBorderless = false
    @objc
    public var isLoopingVideo = false

    // Returns the MIME type for this attachment or nil if no MIME type
    // can be identified.
    @objc
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

        if let filename = sourceFilename {
            let fileExtension = (filename as NSString).pathExtension
            if fileExtension.count > 0 {
                if let mimeType = MIMETypeUtil.mimeType(forFileExtension: fileExtension) {
                    // UTI types are an imperfect means of representing file type;
                    // file extensions are also imperfect but far more reliable and
                    // comprehensive so we always prefer to try to deduce MIME type
                    // from the file extension.
                    return mimeType
                }
            }
        }
        if isOversizeText {
            return OWSMimeTypeOversizeTextMessage
        }
        if dataUTI == kUnknownTestAttachmentUTI {
            return OWSMimeTypeUnknownForTests
        }
        guard let mimeType = UTTypeCopyPreferredTagWithClass(dataUTI as CFString, kUTTagClassMIMEType) else {
            return OWSMimeTypeApplicationOctetStream
        }
        return mimeType.takeRetainedValue() as String
    }

    // Use the filename if known. If not, e.g. if the attachment was copy/pasted, we'll generate a filename
    // like: "signal-2017-04-24-095918.zip"
    @objc
    public var filenameOrDefault: String {
        if let filename = sourceFilename {
            return filename.filterFilename()
        } else {
            let kDefaultAttachmentName = "signal"

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "YYYY-MM-dd-HHmmss"
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
    @objc
    public var fileExtension: String? {
        if let filename = sourceFilename {
            let fileExtension = (filename as NSString).pathExtension
            if fileExtension.count > 0 {
                return fileExtension.filterFilename()
            }
        }
        if isOversizeText {
            return kOversizeTextAttachmentFileExtension
        }
        if dataUTI == kUnknownTestAttachmentUTI {
            return "unknown"
        }
        guard let fileExtension = MIMETypeUtil.fileExtension(forUTIType: dataUTI) else {
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

        return MIMETypeUtil.supportedInputImageUTITypes()
            .union(animatedImageUTISet)
            .union(heicSet)
    }

    // Returns the set of UTIs that correspond to valid _output_ image formats
    // for Signal attachments.
    private class var outputImageUTISet: Set<String> {
        return MIMETypeUtil.supportedOutputImageUTITypes().union(animatedImageUTISet)
    }

    private class var outputVideoUTISet: Set<String> {
        return Set([kUTTypeMPEG4 as String])
    }

    // Returns the set of UTIs that correspond to valid animated image formats
    // for Signal attachments.
    private class var animatedImageUTISet: Set<String> {
        return MIMETypeUtil.supportedAnimatedImageUTITypes()
    }

    // Returns the set of UTIs that correspond to valid video formats
    // for Signal attachments.
    private class var videoUTISet: Set<String> {
        return MIMETypeUtil.supportedVideoUTITypes()
    }

    // Returns the set of UTIs that correspond to valid audio formats
    // for Signal attachments.
    private class var audioUTISet: Set<String> {
        return MIMETypeUtil.supportedAudioUTITypes()
    }

    // Returns the set of UTIs that correspond to valid image, video and audio formats
    // for Signal attachments.
    private class var mediaUTISet: Set<String> {
        return audioUTISet.union(videoUTISet).union(animatedImageUTISet).union(inputImageUTISet)
    }

    @objc
    public var isImage: Bool {
        return SignalAttachment.outputImageUTISet.contains(dataUTI)
    }

    @objc
    public var isAnimatedImage: Bool {
        if dataUTI == (kUTTypePNG as String),
            dataSource.imageMetadata.isAnimated {
            return true
        }

        return SignalAttachment.animatedImageUTISet.contains(dataUTI)
    }

    @objc
    public var isVideo: Bool {
        return SignalAttachment.videoUTISet.contains(dataUTI)
    }

    @objc
    public var isAudio: Bool {
        return SignalAttachment.audioUTISet.contains(dataUTI)
    }

    @objc
    public var isOversizeText: Bool {
        return dataUTI == kOversizeTextAttachmentUTI
    }

    @objc
    public var isText: Bool {
        return UTTypeConformsTo(dataUTI as CFString, kUTTypeText) || isOversizeText
    }

    @objc
    public var isUrl: Bool {
        return UTTypeConformsTo(dataUTI as CFString, kUTTypeURL)
    }

    @objc
    public class func pasteboardHasPossibleAttachment() -> Bool {
        return UIPasteboard.general.numberOfItems > 0
    }

    public static let mentionPasteboardType = "private.archived-mention-text"

    @objc
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
        guard !pasteboardUTISet.contains(mentionPasteboardType) else {
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
            if UTTypeConformsTo(utiType as CFString, kUTTypeText) {
                hasTextUTIType = true
            } else if mediaUTISet.contains(utiType) {
                hasNonTextUTIType = true
            }
        }
        if pasteboardUTISet.contains(kUTTypeURL as String) {
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

    // Returns an attachment from the pasteboard, or nil if no attachment
    // can be found.
    //
    // NOTE: The attachment returned by this method may not be valid.
    //       Check the attachment's error property.
    @objc
    public class func attachmentFromPasteboard() -> SignalAttachment? {
        guard UIPasteboard.general.numberOfItems >= 1 else {
            return nil
        }

        // If pasteboard contains multiple items, use only the first.
        let itemSet = IndexSet(integer: 0)
        guard let pasteboardUTITypes = UIPasteboard.general.types(forItemSet: itemSet) else {
            return nil
        }

        var pasteboardUTISet = Set<String>(filterDynamicUTITypes(pasteboardUTITypes[0]))
        guard pasteboardUTISet.count > 0 else {
            return nil
        }

        // If we have the choice between a png and a jpg, always choose
        // the png as it may have transparency. Apple provides both jpg
        //  and png uti types when sending memoji stickers and
        // `inputImageUTISet` is unordered, so without this check there
        // is a 50/50 chance that we'd pick the jpg.
        if pasteboardUTISet.isSuperset(of: [kUTTypeJPEG as String, kUTTypePNG as String]) {
            pasteboardUTISet.remove(kUTTypeJPEG as String)
        }

        for dataUTI in inputImageUTISet {
            if pasteboardUTISet.contains(dataUTI) {
                guard let data = dataForFirstPasteboardItem(dataUTI: dataUTI) else {
                    owsFailDebug("Missing expected pasteboard data for UTI: \(dataUTI)")
                    return nil
                }
                let dataSource = DataSourceValue.dataSource(with: data, utiType: dataUTI)

                // If the data source is sticker like AND we're pasting the attachment,
                // we want to make it borderless.
                let isBorderless = dataSource?.hasStickerLikeProperties ?? false

                return imageAttachment(dataSource: dataSource, dataUTI: dataUTI, isBorderless: isBorderless)
            }
        }
        for dataUTI in videoUTISet {
            if pasteboardUTISet.contains(dataUTI) {
                guard let data = dataForFirstPasteboardItem(dataUTI: dataUTI) else {
                    owsFailDebug("Missing expected pasteboard data for UTI: \(dataUTI)")
                    return nil
                }
                let dataSource = DataSourceValue.dataSource(with: data, utiType: dataUTI)
                return videoAttachment(dataSource: dataSource, dataUTI: dataUTI)
            }
        }
        for dataUTI in audioUTISet {
            if pasteboardUTISet.contains(dataUTI) {
                guard let data = dataForFirstPasteboardItem(dataUTI: dataUTI) else {
                    owsFailDebug("Missing expected pasteboard data for UTI: \(dataUTI)")
                    return nil
                }
                let dataSource = DataSourceValue.dataSource(with: data, utiType: dataUTI)
                return audioAttachment(dataSource: dataSource, dataUTI: dataUTI)
            }
        }

        let dataUTI = pasteboardUTISet[pasteboardUTISet.startIndex]
        guard let data = dataForFirstPasteboardItem(dataUTI: dataUTI) else {
            owsFailDebug("Missing expected pasteboard data for UTI: \(dataUTI)")
            return nil
        }
        let dataSource = DataSourceValue.dataSource(with: data, utiType: dataUTI)
        return genericAttachment(dataSource: dataSource, dataUTI: dataUTI)
    }

    // This method should only be called for dataUTIs that
    // are appropriate for the first pasteboard item.
    private class func dataForFirstPasteboardItem(dataUTI: String) -> Data? {
        let itemSet = IndexSet(integer: 0)
        guard let datas = UIPasteboard.general.data(forPasteboardType: dataUTI, inItemSet: itemSet) else {
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
    //
    // NOTE: The attachment returned by this method may not be valid.
    //       Check the attachment's error property.
    @objc
    private class func imageAttachment(dataSource: DataSource?, dataUTI: String, isBorderless: Bool = false) -> SignalAttachment {
        assert(dataUTI.count > 0)
        assert(dataSource != nil)
        guard let dataSource = dataSource else {
            let attachment = SignalAttachment(dataSource: DataSourceValue.emptyDataSource(), dataUTI: dataUTI)
            attachment.error = .missingData
            return attachment
        }

        let attachment = SignalAttachment(dataSource: dataSource, dataUTI: dataUTI)

        attachment.isBorderless = isBorderless

        guard inputImageUTISet.contains(dataUTI) else {
            attachment.error = .invalidFileFormat
            return attachment
        }

        guard dataSource.dataLength > 0 else {
            owsFailDebug("imageData was empty")
            attachment.error = .invalidData
            return attachment
        }

        let imageMetadata = dataSource.imageMetadata
        let isAnimated = imageMetadata.isAnimated
        if isAnimated {
            guard dataSource.dataLength <= kMaxFileSizeAnimatedImage else {
                attachment.error = .fileSizeTooLarge
                return attachment
            }

            // Never re-encode animated images (i.e. GIFs) as JPEGs.
            if dataUTI == (kUTTypePNG as String) {
                Logger.verbose("Attempting to remove metadata from animated PNG")
                do {
                    return try attachment.removingImageMetadata()
                } catch {
                    Logger.warn("Failed to remove metadata from animated PNG. Error: \(error)")
                    attachment.error = .couldNotRemoveMetadata
                    return attachment
                }
            } else {
                Logger.verbose("Sending raw \(attachment.mimeType) to retain any animation")
                return attachment
            }
        } else {
            if let sourceFilename = dataSource.sourceFilename,
                let sourceFileExtension = sourceFilename.fileExtension,
                ["heic", "heif"].contains(sourceFileExtension.lowercased()),
                dataUTI == kUTTypeJPEG as String {

                // If a .heic file actually contains jpeg data, update the extension to match.
                //
                // Here's how that can happen:
                // In iOS11, the Photos.app records photos with HEIC UTIType, with the .HEIC extension.
                // Since HEIC isn't a valid output format for Signal, we'll detect that and convert to JPEG,
                // updating the extension as well. No problem.
                // However the problem comes in when you edit an HEIC image in Photos.app - the image is saved
                // in the Photos.app as a JPEG, but retains the (now incongruous) HEIC extension in the filename.
                Logger.verbose("changing extension: \(sourceFileExtension) to match jpg uti type")

                let baseFilename = sourceFilename.filenameWithoutExtension
                dataSource.sourceFilename = baseFilename.appendingFileExtension("jpg")
            }

            // When preparing an attachment, we always prepare it in the max quality for the current
            // context. The user can choose during sending whether they want the final send to be in
            // standard or high quality. We will do the final convert and compress before uploading.

            if isValidOutputOriginalImage(dataSource: dataSource, dataUTI: dataUTI, imageQuality: .max) {
                Logger.verbose("Rewriting attachment with metadata removed \(attachment.mimeType)")
                do {
                    return try attachment.removingImageMetadata()
                } catch {
                    Logger.verbose("Failed to remove metadata directly: \(error)")
                }
            }

            let size = ByteCountFormatter.string(fromByteCount: Int64(dataSource.dataLength), countStyle: .file)
            Logger.verbose("Rebuilding image attachment of type: \(attachment.mimeType), size: \(size)")

            return convertAndCompressImage(
                dataSource: dataSource,
                attachment: attachment,
                imageQuality: .max
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
        guard SignalAttachment.outputImageUTISet.contains(dataUTI) else { return false }
        guard dataSource.dataLength <= imageQuality.maxFileSize else { return false }
        if dataSource.hasStickerLikeProperties { return true }
        guard dataSource.dataLength <= imageQuality.maxOriginalFileSize else { return false }
        return true
    }

    private class func convertAndCompressImage(dataSource: DataSource, attachment: SignalAttachment, imageQuality: ImageQualityLevel) -> SignalAttachment {
        assert(attachment.error == nil)

        var imageUploadQuality = imageQuality.startingTier

        while true {
            let outcome = convertAndCompressImageAttempt(dataSource: dataSource,
                                                         attachment: attachment,
                                                         imageQuality: imageQuality,
                                                         imageUploadQuality: imageUploadQuality)
            switch outcome {
            case .signalAttachment(let signalAttachment):
                return signalAttachment
            case .error(let error):
                attachment.error = error
                return attachment
            case .reduceQuality(let imageQualityTier):
                imageUploadQuality = imageQualityTier
            }
        }
    }

    private enum ConvertAndCompressOutcome {
        case signalAttachment(signalAttachment: SignalAttachment)
        case reduceQuality(imageQualityTier: ImageQualityTier)
        case error(error: SignalAttachmentError)
    }

    private class func convertAndCompressImageAttempt(dataSource: DataSource,
                                                      attachment: SignalAttachment,
                                                      imageQuality: ImageQualityLevel,
                                                      imageUploadQuality: ImageQualityTier) -> ConvertAndCompressOutcome {
        autoreleasepool {  () -> ConvertAndCompressOutcome in
            owsAssertDebug(attachment.error == nil)

            let maxSize = imageUploadQuality.maxEdgeSize
            let pixelSize = dataSource.imageMetadata.pixelSize
            var imageProperties = [CFString: Any]()

            let cgImage: CGImage
            if pixelSize.width > maxSize || pixelSize.height > maxSize {
                guard let downsampledCGImage = downsampleImage(dataSource: dataSource, toMaxSize: maxSize) else {
                    return .error(error: .couldNotResizeImage)
                }

                cgImage = downsampledCGImage
            } else {
                guard let imageSource = cgImageSource(for: dataSource) else {
                    return .error(error: .couldNotParseImage)
                }

                guard let originalImageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, [
                    kCGImageSourceShouldCache: false
                ] as CFDictionary) as? [CFString: Any] else {
                    return .error(error: .couldNotParseImage)
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
                    return .error(error: .couldNotParseImage)
                }

                cgImage = image
            }

            // Write to disk and convert to file based data source,
            // so we can keep the image out of memory.

            let dataFileExtension: String
            let dataUTI: CFString
            let dataMIMEType: String

            // We convert everything that's not sticker-like to jpg, because
            // often images with alpha channels don't actually have any
            // transparent pixels (all screenshots fall into this bucket)
            // and there is not a simple, performant way, to check if there
            // are any transparent pixels in an image.
            if dataSource.hasStickerLikeProperties {
                dataFileExtension = "png"
                dataUTI = kUTTypePNG
                dataMIMEType = OWSMimeTypeImagePng
            } else {
                dataFileExtension = "jpg"
                dataUTI = kUTTypeJPEG
                dataMIMEType = OWSMimeTypeImageJpeg
                imageProperties[kCGImageDestinationLossyCompressionQuality] = compressionQuality(for: pixelSize)
            }

            let tempFileUrl = OWSFileSystem.temporaryFileUrl(fileExtension: dataFileExtension)
            guard let destination = CGImageDestinationCreateWithURL(tempFileUrl as CFURL, dataUTI, 1, nil) else {
                owsFailDebug("Failed to create CGImageDestination for attachment")
                return .error(error: .couldNotConvertImage)
            }
            CGImageDestinationAddImage(destination, cgImage, imageProperties as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                owsFailDebug("Failed to write downsampled attachment to disk")
                return .error(error: .couldNotConvertImage)
            }

            let outputDataSource: DataSource
            do {
                outputDataSource = try DataSourcePath.dataSource(with: tempFileUrl, shouldDeleteOnDeallocation: false)
            } catch {
                owsFailDebug("Failed to create data source for downsampled image \(error)")
                return .error(error: .couldNotConvertImage)
            }

            // Preserve the original filename
            let baseFilename = dataSource.sourceFilename?.filenameWithoutExtension
            let newFilenameWithExtension = baseFilename?.appendingFileExtension(dataFileExtension)
            outputDataSource.sourceFilename = newFilenameWithExtension

            if outputDataSource.dataLength <= imageQuality.maxFileSize, outputDataSource.dataLength <= kMaxFileSizeImage {
                let recompressedAttachment = attachment.replacingDataSource(with: outputDataSource, dataUTI: dataUTI as String)
                Logger.verbose("Converted \(attachment.mimeType), size: \(outputDataSource.dataLength) to \(ByteCountFormatter.string(fromByteCount: Int64(outputDataSource.dataLength), countStyle: .file)) \(dataMIMEType)")
                return .signalAttachment(signalAttachment: recompressedAttachment)
            }

            // If the image output is larger than the file size limit,
            // continue to try again by progressively reducing the
            // image upload quality.
            if let reducedQuality = imageUploadQuality.reduced {
                return .reduceQuality(imageQualityTier: reducedQuality)
            } else {
                return .error(error: .fileSizeTooLarge)
            }
        }
    }

    private class func compressionQuality(for pixelSize: CGSize) -> CGFloat {
        // For very large images, we can use a higher
        // jpeg compression without seeing artifacting
        if pixelSize.largerAxis >= 3072 { return 0.55 }
        return 0.6
    }

    private class func cgImageSource(for dataSource: DataSource) -> CGImageSource? {
        if dataSource.imageMetadata.imageFormat == ImageFormat.webp {
            // CGImageSource doesn't know how to handle webp, so we have
            // to pass it through YYImage. This is costly and we could
            // perhaps do better, but webp images are usually small.
            guard let yyImage = YYImage(data: dataSource.data) else {
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
            Logger.verbose("maxSize: \(maxSize)")

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
            ] as CFDictionary
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
    private static func removeMetadata(fromPng pngData: Data) throws -> Data {
        do {
            let chunker = try PngChunker(data: pngData)
            var result = PngChunker.pngSignature
            while let chunk = try chunker.next() {
                if pngChunkTypesToKeep.contains(chunk.type) {
                    result += chunk.allBytes()
                }
            }
            return result
        } catch {
            Logger.warn("Could not remove PNG metadata: \(error)")
            throw SignalAttachmentError.couldNotRemoveMetadata
        }
    }

    private func removingImageMetadata() throws -> SignalAttachment {
        owsAssertDebug(isImage)

        if dataUTI == (kUTTypePNG as String) {
            let cleanedData = try Self.removeMetadata(fromPng: data)
            guard let dataSource = DataSourceValue.dataSource(with: cleanedData, utiType: dataUTI) else {
                throw SignalAttachmentError.couldNotRemoveMetadata
            }
            return replacingDataSource(with: dataSource)
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw SignalAttachmentError.missingData
        }

        guard let type = CGImageSourceGetType(source) else {
            throw SignalAttachmentError.invalidFileFormat
        }

        let count = CGImageSourceGetCount(source)
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData as CFMutableData, type, count, nil) else {
            throw SignalAttachmentError.couldNotRemoveMetadata
        }

        // Build up a metadata with CFNulls in the place of all tags present in the original metadata.
        // (Unfortunately CGImageDestinationCopyImageSource can only merge metadata, not replace it.)
        let metadata = CGImageMetadataCreateMutable()
        let enumerateOptions: NSDictionary = [kCGImageMetadataEnumerateRecursively: false]
        var hadError = false
        for i in 0..<count {
            guard let originalMetadata = CGImageSourceCopyMetadataAtIndex(source, i, nil) else {
                throw SignalAttachmentError.couldNotRemoveMetadata
            }
            CGImageMetadataEnumerateTagsUsingBlock(originalMetadata, nil, enumerateOptions) { path, tag in
                if Self.preservedMetadata.contains(path) {
                    return true
                }
                guard let namespace = CGImageMetadataTagCopyNamespace(tag),
                      let prefix = CGImageMetadataTagCopyPrefix(tag),
                      CGImageMetadataRegisterNamespaceForPrefix(metadata, namespace, prefix, nil),
                      CGImageMetadataSetValueWithPath(metadata, nil, path, kCFNull) else {
                    hadError = true
                    return false // stop iteration
                }
                return true
            }
            if hadError {
                throw SignalAttachmentError.couldNotRemoveMetadata
            }
        }

        var error: Unmanaged<CFError>?
        let copyOptions: NSDictionary = [
            kCGImageDestinationMergeMetadata: true,
            kCGImageDestinationMetadata: metadata
        ]
        guard CGImageDestinationCopyImageSource(destination, source, copyOptions, &error) else {
            let errorMessage = (error?.takeRetainedValue()).map { String(describing: $0) } ?? "(unknown error)"
            Logger.verbose("CGImageDestinationCopyImageSource failed for \(dataUTI): \(errorMessage)")
            throw SignalAttachmentError.couldNotRemoveMetadata
        }

        guard let dataSource = DataSourceValue.dataSource(with: mutableData as Data, utiType: dataUTI) else {
            throw SignalAttachmentError.couldNotRemoveMetadata
        }

        return self.replacingDataSource(with: dataSource)
    }

    // MARK: Video Attachments

    // Factory method for video attachments.
    //
    // NOTE: The attachment returned by this method may not be valid.
    //       Check the attachment's error property.
    private class func videoAttachment(dataSource: DataSource?, dataUTI: String) -> SignalAttachment {
        guard let dataSource = dataSource else {
            let dataSource = DataSourceValue.emptyDataSource()
            let attachment = SignalAttachment(dataSource: dataSource, dataUTI: dataUTI)
            attachment.error = .missingData
            return attachment
        }

        if !isValidOutputVideo(dataSource: dataSource, dataUTI: dataUTI) {
            owsFailDebug("building video with invalid output, migrate to async API using compressVideoAsMp4")
        }

        return newAttachment(dataSource: dataSource,
                             dataUTI: dataUTI,
                             validUTISet: videoUTISet,
                             maxFileSize: kMaxFileSizeVideo)
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

    public class func compressVideoAsMp4(dataSource: DataSource, dataUTI: String) -> (Promise<SignalAttachment>, AVAssetExportSession?) {
        Logger.debug("")

        guard let url = dataSource.dataUrl else {
            let attachment = SignalAttachment(dataSource: DataSourceValue.emptyDataSource(), dataUTI: dataUTI)
            attachment.error = .missingData
            return (Promise.value(attachment), nil)
        }

        return compressVideoAsMp4(asset: AVAsset(url: url), baseFilename: dataSource.sourceFilename, dataUTI: dataUTI)
    }

    public class func compressVideoAsMp4(asset: AVAsset, baseFilename: String?, dataUTI: String) -> (Promise<SignalAttachment>, AVAssetExportSession?) {
        Logger.debug("")
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset640x480) else {
            let attachment = SignalAttachment(dataSource: DataSourceValue.emptyDataSource(), dataUTI: dataUTI)
            attachment.error = .couldNotConvertToMpeg4
            return (Promise.value(attachment), nil)
        }

        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.outputFileType = AVFileType.mp4
        exportSession.metadataItemFilter = AVMetadataItemFilter.forSharing()

        let exportURL = videoTempPath.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        exportSession.outputURL = exportURL

        let (promise, future) = Promise<SignalAttachment>.pending()

        Logger.debug("Starting video export")

        exportSession.exportAsynchronously {
            if let error = exportSession.error {
                owsFailDebug("Error: \(error)")
                future.reject(error)
                return
            }
            switch exportSession.status {
            case .unknown:
                future.reject(OWSAssertionError("Unknown export status."))
                return
            case .waiting:
                future.reject(OWSAssertionError("Export status: .waiting."))
                return
            case .exporting:
                future.reject(OWSAssertionError("Export status: .exporting."))
                return
            case .completed:
                break
            case .failed:
                future.reject(OWSAssertionError("Export failed without error."))
                return
            case .cancelled:
                future.reject(OWSGenericError("Cancelled."))
                return
            @unknown default:
                future.reject(OWSAssertionError("Unknown export status: \(exportSession.status.rawValue)"))
                return
            }
            Logger.debug("Completed video export")
            let mp4Filename = baseFilename?.filenameWithoutExtension.appendingFileExtension("mp4")

            do {
                let dataSource = try DataSourcePath.dataSource(with: exportURL,
                                                               shouldDeleteOnDeallocation: true)
                dataSource.sourceFilename = mp4Filename

                let attachment = SignalAttachment(dataSource: dataSource, dataUTI: kUTTypeMPEG4 as String)
                future.resolve(attachment)
            } catch {
                owsFailDebug("Failed to build data source for exported video URL")
                let attachment = SignalAttachment(dataSource: DataSourceValue.emptyDataSource(), dataUTI: dataUTI)
                attachment.error = .couldNotConvertToMpeg4
                future.resolve(attachment)
                return
            }
        }

        return (promise, exportSession)
    }

    @objc
    public class func isVideoThatNeedsCompression(dataSource: DataSource, dataUTI: String) -> Bool {
        guard videoUTISet.contains(dataUTI) else {
            // not a video
            return false
        }

        // Today we re-encode all videos for the most consistent experience.
        return true
    }

    private class func isValidOutputVideo(dataSource: DataSource?, dataUTI: String) -> Bool {
        guard let dataSource = dataSource else {
            Logger.warn("Missing dataSource.")
            return false
        }

        guard SignalAttachment.outputVideoUTISet.contains(dataUTI) else {
            Logger.warn("Invalid UTI type: \(dataUTI).")
            return false
        }

        if dataSource.dataLength <= kMaxFileSizeVideo {
            return true
        }
        Logger.verbose("Invalid file size: \(dataSource.dataLength) > \(kMaxFileSizeVideo).")
        Logger.warn("Invalid file size.")
        return false
    }

    // MARK: Audio Attachments

    // Factory method for audio attachments.
    //
    // NOTE: The attachment returned by this method may not be valid.
    //       Check the attachment's error property.
    private class func audioAttachment(dataSource: DataSource?, dataUTI: String) -> SignalAttachment {
        return newAttachment(dataSource: dataSource,
                             dataUTI: dataUTI,
                             validUTISet: audioUTISet,
                             maxFileSize: kMaxFileSizeAudio)
    }

    // MARK: Oversize Text Attachments

    // Factory method for oversize text attachments.
    //
    // NOTE: The attachment returned by this method may not be valid.
    //       Check the attachment's error property.
    private class func oversizeTextAttachment(text: String?) -> SignalAttachment {
        let dataSource = DataSourceValue.dataSource(withOversizeText: text)
        return newAttachment(dataSource: dataSource,
                             dataUTI: kOversizeTextAttachmentUTI,
                             validUTISet: nil,
                             maxFileSize: kMaxFileSizeGeneric)
    }

    // MARK: Generic Attachments

    // Factory method for generic attachments.
    //
    // NOTE: The attachment returned by this method may not be valid.
    //       Check the attachment's error property.
    private class func genericAttachment(dataSource: DataSource?, dataUTI: String) -> SignalAttachment {
        return newAttachment(dataSource: dataSource,
                             dataUTI: dataUTI,
                             validUTISet: nil,
                             maxFileSize: kMaxFileSizeGeneric)
    }

    // MARK: Voice Messages

    @objc
    public class func voiceMessageAttachment(dataSource: DataSource?, dataUTI: String) -> SignalAttachment {
        let attachment = audioAttachment(dataSource: dataSource, dataUTI: dataUTI)
        attachment.isVoiceMessage = true
        return attachment
    }

    // MARK: Attachments

    // Factory method for attachments of any kind.
    //
    // NOTE: The attachment returned by this method may not be valid.
    //       Check the attachment's error property.
    @objc
    public class func attachment(dataSource: DataSource?, dataUTI: String) -> SignalAttachment {
        if inputImageUTISet.contains(dataUTI) {
            return imageAttachment(dataSource: dataSource, dataUTI: dataUTI)
        } else if videoUTISet.contains(dataUTI) {
            return videoAttachment(dataSource: dataSource, dataUTI: dataUTI)
        } else if audioUTISet.contains(dataUTI) {
            return audioAttachment(dataSource: dataSource, dataUTI: dataUTI)
        } else {
            return genericAttachment(dataSource: dataSource, dataUTI: dataUTI)
        }
    }

    @objc
    public class func empty() -> SignalAttachment {
        return SignalAttachment.attachment(dataSource: DataSourceValue.emptyDataSource(),
                                           dataUTI: kUTTypeContent as String)
    }

    // MARK: Helper Methods

    private class func newAttachment(dataSource: DataSource?,
                                     dataUTI: String,
                                     validUTISet: Set<String>?,
                                     maxFileSize: UInt) -> SignalAttachment {
        assert(dataUTI.count > 0)

        assert(dataSource != nil)
        guard let dataSource = dataSource else {
            let attachment = SignalAttachment(dataSource: DataSourceValue.emptyDataSource(), dataUTI: dataUTI)
            attachment.error = .missingData
            return attachment
        }

        let attachment = SignalAttachment(dataSource: dataSource, dataUTI: dataUTI)

        if let validUTISet = validUTISet {
            guard validUTISet.contains(dataUTI) else {
                attachment.error = .invalidFileFormat
                return attachment
            }
        }

        guard dataSource.dataLength > 0 else {
            owsFailDebug("Empty attachment")
            assert(dataSource.dataLength > 0)
            attachment.error = .invalidData
            return attachment
        }

        guard dataSource.dataLength <= maxFileSize else {
            attachment.error = .fileSizeTooLarge
            return attachment
        }

        // Attachment is valid
        return attachment
    }
}
