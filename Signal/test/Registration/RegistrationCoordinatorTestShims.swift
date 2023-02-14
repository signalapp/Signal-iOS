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
        public typealias TSAccountManager = _RegistrationCoordinator_TSAccountManagerMock
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
}

// MARK: - ProfileManager

public class _RegistrationCoordinator_ProfileManagerMock: _RegistrationCoordinator_ProfileManagerShim {

    public init() {}

    public var hasProfileName: Bool = false
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

// MARK: - TSAccountManager

public class _RegistrationCoordinator_TSAccountManagerMock: _RegistrationCoordinator_TSAccountManagerShim {

    public init() {}

    public var doesHaveDefinedIsDiscoverableByPhoneNumber = false

    public func hasDefinedIsDiscoverableByPhoneNumber() -> Bool {
        return doesHaveDefinedIsDiscoverableByPhoneNumber
    }
}
