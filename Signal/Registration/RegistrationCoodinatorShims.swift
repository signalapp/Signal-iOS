//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
import Foundation
import LibSignalClient
import SignalMessaging
import SignalServiceKit

extension RegistrationCoordinatorImpl {

    public enum Shims {
        public typealias AccountManager = _RegistrationCoordinator_AccountManagerShim
        public typealias ContactsManager = _RegistrationCoordinator_ContactsManagerShim
        public typealias ContactsStore = _RegistrationCoordinator_CNContactsStoreShim
        public typealias ExperienceManager = _RegistrationCoordinator_ExperienceManagerShim
        public typealias MessagePipelineSupervisor = _RegistrationCoordinator_MessagePipelineSupervisorShim
        public typealias MessageProcessor = _RegistrationCoordinator_MessageProcessorShim
        public typealias OWS2FAManager = _RegistrationCoordinator_OWS2FAManagerShim
        public typealias ProfileManager = _RegistrationCoordinator_ProfileManagerShim
        public typealias PushRegistrationManager = _RegistrationCoordinator_PushRegistrationManagerShim
        public typealias ReceiptManager = _RegistrationCoordinator_ReceiptManagerShim
        public typealias UDManager = _RegistrationCoordinator_UDManagerShim
    }
    public enum Wrappers {
        public typealias AccountManager = _RegistrationCoordinator_AccountManagerWrapper
        public typealias ContactsManager = _RegistrationCoordinator_ContactsManagerWrapper
        public typealias ContactsStore = _RegistrationCoordinator_CNContactsStoreWrapper
        public typealias ExperienceManager = _RegistrationCoordinator_ExperienceManagerWrapper
        public typealias MessagePipelineSupervisor = _RegistrationCoordinator_MessagePipelineSupervisorWrapper
        public typealias MessageProcessor = _RegistrationCoordinator_MessageProcessorWrapper
        public typealias OWS2FAManager = _RegistrationCoordinator_OWS2FAManagerWrapper
        public typealias ProfileManager = _RegistrationCoordinator_ProfileManagerWrapper
        public typealias PushRegistrationManager = _RegistrationCoordinator_PushRegistrationManagerWrapper
        public typealias ReceiptManager = _RegistrationCoordinator_ReceiptManagerWrapper
        public typealias UDManager = _RegistrationCoordinator_UDManagerWrapper
    }
}

// MARK: - AccountManager

public protocol _RegistrationCoordinator_AccountManagerShim {

    func performInitialStorageServiceRestore(authedAccount: AuthedAccount) -> Promise<Void>
}

public class _RegistrationCoordinator_AccountManagerWrapper: _RegistrationCoordinator_AccountManagerShim {

    private let manager: AccountManager
    public init(_ manager: AccountManager) { self.manager = manager }

    public func performInitialStorageServiceRestore(authedAccount: AuthedAccount) -> Promise<Void> {
        return manager.performInitialStorageServiceRestore(authedAccount: authedAccount)
    }
}

// MARK: OWSContactsManager

public protocol _RegistrationCoordinator_ContactsManagerShim {

    func fetchSystemContactsOnceIfAlreadyAuthorized()

    func setIsPrimaryDevice()
}

public class _RegistrationCoordinator_ContactsManagerWrapper: _RegistrationCoordinator_ContactsManagerShim {

    private let manager: OWSContactsManager
    public init(_ manager: OWSContactsManager) { self.manager = manager }

    public func fetchSystemContactsOnceIfAlreadyAuthorized() {
        manager.fetchSystemContactsOnceIfAlreadyAuthorized()
    }

    public func setIsPrimaryDevice() {
        manager.setIsPrimaryDevice()
    }
}

// MARK: CNContacts

public protocol _RegistrationCoordinator_CNContactsStoreShim {

    func needsContactsAuthorization() -> Guarantee<Bool>

    func requestContactsAuthorization() -> Guarantee<Void>
}

public class _RegistrationCoordinator_CNContactsStoreWrapper: _RegistrationCoordinator_CNContactsStoreShim {

    public init() {}

    public func needsContactsAuthorization() -> Guarantee<Bool> {
        return .value(CNContactStore.authorizationStatus(for: .contacts) == .notDetermined)
    }

    public func requestContactsAuthorization() -> Guarantee<Void> {
        let (guarantee, future) = Guarantee<Void>.pending()
        CNContactStore().requestAccess(for: CNEntityType.contacts) { (granted, error) -> Void in
            if granted {
                Logger.info("User granted contacts permission")
            } else {
                // Unfortunately, we can't easily disambiguate "not granted" and
                // "other error".
                Logger.warn("User denied contacts permission or there was an error. Error: \(String(describing: error))")
            }
            future.resolve()
        }
        return guarantee
    }
}

// MARK: - ExperienceManager

public protocol _RegistrationCoordinator_ExperienceManagerShim {

