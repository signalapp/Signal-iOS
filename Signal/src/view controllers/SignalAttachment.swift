//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import MobileCoreServices

enum SignalAttachmentError: Error {
    case missingData
    case fileSizeTooLarge
    case invalidData
    case couldNotParseImage
    case couldNotConvertToJpeg
    case invalidFileFormat
}

extension SignalAttachmentError: LocalizedError {
    public var errorDescription: String {
        switch self {
        case .missingData:
            return NSLocalizedString("ATTACHMENT_ERROR_MISSING_DATA", comment: "Attachment error message for attachments without any data")
        case .fileSizeTooLarge:
            return NSLocalizedString("ATTACHMENT_ERROR_FILE_SIZE_TOO_LARGE", comment: "Attachment error message for attachments whose data exceed file size limits")
        case .invalidData:
            return NSLocalizedString("ATTACHMENT_ERROR_INVALID_DATA", comment: "Attachment error message for attachments with invalid data")
        case .couldNotParseImage:
            return NSLocalizedString("ATTACHMENT_ERROR_COULD_NOT_PARSE_IMAGE", comment: "Attachment error message for image attachments which cannot be parsed")
        case .couldNotConvertToJpeg:
            return NSLocalizedString("ATTACHMENT_ERROR_COULD_NOT_CONVERT_TO_JPEG", comment: "Attachment error message for image attachments which could not be converted to JPEG")
        case .invalidFileFormat:
            return NSLocalizedString("ATTACHMENT_ERROR_INVALID_FILE_FORMAT", comment: "Attachment error message for attachments with an invalid file format")
        }
    }
}

enum TSImageQuality {
    case uncropped
    case high
    case medium
    case low
}

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
// TODO: Show error on error.
// TODO: Show progress on upload.
class SignalAttachment: NSObject {

    static let TAG = "[SignalAttachment]"

    // MARK: Properties

    let data: Data

    // Attachment types are identified using UTIs.
    //
    // See: https://developer.apple.com/library/content/documentation/Miscellaneous/Reference/UTIRef/Articles/System-DeclaredUniformTypeIdentifiers.html
    let dataUTI: String

    static let kOversizeTextAttachmentUTI = "org.whispersystems.oversize-text-attachment"
    static let kUnknownTestAttachmentUTI = "org.whispersystems.unknown"

    var error: SignalAttachmentError? {
        didSet {
            AssertIsOnMainThread()

            assert(oldValue == nil)
            Logger.verbose("\(SignalAttachment.TAG) Attachment has error: \(error)")
        }
    }

    // To avoid redundant work of repeatedly compressing/uncompressing
    // images, we cache the UIImage associated with this attachment if
    // possible.
    public var image: UIImage?

    // MARK: Constants

    /**
     * Media Size constraints from Signal-Android
     *
     * https://github.com/WhisperSystems/Signal-Android/blob/master/src/org/thoughtcrime/securesms/mms/PushMediaConstraints.java
     */
    static let kMaxFileSizeAnimatedImage = 15 * 1024 * 1024
    static let kMaxFileSizeImage = 6 * 1024 * 1024
    static let kMaxFileSizeVideo = 100 * 1024 * 1024
    static let kMaxFileSizeAudio = 100 * 1024 * 1024
    static let kMaxFileSizeGeneric = 100 * 1024 * 1024

    // MARK: Constructor

    // This method should not be called directly; use the factory
    // methods instead.
    internal required init(data: Data, dataUTI: String) {
        self.data = data
        self.dataUTI = dataUTI
        super.init()
    }

    var hasError: Bool {
        return error != nil
    }

    var errorName: String? {
        guard let error = error else {
            // This method should only be called if there is an error.
            assert(false)
            return nil
        }

        return "\(error)"
    }

    var localizedErrorDescription: String? {
        guard let error = self.error else {
            // This method should only be called if there is an error.
            assert(false)
            return nil
        }

        return "\(error.errorDescription)"
    }

    class var missingDataErrorMessage: String {
        return SignalAttachmentError.missingData.errorDescription
    }

    // Returns the MIME type for this attachment or nil if no MIME type
    // can be identified.
    var mimeType: String? {
        if dataUTI == SignalAttachment.kOversizeTextAttachmentUTI {
            return OWSMimeTypeOversizeTextMessage
        }
        if dataUTI == SignalAttachment.kUnknownTestAttachmentUTI {
            return OWSMimeTypeUnknownForTests
        }
        let mimeType = UTTypeCopyPreferredTagWithClass(dataUTI as CFString, kUTTagClassMIMEType)
        guard mimeType != nil else {
            return nil
        }
        return mimeType?.takeRetainedValue() as? String
    }

