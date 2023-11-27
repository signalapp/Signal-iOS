//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit
@testable import SignalServiceKit
@testable import Signal

extension RegistrationCoordinatorImpl {

    public enum TestMocks {
        public typealias ContactsManager = _RegistrationCoordinator_ContactsManagerMock
        public typealias ContactsStore = _RegistrationCoordinator_CNContactsStoreMock
        public typealias ExperienceManager = _RegistrationCoordinator_ExperienceManagerMock
        public typealias MessagePipelineSupervisor = _RegistrationCoordinator_MessagePipelineSupervisorMock
        public typealias MessageProcessor = _RegistrationCoordinator_MessageProcessorMock
        public typealias OWS2FAManager = _RegistrationCoordinator_OWS2FAManagerMock
        public typealias PreKeyManager = _RegistrationCoordinator_PreKeyManagerMock
        public typealias ProfileManager = _RegistrationCoordinator_ProfileManagerMock
        public typealias PushRegistrationManager = _RegistrationCoordinator_PushRegistrationManagerMock
        public typealias ReceiptManager = _RegistrationCoordinator_ReceiptManagerMock
        public typealias UDManager = _RegistrationCoordinator_UDManagerMock
    }
}

// MARK: - ContactsManager

public class _RegistrationCoordinator_ContactsManagerMock: _RegistrationCoordinator_ContactsManagerShim {

    public init() {}

    public func fetchSystemContactsOnceIfAlreadyAuthorized() {
        // TODO[Registration]: test that this gets called.
    }

    public func setIsPrimaryDevice() {
        // TODO[Registration]: test that this gets called.
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

// MARK: - MessagePipelineSupervisor

public class _RegistrationCoordinator_MessagePipelineSupervisorMock: _RegistrationCoordinator_MessagePipelineSupervisorShim {

    public init() {}

    public var suspensions = Set<MessagePipelineSupervisor.Suspension>()

    public func suspendMessageProcessingWithoutHandle(for suspension: MessagePipelineSupervisor.Suspension) {
        suspensions.insert(suspension)
    }

    public func unsuspendMessageProcessing(for suspension: MessagePipelineSupervisor.Suspension) {
        suspensions.remove(suspension)
    }
}

// MARK: - MessageProcessor

public class _RegistrationCoordinator_MessageProcessorMock: _RegistrationCoordinator_MessageProcessorShim {

    public init() {}

    public var waitForProcessingCompleteAndThenSuspendMock: (() -> Guarantee<Void>)?

    public func waitForProcessingCompleteAndThenSuspend(for suspension: MessagePipelineSupervisor.Suspension) -> Guarantee<Void> {
        return waitForProcessingCompleteAndThenSuspendMock!()
    }
}

// MARK: - OWS2FAManager

public class _RegistrationCoordinator_OWS2FAManagerMock: _RegistrationCoordinator_OWS2FAManagerShim {

    public init() {}

    public var pinCodeMock: (() -> String?)?

    public func pinCode(_ tx: SignalServiceKit.DBReadTransaction) -> String? {
        return pinCodeMock!()
    }

    public var clearLocalPinCodeMock: (() -> Void)?

    public func clearLocalPinCode(_ tx: SignalServiceKit.DBWriteTransaction) {
        clearLocalPinCodeMock?()
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

// MARK: - PreKeyManager

public class _RegistrationCoordinator_PreKeyManagerMock: MockPreKeyManager {
    public var createPreKeysMock: (() -> Promise<RegistrationPreKeyUploadBundles>)?

    override public func createPreKeysForRegistration() -> Promise<RegistrationPreKeyUploadBundles> {
        return createPreKeysMock!()
    }

    public var finalizePreKeysMock: ((_ didSucceed: Bool) -> Promise<Void>)?

    override public func finalizeRegistrationPreKeys(_ bundles: RegistrationPreKeyUploadBundles, uploadDidSucceed: Bool) -> Promise<Void> {
        return finalizePreKeysMock!(uploadDidSucceed)
    }

    public var rotateOneTimePreKeysMock: ((ChatServiceAuth) -> Promise<Void>)?

    override public func rotateOneTimePreKeysForRegistration(auth: ChatServiceAuth) -> Promise<Void> {
        return rotateOneTimePreKeysMock!(auth)
    }
}

// MARK: - ProfileManager

public class _RegistrationCoordinator_ProfileManagerMock: _RegistrationCoordinator_ProfileManagerShim {

    public init() {}

    public var hasProfileNameMock: () -> Bool = { false }

    public var hasProfileName: Bool { return hasProfileNameMock() }

    public var localProfileKeyMock: () -> OWSAES256Key = { OWSAES256Key() }

    public var localProfileKey: OWSAES256Key { return localProfileKeyMock() }

    public var updateLocalProfileMock: ((
        _ givenName: String,
        _ familyName: String?,
        _ avatarData: Data?,
        _ authedAccount: AuthedAccount
    ) -> Promise<Void>)?

    public func updateLocalProfile(
        givenName: String,
        familyName: String?,
        avatarData: Data?,
        authedAccount: AuthedAccount
    ) -> Promise<Void> {
        return updateLocalProfileMock!(givenName, familyName, avatarData, authedAccount)
    }

    public var didScheduleReuploadLocalProfile = false

    public func scheduleReuploadLocalProfile(authedAccount: AuthedAccount) {
        didScheduleReuploadLocalProfile = true
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

    public var requestPushTokenMock: (() -> Guarantee<Registration.RequestPushTokensResult>)?

    public func requestPushToken() -> Guarantee<Registration.RequestPushTokensResult> {
        return requestPushTokenMock!()
    }

    public var receivePreAuthChallengeTokenMock: (() -> Guarantee<String>)!

    public func receivePreAuthChallengeToken() -> Guarantee<String> {
        return receivePreAuthChallengeTokenMock!()
    }

    public var didClearPreAuthChallengeToken = false

    public func clearPreAuthChallengeToken() {
        didClearPreAuthChallengeToken = true
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

// MARK: UDManager

public class _RegistrationCoordinator_UDManagerMock: _RegistrationCoordinator_UDManagerShim {

    public init() {}

    public var shouldAllowUnrestrictedAccessLocalMock: (() -> Bool) = { true }

    public func shouldAllowUnrestrictedAccessLocal(transaction: DBReadTransaction) -> Bool {
        return shouldAllowUnrestrictedAccessLocalMock()
    }
}