    func clearIntroducingPinsExperience(_ tx: DBWriteTransaction)

    func enableAllGetStartedCards(_ tx: DBWriteTransaction)
}

public class _RegistrationCoordinator_ExperienceManagerWrapper: _RegistrationCoordinator_ExperienceManagerShim {

    public init() {}

    public func clearIntroducingPinsExperience(_ tx: DBWriteTransaction) {
        ExperienceUpgradeManager.clearExperienceUpgrade(.introducingPins, transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite)
    }

    public func enableAllGetStartedCards(_ tx: DBWriteTransaction) {
        GetStartedBannerViewController.enableAllCards(writeTx: SDSDB.shimOnlyBridge(tx))
    }
}

// MARK: - MessagePipelineSupervisor

public protocol _RegistrationCoordinator_MessagePipelineSupervisorShim {

    func suspendMessageProcessingWithoutHandle(for: MessagePipelineSupervisor.Suspension)

    func unsuspendMessageProcessing(for: MessagePipelineSupervisor.Suspension)
}

public class _RegistrationCoordinator_MessagePipelineSupervisorWrapper: _RegistrationCoordinator_MessagePipelineSupervisorShim {

    private let supervisor: MessagePipelineSupervisor

    public init(_ supervisor: MessagePipelineSupervisor) {
        self.supervisor = supervisor
    }

    public func suspendMessageProcessingWithoutHandle(for suspension: MessagePipelineSupervisor.Suspension) {
        supervisor.suspendMessageProcessingWithoutHandle(for: suspension)
    }

    public func unsuspendMessageProcessing(for suspension: MessagePipelineSupervisor.Suspension) {
        supervisor.unsuspendMessageProcessing(for: suspension)
    }
}

// MARK: - MessageProcessor

public protocol _RegistrationCoordinator_MessageProcessorShim {

    func waitForProcessingCompleteAndThenSuspend(
        for suspension: MessagePipelineSupervisor.Suspension
    ) -> Guarantee<Void>
}

public class _RegistrationCoordinator_MessageProcessorWrapper: _RegistrationCoordinator_MessageProcessorShim {

    private let processor: MessageProcessor

    public init(_ processor: MessageProcessor) {
        self.processor = processor
    }

    public func waitForProcessingCompleteAndThenSuspend(
        for suspension: MessagePipelineSupervisor.Suspension
    ) -> Guarantee<Void> {
        return processor.waitForProcessingCompleteAndThenSuspend(for: suspension)
    }
}

// MARK: - OWS2FAManager

public protocol _RegistrationCoordinator_OWS2FAManagerShim {

    func pinCode(_ tx: DBReadTransaction) -> String?

    func clearLocalPinCode(_ tx: DBWriteTransaction)

    func isReglockEnabled(_ tx: DBReadTransaction) -> Bool

    func markPinEnabled(_ pin: String, _ tx: DBWriteTransaction)

    func markRegistrationLockEnabled(_  tx: DBWriteTransaction)
}

public class _RegistrationCoordinator_OWS2FAManagerWrapper: _RegistrationCoordinator_OWS2FAManagerShim {

    private let manager: OWS2FAManager
    public init(_ manager: OWS2FAManager) { self.manager = manager }

    public func pinCode(_ tx: DBReadTransaction) -> String? {
        return manager.pinCode(with: SDSDB.shimOnlyBridge(tx))
    }