    // Returns the file extension for this attachment or nil if no file extension
    // can be identified.
    var fileExtension: String? {
        if dataUTI == SignalAttachment.kOversizeTextAttachmentUTI ||
        dataUTI == SignalAttachment.kUnknownTestAttachmentUTI {
            assert(false)
            return ""
        }

        guard let fileExtension = UTTypeCopyPreferredTagWithClass(dataUTI as CFString,
                                                                  kUTTagClassFilenameExtension) else {
            return nil
        }
        return fileExtension.takeRetainedValue() as String
    }

    private static let allowArbitraryAttachments = false

    // Returns the set of UTIs that correspond to valid _input_ image formats
    // for Signal attachments.
    //
    // Image attachments may be converted to another image format before 
    // being uploaded.
    private class var inputImageUTISet: Set<String> {
        return MIMETypeUtil.supportedImageUTITypes().union(animatedImageUTISet)
    }

    // Returns the set of UTIs that correspond to valid _output_ image formats
    // for Signal attachments.
    private class var outputImageUTISet: Set<String> {
        if allowArbitraryAttachments {
            return MIMETypeUtil.supportedImageUTITypes().union(animatedImageUTISet)
        } else {
            // Until Android client can handle arbitrary attachments,
            // restrict output.
            return [
                kUTTypeJPEG as String,
                kUTTypeGIF as String,
                kUTTypePNG as String
            ]
        }
    }

    // Returns the set of UTIs that correspond to valid animated image formats
    // for Signal attachments.
    private class var animatedImageUTISet: Set<String> {
        return MIMETypeUtil.supportedAnimatedImageUTITypes()
    }

    // Returns the set of UTIs that correspond to valid video formats
    // for Signal attachments.
    private class var videoUTISet: Set<String> {
        if allowArbitraryAttachments {
            return MIMETypeUtil.supportedVideoUTITypes()
        } else {
            return [
                kUTTypeMPEG4 as String
            ]
        }
    }

    // Returns the set of UTIs that correspond to valid audio formats
    // for Signal attachments.
    private class var audioUTISet: Set<String> {
        if allowArbitraryAttachments {
            return MIMETypeUtil.supportedAudioUTITypes()
        } else {
            return [
                kUTTypeMP3 as String,
                kUTTypeMPEG4Audio as String
            ]
        }
    }

    // Returns the set of UTIs that correspond to valid input formats
    // for Signal attachments.
    public class var validInputUTISet: Set<String> {
        return inputImageUTISet.union(videoUTISet.union(audioUTISet))
    }

    public var isImage: Bool {
        return SignalAttachment.outputImageUTISet.contains(dataUTI)
    }

    public var isVideo: Bool {
        return SignalAttachment.videoUTISet.contains(dataUTI)
    }

    public var isAudio: Bool {
        return SignalAttachment.audioUTISet.contains(dataUTI)
    }

    // Returns an attachment from the pasteboard, or nil if no attachment
    // can be found.
    //
    // NOTE: The attachment returned by this method may not be valid.
    //       Check the attachment's error property.
    public class func attachmentFromPasteboard() -> SignalAttachment? {
        guard UIPasteboard.general.numberOfItems >= 1 else {
            return nil
        }
        // If pasteboard contains multiple items, use only the first.
        let itemSet = IndexSet(integer:0)
        guard let pasteboardUTITypes = UIPasteboard.general.types(forItemSet:itemSet) else {
            return nil
        }
        let pasteboardUTISet = Set<String>(pasteboardUTITypes[0])
        for dataUTI in inputImageUTISet {
            if pasteboardUTISet.contains(dataUTI) {
                guard let data = dataForFirstPasteboardItem(dataUTI:dataUTI) else {
                    Logger.verbose("\(TAG) Missing expected pasteboard data for UTI: \(dataUTI)")
                    return nil
                }
                return imageAttachment(data : data, dataUTI : dataUTI)
            }
        }
        for dataUTI in videoUTISet {
            if pasteboardUTISet.contains(dataUTI) {
                guard let data = dataForFirstPasteboardItem(dataUTI:dataUTI) else {
                    Logger.verbose("\(TAG) Missing expected pasteboard data for UTI: \(dataUTI)")
                    return nil
                }
                return videoAttachment(data : data, dataUTI : dataUTI)
            }
        }
        for dataUTI in audioUTISet {
            if pasteboardUTISet.contains(dataUTI) {
                guard let data = dataForFirstPasteboardItem(dataUTI:dataUTI) else {
                    Logger.verbose("\(TAG) Missing expected pasteboard data for UTI: \(dataUTI)")
                    return nil
                }
                return audioAttachment(data : data, dataUTI : dataUTI)
            }
        }
        // TODO: We could handle generic attachments at this point.

        return nil
    }

