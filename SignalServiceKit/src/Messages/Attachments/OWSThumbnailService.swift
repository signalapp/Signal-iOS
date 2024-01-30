//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import AVFoundation

public enum OWSThumbnailError: Error {
    case failure(description: String)
    case assertionFailure(description: String)
    case externalError(description: String, underlyingError: Error)
}

@objc
public class OWSLoadedThumbnail: NSObject {
    public typealias DataSourceBlock = () throws -> Data

    @objc
    public let image: UIImage
    let dataSourceBlock: DataSourceBlock

    @objc
    public init(image: UIImage, filePath: String) {
        // Always preload thumbnail images for rendering.
        self.image = image.preloadForRendering()

        self.dataSourceBlock = {
            return try Data(contentsOf: URL(fileURLWithPath: filePath))
        }
    }

    @objc
    public init(image: UIImage, data: Data) {
        self.image = image
        self.dataSourceBlock = {
            return data
        }
    }

    @objc
    public func data() throws -> Data {
        return try dataSourceBlock()
    }
}

private struct OWSThumbnailRequest {
    public typealias SuccessBlock = (OWSLoadedThumbnail) -> Void
    public typealias FailureBlock = (Error) -> Void

    let attachment: TSAttachmentStream
    let thumbnailDimensionPoints: CGFloat
    let success: SuccessBlock
    let failure: FailureBlock

    init(attachment: TSAttachmentStream, thumbnailDimensionPoints: CGFloat, success: @escaping SuccessBlock, failure: @escaping FailureBlock) {
        self.attachment = attachment
        self.thumbnailDimensionPoints = thumbnailDimensionPoints
        self.success = success
        self.failure = failure
    }
}

// MARK: - 

@objc
public class OWSThumbnailService: NSObject {

    // MARK: - Singleton class

    @objc(shared)
    public static let shared = OWSThumbnailService()

    public typealias SuccessBlock = (OWSLoadedThumbnail) -> Void
    public typealias FailureBlock = (Error) -> Void

    @objc
    public static let serialQueue = DispatchQueue(label: "org.signal.thumbnail-service")

    private var serialQueue: DispatchQueue { OWSThumbnailService.serialQueue }

    // This property should only be accessed on the serialQueue.
    //
    // We want to process requests in _reverse_ order in which they
    // arrive so that we prioritize the most recent view state.
    private var thumbnailRequestStack = [OWSThumbnailRequest]()

    private override init() {
        super.init()

        SwiftSingletons.register(self)
    }

    private func canThumbnailAttachment(attachment: TSAttachmentStream) -> Bool {
        return attachment.isImageMimeType || attachment.isAnimatedMimeType != .notAnimated || attachment.isVideoMimeType
    }

    // success and failure will be called async _off_ the main thread.
    @objc
    public func ensureThumbnail(forAttachment attachment: TSAttachmentStream,
                                thumbnailDimensionPoints: CGFloat,
                                success: @escaping SuccessBlock,
                                failure: @escaping FailureBlock) {
        serialQueue.async {
            let thumbnailRequest = OWSThumbnailRequest(attachment: attachment,
                                                       thumbnailDimensionPoints: thumbnailDimensionPoints,
                                                       success: success,
                                                       failure: failure)
            self.thumbnailRequestStack.append(thumbnailRequest)

            self.processNextRequestSync()
        }
    }

    // This should only be called on the serialQueue.
    private func processNextRequestSync() {
        guard let thumbnailRequest = thumbnailRequestStack.popLast() else {
            return
        }

        do {
            let loadedThumbnail = try process(thumbnailRequest: thumbnailRequest)
            DispatchQueue.global().async {
                thumbnailRequest.success(loadedThumbnail)
            }
        } catch {
            Logger.error("Could not create thumbnail: \(error)")

            DispatchQueue.global().async {
                thumbnailRequest.failure(error)
            }
        }
    }

