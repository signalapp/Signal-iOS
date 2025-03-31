//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit

extension ProvisioningManager {
    public enum Shims {
        public typealias ReceiptManager = _ProvisioningManager_ReceiptManagerShim
        public typealias ProfileManager = _ProvisioningManager_ProfileManagerShim
    }

    public enum Wrappers {
        public typealias ReceiptManager = _ProvisioningManager_ReceiptManagerWrapper
        public typealias ProfileManager = _ProvisioningManager_ProfileManagerWrapper
    }
}

public protocol _ProvisioningManager_ReceiptManagerShim {
    func areReadReceiptsEnabled(tx: DBReadTransaction) -> Bool
}

public class _ProvisioningManager_ReceiptManagerWrapper: _ProvisioningManager_ReceiptManagerShim {
    private let receiptManager: OWSReceiptManager

    public init(_ receiptManager: OWSReceiptManager) {
        self.receiptManager = receiptManager
    }

    public func areReadReceiptsEnabled(tx: DBReadTransaction) -> Bool {
        return OWSReceiptManager.areReadReceiptsEnabled(transaction: SDSDB.shimOnlyBridge(tx))
    }
}

public protocol _ProvisioningManager_ProfileManagerShim {
    func localUserProfile(tx: DBReadTransaction) -> OWSUserProfile?
}

public class _ProvisioningManager_ProfileManagerWrapper: _ProvisioningManager_ProfileManagerShim {
    private let profileManager: ProfileManagerProtocol

    public init(_ profileManager: ProfileManagerProtocol) {
        self.profileManager = profileManager
    }

    public func localUserProfile(tx: DBReadTransaction) -> OWSUserProfile? {
        return profileManager.localUserProfile(tx: SDSDB.shimOnlyBridge(tx))
    }
}

#if TESTABLE_BUILD
extension ProvisioningManager {
    public enum Mocks {
        public typealias ReceiptManager = _ProvisioningManager_ReceiptManagerMock
        public typealias ProfileManager = _ProvisioningManager_ProfileManagerMock
    }
}

public class _ProvisioningManager_ReceiptManagerMock: _ProvisioningManager_ReceiptManagerShim {
    public var areReadReceiptsEnabledValue: Bool = true
    public func areReadReceiptsEnabled(tx: DBReadTransaction) -> Bool { areReadReceiptsEnabledValue }
}

public class _ProvisioningManager_ProfileManagerMock: _ProvisioningManager_ProfileManagerShim {
    public var localUserProfile: OWSUserProfile?
    public func localUserProfile(tx: DBReadTransaction) -> OWSUserProfile? { localUserProfile }
}

#endif