    // This method should only be called for dataUTIs that
    // are appropriate for the first pasteboard item.
    private class func dataForFirstPasteboardItem(dataUTI: String) -> Data? {
        let itemSet = IndexSet(integer:0)
        guard let datas = UIPasteboard.general.data(forPasteboardType:dataUTI, inItemSet:itemSet) else {
            Logger.verbose("\(TAG) Missing expected pasteboard data for UTI: \(dataUTI)")
            return nil
        }
        guard datas.count > 0 else {
            Logger.verbose("\(TAG) Missing expected pasteboard data for UTI: \(dataUTI)")
            return nil
        }
        guard let data = datas[0] as? Data else {
            Logger.verbose("\(TAG) Missing expected pasteboard data for UTI: \(dataUTI)")
            return nil
        }
        return data
    }

    // MARK: Image Attachments

    // Factory method for an image attachment.
    //
    // NOTE: The attachment returned by this method may not be valid.
    //       Check the attachment's error property.
    public class func imageAttachment(data imageData: Data?, dataUTI: String) -> SignalAttachment {
        assert(dataUTI.characters.count > 0)

        assert(imageData != nil)
        guard let imageData = imageData else {
            let attachment = SignalAttachment(data : Data(), dataUTI: dataUTI)
            attachment.error = .missingData
            return attachment
        }

        let attachment = SignalAttachment(data : imageData, dataUTI: dataUTI)

        guard inputImageUTISet.contains(dataUTI) else {
            attachment.error = .invalidFileFormat
            return attachment
        }

        guard imageData.count > 0 else {
            assert(imageData.count > 0)
            attachment.error = .invalidData
            return attachment
        }

        if animatedImageUTISet.contains(dataUTI) {
            guard imageData.count <= kMaxFileSizeAnimatedImage else {
                attachment.error = .fileSizeTooLarge
                return attachment
            }
            // Never re-encode animated images (i.e. GIFs) as JPEGs.
            Logger.verbose("\(TAG) Sending raw \(attachment.mimeType) to retain any animation")
            return attachment
        } else {
            guard let image = UIImage(data:imageData) else {
                attachment.error = .couldNotParseImage
                return attachment
            }
            attachment.image = image

            if isInputImageValidOutputImage(image: image, imageData: imageData, dataUTI: dataUTI) {
                Logger.verbose("\(TAG) Sending raw \(attachment.mimeType)")
                return attachment
            }

            Logger.verbose("\(TAG) Compressing attachment as image/jpeg")
            return compressImageAsJPEG(image : image, attachment : attachment)
        }
    }

    private class func defaultImageUploadQuality() -> TSImageQuality {
        // Currently default to a original image quality and size.
        return .uncropped
    }

    // If the proposed attachment already conforms to the
    // file size and content size limits, don't recompress it.
    private class func isInputImageValidOutputImage(image: UIImage?, imageData: Data?, dataUTI: String) -> Bool {
        guard let image = image else {
            return false
        }
        guard let imageData = imageData else {
            return false
        }
        guard SignalAttachment.outputImageUTISet.contains(dataUTI) else {
            return false
        }

        let maxSize = maxSizeForImage(image: image,
                                      imageUploadQuality:defaultImageUploadQuality())
        if image.size.width <= maxSize &&
            image.size.height <= maxSize &&
            imageData.count <= kMaxFileSizeImage {
            return true
        }
        return false
    }

    // Factory method for an image attachment.
    //
    // NOTE: The attachment returned by this method may nil or not be valid.
    //       Check the attachment's error property.
    public class func imageAttachment(image: UIImage?, dataUTI: String) -> SignalAttachment {
        assert(dataUTI.characters.count > 0)

        guard let image = image else {
            let attachment = SignalAttachment(data : Data(), dataUTI: dataUTI)
            attachment.error = .missingData
            return attachment
        }

        // Make a placeholder attachment on which to hang errors if necessary.
        let attachment = SignalAttachment(data : Data(), dataUTI: dataUTI)
        attachment.image = image

        Logger.verbose("\(TAG) Writing \(attachment.mimeType) as image/jpeg")
        return compressImageAsJPEG(image : image, attachment : attachment)
    }

    private class func compressImageAsJPEG(image: UIImage, attachment: SignalAttachment) -> SignalAttachment {
        assert(attachment.error == nil)

        var imageUploadQuality = defaultImageUploadQuality()

