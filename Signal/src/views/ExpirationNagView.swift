//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalServiceKit
import SignalUI

public class ExpirationNagView: ReminderView {
    private let dateProvider: DateProvider
    private let appExpiry: AppExpiry
    private let osExpiry: OsExpiry
    private let device: UpgradableDevice

    // This default value may be quickly overwritten.
    var urlToOpen: URL = .appStoreUrl

    required init(
        dateProvider: @escaping DateProvider,
        appExpiry: AppExpiry,
        osExpiry: OsExpiry,
        device: UpgradableDevice
    ) {
        self.dateProvider = dateProvider
        self.appExpiry = appExpiry
        self.osExpiry = osExpiry
        self.device = device

        super.init(style: .warning, text: "")

        // Because this captures `self`, we can't initialize it until after
        // `super.init()` is called.
        self.tapAction = { [weak self] in
            guard let self else { return }
            UIApplication.shared.open(self.urlToOpen, options: [:])
        }

        update()
    }

    func update() {
        let now = dateProvider()
        lazy var daysUntilAppExpiry = DateUtil.daysFrom(
            firstDate: now,
            toSecondDate: appExpiry.expirationDate
        )

        isHidden = false

        if device.iosMajorVersion < osExpiry.minimumIosMajorVersion {
            let expirationDate = min(osExpiry.enforcedAfter, appExpiry.expirationDate)
            let isExpired = expirationDate < now
            let canUpgradeDevice = device.canUpgrade(to: osExpiry.minimumIosMajorVersion)
            switch (isExpired, canUpgradeDevice) {
            case (false, false):
                text = .osSoonToExpireAndDeviceWillBeStuck(on: expirationDate)
                actionTitle = CommonStrings.learnMore
                urlToOpen = .unsupportedOsUrl
            case (false, true):
                text = .osSoonToExpireAndCanUpgradeOs(expirationDate: expirationDate)
                actionTitle = .upgradeOsActionTitle
                urlToOpen = .upgradeOsUrl
            case (true, false):
                text = .osExpiredAndDeviceIsStuck
                actionTitle = CommonStrings.learnMore
                urlToOpen = .unsupportedOsUrl
            case (true, true):
                text = .osExpiredAndCanUpgradeOs
                actionTitle = .upgradeOsActionTitle
                urlToOpen = .upgradeOsUrl
            }
        } else if appExpiry.expirationDate.isBefore(now) {
            text = .appExpired
            actionTitle = .expiredActionTitle
            urlToOpen = .appStoreUrl
        } else if daysUntilAppExpiry <= 1 {
            text = .appExpiresToday
            actionTitle = .expiredActionTitle
            urlToOpen = .appStoreUrl
        } else if daysUntilAppExpiry <= 10 {
            text = .appExpires(on: appExpiry.expirationDate)
            actionTitle = .expiredActionTitle
            urlToOpen = .appStoreUrl
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
        return String(
            format: OWSLocalizedString(
                "EXPIRATION_WARNING_SOON",
                comment: "Label warning the user that the app will expire soon. Embeds {{date}}."
            ),
            formatDate(date)
        )
    }

    static var expiredActionTitle: String {
        return OWSLocalizedString(
            "EXPIRATION_WARNING_ACTION_TITLE",
            comment: "If the user's app is too old, they'll be shown a warning asking them to upgrade. This is the text on the warning, and tapping it will open the App Store page for Signal."
        )
    }

    static func osSoonToExpireAndDeviceWillBeStuck(on expirationDate: Date) -> String {
        return String(
            format: OWSLocalizedString(
                "OS_SOON_TO_EXPIRE_AND_DEVICE_WILL_BE_STUCK_FORMAT",
                comment: "Signal doesn't support old versions of iOS and shows a warning if you're on an old version that will soon lose support. This is the text on that warning when users can't upgrade iOS without getting a new device. Embeds {{expiration date}}."
            ),
            formatDate(expirationDate)
        )
    }

    static func osSoonToExpireAndCanUpgradeOs(expirationDate: Date) -> String {
        return String(
            format: OWSLocalizedString(
                "OS_SOON_TO_EXPIRE_AND_CAN_UPGRADE_OS_FORMAT",
                comment: "Signal doesn't support old versions of iOS and shows a warning if you're an old version that will soon lose support. Some users can upgrade their device to a newer version of iOS to continue using Signal. If that's the case, they'll be shown this text. Embeds {{expiration date}}."
            ),
            formatDate(expirationDate)
        )
    }

    static var upgradeOsActionTitle: String {
        return OWSLocalizedString(
            "OS_SOON_TO_EXPIRE_ACTION_TITLE",
            comment: "Signal doesn't support old versions of iOS and shows a warning if you're on an old version. Some users can upgrade their device to a newer version of iOS to continue using Signal. If that's the case, they'll be shown this action, and tapping it will open device update instructions."
        )
    }

    static var osExpiredAndDeviceIsStuck: String {
        return OWSLocalizedString(
            "OS_EXPIRED_AND_DEVICE_IS_STUCK",
            value: "Signal no longer works on this device. To use Signal again, switch to a newer device.",
            comment: "Signal doesn't support old devices. If that's the case, they'll be shown this action, and tapping it will open information about Signal's minimum supported operating systems."
        )
    }

    static var osExpiredAndCanUpgradeOs: String {
        return OWSLocalizedString(
            "OS_EXPIRED_AND_CAN_UPGRADE_OS",
            comment: "Signal doesn't support old versions of iOS and shows a warning if you're on unsupported version. Some users can upgrade their device to a newer version of iOS to continue using Signal. If that's the case, they'll be shown this text."
        )
    }

    private static func formatDate(_ date: Date) -> String {
        return DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .none)
    }
}

// MARK: - URLs

fileprivate extension URL {
    static var appStoreUrl: URL {
        return TSConstants.appStoreUrl
    }

    static var upgradeOsUrl: URL {
        return URL(string: "https://support.apple.com/en-us/HT204204")!
    }

    static var unsupportedOsUrl: URL {
        return URL(string: "https://support.signal.org/hc/articles/5109141421850")!
    }
}
