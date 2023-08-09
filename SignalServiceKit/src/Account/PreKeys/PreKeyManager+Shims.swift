//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension PreKey {
    public enum Manager {
        public enum Shims {
            public typealias TSAccountManager = _PreKeyManager_TSAccountManagerShim
            public typealias MessageProcessor = _PreKeyManager_MessageProcessorShim
        }

        public enum Wrappers {
            public typealias TSAccountManager = _PreKeyManager_TSAccountManagerWrapper
            public typealias MessageProcessor = _PreKeyManager_MessageProcessorWrapper
        }
    }
}

// MARK: - AccountManager

public protocol _PreKeyManager_TSAccountManagerShim {
    func isRegisteredAndReady(tx: DBReadTransaction) -> Bool
}

public class _PreKeyManager_TSAccountManagerWrapper: PreKey.Manager.Shims.TSAccountManager {
    private let accountManager: TSAccountManager
    public init(_ accountManager: TSAccountManager) { self.accountManager = accountManager }

    public func isRegisteredAndReady(tx: DBReadTransaction) -> Bool {
        return accountManager.isRegisteredAndReady(transaction: SDSDB.shimOnlyBridge(tx))
    }
}

// MARK: - MessageProcessor

public protocol _PreKeyManager_MessageProcessorShim {
    func fetchingAndProcessingCompletePromise() -> Promise<Void>
}

public struct _PreKeyManager_MessageProcessorWrapper: PreKey.Manager.Shims.MessageProcessor {
    private let messageProcessor: MessageProcessor
    public init(messageProcessor: MessageProcessor) {
        self.messageProcessor = messageProcessor
    }

    public func fetchingAndProcessingCompletePromise() -> Promise<Void> {
        messageProcessor.fetchingAndProcessingCompletePromise()
    }
}
