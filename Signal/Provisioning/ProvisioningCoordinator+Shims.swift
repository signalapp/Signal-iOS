//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit

extension ProvisioningCoordinatorImpl {
    public enum Shims {
        public typealias PushRegistrationManager = _ProvisioningCoordinator_PushRegistrationManagerShim
        public typealias ReceiptManager = _ProvisioningCoordinator_ReceiptManagerShim
    }

    public enum Wrappers {
        public typealias PushRegistrationManager = _ProvisioningCoordinator_PushRegistrationManagerWrapper
        public typealias ReceiptManager = _ProvisioningCoordinator_ReceiptManagerWrapper
    }
}

// MARK: PushRegistrationManager

public protocol _ProvisioningCoordinator_PushRegistrationManagerShim {

    typealias ApnRegistrationId = PushRegistrationManager.ApnRegistrationId

    func requestPushTokens(
        forceRotation: Bool,
    ) async throws -> ApnRegistrationId
}

public class _ProvisioningCoordinator_PushRegistrationManagerWrapper: _ProvisioningCoordinator_PushRegistrationManagerShim {

    private let pushRegistrationManager: PushRegistrationManager

    public init(_ pushRegistrationManager: PushRegistrationManager) {
        self.pushRegistrationManager = pushRegistrationManager
    }

    public func requestPushTokens(forceRotation: Bool) async throws -> ApnRegistrationId {
        return try await pushRegistrationManager.requestPushTokens(forceRotation: forceRotation)
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
        receiptManager.setAreReadReceiptsEnabled(areEnabled, transaction: tx)
    }
}
