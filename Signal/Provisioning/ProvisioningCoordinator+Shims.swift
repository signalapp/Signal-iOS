//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit
import SignalMessaging
import SignalServiceKit

extension ProvisioningCoordinatorImpl {
    public enum Shims {
        public typealias MessageFactory = _ProvisioningCoordinator_MessageFactoryShim
        public typealias ProfileManager = _ProvisioningCoordinator_ProfileManagerShim
        public typealias PushRegistrationManager = _ProvisioningCoordinator_PushRegistrationManagerShim
        public typealias ReceiptManager = _ProvisioningCoordinator_ReceiptManagerShim
        public typealias SyncManager = _ProvisioningCoordinator_SyncManagerShim
        public typealias UDManager = _ProvisioningCoordinator_UDManagerShim
    }
    public enum Wrappers {
        public typealias MessageFactory = _ProvisioningCoordinator_MessageFactoryWrapper
        public typealias ProfileManager = _ProvisioningCoordinator_ProfileManagerWrapper
        public typealias PushRegistrationManager = _ProvisioningCoordinator_PushRegistrationManagerWrapper
        public typealias ReceiptManager = _ProvisioningCoordinator_ReceiptManagerWrapper
        public typealias SyncManager = _ProvisioningCoordinator_SyncManagerWrapper
        public typealias UDManager = _ProvisioningCoordinator_UDManagerWrapper
    }
}

// MARK: MessageFactory

public protocol _ProvisioningCoordinator_MessageFactoryShim {

    func insertInfoMessage(
        into thread: TSThread,
        messageType: TSInfoMessageType,
        tx: DBWriteTransaction
    )
}

public class _ProvisioningCoordinator_MessageFactoryWrapper: _ProvisioningCoordinator_MessageFactoryShim {

    public init() {}

    public func insertInfoMessage(
        into thread: TSThread,
        messageType: TSInfoMessageType,
        tx: DBWriteTransaction
    ) {
        let infoMessage = TSInfoMessage(thread: thread, messageType: messageType)
        infoMessage.anyInsert(transaction: SDSDB.shimOnlyBridge(tx))
    }
}

// MARK: ProfileManager

public protocol _ProvisioningCoordinator_ProfileManagerShim {

    func localProfileKey() -> OWSAES256Key

    func setLocalProfileKey(
        _ key: OWSAES256Key,
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
        tx: DBWriteTransaction
    )
}

public class _ProvisioningCoordinator_ProfileManagerWrapper: _ProvisioningCoordinator_ProfileManagerShim {

    private let profileManager: OWSProfileManager

    public init(_ profileManager: OWSProfileManager) {
        self.profileManager = profileManager
    }

    public func localProfileKey() -> OWSAES256Key {
        return profileManager.localProfileKey()
    }

    public func setLocalProfileKey(
        _ key: OWSAES256Key,
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
        tx: DBWriteTransaction
    ) {
        profileManager.setLocalProfileKey(
            key,
            userProfileWriter: userProfileWriter,
            authedAccount: authedAccount,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }
}

// MARK: PushRegistrationManager

public protocol _ProvisioningCoordinator_PushRegistrationManagerShim {

    typealias ApnRegistrationId = PushRegistrationManager.ApnRegistrationId

    func requestPushTokens(
        forceRotation: Bool
    ) async throws -> ApnRegistrationId
}

public class _ProvisioningCoordinator_PushRegistrationManagerWrapper: _ProvisioningCoordinator_PushRegistrationManagerShim {

    private let pushRegistrationManager: PushRegistrationManager

    public init(_ pushRegistrationManager: PushRegistrationManager) {
        self.pushRegistrationManager = pushRegistrationManager
    }

    public func requestPushTokens(forceRotation: Bool) async throws -> ApnRegistrationId {
        return try await pushRegistrationManager.requestPushTokens(forceRotation: forceRotation).awaitable()
    }
}

// MARK: ReceiptManager

public protocol _ProvisioningCoordinator_ReceiptManagerShim {

    func setAreReadReceiptsEnabled(_ areEnabled: Bool, tx: DBWriteTransaction)
}

public class _ProvisioningCoordinator_ReceiptManagerWrapper: _ProvisioningCoordinator_ReceiptManagerShim {

    private let receiptManager: OWSReceiptManager

    public init(_ receiptManager: OWSReceiptManager) {
        self.receiptManager = receiptManager
    }

    public func setAreReadReceiptsEnabled(_ areEnabled: Bool, tx: DBWriteTransaction) {
        receiptManager.setAreReadReceiptsEnabled(areEnabled, transaction: SDSDB.shimOnlyBridge(tx))
    }
}

// MARK: SyncManager

public protocol _ProvisioningCoordinator_SyncManagerShim {

    func sendKeysSyncRequestMessage(tx: DBWriteTransaction)

    func sendInitialSyncRequestsAwaitingCreatedThreadOrdering(
        timeout: TimeInterval
    ) async throws -> [String]
}

public class _ProvisioningCoordinator_SyncManagerWrapper: _ProvisioningCoordinator_SyncManagerShim {

    private let syncManager: OWSSyncManager

    public init(_ syncManager: OWSSyncManager) {
        self.syncManager = syncManager
    }

    public func sendKeysSyncRequestMessage(tx: DBWriteTransaction) {
        syncManager.sendKeysSyncRequestMessage(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func sendInitialSyncRequestsAwaitingCreatedThreadOrdering(
        timeout: TimeInterval
    ) async throws -> [String] {
        return try await syncManager
            .sendInitialSyncRequestsAwaitingCreatedThreadOrdering(
                timeoutSeconds: timeout
            )
            .awaitable()
    }
}

// MARK: - UDManager

public protocol _ProvisioningCoordinator_UDManagerShim {

    func shouldAllowUnrestrictedAccessLocal(tx: DBReadTransaction) -> Bool
}

public class _ProvisioningCoordinator_UDManagerWrapper: _ProvisioningCoordinator_UDManagerShim {

    private let manager: OWSUDManager
    public init(_ manager: OWSUDManager) { self.manager = manager }

    public func shouldAllowUnrestrictedAccessLocal(tx: DBReadTransaction) -> Bool {
        return manager.shouldAllowUnrestrictedAccessLocal(transaction: SDSDB.shimOnlyBridge(tx))
    }
}
