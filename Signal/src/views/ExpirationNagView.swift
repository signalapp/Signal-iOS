//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import UIKit

class ExpirationNagView: ReminderView {
    private var appExpiry: AppExpiry { .shared }
    private static let updateLink = URL(string: "itms-apps://itunes.apple.com/app/id874139669")!

    @objc convenience init() {
        self.init(mode: .nag, text: "") {
            UIApplication.shared.open(ExpirationNagView.updateLink, options: [:])
        }
    }

    @objc func updateText() {
        if appExpiry.isExpired {
            text = NSLocalizedString("EXPIRATION_ERROR", comment: "Label notifying the user that the app has expired.")
        } else if appExpiry.daysUntilBuildExpiry == 1 {
            text = NSLocalizedString("EXPIRATION_WARNING_TODAY", comment: "Label warning the user that the app will expire today.")
        } else {
            let soonWarning = NSLocalizedString("EXPIRATION_WARNING_SOON", comment: "Label warning the user that the app will expire soon.")
            text = String(format: soonWarning, appExpiry.daysUntilBuildExpiry)
        }
    }
}
