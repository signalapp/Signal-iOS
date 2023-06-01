//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalUI

// MARK: - NSObject

@objc
public extension NSObject {

    final var accountManager: AccountManager {
        AppEnvironment.shared.accountManagerRef
    }

    static var accountManager: AccountManager {
        AppEnvironment.shared.accountManagerRef
    }

    final var callService: CallService {
        AppEnvironment.shared.callServiceRef
    }

    static var callService: CallService {
        AppEnvironment.shared.callServiceRef
    }

    final var notificationPresenter: NotificationPresenter {
        AppEnvironment.shared.notificationPresenterRef
    }

    static var notificationPresenter: NotificationPresenter {
        AppEnvironment.shared.notificationPresenterRef
    }

    final var pushRegistrationManager: PushRegistrationManager {
        AppEnvironment.shared.pushRegistrationManagerRef
    }

    static var pushRegistrationManager: PushRegistrationManager {
        AppEnvironment.shared.pushRegistrationManagerRef
    }

    final var cvAudioPlayer: CVAudioPlayer {
        AppEnvironment.shared.cvAudioPlayerRef
    }

    static var cvAudioPlayer: CVAudioPlayer {
        AppEnvironment.shared.cvAudioPlayerRef
    }

    final var speechManager: SpeechManager {
        AppEnvironment.shared.speechManagerRef
    }

    static var speechManager: SpeechManager {
        AppEnvironment.shared.speechManagerRef
    }

    @nonobjc
    final var deviceSleepManager: DeviceSleepManager {
        .shared
    }

    @nonobjc
    static var deviceSleepManager: DeviceSleepManager {
        .shared
    }

    var avatarHistoryManager: AvatarHistoryManager {
        AppEnvironment.shared.avatarHistorManagerRef
    }

    static var avatarHistoryManager: AvatarHistoryManager {
        AppEnvironment.shared.avatarHistorManagerRef
    }
}

// MARK: - Obj-C Dependencies

public extension Dependencies {
    var accountManager: AccountManager {
        AppEnvironment.shared.accountManagerRef
    }

    static var accountManager: AccountManager {
        AppEnvironment.shared.accountManagerRef
    }

    var callService: CallService {
        AppEnvironment.shared.callServiceRef
    }

    static var callService: CallService {
        AppEnvironment.shared.callServiceRef
    }

    var notificationPresenter: NotificationPresenter {
        AppEnvironment.shared.notificationPresenterRef
    }

    static var notificationPresenter: NotificationPresenter {
        AppEnvironment.shared.notificationPresenterRef
    }

    var pushRegistrationManager: PushRegistrationManager {
        AppEnvironment.shared.pushRegistrationManagerRef
    }

    static var pushRegistrationManager: PushRegistrationManager {
        AppEnvironment.shared.pushRegistrationManagerRef
    }

    var cvAudioPlayer: CVAudioPlayer {
        AppEnvironment.shared.cvAudioPlayerRef
    }

    static var cvAudioPlayer: CVAudioPlayer {
        AppEnvironment.shared.cvAudioPlayerRef
    }

    var deviceSleepManager: DeviceSleepManager {
        .shared
    }

    static var deviceSleepManager: DeviceSleepManager {
        .shared
    }

    var avatarHistoryManager: AvatarHistoryManager {
        AppEnvironment.shared.avatarHistorManagerRef
    }

    static var avatarHistoryManager: AvatarHistoryManager {
        AppEnvironment.shared.avatarHistorManagerRef
    }
}

// MARK: - Swift-only Dependencies

extension NSObject {
    final var deviceTransferService: DeviceTransferService { .shared }

    static var deviceTransferService: DeviceTransferService { .shared }
}

// MARK: - Swift-only Dependencies

public extension Dependencies {

}

// MARK: -

extension DeviceTransferService {
    static var shared: DeviceTransferService {
        AppEnvironment.shared.deviceTransferServiceRef
    }
}

// MARK: -

extension PushRegistrationManager {
    static var shared: PushRegistrationManager {
        AppEnvironment.shared.pushRegistrationManagerRef
    }
}

// MARK: -

extension OWSSyncManager {
    static var shared: OWSSyncManager {
        SSKEnvironment.shared.syncManagerRef as! OWSSyncManager
    }
}

// MARK: -

extension WindowManager {
    static var shared: WindowManager {
        AppEnvironment.shared.windowManagerRef
    }
}
