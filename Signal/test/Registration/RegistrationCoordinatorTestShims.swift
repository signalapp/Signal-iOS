//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
@testable import Signal

extension RegistrationCoordinatorImpl {

    public enum TestMocks {
        public typealias ContactsStore = _RegistrationCoordinator_CNContactsStoreMock
        public typealias OWS2FAManager = _RegistrationCoordinator_OWS2FAManagerMock
        public typealias ProfileManager = _RegistrationCoordinator_ProfileManagerMock
        public typealias PushRegistrationManager = _RegistrationCoordinator_PushRegistrationManagerMock
        public typealias RemoteConfig = _RegistrationCoordinator_RemoteConfigMock
        public typealias TSAccountManager = _RegistrationCoordinator_TSAccountManagerMock
        public typealias UDManager = _RegistrationCoordinator_UDManagerMock
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

// MARK: - OWS2FAManager

public class _RegistrationCoordinator_OWS2FAManagerMock: _RegistrationCoordinator_OWS2FAManagerShim {

    public init() {}

    public var pinCode: String?

    public func pinCode(_ tx: SignalServiceKit.DBReadTransaction) -> String? {
        return pinCode
    }
}

// MARK: - ProfileManager

public class _RegistrationCoordinator_ProfileManagerMock: _RegistrationCoordinator_ProfileManagerShim {

    public init() {}

    public var hasProfileName: Bool = false

    public var localProfileKey: OWSAES256Key = OWSAES256Key()
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

    public var pushToken: String?

    public func requestPushToken() -> Guarantee<String?> {
        return .value(pushToken)
    }
}

// MARK: - Remote Config

public class _RegistrationCoordinator_RemoteConfigMock: _RegistrationCoordinator_RemoteConfigShim {

    public var canReceiveGiftBadges: Bool = true
}

// MARK: - TSAccountManager

public class _RegistrationCoordinator_TSAccountManagerMock: _RegistrationCoordinator_TSAccountManagerShim {

    public init() {}

    public var doesHaveDefinedIsDiscoverableByPhoneNumber = false

    public func hasDefinedIsDiscoverableByPhoneNumber() -> Bool {
        return doesHaveDefinedIsDiscoverableByPhoneNumber
    }

    // These are only used to generate AccountAttributes, their values are irrelevant.

    public func isManualMessageFetchEnabled(_ transaction: SignalServiceKit.DBReadTransaction) -> Bool {
        return false
    }

    public func getOrGenerateRegistrationId(_ transaction: SignalServiceKit.DBWriteTransaction) -> UInt32 {
        return 8
    }

    public func getOrGeneratePniRegistrationId(_ transaction: SignalServiceKit.DBWriteTransaction) -> UInt32 {
        return 9
    }

    public func isDiscoverableByPhoneNumber(_ transaction: SignalServiceKit.DBReadTransaction) -> Bool {
        return true
    }
}

// MARK: UDManager

public class _RegistrationCoordinator_UDManagerMock: _RegistrationCoordinator_UDManagerShim {

    public func shouldAllowUnrestrictedAccessLocal(transaction: DBReadTransaction) -> Bool {
        return true
    }
}
