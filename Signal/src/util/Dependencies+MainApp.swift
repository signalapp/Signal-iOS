//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

// MARK: - NSObject

@objc
public extension NSObject {

    final var accountManager: AccountManager {
        AppEnvironment.shared.accountManagerRef
    }

    static var accountManager: AccountManager {
        AppEnvironment.shared.accountManagerRef
    }

    final var individualCallUIAdapter: CallUIAdapter {
        AppEnvironment.shared.callServiceRef.individualCallService.callUIAdapter
    }

    static var individualCallUIAdapter: CallUIAdapter {
        AppEnvironment.shared.callServiceRef.individualCallService.callUIAdapter
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

    final var outboundIndividualCallInitiator: OutboundIndividualCallInitiator {
        AppEnvironment.shared.outboundIndividualCallInitiatorRef
    }

    static var outboundIndividualCallInitiator: OutboundIndividualCallInitiator {
        AppEnvironment.shared.outboundIndividualCallInitiatorRef
    }

    final var pushRegistrationManager: PushRegistrationManager {
        AppEnvironment.shared.pushRegistrationManagerRef
    }

    static var pushRegistrationManager: PushRegistrationManager {
        AppEnvironment.shared.pushRegistrationManagerRef
    }

    final var sessionResetJobQueue: SessionResetJobQueue {
        AppEnvironment.shared.sessionResetJobQueueRef
    }

    static var sessionResetJobQueue: SessionResetJobQueue {
        AppEnvironment.shared.sessionResetJobQueueRef
    }

    final var userNotificationActionHandler: UserNotificationActionHandler {
        AppEnvironment.shared.userNotificationActionHandlerRef
    }

    static var userNotificationActionHandler: UserNotificationActionHandler {
        AppEnvironment.shared.userNotificationActionHandlerRef
    }

    final var cvAudioPlayer: CVAudioPlayer {
        AppEnvironment.shared.cvAudioPlayerRef
    }

    static var cvAudioPlayer: CVAudioPlayer {
        AppEnvironment.shared.cvAudioPlayerRef
    }

    final var deviceSleepManager: DeviceSleepManager {
        .shared
    }

    static var deviceSleepManager: DeviceSleepManager {
        .shared
    }

    final var signalApp: SignalApp {
        .shared()
    }

    static var signalApp: SignalApp {
        .shared()
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

    var individualCallUIAdapter: CallUIAdapter {
        AppEnvironment.shared.callServiceRef.individualCallService.callUIAdapter
    }

    static var individualCallUIAdapter: CallUIAdapter {
        AppEnvironment.shared.callServiceRef.individualCallService.callUIAdapter
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

    var outboundIndividualCallInitiator: OutboundIndividualCallInitiator {
        AppEnvironment.shared.outboundIndividualCallInitiatorRef
    }

    static var outboundIndividualCallInitiator: OutboundIndividualCallInitiator {
        AppEnvironment.shared.outboundIndividualCallInitiatorRef
    }

    var pushRegistrationManager: PushRegistrationManager {
        AppEnvironment.shared.pushRegistrationManagerRef
    }

    static var pushRegistrationManager: PushRegistrationManager {
        AppEnvironment.shared.pushRegistrationManagerRef
    }

    var sessionResetJobQueue: SessionResetJobQueue {
        AppEnvironment.shared.sessionResetJobQueueRef
    }

    static var sessionResetJobQueue: SessionResetJobQueue {
        AppEnvironment.shared.sessionResetJobQueueRef
    }

    var userNotificationActionHandler: UserNotificationActionHandler {
        AppEnvironment.shared.userNotificationActionHandlerRef
    }

    static var userNotificationActionHandler: UserNotificationActionHandler {
        AppEnvironment.shared.userNotificationActionHandlerRef
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

    var signalApp: SignalApp {
        .shared()
    }

    static var signalApp: SignalApp {
        .shared()
    }
}

// MARK: - Swift-only Dependencies

@objc
extension NSObject {

    final var giphyAPI: GiphyAPI { .shared }

    static var giphyAPI: GiphyAPI { .shared }

    final var deviceTransferService: DeviceTransferService { .shared }

    static var deviceTransferService: DeviceTransferService { .shared }
}

// MARK: - Swift-only Dependencies

public extension Dependencies {

}

// MARK: -

@objc
extension DeviceTransferService {
    static var shared: DeviceTransferService {
        AppEnvironment.shared.deviceTransferServiceRef
    }
}

// MARK: -

@objc
extension PushRegistrationManager {
    static var shared: PushRegistrationManager {
        AppEnvironment.shared.pushRegistrationManagerRef
    }
}

// MARK: -

@objc
extension OWSSyncManager {
    static var shared: OWSSyncManager {
        SSKEnvironment.shared.syncManagerRef as! OWSSyncManager
    }
}
