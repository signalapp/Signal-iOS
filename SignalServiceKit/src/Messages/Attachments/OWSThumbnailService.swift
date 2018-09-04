//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

private struct OWSThumbnailRequest {
    public typealias CompletionBlock = (UIImage) -> Void

    let attachmentId: String
    let thumbnailDimensionPoints: UInt
    let completion: CompletionBlock

    init(attachmentId: String, thumbnailDimensionPoints: UInt, completion: @escaping CompletionBlock) {
        self.attachmentId = attachmentId
        self.thumbnailDimensionPoints = thumbnailDimensionPoints
        self.completion = completion
    }
}

@objc public class OWSThumbnailService: NSObject {

    // MARK: - Singleton class

    @objc(shared)
    public static let shared = OWSThumbnailService()

    public typealias CompletionBlock = (UIImage) -> Void

    private let serialQueue = DispatchQueue(label: "OWSThumbnailService")

    private let dbConnection: YapDatabaseConnection

    // This property should only be accessed on the serialQueue.
    //
    // We want to process requests in _reverse_ order in which they
    // arrive so that we prioritize the most recent view state.
    // This data structure is actually used like a stack.
    private var thumbnailRequestQueue = [OWSThumbnailRequest]()

    private override init() {

        dbConnection = OWSPrimaryStorage.shared().newDatabaseConnection()

        super.init()

        SwiftSingletons.register(self)
    }

    private func canThumbnailAttachment(attachment: TSAttachmentStream) -> Bool {
        guard attachment.isImage() else {
            return false
        }
        guard !attachment.isAnimated() else {
            return false
        }
        guard attachment.isValidImage() else {
            return false
        }
        return true
    }

    // completion will only be called on success.
    // completion will be called async on the main thread.
    @objc public func ensureThumbnailForAttachmentId(attachmentId: String,
                                                     thumbnailDimensionPoints: UInt,
                                                     completion:@escaping CompletionBlock) {
        guard attachmentId.count > 0 else {
            owsFail("Empty attachment id.")
            return
        }
        serialQueue.async {
            let thumbnailRequest = OWSThumbnailRequest(attachmentId: attachmentId, thumbnailDimensionPoints: thumbnailDimensionPoints, completion: completion)
            self.thumbnailRequestQueue.append(thumbnailRequest)

            self.processNextRequestSync()
        }
    }

    private func processNextRequestAsync() {
        serialQueue.async {
            self.processNextRequestSync()
        }
    }

    // This should only be called on the serialQueue.
    private func processNextRequestSync() {
        guard !thumbnailRequestQueue.isEmpty else {
            return
        }
        let thumbnailRequest = thumbnailRequestQueue.removeLast()

        if let image = process(thumbnailRequest: thumbnailRequest) {
            DispatchQueue.main.async {
                thumbnailRequest.completion(image)
            }
        }
    }

    // This should only be called on the serialQueue.
    private func process(thumbnailRequest: OWSThumbnailRequest) -> UIImage? {
        var possibleAttachment: TSAttachmentStream?
        self.dbConnection.read({ (transaction) in
            possibleAttachment = TSAttachmentStream.fetch(uniqueId: thumbnailRequest.attachmentId, transaction: transaction)
        })
        guard let attachment = possibleAttachment else {
            Logger.warn("Could not load attachment for thumbnailing.")
            return nil
        }
        guard canThumbnailAttachment(attachment: attachment) else {
            Logger.warn("Cannot thumbnail attachment.")
            return nil
        }
        if let thumbnails = attachment.thumbnails {
            for thumbnail in thumbnails {
                if thumbnail.thumbnailDimensionPoints == thumbnailRequest.thumbnailDimensionPoints {
                    guard let filePath = attachment.path(for: thumbnail) else {
                        owsFail("Could not determine thumbnail path.")
                        return nil
                    }
                    guard let image = UIImage(contentsOfFile: filePath) else {
                        owsFail("Could not load thumbnail.")
                        return nil
                    }
                    return image
                }
            }
        }
        guard let originalFilePath = attachment.originalFilePath() else {
            owsFail("Could not determine thumbnail path.")
            return nil
        }
        guard let originalImage = UIImage(contentsOfFile: originalFilePath) else {
            owsFail("Could not load original image.")
            return nil
        }
        let originalSize = originalImage.size
        guard originalSize.width > 0 && originalSize.height > 0 else {
            owsFail("Original image has invalid size.")
            return nil
        }
        var thumbnailSize = CGSize.zero
        if originalSize.width > originalSize.height {
            thumbnailSize.width = CGFloat(thumbnailRequest.thumbnailDimensionPoints)
            thumbnailSize.height = round(CGFloat(thumbnailRequest.thumbnailDimensionPoints) * thumbnailSize.height / thumbnailSize.width)
        } else {
            thumbnailSize.width = round(CGFloat(thumbnailRequest.thumbnailDimensionPoints) * thumbnailSize.width / thumbnailSize.height)
            thumbnailSize.height = CGFloat(thumbnailRequest.thumbnailDimensionPoints)
        }
        guard thumbnailSize.width > 0 && thumbnailSize.height > 0 else {
            owsFail("Thumbnail has invalid size.")
            return nil
        }
        guard originalSize.width < thumbnailSize.width &&
                originalSize.height < thumbnailSize.height else {
                owsFail("Thumbnail isn't smaller than the original.")
                return nil
        }
        // We use UIGraphicsBeginImageContextWithOptions() to scale.
        // Core Image would provide better quality (e.g. Lanczos) but
        // at perf cost we don't want to pay.  We could also use
        // CoreGraphics directly, but I'm not sure there's any benefit.
        guard let thumbnailImage = originalImage.resizedImage(to: thumbnailSize) else {
            owsFail("Could not thumbnail image.")
            return nil
        }
        guard let thumbnailData = UIImageJPEGRepresentation(thumbnailImage, 0.85) else {
            owsFail("Could not convert thumbnail to JPEG.")
            return nil
        }
        let temporaryDirectory = NSTemporaryDirectory()
        let thumbnailFilename = "\(NSUUID().uuidString).jpg"
        let thumbnailFilePath = (temporaryDirectory as NSString).appendingPathComponent(thumbnailFilename)
        do {
            try thumbnailData.write(to: NSURL.fileURL(withPath: thumbnailFilePath), options: .atomicWrite)
        } catch let error as NSError {
            owsFail("File write failed: \(thumbnailFilePath), \(error)")
            return nil
        }
        // It should be safe to assume that an attachment will never end up with two thumbnails of
        // the same size since:
        //
        // * Thumbnails are only added by this method.
        // * This method checks for an existing thumbnail using the same connection.
        // * This method is performed on the serial queue.
        self.dbConnection.readWrite({ (transaction) in
            attachment.update(withNewThumbnail: thumbnailFilePath,
                              thumbnailDimensionPoints: thumbnailRequest.thumbnailDimensionPoints,
                              size: thumbnailSize,
                              transaction: transaction)
        })
        return thumbnailImage
    }
}