    public func clearLocalPinCode(_ tx: DBWriteTransaction) {
        return manager.clearLocalPinCode(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func isReglockEnabled(_ tx: DBReadTransaction) -> Bool {
        return manager.isRegistrationLockV2Enabled(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func markPinEnabled(_ pin: String, _ tx: DBWriteTransaction) {
        manager.markEnabled(pin: pin, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func markRegistrationLockEnabled(_ tx: DBWriteTransaction) {
        manager.markRegistrationLockV2Enabled(transaction: SDSDB.shimOnlyBridge(tx))
    }
}

// MARK: - ProfileManager

public protocol _RegistrationCoordinator_ProfileManagerShim {

    var hasProfileName: Bool { get }

    // NOTE: non-optional because OWSProfileManager generates a random key
    // if one doesn't already exist.
    var localProfileKey: OWSAES256Key { get }

    func updateLocalProfile(
        givenName: String,
        familyName: String?,
        avatarData: Data?,
        authedAccount: AuthedAccount
    ) -> Promise<Void>
}

public class _RegistrationCoordinator_ProfileManagerWrapper: _RegistrationCoordinator_ProfileManagerShim {

    private let manager: ProfileManagerProtocol
    public init(_ manager: ProfileManagerProtocol) { self.manager = manager }

    public var hasProfileName: Bool { manager.hasProfileName }

    public var localProfileKey: OWSAES256Key { manager.localProfileKey() }

    public func updateLocalProfile(
        givenName: String,
        familyName: String?,
        avatarData: Data?,
        authedAccount: AuthedAccount
    ) -> Promise<Void> {
        return OWSProfileManager.updateLocalProfilePromise(
            profileGivenName: givenName,
            profileFamilyName: familyName,
            profileBio: nil,
            profileBioEmoji: nil,
            profileAvatarData: avatarData,
            visibleBadgeIds: [],
            userProfileWriter: .registration,
            authedAccount: authedAccount
        )
    }
}

// MARK: - PushRegistrationManager

extension Registration {
    public enum RequestPushTokensResult {
        case success(RegistrationRequestFactory.ApnRegistrationId)
        case pushUnsupported(description: String)
        case timeout
        case genericError(Error)
    }

    public enum SyncPushTokensResult {
        case success
        case pushUnsupported(description: String)
        case networkError
        case genericError(Error)
    }
}

public protocol _RegistrationCoordinator_PushRegistrationManagerShim {

    func needsNotificationAuthorization() -> Guarantee<Bool>

    func registerUserNotificationSettings() -> Guarantee<Void>

    func requestPushToken() -> Guarantee<Registration.RequestPushTokensResult>

    func receivePreAuthChallengeToken() -> Guarantee<String>

    func clearPreAuthChallengeToken()

    func syncPushTokensForcingUpload(
        auth: ChatServiceAuth
    ) -> Guarantee<Registration.SyncPushTokensResult>
}

public class _RegistrationCoordinator_PushRegistrationManagerWrapper: _RegistrationCoordinator_PushRegistrationManagerShim {

    private let manager: PushRegistrationManager
    public init(_ manager: PushRegistrationManager) { self.manager = manager }

    public func needsNotificationAuthorization() -> Guarantee<Bool> {
        return manager.needsNotificationAuthorization()
    }

    public func registerUserNotificationSettings() -> Guarantee<Void> {
        return manager.registerUserNotificationSettings()
    }

    public func requestPushToken() -> Guarantee<Registration.RequestPushTokensResult> {
        return manager.requestPushTokens(forceRotation: false, timeOutEventually: true)
            .map(on: SyncScheduler()) { .success($0) }
            .recover(on: SyncScheduler()) { error in
                switch error {
                case PushRegistrationError.pushNotSupported(let description):
                    return .value(.pushUnsupported(description: description))
                case PushRegistrationError.timeout:
                    return .value(.timeout)
                default:
                    return .value(.genericError(error))
                }
            }
    }

    public func receivePreAuthChallengeToken() -> Guarantee<String> {
        return manager.receivePreAuthChallengeToken()
    }

    public func clearPreAuthChallengeToken() {
        manager.clearPreAuthChallengeToken()
    }

    public func syncPushTokensForcingUpload(
        auth: ChatServiceAuth
    ) -> Guarantee<Registration.SyncPushTokensResult> {
        let job = SyncPushTokensJob(mode: .forceUpload, auth: auth)
        return Guarantee.wrapAsync {
            do {
                try await job.run()
                return .success
            } catch {
                if error.isNetworkFailureOrTimeout {
                    return .networkError
                }
                switch error {
                case PushRegistrationError.pushNotSupported(let description):
                    return .pushUnsupported(description: description)
                default:
                    return .genericError(error)
                }
            }
        }
    }
}

// MARK: - ReceiptManager

public protocol _RegistrationCoordinator_ReceiptManagerShim {

    func setAreReadReceiptsEnabled(_ areEnabled: Bool, _ tx: DBWriteTransaction)
    func setAreStoryViewedReceiptsEnabled(_ areEnabled: Bool, _ tx: DBWriteTransaction)
}

public class _RegistrationCoordinator_ReceiptManagerWrapper: _RegistrationCoordinator_ReceiptManagerShim {

    private let manager: OWSReceiptManager
    public init(_ manager: OWSReceiptManager) { self.manager = manager }

    public func setAreReadReceiptsEnabled(_ areEnabled: Bool, _ tx: DBWriteTransaction) {
        manager.setAreReadReceiptsEnabled(areEnabled, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func setAreStoryViewedReceiptsEnabled(_ areEnabled: Bool, _ tx: DBWriteTransaction) {
        StoryManager.setAreViewReceiptsEnabled(areEnabled, transaction: SDSDB.shimOnlyBridge(tx))
    }
}

// MARK: - UDManager

public protocol _RegistrationCoordinator_UDManagerShim {

    func shouldAllowUnrestrictedAccessLocal(transaction: DBReadTransaction) -> Bool
}

public class _RegistrationCoordinator_UDManagerWrapper: _RegistrationCoordinator_UDManagerShim {

    private let manager: OWSUDManager
    public init(_ manager: OWSUDManager) { self.manager = manager }

    public func shouldAllowUnrestrictedAccessLocal(transaction: DBReadTransaction) -> Bool {
        return manager.shouldAllowUnrestrictedAccessLocal(transaction: SDSDB.shimOnlyBridge(transaction))
    }
}
