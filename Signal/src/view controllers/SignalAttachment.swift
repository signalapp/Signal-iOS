//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import MobileCoreServices

enum SignalAttachmentError: String {
    case fileSizeTooLarge
    case invalidData
    case couldNotParseImage
    case couldNotConvertToJpeg
    case invalidFileFormat
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

    let data: Data!

    // Attachment types are identified using UTIs.
    //
    // See: https://developer.apple.com/library/content/documentation/Miscellaneous/Reference/UTIRef/Articles/System-DeclaredUniformTypeIdentifiers.html
    let dataUTI: String!

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
     * (org/thoughtcrime/securesms/mms/PushMediaConstraints.java)
     */
    static let kMaxFileSizeGif = 5 * 1024 * 1024
    static let kMaxFileSizeImage = 420 * 1024
    static let kMaxFileSizeVideo = 100 * 1024 * 1024
    static let kMaxFileSizeAudio = 100 * 1024 * 1024
    // TODO: What should the max file size on "other" attachments be?
    static let kMaxFileSizeGeneric = 100 * 1024 * 1024

    // MARK: Constructor

    // This method should not be called directly; use the factory
    // methods instead.
    internal required init(data: Data!, dataUTI: String!) {
        self.data = data
        self.dataUTI = dataUTI
        super.init()
    }

    public func hasError() -> Bool {
        return error != nil
    }

    // Returns the MIME type for this attachment or nil if no MIME type
    // can be identified.
    public func mimeType() -> String? {
        let mimeType = UTTypeCopyPreferredTagWithClass(dataUTI as CFString, kUTTagClassMIMEType)
        guard mimeType != nil else {
            return nil
        }
        return mimeType?.takeRetainedValue() as? String
    }

    // Returns the file extension for this attachment or nil if no file extension
    // can be identified.
    public func fileExtension() -> String? {
        let fileExtension = UTTypeCopyPreferredTagWithClass(dataUTI as CFString, kUTTagClassFilenameExtension)
        guard fileExtension != nil else {
            return nil
        }
        return fileExtension?.takeRetainedValue() as? String
    }

    // Returns the set of UTIs that correspond to valid _input_ image formats
    // for Signal attachments.
    //
    // Image attachments may be converted to another image format before 
    // being uploaded.
    //
    // TODO: We need to finalize which formats we support.
    private class func inputImageUTISet() -> Set<String>! {
        return [
            kUTTypeJPEG as String,
            kUTTypeGIF as String,
            kUTTypePNG as String
        ]
    }

    // Returns the set of UTIs that correspond to valid _output_ image formats
    // for Signal attachments.
    //
    // TODO: We need to finalize which formats we support.
    private class func outputImageUTISet() -> Set<String>! {
        return [
            kUTTypeJPEG as String,
            kUTTypeGIF as String,
            kUTTypePNG as String
        ]
    }

    // Returns the set of UTIs that correspond to valid video formats
    // for Signal attachments.
    //
    // TODO: We need to finalize which formats we support.
    private class func videoUTISet() -> Set<String>! {
        return [
            kUTTypeMPEG4 as String
        ]
    }

    // Returns the set of UTIs that correspond to valid audio formats
    // for Signal attachments.
    //
    // TODO: We need to finalize which formats we support.
    private class func audioUTISet() -> Set<String>! {
        return [
            kUTTypeMP3 as String,
            kUTTypeMPEG4Audio as String
        ]
    }

    // Returns the set of UTIs that correspond to valid input formats
    // for Signal attachments.
    public class func validInputUTISet() -> Set<String>! {
        return inputImageUTISet().union(videoUTISet().union(audioUTISet()))
    }

    public func isImage() -> Bool {
        return SignalAttachment.outputImageUTISet().contains(dataUTI)
    }

    public func isVideo() -> Bool {
        return SignalAttachment.videoUTISet().contains(dataUTI)
    }

    public func isAudio() -> Bool {
        return SignalAttachment.audioUTISet().contains(dataUTI)
    }

    // Returns an attachment from the pasteboard, or nil if no attachment
    // can be found.
    //
    // NOTE: The attachment returned by this method may not be valid.
    //       Check the attachment's error property.
    public class func attachmentFromPasteboard() -> SignalAttachment? {
        guard UIPasteboard.general.numberOfItems == 1 else {
            // Ignore pasteboard if it contains multiple items.
            //
            // TODO: Should we try to use the first?
            return nil
        }
        let pasteboardUTISet = Set(UIPasteboard.general.types)
        for dataUTI in inputImageUTISet() {
            if pasteboardUTISet.contains(dataUTI) {
                let imageData = UIPasteboard.general.data(forPasteboardType:dataUTI)
                return imageAttachment(withData : imageData, dataUTI : dataUTI)
            }
        }
        for dataUTI in videoUTISet() {
            if pasteboardUTISet.contains(dataUTI) {
                let imageData = UIPasteboard.general.data(forPasteboardType:dataUTI)
                return videoAttachment(withData : imageData, dataUTI : dataUTI)
            }
        }
        for dataUTI in audioUTISet() {
            if pasteboardUTISet.contains(dataUTI) {
                let imageData = UIPasteboard.general.data(forPasteboardType:dataUTI)
                return audioAttachment(withData : imageData, dataUTI : dataUTI)
            }
        }
        // TODO: We could handle generic attachments at this point.

