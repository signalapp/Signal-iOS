//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// MARK: Shims

extension PreKey.Operation {
    internal enum Shims {
        internal typealias AccountManager = _PreKey_AccountManagerShim
        internal typealias IdentityManager = _PreKey_IdentityManagerShim
        internal typealias MessageProcessor = _PreKey_MessageProcessorShim
    }

    internal enum Wrappers {
        internal typealias AccountManager = _PreKey_AccountManagerWrapper
        internal typealias IdentityManager = _PreKey_IdentityManagerWrapper
        internal typealias MessageProcessor = _PreKey_MessageProcessorWrapper
    }
}

// MARK: - AccountManager Shim

internal protocol _PreKey_AccountManagerShim {
    func isRegisteredAndReady(tx: DBReadTransaction) -> Bool
}

internal class _PreKey_AccountManagerWrapper: _PreKey_AccountManagerShim {
    private let accountManager: TSAccountManager
    init(accountManager: TSAccountManager) {
        self.accountManager = accountManager
    }

    func isRegisteredAndReady(tx: DBReadTransaction) -> Bool {
        return accountManager.isRegisteredAndReady(transaction: SDSDB.shimOnlyBridge(tx))
    }
}

// MARK: - IdentityManager Shim

internal protocol _PreKey_IdentityManagerShim {

    func identityKeyPair(for identity: OWSIdentity, tx: DBReadTransaction) -> ECKeyPair?

    func generateNewIdentityKeyPair() -> ECKeyPair

    func store(
        keyPair: ECKeyPair?,
        for identity: OWSIdentity,
        tx: DBWriteTransaction
    )
}

internal class _PreKey_IdentityManagerWrapper: _PreKey_IdentityManagerShim {
    private let identityManager: OWSIdentityManager
    init(identityManager: OWSIdentityManager) {
        self.identityManager = identityManager
    }

    func identityKeyPair(for identity: OWSIdentity, tx: DBReadTransaction) -> ECKeyPair? {
        identityManager.identityKeyPair(for: identity, transaction: SDSDB.shimOnlyBridge(tx))
    }

    func generateNewIdentityKeyPair() -> ECKeyPair {
        identityManager.generateNewIdentityKeyPair()
    }

    func store(keyPair: ECKeyPair?, for identity: OWSIdentity, tx: DBWriteTransaction) {
        identityManager.storeIdentityKeyPair(
            keyPair,
            for: identity,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }
}

// MARK: - MessageProcessor Shim

internal protocol _PreKey_MessageProcessorShim {
    func fetchingAndProcessingCompletePromise() -> Promise<Void>
}

internal struct _PreKey_MessageProcessorWrapper: _PreKey_MessageProcessorShim {
    private let messageProcessor: MessageProcessor
    init(messageProcessor: MessageProcessor) {
        self.messageProcessor = messageProcessor
    }
    func fetchingAndProcessingCompletePromise() -> Promise<Void> {
        messageProcessor.fetchingAndProcessingCompletePromise()
    }
}
