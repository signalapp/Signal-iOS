//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit

extension ProvisioningManager {
    public enum Shims {
        public typealias ReceiptManager = _ProvisioningManager_ReceiptManagerShim
    }

    public enum Wrappers {
        public typealias ReceiptManager = _ProvisioningManager_ReceiptManagerWrapper
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
        return OWSReceiptManager.areReadReceiptsEnabled(transaction: tx)
    }
}

#if TESTABLE_BUILD
extension ProvisioningManager {
    public enum Mocks {
        public typealias ReceiptManager = _ProvisioningManager_ReceiptManagerMock
    }
}

public class _ProvisioningManager_ReceiptManagerMock: _ProvisioningManager_ReceiptManagerShim {
    public var areReadReceiptsEnabledValue: Bool = true
    public func areReadReceiptsEnabled(tx: DBReadTransaction) -> Bool { areReadReceiptsEnabledValue }
}

#endif
