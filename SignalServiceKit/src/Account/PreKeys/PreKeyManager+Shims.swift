//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension PreKey {
    public enum Manager {
        public enum Shims {
            public typealias IdentityManager = _PreKeyManager_IdentityManagerShim
            public typealias MessageProcessor = _PreKeyManager_MessageProcessorShim
        }

        public enum Wrappers {
            public typealias IdentityManager = _PreKeyManager_IdentityManagerWrapper
            public typealias MessageProcessor = _PreKeyManager_MessageProcessorWrapper
        }
    }
}

// MARK: - IdentityManager

public protocol _PreKeyManager_IdentityManagerShim {

    func identityKeyPair(for identity: OWSIdentity, tx: DBReadTransaction) -> ECKeyPair?
}

public class _PreKeyManager_IdentityManagerWrapper: _PreKeyManager_IdentityManagerShim {
    private let identityManager: OWSIdentityManager
    init(_ identityManager: OWSIdentityManager) {
        self.identityManager = identityManager
    }

    public func identityKeyPair(for identity: OWSIdentity, tx: DBReadTransaction) -> ECKeyPair? {
        identityManager.identityKeyPair(for: identity, tx: tx)
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
        messageProcessor.fetchingAndProcessingCompletePromise(
            suspensionBehavior: .onlyWaitIfAlreadyInProgress
        )
    }
}