        return nil
    }

    // MARK: Image Attachments

    // Factory method for an image attachment.
    //
    // NOTE: The attachment returned by this method may not be valid.
    //       Check the attachment's error property.
    public class func imageAttachment(withData imageData: Data?, dataUTI: String!) -> SignalAttachment! {
        assert(dataUTI.characters.count > 0)

        assert(imageData != nil)
        guard let imageData = imageData else {
            return nil
        }

        let attachment = SignalAttachment(data : imageData, dataUTI: dataUTI)

        guard inputImageUTISet().contains(dataUTI) else {
            attachment.error = .invalidFileFormat
            return attachment
        }

        guard imageData.count > 0 else {
            assert(imageData.count > 0)
            attachment.error = .invalidData
            return attachment
        }

        if dataUTI == kUTTypeGIF as String {
            guard imageData.count <= kMaxFileSizeGif else {
                attachment.error = .fileSizeTooLarge
                return attachment
            }
            // We don't re-encode GIFs as JPEGs, presumably in case they are
            // animated.
            //
            // TODO: Consider re-encoding non-animated GIFs as JPEG?
            Logger.verbose("\(TAG) Sending raw \(attachment.mimeType()) to retain any animation")
            return attachment
        } else {
            guard let image = UIImage(data:imageData) else {
                attachment.error = .couldNotParseImage
                return attachment
            }
            attachment.image = image

            if isInputImageValidOutputImage(image: image, imageData: imageData, dataUTI: dataUTI) {
                Logger.verbose("\(TAG) Sending raw \(attachment.mimeType())")
                return attachment
            }

            Logger.verbose("\(TAG) Compressing attachment as image/jpeg")
            return compressImageAsJPEG(image : image, attachment : attachment)
        }
    }

    // If the proposed attachment already is a JPEG, and already conforms to the 
    // file size and content size limits, don't recompress it.
    //
    // TODO: Should non-JPEGs always be converted to JPEG?
    private class func isInputImageValidOutputImage(image: UIImage?, imageData: Data?, dataUTI: String!) -> Bool {
        guard let image = image else {
            return false
        }
        guard let imageData = imageData else {
            return false
        }
        if dataUTI == kUTTypeJPEG as String {
            let imageUploadQuality = Environment.preferences().imageUploadQuality()
            let maxSize = maxSizeForImage(image: image, imageUploadQuality:imageUploadQuality)
            if image.size.width <= maxSize &&
                image.size.height <= maxSize &&
                imageData.count <= kMaxFileSizeImage {
                return true
            }
        }
        return false
    }

    // Factory method for an image attachment.
    //
    // NOTE: The attachment returned by this method may nil or not be valid.
    //       Check the attachment's error property.
    public class func imageAttachment(withImage image: UIImage?, dataUTI: String!) -> SignalAttachment! {
        assert(dataUTI.characters.count > 0)

        guard let image = image else {
            return nil
        }

        // Make a placeholder attachment on which to hang errors if necessary.
        let attachment = SignalAttachment(data : Data(), dataUTI: dataUTI)
        attachment.image = image

        Logger.verbose("\(TAG) Writing \(attachment.mimeType()) as image/jpeg")
        return compressImageAsJPEG(image : image, attachment : attachment)
    }

    private class func compressImageAsJPEG(image: UIImage!, attachment: SignalAttachment!) -> SignalAttachment! {
        assert(attachment.error == nil)

        var imageUploadQuality = Environment.preferences().imageUploadQuality()

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
    public class func videoAttachment(withData data: Data?, dataUTI: String!) -> SignalAttachment! {
        return newAttachment(withData : data,
                             dataUTI : dataUTI,
                             validUTISet : videoUTISet(),
                             maxFileSize : kMaxFileSizeVideo)
    }

    // MARK: Audio Attachments

    // Factory method for audio attachments.
    //
    // NOTE: The attachment returned by this method may not be valid.
    //       Check the attachment's error property.
    public class func audioAttachment(withData data: Data?, dataUTI: String!) -> SignalAttachment! {
        return newAttachment(withData : data,
                             dataUTI : dataUTI,
                             validUTISet : audioUTISet(),
                             maxFileSize : kMaxFileSizeAudio)
    }

    // MARK: Generic Attachments

    // Factory method for generic attachments.
    //
    // NOTE: The attachment returned by this method may not be valid.
    //       Check the attachment's error property.
    public class func genericAttachment(withData data: Data?, dataUTI: String!) -> SignalAttachment! {
        return newAttachment(withData : data,
                             dataUTI : dataUTI,
                             validUTISet : nil,
                             maxFileSize : kMaxFileSizeGeneric)
    }

    // MARK: Helper Methods

    private class func newAttachment(withData data: Data?,
                                     dataUTI: String!,
                                     validUTISet: Set<String>?,
                                     maxFileSize: Int) -> SignalAttachment! {
        assert(dataUTI.characters.count > 0)

        assert(data != nil)
        guard let data = data else {
            return nil
        }

        let attachment = SignalAttachment(data : data, dataUTI: dataUTI)

        if validUTISet != nil {
            guard validUTISet!.contains(dataUTI) else {
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
