//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
@testable import Signal

extension RegistrationCoordinatorImpl {

    public enum TestMocks {
        public typealias AccountManager = _RegistrationCoordinator_AccountManagerMock
        public typealias ContactsStore = _RegistrationCoordinator_CNContactsStoreMock
        public typealias ExperienceManager = _RegistrationCoordinator_ExperienceManagerMock
        public typealias OWS2FAManager = _RegistrationCoordinator_OWS2FAManagerMock
        public typealias ProfileManager = _RegistrationCoordinator_ProfileManagerMock
        public typealias PushRegistrationManager = _RegistrationCoordinator_PushRegistrationManagerMock
        public typealias ReceiptManager = _RegistrationCoordinator_ReceiptManagerMock
        public typealias RemoteConfig = _RegistrationCoordinator_RemoteConfigMock
        public typealias TSAccountManager = _RegistrationCoordinator_TSAccountManagerMock
        public typealias UDManager = _RegistrationCoordinator_UDManagerMock
    }
}

// MARK: - AccountManager

public class _RegistrationCoordinator_AccountManagerMock: _RegistrationCoordinator_AccountManagerShim {

    public init() {}

    public var performInitialStorageServiceRestoreMock: (() -> Promise<Void>)?

    public func performInitialStorageServiceRestore() -> Promise<Void> {
        return performInitialStorageServiceRestoreMock!()
    }
}

// MARK: CNContacts

public class _RegistrationCoordinator_CNContactsStoreMock: _RegistrationCoordinator_CNContactsStoreShim {

    public init() {}

    public var doesNeedContactsAuthorization = false

    public func needsContactsAuthorization() -> Guarantee<Bool> {
        return .value(doesNeedContactsAuthorization)
    }

    public func requestContactsAuthorization() -> Guarantee<Void> {
        doesNeedContactsAuthorization = false
        return .value(())
    }
}

public class _RegistrationCoordinator_ExperienceManagerMock: _RegistrationCoordinator_ExperienceManagerShim {

    public init() {}

    public var didClearIntroducingPinsExperience: Bool = false
    public var clearIntroducingPinsExperienceMock: (() -> Void)?

    public func clearIntroducingPinsExperience(_ tx: DBWriteTransaction) {
        didClearIntroducingPinsExperience = true
        clearIntroducingPinsExperienceMock?()
    }

    public var didEnableAllGetStartedCards: Bool = false
    public var enableAllGetStartedCardsMock: (() -> Void)?

    public func enableAllGetStartedCards(_ tx: DBWriteTransaction) {
        didEnableAllGetStartedCards = true
        enableAllGetStartedCardsMock?()
    }
}

// MARK: - OWS2FAManager

public class _RegistrationCoordinator_OWS2FAManagerMock: _RegistrationCoordinator_OWS2FAManagerShim {

    public init() {}

    public var pinCodeMock: (() -> String?)?

    public func pinCode(_ tx: SignalServiceKit.DBReadTransaction) -> String? {
        return pinCodeMock!()
    }

    public var isReglockEnabledMock: (() -> Bool)?

    public func isReglockEnabled(_ tx: SignalServiceKit.DBReadTransaction) -> Bool {
        return isReglockEnabledMock!()
    }

    public var didMarkPinEnabled: ((String) -> Void)?

    public func markPinEnabled(_ pin: String, _ tx: SignalServiceKit.DBWriteTransaction) {
        didMarkPinEnabled?(pin)
    }

    public var didMarkRegistrationLockEnabled: (() -> Void)?

    public func markRegistrationLockEnabled(_ tx: SignalServiceKit.DBWriteTransaction) {
        didMarkRegistrationLockEnabled?()
    }
}

// MARK: - ProfileManager

public class _RegistrationCoordinator_ProfileManagerMock: _RegistrationCoordinator_ProfileManagerShim {

    public init() {}

    public var hasProfileNameMock: () -> Bool = { false }

    public var hasProfileName: Bool { return hasProfileNameMock() }

    public var localProfileKeyMock: () -> OWSAES256Key = { OWSAES256Key() }

    public var localProfileKey: OWSAES256Key { return localProfileKeyMock() }

    public var updateLocalProfileMock: ((_ givenName: String, _ familyName: String?, _ avatarData: Data?) -> Promise<Void>)?

    public func updateLocalProfile(givenName: String, familyName: String?, avatarData: Data?) -> Promise<Void> {
        return updateLocalProfileMock!(givenName, familyName, avatarData)
    }
}

// MARK: - PushRegistrationManager

public class _RegistrationCoordinator_PushRegistrationManagerMock: _RegistrationCoordinator_PushRegistrationManagerShim {

    public init() {}

    public var doesNeedNotificationAuthorization = false

    public func needsNotificationAuthorization() -> Guarantee<Bool> {
        return .value(doesNeedNotificationAuthorization)
    }

    public func registerUserNotificationSettings() -> Guarantee<Void> {
        doesNeedNotificationAuthorization = true
        return .value(())
    }

