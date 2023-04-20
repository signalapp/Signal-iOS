//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit
import SignalMessaging
import SignalServiceKit

public class ExpirationNagView: ReminderView {
    private let appExpiry: AppExpiry

    required init(appExpiry: AppExpiry) {
        self.appExpiry = appExpiry

        super.init(
            style: .warning,
            text: "",
            tapAction: { UIApplication.shared.open(TSConstants.appStoreUrl, options: [:]) }
        )
    }

    func update() {
        let now = Date()
        lazy var daysUntilAppExpiry = DateUtil.daysFrom(
            firstDate: now,
            toSecondDate: appExpiry.expirationDate
        )

        isHidden = false
        if appExpiry.expirationDate.isBefore(now) {
            text = .appExpired
            actionTitle = .expiredActionTitle
        } else if daysUntilAppExpiry <= 1 {
            text = .appExpiresToday
            actionTitle = .expiredActionTitle
        } else if daysUntilAppExpiry <= 10 {
            text = .appExpires(on: appExpiry.expirationDate)
            actionTitle = .expiredActionTitle
        } else {
            isHidden = true
        }
    }
}

// MARK: - Strings

fileprivate extension String {
    static var appExpired: String {
        return OWSLocalizedString(
            "EXPIRATION_ERROR",
            comment: "Label notifying the user that the app has expired."
        )
    }

    static var appExpiresToday: String {
        return OWSLocalizedString(
            "EXPIRATION_WARNING_TODAY",
            comment: "Label warning the user that the app will expire today."
        )
    }

    static func appExpires(on date: Date) -> String {
        let dateString = DateFormatter.localizedString(
            from: date,
            dateStyle: .short,
            timeStyle: .none
        )
        let format = OWSLocalizedString(
            "EXPIRATION_WARNING_SOON",
            comment: "Label warning the user that the app will expire soon. Embeds {{date}}."
        )
        return String(format: format, dateString)
    }

    static var expiredActionTitle: String {
        return OWSLocalizedString(
            "EXPIRATION_WARNING_ACTION_TITLE",
            comment: "If the user's app is too old, they'll be shown a warning asking them to upgrade. This is the text on the warning, and tapping it will open the App Store page for Signal."
        )
    }
}
