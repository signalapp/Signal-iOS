//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
@testable import Signal
@testable import SignalCoreKit
@testable import SignalServiceKit

extension ProvisioningCoordinatorImpl {
    public enum Mocks {
        public typealias MessageFactory = _ProvisioningCoordinator_MessageFactoryMock
        public typealias ProfileManager = _ProvisioningCoordinator_ProfileManagerMock
        public typealias PushRegistrationManager = _ProvisioningCoordinator_PushRegistrationManagerMock
        public typealias ReceiptManager = _ProvisioningCoordinator_ReceiptManagerMock
        public typealias SyncManager = _ProvisioningCoordinator_SyncManagerMock
        public typealias UDManager = _ProvisioningCoordinator_UDManagerMock
    }
}

// MARK: MessageFactory

public class _ProvisioningCoordinator_MessageFactoryMock: _ProvisioningCoordinator_MessageFactoryShim {

    public init() {}

    private var insertedMessageCount = 0

    public func insertInfoMessage(
        into thread: TSThread,
        messageType: TSInfoMessageType,
        tx: DBWriteTransaction
    ) {
        insertedMessageCount += 1
    }
}

// MARK: ProfileManager

public class _ProvisioningCoordinator_ProfileManagerMock: _ProvisioningCoordinator_ProfileManagerShim {

    public init() {}

    public var localProfileKeyMock: OWSAES256Key?

    public func localProfileKey() -> OWSAES256Key {
        return localProfileKeyMock!
    }

    public func setLocalProfileKey(
        _ key: OWSAES256Key,
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
        tx: DBWriteTransaction
    ) {
        self.localProfileKeyMock = key
    }
}

// MARK: PushRegistrationManager

public class _ProvisioningCoordinator_PushRegistrationManagerMock: _ProvisioningCoordinator_PushRegistrationManagerShim {

    public init() {}

    public var mockRegistrationId: ApnRegistrationId?

    public func requestPushTokens(forceRotation: Bool) async throws -> ApnRegistrationId {
        return mockRegistrationId!
    }
}

// MARK: ReceiptManager

public class _ProvisioningCoordinator_ReceiptManagerMock: _ProvisioningCoordinator_ReceiptManagerShim {

    public init() {}

    public var areReadReceiptsEnabled: Bool?

    public func setAreReadReceiptsEnabled(_ areEnabled: Bool, tx: DBWriteTransaction) {
        areReadReceiptsEnabled = areEnabled
    }
}

// MARK: SyncManager

public class _ProvisioningCoordinator_SyncManagerMock: _ProvisioningCoordinator_SyncManagerShim {

    public init() {}

    public var sendKeysSyncMessageMock: (() -> Void)?

    public func sendKeysSyncRequestMessage(tx: DBWriteTransaction) {
        sendKeysSyncMessageMock!()
    }

    public func sendInitialSyncRequestsAwaitingCreatedThreadOrdering(
        timeout: TimeInterval
    ) async throws -> [String] {
        return []
    }
}

// MARK: UDManager

public class _ProvisioningCoordinator_UDManagerMock: _ProvisioningCoordinator_UDManagerShim {

    public init() {}

    public func shouldAllowUnrestrictedAccessLocal(tx: DBReadTransaction) -> Bool {
        return true
    }
}
