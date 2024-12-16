//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit
public import YYImage

public class AttachmentSharing {

    private init() {}

    // MARK: -

    public static func showShareUI(
        for attachment: ShareableAttachment,
        sender: Any? = nil,
        completion: (() -> Void)? = nil
    ) {
        showShareUIForActivityItems(
            [attachment],
            sender: sender,
            completion: completion
        )
    }

    public static func showShareUI(
        for attachments: [ShareableAttachment],
        sender: Any? = nil,
        completion: (() -> Void)? = nil
    ) {
        showShareUIForActivityItems(
            attachments,
            sender: sender,
            completion: completion
        )
    }

    // MARK: -

    public static func showShareUI(
        for url: URL,
        sender: Any? = nil,
        completion: (() -> Void)? = nil
    ) {
        showShareUIForActivityItems([url], sender: sender, completion: completion)
    }

    public static func showShareUI(
        for urls: [URL],
        sender: Any? = nil,
        completion: (() -> Void)? = nil
    ) {
        showShareUIForActivityItems(urls, sender: sender, completion: completion)
    }

    // MARK: -

    public static func showShareUI(
        for text: String,
        sender: Any? = nil,
        completion: (() -> Void)? = nil
    ) {
        showShareUIForActivityItems([text], sender: sender, completion: completion)
    }

    // MARK: -

    #if USE_DEBUG_UI

    public static func showShareUI(
        for image: UIImage,
        sender: Any? = nil,
        completion: (() -> Void)? = nil
    ) {
        showShareUIForActivityItems([image], sender: sender, completion: completion)
    }

    #endif

    // MARK: -

    internal static func showShareUIForActivityItems(
        _ activityItems: [Any],
        sender: Any?,
        completion: (() -> Void)? = nil
    ) {
        DispatchMainThreadSafe {
            let activityViewController = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
            activityViewController.completionWithItemsHandler = { activityType, completed, returnedItems, activityError in
                if let activityError {
                    Logger.info("Failed to share with activityError: \(activityError)")
                } else if completed {
                    Logger.info("Did share with activityType: \(String(describing: activityType))")
                }

                if let completion {
                    DispatchMainThreadSafe(completion)
                }
            }

            var fromViewController = CurrentAppContext().frontmostViewController()
            while fromViewController?.presentedViewController != nil {
                fromViewController = fromViewController?.presentedViewController
            }

            if let popoverPresentationController = activityViewController.popoverPresentationController {
                if let barButtonItem = sender as? UIBarButtonItem {
                    popoverPresentationController.barButtonItem = barButtonItem
                } else if let uiView = sender as? UIView {
                    popoverPresentationController.sourceView = uiView
                    popoverPresentationController.sourceRect = uiView.bounds
                } else if let fromViewController {
                    if let sender {
                        owsFailDebug("Unexpected sender of type: \(sender.self)")
                    }

                    // Centered at the bottom of the screen.
                    let sourceRect = CGRect(
                        x: fromViewController.view.center.x,
                        y: fromViewController.view.frame.maxY,
                        width: 0,
                        height: 0
                    )

                    popoverPresentationController.sourceView = fromViewController.view
                    popoverPresentationController.sourceRect = sourceRect
                    popoverPresentationController.permittedArrowDirections = []
                }
            }

            fromViewController!.present(activityViewController, animated: true)
        }
    }
}

extension Array where Element == ReferencedAttachmentStream {

    public func asShareableAttachments() throws -> [ShareableAttachment] {
        var hadUrlType = false
        var types = [ShareableAttachment.ShareType]()
        var dedupedSourceFilenames = [String?]()
        var sourceFilenamesSet = Set<String>()
        for attachment in self {
            let shareType = ShareableAttachment.shareType(attachment.attachmentStream)
            switch shareType {
            case .decryptedFileURL:
                hadUrlType = true
                types.append(.decryptedFileURL)
            case .image:
                types.append(.image)
            }

            if
                let sourceFilename = attachment.reference.sourceFilename,
                sourceFilenamesSet.contains(sourceFilename)
            {
                // Avoid source filename collisions.
                let pathExtension = (sourceFilename as NSString).pathExtension
                let normalizedFilename = (sourceFilename as NSString)
                    .deletingPathExtension
                    .trimmingCharacters(in: .whitespaces)

                var i = 0
                sourceFilenameLoop: while true {
                    i += 1
                    var newSourceFilename = normalizedFilename + "_\(i)"
                    newSourceFilename = (newSourceFilename as NSString).appendingPathExtension(pathExtension) ?? newSourceFilename
                    if !sourceFilenamesSet.contains(newSourceFilename) {
                        dedupedSourceFilenames.append(newSourceFilename)
                        sourceFilenamesSet.insert(newSourceFilename)
                        break sourceFilenameLoop
                    }
                }
            } else {
                dedupedSourceFilenames.append(attachment.reference.sourceFilename)
                _ = attachment.reference.sourceFilename.map { sourceFilenamesSet.insert($0) }
            }
        }
        if hadUrlType {
            // Once one of them are all file, they all have to be files.
            types = [ShareableAttachment.ShareType](repeating: .decryptedFileURL, count: self.count)
        }

        return try zip(zip(self, types), dedupedSourceFilenames).compactMap {
            let ((attachment, shareType), sourceFilename) = $0
            return try ShareableAttachment(
                attachment.attachmentStream,
                sourceFilename: sourceFilename,
                shareType: shareType
            )
        }
    }
}

