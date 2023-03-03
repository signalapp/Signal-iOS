//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// Use this class to test for various properties of attachments related to their status as video (e.g., GIFs, stickers,
// etc.). It can check an attachment or generate SQL to use in a WHERE clause to the same effect. If you modify this
// in the future ensure the SQL and non-SQL code paths have the same logic.
@objc(OWSVideoAttachmentDetection)
public class VideoAttachmentDetection: NSObject {
    @objc(sharedInstance)
    public static var shared: VideoAttachmentDetection = VideoAttachmentDetection()

    private static var videoMimeTypes: Set<String> = {
        return Set(MIMETypeUtil.supportedVideoMIMETypesToExtensionTypes().keys.compactMap { $0 as? String })
    }()

    private static var imageMimeTypes: Set<String> = {
        return Set(MIMETypeUtil.supportedImageMIMETypesToExtensionTypes().keys.compactMap { $0 as? String })
    }()

    private func isVideo(_ attachment: TSAttachment) -> Bool {
        let mimeTypes = Self.videoMimeTypes
        return mimeTypes.contains(attachment.contentType)
    }

    private var isVideoSQL: String {
        let mimeTypes = Self.videoMimeTypes.map { "\"\($0)\"" }
        return "\(attachmentColumn: .contentType) in (\(mimeTypes.joined(separator: ",")))"
    }

    @objc
    public func attachmentIsLoopingVideo(_ attachment: TSAttachment) -> Bool {
        return attachment.attachmentType == .GIF && isVideo(attachment)
    }

    private var attachmentIsLoopingVideoSQL: String {
        return "\(attachmentColumn: .attachmentType) = \(TSAttachmentType.GIF.rawValue) AND \(isVideoSQL)"
    }

    public var attachmentIsNonLoopingVideoSQL: String {
        return "\(attachmentColumn: .attachmentType) != \(TSAttachmentType.GIF.rawValue) AND \(isVideoSQL) "
    }

    @objc
    public func attachmentIsVideo(_ attachment: TSAttachment) -> Bool {
        return isVideo(attachment)
    }

    @objc
    public func attachmentIsGIF(_ attachment: TSAttachment) -> Bool {
        return attachment.contentType == OWSMimeTypeImageGif
    }

    @objc
    public func attachmentStreamIsAnimated(_ attachmentStream: TSAttachmentStream) -> Bool {
        return attachmentStreamIsGIFOrLoopingVideo(attachmentStream) || attachmentStream.hasNonGIFAnimatedImageContent
    }

    public var attachmentIsNonGIFImageSQL: String {
        let mimeTypes = Self.imageMimeTypes.map { "\"\($0)\"" }
        return "\(attachmentColumn: .contentType) in (\(mimeTypes.joined(separator: ",")))"
    }

    private func attachmentStreamIsGIFOrLoopingVideo(_ attachmentStream: TSAttachmentStream) -> Bool {
        return attachmentIsGIF(attachmentStream) || attachmentIsLoopingVideo(attachmentStream)
    }

    private var attachmentIsGIFSQL: String {
        return "\(attachmentColumn: .contentType) = \"\(OWSMimeTypeImageGif)\""
    }

    public var attachmentStreamIsGIFOrLoopingVideoSQL: String {
        return attachmentIsGIFSQL + " OR (" + attachmentIsLoopingVideoSQL + ")"
    }
}

fileprivate extension TSAttachmentStream {
    var hasNonGIFAnimatedImageContent: Bool {
        if contentType != OWSMimeTypeImageWebp && contentType != OWSMimeTypeImagePng {
            return false
        }
        guard let filePath = originalFilePath else {
            owsFailDebug("Missing filePath.")
            return false
        }

        let imageMetadata = NSData.imageMetadata(withPath: filePath, mimeType: contentType)
        guard imageMetadata.isValid else {
            return false
        }
        return imageMetadata.isAnimated
    }
}
