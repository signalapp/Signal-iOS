//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension EditManagerImpl {
    public enum Shims {
        public typealias ReceiptManager = _EditManagerImpl_ReceiptManagerShim
    }

    public enum Wrappers {
        public typealias ReceiptManager = _EditManagerImpl_ReceiptManagerWrapper
    }
}

// MARK: - OWSReceiptManager

public protocol _EditManagerImpl_ReceiptManagerShim {
    func messageWasRead(
        _ message: TSIncomingMessage,
        thread: TSThread,
        circumstance: OWSReceiptCircumstance,
        tx: DBWriteTransaction,
    )
}

public struct _EditManagerImpl_ReceiptManagerWrapper: EditManagerImpl.Shims.ReceiptManager {

    private let receiptManager: OWSReceiptManager
    public init(receiptManager: OWSReceiptManager) {
        self.receiptManager = receiptManager
    }

    public func messageWasRead(
        _ message: TSIncomingMessage,
        thread: TSThread,
        circumstance: OWSReceiptCircumstance,
        tx: DBWriteTransaction,
    ) {
        receiptManager.messageWasRead(
            message,
            thread: thread,
            circumstance: circumstance,
            transaction: tx,
        )
    }
}
