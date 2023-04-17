//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit
import SignalMessaging

public class ExpirationNagView: ReminderView {
    convenience init() {
        self.init(mode: .nag, text: "") {
            UIApplication.shared.open(TSConstants.appStoreUrl, options: [:])
        }
    }

    func update() {
        let now = Date()
        lazy var daysUntilAppExpiry = DateUtil.daysFrom(
            firstDate: now,
            toSecondDate: appExpiry.expirationDate
        )

        isHidden = false
        if appExpiry.expirationDate.isBefore(now) {
            text = NSLocalizedString("EXPIRATION_ERROR", comment: "Label notifying the user that the app has expired.")
        } else if daysUntilAppExpiry == 1 {
            text = NSLocalizedString("EXPIRATION_WARNING_TODAY", comment: "Label warning the user that the app will expire today.")
        } else if daysUntilAppExpiry <= 10 {
            let format = NSLocalizedString("EXPIRATION_WARNING_%d", tableName: "PluralAware", comment: "Label warning the user that the app will expire soon.")
            text = String.localizedStringWithFormat(format, daysUntilAppExpiry)
        } else {
            isHidden = true
        }
    }
}
