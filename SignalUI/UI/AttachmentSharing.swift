//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import YYImage

public class AttachmentSharing {

    private init() {}

    // MARK: -

    public static func showShareUI(
        for attachmentStream: TSAttachmentStream,
        sender: Any? = nil,
        completion: (() -> Void)? = nil
    ) {
        showShareUIForActivityItems([attachmentStream], sender: sender, completion: completion)
    }

    public static func showShareUI(
        for attachmentStreams: [TSAttachmentStream],
        sender: Any? = nil,
        completion: (() -> Void)? = nil
    ) {
        showShareUIForActivityItems(attachmentStreams, sender: sender, completion: completion)
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

    private static func showShareUIForActivityItems(
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

extension TSAttachmentStream: UIActivityItemSource {

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
        if isImageMimeType {
            return UIImage()
        }
        return originalMediaURL as Any
    }

    // called to fetch data after an activity is selected. you can return nil.
    public func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        if contentType == OWSMimeTypeImageWebp {
            return originalImage
        }
        if isAnimatedMimeType == .animated {
            return originalMediaURL
        }
        if isImageMimeType {
            return originalImage
        }
        return originalMediaURL
    }
}

// YYImage does not specify that the sublcass still supports secure coding,
// this is required for anything that subclasses a class that supports secure
// coding. We do so here, otherwise copy / save will not work for YYImages
extension YYImage {
    open class override var supportsSecureCoding: Bool { true }
}
