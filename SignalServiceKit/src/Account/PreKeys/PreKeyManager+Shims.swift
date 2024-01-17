//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

extension PreKey {
    public enum Shims {
        public typealias IdentityManager = _PreKeyManager_IdentityManagerShim
        public typealias MessageProcessor = _PreKeyManager_MessageProcessorShim
    }

    public enum Wrappers {
        public typealias IdentityManager = _PreKeyManager_IdentityManagerWrapper
        public typealias MessageProcessor = _PreKeyManager_MessageProcessorWrapper
    }
}

// MARK: - IdentityManager

public protocol _PreKeyManager_IdentityManagerShim {

    func identityKeyPair(for identity: OWSIdentity, tx: DBReadTransaction) -> ECKeyPair?

    func generateNewIdentityKeyPair() -> ECKeyPair

    func store(
        keyPair: ECKeyPair?,
        for identity: OWSIdentity,
        tx: DBWriteTransaction
    )
}

public class _PreKeyManager_IdentityManagerWrapper: _PreKeyManager_IdentityManagerShim {
    private let identityManager: OWSIdentityManager
    init(_ identityManager: OWSIdentityManager) {
        self.identityManager = identityManager
    }

    public func identityKeyPair(for identity: OWSIdentity, tx: DBReadTransaction) -> ECKeyPair? {
        identityManager.identityKeyPair(for: identity, tx: tx)
    }

    public func generateNewIdentityKeyPair() -> ECKeyPair {
        identityManager.generateNewIdentityKeyPair()
    }

    public func store(keyPair: ECKeyPair?, for identity: OWSIdentity, tx: DBWriteTransaction) {
        identityManager.setIdentityKeyPair(keyPair, for: identity, tx: tx)
    }
}

// MARK: - MessageProcessor

public protocol _PreKeyManager_MessageProcessorShim {
    func waitForFetchingAndProcessing() -> Guarantee<Void>
}

public struct _PreKeyManager_MessageProcessorWrapper: PreKey.Shims.MessageProcessor {
    private let messageProcessor: MessageProcessor
    public init(messageProcessor: MessageProcessor) {
        self.messageProcessor = messageProcessor
    }

    public func waitForFetchingAndProcessing() -> Guarantee<Void> {
        messageProcessor.waitForFetchingAndProcessing(
            suspensionBehavior: .onlyWaitIfAlreadyInProgress
        )
    }
}
