//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

// Exposes singleton accessors for all UIViews, UIViewControllers, etc.
@objc
public extension UIResponder {

    // MARK: - Dependencies

    var backup: OWSBackup {
        return AppEnvironment.shared.backup
    }

    static var backup: OWSBackup {
        return AppEnvironment.shared.backup
    }

    var accountManager: AccountManager {
        return AppEnvironment.shared.accountManager
    }

    static var accountManager: AccountManager {
        return AppEnvironment.shared.accountManager
    }

    var notificationPresenter: NotificationPresenter {
        return AppEnvironment.shared.notificationPresenter
    }

    static var notificationPresenter: NotificationPresenter {
        return AppEnvironment.shared.notificationPresenter
    }

    var pushRegistrationManager: PushRegistrationManager {
        return AppEnvironment.shared.pushRegistrationManager
    }

    static var pushRegistrationManager: PushRegistrationManager {
        return AppEnvironment.shared.pushRegistrationManager
    }

    var userNotificationActionHandler: UserNotificationActionHandler {
        return AppEnvironment.shared.userNotificationActionHandler
    }

    static var userNotificationActionHandler: UserNotificationActionHandler {
        return AppEnvironment.shared.userNotificationActionHandler
    }
}

// MARK: -

@objc
extension UIResponder {
    var deviceTransferService: DeviceTransferService { .shared }

    static var deviceTransferService: DeviceTransferService { .shared }
}
