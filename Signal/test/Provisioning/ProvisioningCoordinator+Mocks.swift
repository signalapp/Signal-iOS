//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
@testable public import Signal
@testable public import SignalServiceKit

extension ProvisioningCoordinatorImpl {
    public enum Mocks {
        public typealias PushRegistrationManager = _ProvisioningCoordinator_PushRegistrationManagerMock
        public typealias ReceiptManager = _ProvisioningCoordinator_ReceiptManagerMock
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