        while true {
            let maxSize = maxSizeForImage(image: image, imageUploadQuality:imageUploadQuality)
            var dstImage: UIImage! = image
            if image.size.width > maxSize ||
                image.size.height > maxSize {
                dstImage = imageScaled(image, toMaxSize: maxSize)
            }
            guard let jpgImageData = UIImageJPEGRepresentation(dstImage,
                                                               jpegCompressionQuality(imageUploadQuality:imageUploadQuality)) else {
                                                                attachment.error = .couldNotConvertToJpeg
                                                                return attachment
            }

            if jpgImageData.count <= kMaxFileSizeImage {
                let recompressedAttachment = SignalAttachment(data : jpgImageData, dataUTI: kUTTypeJPEG as String)
                recompressedAttachment.image = dstImage
                return recompressedAttachment
            }

            // If the JPEG output is larger than the file size limit,
            // continue to try again by progressively reducing the
            // image upload quality.
            switch imageUploadQuality {
            case .uncropped:
                imageUploadQuality = .high
            case .high:
                imageUploadQuality = .medium
            case .medium:
                imageUploadQuality = .low
            case .low:
                attachment.error = .fileSizeTooLarge
                return attachment
            }
        }
    }

    private class func imageScaled(_ image: UIImage, toMaxSize size: CGFloat) -> UIImage {
        var scaleFactor: CGFloat
        let aspectRatio: CGFloat = image.size.height / image.size.width
        if aspectRatio > 1 {
            scaleFactor = size / image.size.width
        } else {
            scaleFactor = size / image.size.height
        }
        let newSize = CGSize(width: CGFloat(image.size.width * scaleFactor), height: CGFloat(image.size.height * scaleFactor))
        UIGraphicsBeginImageContext(newSize)
        image.draw(in: CGRect(x: CGFloat(0), y: CGFloat(0), width: CGFloat(newSize.width), height: CGFloat(newSize.height)))
        let updatedImage: UIImage? = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return updatedImage!
    }

    private class func maxSizeForImage(image: UIImage, imageUploadQuality: TSImageQuality) -> CGFloat {
        switch imageUploadQuality {
        case .uncropped:
            return max(image.size.width, image.size.height)
        case .high:
            return 2048
        case .medium:
            return 1024
        case .low:
            return 512
        }
    }

    private class func jpegCompressionQuality(imageUploadQuality: TSImageQuality) -> CGFloat {
        switch imageUploadQuality {
        case .uncropped:
            return 1
        case .high:
            return 0.9
        case .medium:
            return 0.5
        case .low:
            return 0.3
        }
    }

    // MARK: Video Attachments

    // Factory method for video attachments.
    //
    // NOTE: The attachment returned by this method may not be valid.
    //       Check the attachment's error property.
    public class func videoAttachment(data: Data?, dataUTI: String) -> SignalAttachment {
        return newAttachment(data : data,
                             dataUTI : dataUTI,
                             validUTISet : videoUTISet,
                             maxFileSize : kMaxFileSizeVideo)
    }

    // MARK: Audio Attachments

    // Factory method for audio attachments.
    //
    // NOTE: The attachment returned by this method may not be valid.
    //       Check the attachment's error property.
    public class func audioAttachment(data: Data?, dataUTI: String) -> SignalAttachment {
        return newAttachment(data : data,
                             dataUTI : dataUTI,
                             validUTISet : audioUTISet,
                             maxFileSize : kMaxFileSizeAudio)
    }

    // MARK: Oversize Text Attachments

    // Factory method for oversize text attachments.
    //
    // NOTE: The attachment returned by this method may not be valid.
    //       Check the attachment's error property.
    public class func oversizeTextAttachment(text: String?) -> SignalAttachment {
        return newAttachment(data : text?.data(using: .utf8),
                             dataUTI : kOversizeTextAttachmentUTI,
                             validUTISet : nil,
                             maxFileSize : kMaxFileSizeGeneric)
    }

    // MARK: Generic Attachments

    // Factory method for generic attachments.
    //
    // NOTE: The attachment returned by this method may not be valid.
    //       Check the attachment's error property.
    public class func genericAttachment(data: Data?, dataUTI: String) -> SignalAttachment {
        return newAttachment(data : data,
                             dataUTI : dataUTI,
                             validUTISet : nil,
                             maxFileSize : kMaxFileSizeGeneric)
    }

    // MARK: Helper Methods

    private class func newAttachment(data: Data?,
                                     dataUTI: String,
                                     validUTISet: Set<String>?,
                                     maxFileSize: Int) -> SignalAttachment {
        assert(dataUTI.characters.count > 0)

        assert(data != nil)
        guard let data = data else {
            let attachment = SignalAttachment(data : Data(), dataUTI: dataUTI)
            attachment.error = .missingData
            return attachment
        }

        let attachment = SignalAttachment(data : data, dataUTI: dataUTI)

        if let validUTISet = validUTISet {
            guard validUTISet.contains(dataUTI) else {
                attachment.error = .invalidFileFormat
                return attachment
            }
        }

        guard data.count > 0 else {
            assert(data.count > 0)
            attachment.error = .invalidData
            return attachment
        }

        guard data.count <= maxFileSize else {
            attachment.error = .fileSizeTooLarge
            return attachment
        }

        // Attachment is valid
        return attachment
    }
}