    // This should only be called on the serialQueue.
    //
    // It should be safe to assume that an attachment will never end up with two thumbnails of
    // the same size since:
    //
    // * Thumbnails are only added by this method.
    // * This method checks for an existing thumbnail using the same connection.
    // * This method is performed on the serial queue.
    private func process(thumbnailRequest: OWSThumbnailRequest) throws -> OWSLoadedThumbnail {
        let attachment = thumbnailRequest.attachment
        guard canThumbnailAttachment(attachment: attachment) else {
            throw OWSThumbnailError.failure(description: "Cannot thumbnail attachment.")
        }

        // Sticker type metadata isn't reliable and default to
        // a webp MIME type. Therefore for all nominally webp
        // image attachments, determine the MIME type by examining
        // the actual attachment data.
        var contentType = attachment.contentType
        let mightBeWebp = attachment.contentType == OWSMimeTypeImageWebp
        if mightBeWebp,
           let filePath = attachment.originalFilePath {
            let imageMetadata = NSData.imageMetadata(withPath: filePath, mimeType: nil)
            if imageMetadata.imageFormat != .unknown,
               let mimeType = imageMetadata.mimeType {
                contentType = mimeType
            }
        }
        let isWebp = contentType == OWSMimeTypeImageWebp

        let thumbnailPath = attachment.path(forThumbnailDimensionPoints: thumbnailRequest.thumbnailDimensionPoints)
        if FileManager.default.fileExists(atPath: thumbnailPath) {
            guard let image = UIImage(contentsOfFile: thumbnailPath) else {
                throw OWSThumbnailError.failure(description: "Could not load thumbnail.")
            }
            return OWSLoadedThumbnail(image: image, filePath: thumbnailPath)
        }

        Logger.verbose("Creating thumbnail of size: \(thumbnailRequest.thumbnailDimensionPoints)")

        let thumbnailDirPath = (thumbnailPath as NSString).deletingLastPathComponent
        guard OWSFileSystem.ensureDirectoryExists(thumbnailDirPath) else {
            throw OWSThumbnailError.failure(description: "Could not create attachment's thumbnail directory.")
        }
        guard let originalFilePath = attachment.originalFilePath else {
            throw OWSThumbnailError.failure(description: "Missing original file path.")
        }
        let maxDimensionPoints = CGFloat(thumbnailRequest.thumbnailDimensionPoints)
        let thumbnailImage: UIImage
        if isWebp {
            thumbnailImage = try OWSMediaUtils.thumbnail(forWebpAtPath: originalFilePath,
                                                         maxDimensionPoints: maxDimensionPoints)
        } else if attachment.isImageMimeType || attachment.isAnimatedMimeType != .notAnimated {
            thumbnailImage = try OWSMediaUtils.thumbnail(forImageAtPath: originalFilePath,
                                                         maxDimensionPoints: maxDimensionPoints)
        } else if attachment.isVideoMimeType {
            thumbnailImage = try OWSMediaUtils.thumbnail(forVideoAtPath: originalFilePath,
                                                         maxDimensionPoints: maxDimensionPoints)
        } else {
            throw OWSThumbnailError.assertionFailure(description: "Invalid attachment type.")
        }
        let thumbnailData: Data
        if isWebp {
            guard let pngThumbnailData = thumbnailImage.pngData() else {
                throw OWSThumbnailError.failure(description: "Could not convert thumbnail to PNG.")
            }
            thumbnailData = pngThumbnailData
        } else {
            guard let jpegThumbnailData = thumbnailImage.jpegData(compressionQuality: 0.85) else {
                throw OWSThumbnailError.failure(description: "Could not convert thumbnail to JPEG.")
            }
            thumbnailData = jpegThumbnailData
        }
        do {
            try thumbnailData.write(to: URL(fileURLWithPath: thumbnailPath), options: .atomic)
        } catch let error as NSError {
            throw OWSThumbnailError.externalError(description: "File write failed: \(thumbnailPath), \(error)", underlyingError: error)
        }
        OWSFileSystem.protectFileOrFolder(atPath: thumbnailPath)
        return OWSLoadedThumbnail(image: thumbnailImage, data: thumbnailData)
    }

    @objc
    public class func thumbnailFileExtension(forContentType contentType: String) -> String {
        let isWebp = contentType == OWSMimeTypeImageWebp
        return isWebp ? "png" : "jpg"
    }

    @objc
    public class func thumbnailMimetype(forContentType contentType: String) -> String {
        let isWebp = contentType == OWSMimeTypeImageWebp
        return isWebp ? OWSMimeTypeImagePng : OWSMimeTypeImageJpeg
    }
}