    public var requestPushTokenMock: (() -> Guarantee<String?>)?

    public func requestPushToken() -> Guarantee<String?> {
        return requestPushTokenMock!()
    }

    public var syncPushTokensForcingUploadMock: ((_ authUsername: String, _ authPassword: String) -> Guarantee<Registration.SyncPushTokensResult>)?

    public func syncPushTokensForcingUpload(
        authUsername: String,
        authPassword: String
    ) -> Guarantee<Registration.SyncPushTokensResult> {
        return syncPushTokensForcingUploadMock!(authUsername, authPassword)
    }
}

// MARK: - ReceiptManager

public class _RegistrationCoordinator_ReceiptManagerMock: _RegistrationCoordinator_ReceiptManagerShim {

    public init() {}

    public var didSetAreReadReceiptsEnabled = false
    public var setAreReadReceiptsEnabledMock: ((Bool) -> Void)?

    public func setAreReadReceiptsEnabled(_ areEnabled: Bool, _ tx: DBWriteTransaction) {
        didSetAreReadReceiptsEnabled = true
        setAreReadReceiptsEnabledMock?(areEnabled)
    }

    public var didSetAreStoryViewedReceiptsEnabled = false
    public var setAreStoryViewedReceiptsEnabledMock: ((Bool) -> Void)?

    public func setAreStoryViewedReceiptsEnabled(_ areEnabled: Bool, _ tx: DBWriteTransaction) {
        didSetAreStoryViewedReceiptsEnabled = true
        setAreStoryViewedReceiptsEnabledMock?(areEnabled)
    }
}

// MARK: - Remote Config

public class _RegistrationCoordinator_RemoteConfigMock: _RegistrationCoordinator_RemoteConfigShim {

    public var canReceiveGiftBadgesMock: (() -> Bool) = { true }

    public var canReceiveGiftBadges: Bool { canReceiveGiftBadgesMock() }
}

// MARK: - TSAccountManager

public class _RegistrationCoordinator_TSAccountManagerMock: _RegistrationCoordinator_TSAccountManagerShim {

    public init() {}

    public var hasDefinedIsDiscoverableByPhoneNumberMock: (() -> Bool)?

    public func hasDefinedIsDiscoverableByPhoneNumber(_ transaction: DBReadTransaction) -> Bool {
        return hasDefinedIsDiscoverableByPhoneNumberMock!()
    }

    public var isDiscoverableByPhoneNumberMock: () -> Bool = { true }

    public func isDiscoverableByPhoneNumber(_ transaction: DBReadTransaction) -> Bool {
        return isDiscoverableByPhoneNumberMock()
    }

    public var setIsDiscoverableByPhoneNumberMock: ((_ isDiscoverable: Bool, _ updateStorageService: Bool) -> Void)?

    public func setIsDiscoverableByPhoneNumber(_ isDiscoverable: Bool, updateStorageService: Bool, _ transaction: SignalServiceKit.DBWriteTransaction) {
        setIsDiscoverableByPhoneNumberMock?(isDiscoverable, updateStorageService)
    }

    public var isManualMessageFetchEnabledMock: () -> Bool = { false }

    public func isManualMessageFetchEnabled(_ transaction: DBReadTransaction) -> Bool {
        return isManualMessageFetchEnabledMock()
    }

    public var setIsManualMessageFetchEnabledMock: ((_ isEnabled: Bool) -> Void)?

    public func setIsManualMessageFetchEnabled(_ isEnabled: Bool, _ transaction: DBWriteTransaction) {
        setIsManualMessageFetchEnabledMock?(isEnabled)
    }

    public var didRegisterMock: ((_ accountIdentity: RegistrationServiceResponses.AccountIdentityResponse, _ authToken: String) -> Void)?

    public func didRegister(_ accountIdentity: RegistrationServiceResponses.AccountIdentityResponse, authToken: String, _ tx: DBWriteTransaction) {
        didRegisterMock?(accountIdentity, authToken)
    }

    public var registrationIdMock: (() -> UInt32) = { 8 /* an arbitrary default value */ }

    public func getOrGenerateRegistrationId(_ transaction: DBWriteTransaction) -> UInt32 {
        return registrationIdMock()
    }

    public var pniRegistrationIdMock: (() -> UInt32) = { 9 /* an arbitrary default value */ }

    public func getOrGeneratePniRegistrationId(_ transaction: DBWriteTransaction) -> UInt32 {
        return pniRegistrationIdMock()
    }
}

// MARK: UDManager

public class _RegistrationCoordinator_UDManagerMock: _RegistrationCoordinator_UDManagerShim {

    public var shouldAllowUnrestrictedAccessLocalMock: (() -> Bool) = { true }

    public func shouldAllowUnrestrictedAccessLocal(transaction: DBReadTransaction) -> Bool {
        return shouldAllowUnrestrictedAccessLocalMock()
    }
}
