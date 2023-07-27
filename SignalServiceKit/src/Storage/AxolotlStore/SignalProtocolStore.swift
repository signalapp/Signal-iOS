//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Wraps the stores for 1:1 sessions that use the Signal Protocol (Double Ratchet + X3DH).

public protocol SignalProtocolStore {
    var sessionStore: SignalSessionStore { get }
    var preKeyStore: SignalPreKeyStore { get }
    var signedPreKeyStore: SignalSignedPreKeyStore { get }
    var kyberPreKeyStore: SignalKyberPreKeyStore { get }
}

public class SignalProtocolStoreImpl: SignalProtocolStore {
    public let sessionStore: SignalSessionStore
    public let preKeyStore: SignalPreKeyStore
    public let signedPreKeyStore: SignalSignedPreKeyStore
    public let kyberPreKeyStore: SignalKyberPreKeyStore

    public init(for identity: OWSIdentity) {
        sessionStore = SSKSessionStore(for: identity)
        preKeyStore = SSKPreKeyStore(for: identity)
        signedPreKeyStore = SSKSignedPreKeyStore(for: identity)
        kyberPreKeyStore = SSKKyberPreKeyStore(for: identity)
    }
}

// MARK: - SignalProtocolStoreManager

/// Wrapper for ACI/PNI protocol stores that can be passed around to dependencies
public protocol SignalProtocolStoreManager {
    func signalProtocolStore(for identity: OWSIdentity) -> SignalProtocolStore
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
}
