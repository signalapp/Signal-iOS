//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
import Foundation
import SignalMessaging

extension RegistrationCoordinatorImpl {

    public enum Shims {
        public typealias AccountManager = _RegistrationCoordinator_AccountManagerShim
        public typealias ContactsStore = _RegistrationCoordinator_CNContactsStoreShim
        public typealias ExperienceManager = _RegistrationCoordinator_ExperienceManagerShim
        public typealias OWS2FAManager = _RegistrationCoordinator_OWS2FAManagerShim
        public typealias ProfileManager = _RegistrationCoordinator_ProfileManagerShim
        public typealias PushRegistrationManager = _RegistrationCoordinator_PushRegistrationManagerShim
        public typealias ReceiptManager = _RegistrationCoordinator_ReceiptManagerShim
        public typealias RemoteConfig = _RegistrationCoordinator_RemoteConfigShim
        public typealias TSAccountManager = _RegistrationCoordinator_TSAccountManagerShim
        public typealias UDManager = _RegistrationCoordinator_UDManagerShim
    }
    public enum Wrappers {
        public typealias AccountManager = _RegistrationCoordinator_AccountManagerWrapper
        public typealias ContactsStore = _RegistrationCoordinator_CNContactsStoreWrapper
        public typealias ExperienceManager = _RegistrationCoordinator_ExperienceManagerWrapper
        public typealias OWS2FAManager = _RegistrationCoordinator_OWS2FAManagerWrapper
        public typealias ProfileManager = _RegistrationCoordinator_ProfileManagerWrapper
        public typealias PushRegistrationManager = _RegistrationCoordinator_PushRegistrationManagerWrapper
        public typealias ReceiptManager = _RegistrationCoordinator_ReceiptManagerWrapper
        public typealias RemoteConfig = _RegistrationCoordinator_RemoteConfigWrapper
        public typealias TSAccountManager = _RegistrationCoordinator_TSAccountManagerWrapper
        public typealias UDManager = _RegistrationCoordinator_UDManagerWrapper
    }
}

// MARK: - AccountManager

public protocol _RegistrationCoordinator_AccountManagerShim {

    func performInitialStorageServiceRestore() -> Promise<Void>
}

public class _RegistrationCoordinator_AccountManagerWrapper: _RegistrationCoordinator_AccountManagerShim {

    private let manager: AccountManager
    public init(_ manager: AccountManager) { self.manager = manager }

    public func performInitialStorageServiceRestore() -> Promise<Void> {
        return manager.performInitialStorageServiceRestore()
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

// MARK: - OWS2FAManager

public protocol _RegistrationCoordinator_OWS2FAManagerShim {

    func pinCode(_ tx: DBReadTransaction) -> String?

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
        avatarData: Data?
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
        avatarData: Data?
    ) -> Promise<Void> {
        return OWSProfileManager.updateLocalProfilePromise(
            profileGivenName: givenName,
            profileFamilyName: familyName,
            profileBio: nil,
            profileBioEmoji: nil,
            profileAvatarData: avatarData,
            visibleBadgeIds: [],
            userProfileWriter: .registration
        )
    }
}

// MARK: - PushRegistrationManager

extension Registration {
    public enum SyncPushTokensResult {
        case success
        case pushUnsupported(description: String)
        case networkError
        case genericError
    }
}

public protocol _RegistrationCoordinator_PushRegistrationManagerShim {

    func needsNotificationAuthorization() -> Guarantee<Bool>

    func registerUserNotificationSettings() -> Guarantee<Void>

    func requestPushToken() -> Guarantee<String?>

