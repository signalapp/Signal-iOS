//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

enum ShareActivityUtil {
    public static func present(
        activityItems: [Any],
        from viewController: UIViewController,
        sourceView: UIView
    ) {
        // HACK: `UIActivityViewController` will sometimes dismiss its parent due to an iOS bug
        // (see links below). To get around this, we present an invisible view controller and
        // have that present the `UIActivityViewController`. Then, when the latter completes,
        // we dismiss the invisible one.
        //
        // - <https://stackoverflow.com/q/56903030>
        // - <https://stackoverflow.com/q/59413850>
        // - <https://developer.apple.com/forums/thread/119482>
        // - <https://github.com/iMacHumphries/TestShareSheet>
        let wrapperViewControllerToFixIosBug = UIViewController()
        wrapperViewControllerToFixIosBug.modalPresentationStyle = .overCurrentContext
        wrapperViewControllerToFixIosBug.view.backgroundColor = .clear

        let shareActivityViewController = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: []
        )
        if let popoverPresentationController = shareActivityViewController.popoverPresentationController {
            popoverPresentationController.sourceView = sourceView
        }
        shareActivityViewController.excludedActivityTypes = [
            .addToReadingList,
            .assignToContact,
            .openInIBooks,
            .postToFacebook,
            .postToFlickr,
            .postToTencentWeibo,
            .postToTwitter,
            .postToVimeo,
            .postToWeibo
        ]
        shareActivityViewController.completionWithItemsHandler = { _, _, _, _ in
            wrapperViewControllerToFixIosBug.dismiss(animated: false)
        }

        viewController.present(wrapperViewControllerToFixIosBug, animated: false) {
            wrapperViewControllerToFixIosBug.present(shareActivityViewController, animated: true)
        }
    }
}
