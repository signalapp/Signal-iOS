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
}
