//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Wraps the stores for 1:1 sessions that use the Signal Protocol (Double Ratchet + X3DH).

public struct SignalProtocolStore {
    public let sessionStore: SignalSessionStore
    public let preKeyStore: PreKeyStoreImpl
    public let signedPreKeyStore: SignedPreKeyStoreImpl
    public let kyberPreKeyStore: KyberPreKeyStoreImpl

    public static func build(
        dateProvider: @escaping DateProvider,
        identity: OWSIdentity,
        recipientIdFinder: RecipientIdFinder,
    ) -> Self {
        return Self(
            sessionStore: SSKSessionStore(for: identity, recipientIdFinder: recipientIdFinder),
            preKeyStore: PreKeyStoreImpl(for: identity),
            signedPreKeyStore: SignedPreKeyStoreImpl(for: identity),
            kyberPreKeyStore: KyberPreKeyStoreImpl(for: identity, dateProvider: dateProvider),
        )
    }
}

/// Wrapper for ACI/PNI protocol stores that can be passed around to dependencies
public struct SignalProtocolStoreManager {
    let aciProtocolStore: SignalProtocolStore
    let pniProtocolStore: SignalProtocolStore

    public func signalProtocolStore(for identity: OWSIdentity) -> SignalProtocolStore {
        switch identity {
        case .aci:
            return aciProtocolStore
        case .pni:
            return pniProtocolStore
        }
    }

    public func removeAllKeys(tx: DBWriteTransaction) {
        for signalProtocolStore in [aciProtocolStore, pniProtocolStore] {
            signalProtocolStore.sessionStore.removeAll(tx: tx)
            signalProtocolStore.preKeyStore.removeAll(tx: tx)
            signalProtocolStore.signedPreKeyStore.removeAll(tx: tx)
            signalProtocolStore.kyberPreKeyStore.removeAll(tx: tx)
        }
    }
}
