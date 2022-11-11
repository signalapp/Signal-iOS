//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalUI

extension DonateViewController {
    func presentStillProcessingSheet() {
        guard
            let topViewController = navigationController?.topViewController,
            topViewController == self
        else {
            Logger.info("Not showing the \"still processing\" sheet because we're no longer the top view controller")
            return
        }

        let title = NSLocalizedString("SUSTAINER_STILL_PROCESSING_BADGE_TITLE", comment: "Action sheet title for Still Processing Badge sheet")
        let message = NSLocalizedString("SUSTAINER_VIEW_STILL_PROCESSING_BADGE_MESSAGE", comment: "Action sheet message for Still Processing Badge sheet")
        let actionSheet = ActionSheetController(title: title, message: message)
        actionSheet.addAction(OWSActionSheets.okayAction)
        topViewController.presentActionSheet(actionSheet)
    }

    func presentBadgeCantBeAddedSheet() {
        presentBadgeCantBeAddedSheet(currentSubscription: nil)
    }

    func presentBadgeCantBeAddedSheet(currentSubscription: Subscription?) {
        DonationViewsUtil.presentBadgeCantBeAddedSheet(
            viewController: self,
            currentSubscription: currentSubscription
        )
    }
}
