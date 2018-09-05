//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc public class OWSLoadedThumbnail: NSObject {
    public typealias DataSourceBlock = () throws -> Data

    @objc public let image: UIImage
    let dataSourceBlock: DataSourceBlock

    @objc public init(image: UIImage, filePath: String) {
        self.image = image
        self.dataSourceBlock = {
            return try Data(contentsOf: URL(fileURLWithPath: filePath))
        }
    }

    @objc public init(image: UIImage, data: Data) {
        self.image = image
        self.dataSourceBlock = {
            return data
        }
    }

    @objc public func data() throws -> Data {
        return try dataSourceBlock()
    }
}

private struct OWSThumbnailRequest {
    public typealias SuccessBlock = (OWSLoadedThumbnail) -> Void
    public typealias FailureBlock = () -> Void

    let attachmentId: String
    let thumbnailDimensionPoints: UInt
    let success: SuccessBlock
    let failure: FailureBlock

    init(attachmentId: String, thumbnailDimensionPoints: UInt, success: @escaping SuccessBlock, failure: @escaping FailureBlock) {
        self.attachmentId = attachmentId
        self.thumbnailDimensionPoints = thumbnailDimensionPoints
        self.success = success
        self.failure = failure
    }
}

@objc public class OWSThumbnailService: NSObject {

    // MARK: - Singleton class

    @objc(shared)
    public static let shared = OWSThumbnailService()

    public typealias SuccessBlock = (OWSLoadedThumbnail) -> Void
    public typealias FailureBlock = () -> Void

    private let serialQueue = DispatchQueue(label: "OWSThumbnailService")

    private let dbConnection: YapDatabaseConnection

    // This property should only be accessed on the serialQueue.
    //
    // We want to process requests in _reverse_ order in which they
    // arrive so that we prioritize the most recent view state.
    private var thumbnailRequestStack = [OWSThumbnailRequest]()

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
                                                     success: @escaping SuccessBlock,
                                                     failure: @escaping FailureBlock) {
        guard attachmentId.count > 0 else {
            owsFail("Empty attachment id.")
            DispatchQueue.main.async {
                failure()
            }
            return
        }
        serialQueue.async {
            let thumbnailRequest = OWSThumbnailRequest(attachmentId: attachmentId, thumbnailDimensionPoints: thumbnailDimensionPoints, success: success, failure: failure)
            self.thumbnailRequestStack.append(thumbnailRequest)

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
        guard !thumbnailRequestStack.isEmpty else {
            return
        }
        let thumbnailRequest = thumbnailRequestStack.removeLast()

        if let loadedThumbnail = process(thumbnailRequest: thumbnailRequest) {
            DispatchQueue.main.async {
                thumbnailRequest.success(loadedThumbnail)
            }
        } else {
            DispatchQueue.main.async {
                thumbnailRequest.failure()
            }
        }
    }

    // This should only be called on the serialQueue.
    private func process(thumbnailRequest: OWSThumbnailRequest) -> OWSLoadedThumbnail? {
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
                    return OWSLoadedThumbnail(image: image, filePath: filePath)
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
            thumbnailSize.height = round(CGFloat(thumbnailRequest.thumbnailDimensionPoints) * originalSize.height / originalSize.width)
        } else {
            thumbnailSize.width = round(CGFloat(thumbnailRequest.thumbnailDimensionPoints) * originalSize.width / originalSize.height)
            thumbnailSize.height = CGFloat(thumbnailRequest.thumbnailDimensionPoints)
        }
        guard thumbnailSize.width > 0 && thumbnailSize.height > 0 else {
            owsFail("Thumbnail has invalid size.")
            return nil
        }
        guard originalSize.width > thumbnailSize.width &&
                originalSize.height > thumbnailSize.height else {
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
        return OWSLoadedThumbnail(image: thumbnailImage, data: thumbnailData)
    }
}