    func syncPushTokensForcingUpload(
        authUsername: String,
        authPassword: String
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

    public func requestPushToken() -> Guarantee<String?> {
        return manager.requestPushTokens(forceRotation: false)
            .map { $0.0 }
            .recover { _ in return .value(nil) }
    }

    public func syncPushTokensForcingUpload(
        authUsername: String,
        authPassword: String
    ) -> Guarantee<Registration.SyncPushTokensResult> {
        let job = SyncPushTokensJob(mode: .forceUpload)
        job.authUsername = authUsername
        job.authPassword = authPassword
        return job.run()
            .map(on: SyncScheduler()) { return .success }
            .recover(on: SyncScheduler()) { error -> Guarantee<Registration.SyncPushTokensResult> in
                if error.isNetworkConnectivityFailure {
                    return .value(.networkError)
                }
                switch error {
                case PushRegistrationError.pushNotSupported(let description):
                    return .value(.pushUnsupported(description: description))
                default:
                    return .value(.genericError)
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

// MARK: - RemoteConfig

public protocol _RegistrationCoordinator_RemoteConfigShim {

    var canReceiveGiftBadges: Bool { get }
}

public class _RegistrationCoordinator_RemoteConfigWrapper: _RegistrationCoordinator_RemoteConfigShim {

    public init() {}

    public var canReceiveGiftBadges: Bool { RemoteConfig.canSendGiftBadges }
}

// MARK: - TSAccountManager

public protocol _RegistrationCoordinator_TSAccountManagerShim {

    func isManualMessageFetchEnabled(_ transaction: DBReadTransaction) -> Bool
    func setIsManualMessageFetchEnabled(_ isEnabled: Bool, _ transaction: DBWriteTransaction)

    func getOrGenerateRegistrationId(_ transaction: DBWriteTransaction) -> UInt32
    func getOrGeneratePniRegistrationId(_ transaction: DBWriteTransaction) -> UInt32

    func hasDefinedIsDiscoverableByPhoneNumber(_ transaction: DBReadTransaction) -> Bool
    func isDiscoverableByPhoneNumber(_ transaction: DBReadTransaction) -> Bool
    func setIsDiscoverableByPhoneNumber(
        _ isDiscoverable: Bool,
        updateStorageService: Bool,
        _ transaction: DBWriteTransaction
    )

    func didRegister(
        _ accountIdentity: RegistrationServiceResponses.AccountIdentityResponse,
        authToken: String,
        _ tx: DBWriteTransaction
    )
}

public class _RegistrationCoordinator_TSAccountManagerWrapper: _RegistrationCoordinator_TSAccountManagerShim {

    private let manager: TSAccountManager
    public init(_ manager: TSAccountManager) { self.manager = manager }

    public func hasDefinedIsDiscoverableByPhoneNumber(_ transaction: DBReadTransaction) -> Bool {
        return manager.hasDefinedIsDiscoverableByPhoneNumber(with: SDSDB.shimOnlyBridge(transaction))
    }

    public func setIsManualMessageFetchEnabled(_ isEnabled: Bool, _ transaction: DBWriteTransaction) {
        manager.setIsManualMessageFetchEnabled(isEnabled, transaction: SDSDB.shimOnlyBridge(transaction))
    }

    public func isManualMessageFetchEnabled(_ transaction: DBReadTransaction) -> Bool {
        return manager.isManualMessageFetchEnabled(SDSDB.shimOnlyBridge(transaction))
    }

    public func getOrGenerateRegistrationId(_ transaction: DBWriteTransaction) -> UInt32 {
        return manager.getOrGenerateRegistrationId(transaction: SDSDB.shimOnlyBridge(transaction))
    }

    public func getOrGeneratePniRegistrationId(_ transaction: DBWriteTransaction) -> UInt32 {
        return manager.getOrGeneratePniRegistrationId(transaction: SDSDB.shimOnlyBridge(transaction))
    }

    public func isDiscoverableByPhoneNumber(_ transaction: DBReadTransaction) -> Bool {
        return manager.isDiscoverableByPhoneNumber(with: SDSDB.shimOnlyBridge(transaction))
    }

    public func setIsDiscoverableByPhoneNumber(
        _ isDiscoverable: Bool,
        updateStorageService: Bool,
        _ transaction: DBWriteTransaction
    ) {
        manager.setIsDiscoverableByPhoneNumber(
            isDiscoverable,
            updateStorageService: updateStorageService,
            transaction: SDSDB.shimOnlyBridge(transaction)
        )
    }

    public func didRegister(
        _ accountIdentity: RegistrationServiceResponses.AccountIdentityResponse,
        authToken: String,
        _ tx: DBWriteTransaction
    ) {
        manager.didRegister(
            withE164: accountIdentity.e164,
            aci: accountIdentity.aci,
            pni: accountIdentity.pni,
            authToken: authToken,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
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
