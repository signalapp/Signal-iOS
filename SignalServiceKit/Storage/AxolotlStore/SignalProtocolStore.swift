//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Wraps the stores for 1:1 sessions that use the Signal Protocol (Double Ratchet + X3DH).

public protocol SignalProtocolStore {
    var sessionStore: SignalSessionStore { get }
    var preKeyStore: PreKeyStoreImpl { get }
    var signedPreKeyStore: SignedPreKeyStoreImpl { get }
    var kyberPreKeyStore: KyberPreKeyStoreImpl { get }
}

final public class SignalProtocolStoreImpl: SignalProtocolStore {
    public let sessionStore: SignalSessionStore
    public let preKeyStore: PreKeyStoreImpl
    public let signedPreKeyStore: SignedPreKeyStoreImpl
    public let kyberPreKeyStore: KyberPreKeyStoreImpl

    public init(
        for identity: OWSIdentity,
        recipientIdFinder: RecipientIdFinder,
    ) {
        sessionStore = SSKSessionStore(
            for: identity,
            recipientIdFinder: recipientIdFinder
        )
        preKeyStore = PreKeyStoreImpl(for: identity)
        signedPreKeyStore = SignedPreKeyStoreImpl(for: identity)
        kyberPreKeyStore = KyberPreKeyStoreImpl(
            for: identity,
            dateProvider: Date.provider,
        )
    }
}

// MARK: - SignalProtocolStoreManager

/// Wrapper for ACI/PNI protocol stores that can be passed around to dependencies
public protocol SignalProtocolStoreManager {
    func signalProtocolStore(for identity: OWSIdentity) -> SignalProtocolStore

    func removeAllKeys(tx: DBWriteTransaction)
}

public struct SignalProtocolStoreManagerImpl: SignalProtocolStoreManager {
    private let aciProtocolStore: SignalProtocolStore
    private let pniProtocolStore: SignalProtocolStore
    public init(
        aciProtocolStore: SignalProtocolStore,
        pniProtocolStore: SignalProtocolStore
    ) {
        self.aciProtocolStore = aciProtocolStore
        self.pniProtocolStore = pniProtocolStore
    }

    public func signalProtocolStore(for identity: OWSIdentity) -> SignalProtocolStore {
        switch identity {
        case .aci:
            return aciProtocolStore
        case .pni:
            return pniProtocolStore
        }
    }

    public func removeAllKeys(tx: DBWriteTransaction) {
        for identity in [OWSIdentity.aci, OWSIdentity.pni] {
            let signalProtocolStore = self.signalProtocolStore(for: identity)
            signalProtocolStore.sessionStore.removeAll(tx: tx)
            signalProtocolStore.preKeyStore.removeAll(tx: tx)
            signalProtocolStore.signedPreKeyStore.removeAll(tx: tx)
            signalProtocolStore.kyberPreKeyStore.removeAll(tx: tx)
        }
    }
}
