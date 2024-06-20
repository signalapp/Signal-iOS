//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class ExpirationNagView: ReminderView {
    private let dateProvider: DateProvider
    private let appExpiry: AppExpiry
    private let osExpiry: OsExpiry
    private let device: UpgradableDevice

    // This default value may be quickly overwritten.
    var urlToOpen: URL = .appStoreUrl

    init(
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

    enum ExpirationMessage: Equatable {
        case appExpired
        case appWillExpireToday
        case appWillExpireSoon(Date)
        case osExpired(canUpgrade: Bool)
        case osWillExpireSoon(Date, canUpgrade: Bool)

        var text: String {
            switch self {
            case .appExpired: return .appExpired
            case .appWillExpireToday: return .appExpiresToday
            case .appWillExpireSoon(let expirationDate): return .appExpires(on: expirationDate)
            case .osExpired(canUpgrade: true): return .osExpiredAndCanUpgradeOs
            case .osExpired(canUpgrade: false): return .osExpiredAndDeviceIsStuck
            case .osWillExpireSoon(let expirationDate, canUpgrade: true):
                return .osSoonToExpireAndCanUpgradeOs(expirationDate: expirationDate)
            case .osWillExpireSoon(let expirationDate, canUpgrade: false):
                return .osSoonToExpireAndDeviceWillBeStuck(on: expirationDate)
            }
        }

        var actionTitle: String {
            switch self {
            case .appExpired, .appWillExpireToday, .appWillExpireSoon:
                return .expiredActionTitle
            case .osExpired(canUpgrade: true), .osWillExpireSoon(_, canUpgrade: true):
                return .upgradeOsActionTitle
            case .osExpired(canUpgrade: false), .osWillExpireSoon(_, canUpgrade: false):
                return CommonStrings.learnMore
            }
        }

        var urlToOpen: URL {
            switch self {
            case .appExpired, .appWillExpireToday, .appWillExpireSoon:
                return .appStoreUrl
            case .osExpired(canUpgrade: true), .osWillExpireSoon(_, canUpgrade: true):
                return .upgradeOsUrl
            case .osExpired(canUpgrade: false), .osWillExpireSoon(_, canUpgrade: false):
                return .unsupportedOsUrl
            }
        }
    }

    func update() {
        if let expirationMessage = self.expirationMessage() {
            self.isHidden = false
            self.text = expirationMessage.text
            self.actionTitle = expirationMessage.actionTitle
            self.urlToOpen = expirationMessage.urlToOpen
        } else {
            self.isHidden = true
        }
    }

    func expirationMessage() -> ExpirationMessage? {
        let now = dateProvider()
        lazy var daysUntilAppExpiry = DateUtil.daysFrom(
            firstDate: now,
            toSecondDate: appExpiry.expirationDate
        )

        let osExpirationDate: Date = (
            device.iosMajorVersion < osExpiry.minimumIosMajorVersion ? osExpiry.enforcedAfter : .distantFuture
        )

        // If the OS is expired, say that.
        if osExpirationDate < now {
            return .osExpired(canUpgrade: device.canUpgrade(to: osExpiry.minimumIosMajorVersion))
        }
        // If the app expires before the OS, warn about that (within 10 days).
        if appExpiry.expirationDate < osExpirationDate {
            if appExpiry.expirationDate < now {
                return .appExpired
            }
            if daysUntilAppExpiry <= 1 {
                return .appWillExpireToday
            }
            if daysUntilAppExpiry <= 10 {
                return .appWillExpireSoon(appExpiry.expirationDate)
            }
        }
        // If the OS will expire "soon", say that.
        if osExpirationDate < .distantFuture {
            return .osWillExpireSoon(osExpiry.enforcedAfter, canUpgrade: device.canUpgrade(to: osExpiry.minimumIosMajorVersion))
        }

        return nil
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