public class ShareableAttachment: NSObject, UIActivityItemSource {

    fileprivate static func shareType(_ attachmentStream: AttachmentStream) -> ShareType {
        if attachmentStream.mimeType == MimeType.imageWebp.rawValue {
            return .image
        }
        if
            !MimeTypeUtil.isSupportedDefinitelyAnimatedMimeType(attachmentStream.mimeType),
            MimeTypeUtil.isSupportedImageMimeType(attachmentStream.mimeType)
        {
            return .image
        }

        return .decryptedFileURL
    }

    /// Throws an error if decryption fails.
    /// Returns nil if the attachment cannot be shared with the system sharesheet.
    fileprivate init?(
        _ attachmentStream: AttachmentStream,
        sourceFilename: String?,
        shareType: ShareType
    ) throws {
        self.attachmentStream = attachmentStream
        switch shareType {
        case .decryptedFileURL:
            break
        case .image:
            self.shareType = .image
            return
        }

        switch attachmentStream.contentType {
        case .audio, .file:
            self.shareType = .decryptedFileURL(try attachmentStream.makeDecryptedCopy(filename: sourceFilename))
            return
        case .image, .animatedImage:
            self.shareType = .decryptedFileURL(try attachmentStream.makeDecryptedCopy(filename: sourceFilename))
        case .video:
            let decryptedFileUrl = try attachmentStream.makeDecryptedCopy(filename: sourceFilename)
            // Some videos don't support sharing.
            guard UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(decryptedFileUrl.path) else {
                return nil
            }
            self.shareType = .decryptedFileURL(decryptedFileUrl)
        case .invalid:
            // Let the user try to share as long as its a visual mime type.
            guard MimeTypeUtil.isSupportedVisualMediaMimeType(attachmentStream.mimeType) else {
                return nil
            }
            self.shareType = .decryptedFileURL(try attachmentStream.makeDecryptedCopy(filename: sourceFilename))
        }
    }

    // HACK: If this is an image we want to provide the image object to
    // the share sheet rather than the file path. This ensures that when
    // the user saves multiple images to their camera roll the OS doesn't
    // asynchronously read the files and save them to them in a random
    // order. Note: when sharing a mixture of image and non-image data
    // (e.g. an album with photos and videos) the OS will still incorrectly
    // order the video items. I haven't found any way to work around this
    // since videos may only be shared as URLs.
    fileprivate enum ShareType {
        case decryptedFileURL
        case image
    }

    private enum PreparedShareType {
        case decryptedFileURL(URL)
        /// We load the image into memory when it is requested, so that we theoretically
        /// can load them one at a time and not all up front when sharing more than one.
        case image
    }

    private let attachmentStream: AttachmentStream
    private let shareType: PreparedShareType

    deinit {
        switch shareType {
        case .decryptedFileURL(let fileUrl):
            // Best effort deletion; its a tmp file anyway.
            try? OWSFileSystem.deleteFile(url: fileUrl)
        case .image:
            break
        }
    }

    // called to determine data type. only the class of the return type is consulted. it should match what
    // -itemForActivityType: returns later
    public func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        switch shareType {
        case .decryptedFileURL(let url):
            return url as Any
        case .image:
            return UIImage() as Any
        }
    }

    // called to fetch data after an activity is selected. you can return nil.
    public func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        switch shareType {
        case .decryptedFileURL(let url):
            return url
        case .image:
            return try? attachmentStream.decryptedImage()
        }
    }
}

// YYImage does not specify that the sublcass still supports secure coding,
// this is required for anything that subclasses a class that supports secure
// coding. We do so here, otherwise copy / save will not work for YYImages
extension YYImage {
    open class override var supportsSecureCoding: Bool { true }
}
