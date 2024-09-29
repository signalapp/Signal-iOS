//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit

public enum ShareableTSResource {
    case legacy(ShareableTSAttachment)
    case v2(ShareableAttachment)
}

extension AttachmentSharing {

    public static func showShareUI(
        for attachment: ShareableTSResource,
        sender: Any? = nil,
        completion: (() -> Void)? = nil
    ) {
        showShareUI(for: [attachment], sender: sender, completion: completion)
    }

    public static func showShareUI(
        for attachments: [ShareableTSResource],
        sender: Any? = nil,
        completion: (() -> Void)? = nil
    ) {
        var legacyStreams = [ShareableTSAttachment]()
        var streams = [ShareableAttachment]()
        attachments.forEach { attachment in
            switch attachment {
            case .legacy(let tsAttachmentStream):
                legacyStreams.append(tsAttachmentStream)
            case .v2(let attachmentStream):
                streams.append(attachmentStream)
            }
        }
        owsAssertDebug(
            legacyStreams.isEmpty || streams.isEmpty,
            "Mixing and matching attachment types!"
        )

        if streams.isEmpty.negated {
            showShareUI(for: streams, sender: sender, completion: completion)
        } else {
            _showShareUI(for: legacyStreams, sender: sender, completion: completion)
        }
    }

    private static func _showShareUI(
        for attachmentStream: ShareableTSAttachment,
        sender: Any?,
        completion: (() -> Void)?
    ) {
        showShareUIForActivityItems([attachmentStream], sender: sender, completion: completion)
    }

    private static func _showShareUI(
        for attachmentStreams: [ShareableTSAttachment],
        sender: Any?,
        completion: (() -> Void)?
    ) {
        showShareUIForActivityItems(attachmentStreams, sender: sender, completion: completion)
    }
}

extension ReferencedTSResourceStream {

    public func asShareableResource() throws -> ShareableTSResource? {
        return try self.attachmentStream.asShareableResource(sourceFilename: reference.sourceFilename)
    }
}

extension TSResourceStream {

    public func asShareableResource(sourceFilename: String?) throws -> ShareableTSResource? {
        switch concreteStreamType {
        case .legacy(let tsAttachment):
            return ShareableTSAttachment(tsAttachment).map { .legacy($0) }
        case .v2(let attachment):
            return try attachment.asShareableAttachment(sourceFilename: sourceFilename).map { .v2($0) }
        }
    }
}

public class ShareableTSAttachment: NSObject, UIActivityItemSource {

    /// Returns nil if the attachment cannot be shared with the system sharesheet.
    public init?(_ attachmentStream: TSAttachmentStream) {
        self.attachmentStream = attachmentStream
        switch attachmentStream.computeContentType() {
        case .audio, .file:
            break
        case .image, .animatedImage:
            break
        case .video:
            if
                let filePath = attachmentStream.originalFilePath,
                UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(filePath)
            {
                break
            } else {
                return nil
            }
        case .invalid:
            // Let the user try to share as long as its a visual mime type.
            guard MimeTypeUtil.isSupportedVisualMediaMimeType(attachmentStream.mimeType) else {
                return nil
            }
        }
    }

    private let attachmentStream: TSAttachmentStream

    // called to determine data type. only the class of the return type is consulted. it should match what
    // -itemForActivityType: returns later
    public func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        // HACK: If this is an image we want to provide the image object to
        // the share sheet rather than the file path. This ensures that when
        // the user saves multiple images to their camera roll the OS doesn't
        // asynchronously read the files and save them to them in a random
        // order. Note: when sharing a mixture of image and non-image data
        // (e.g. an album with photos and videos) the OS will still incorrectly
        // order the video items. I haven't found any way to work around this
        // since videos may only be shared as URLs.
        if attachmentStream.isImageMimeType {
            return UIImage()
        }
        return attachmentStream.originalMediaURL as Any
    }

    // called to fetch data after an activity is selected. you can return nil.
    public func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        if attachmentStream.contentType == MimeType.imageWebp.rawValue {
            return attachmentStream.originalImage
        }
        if attachmentStream.getAnimatedMimeType() == .animated {
            return attachmentStream.originalMediaURL
        }
        if attachmentStream.isImageMimeType {
            return attachmentStream.originalImage
        }
        return attachmentStream.originalMediaURL
    }
}
