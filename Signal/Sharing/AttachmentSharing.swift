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

extension AttachmentStream {

    public func asShareableAttachment(sourceFilename: String?) throws -> ShareableAttachment? {
        return try ShareableAttachment(self, sourceFilename: sourceFilename)
    }
}

public class ShareableAttachment: NSObject, UIActivityItemSource {

    /// Throws an error if decryption fails.
    /// Returns nil if the attachment cannot be shared with the system sharesheet.
    public init?(_ attachmentStream: AttachmentStream, sourceFilename: String?) throws {
        self.attachmentStream = attachmentStream
        if attachmentStream.mimeType == MimeType.imageWebp.rawValue {
            self.shareType = .image
            return
        }
        if
            !MimeTypeUtil.isSupportedDefinitelyAnimatedMimeType(attachmentStream.mimeType),
            MimeTypeUtil.isSupportedImageMimeType(attachmentStream.mimeType)
        {
            self.shareType = .image
            return
        }

        switch attachmentStream.contentType {
        case .audio, .file:
            self.shareType = .decryptedFileURL(try attachmentStream.makeDecryptedCopy(filename: sourceFilename))
            return
        case .image, .animatedImage:
            shareType = .decryptedFileURL(try attachmentStream.makeDecryptedCopy(filename: sourceFilename))
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
            shareType = .decryptedFileURL(try attachmentStream.makeDecryptedCopy(filename: sourceFilename))
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
    private enum ShareType {
        case decryptedFileURL(URL)
        /// We load the image into memory when it is requested, so that we theoretically
        /// can load them one at a time and not all up front when sharing more than one.
        case image
    }

    private let attachmentStream: AttachmentStream
    private let shareType: ShareType

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
