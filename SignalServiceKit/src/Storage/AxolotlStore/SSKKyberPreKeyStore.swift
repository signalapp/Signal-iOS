//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public protocol SignalKyberPreKeyStore: LibSignalClient.KyberPreKeyStore {
}

public class SSKKyberPreKeyStore {
    let identity: OWSIdentity

    public init(for identity: OWSIdentity) {
        self.identity = identity
    }
}

extension SSKKyberPreKeyStore: SignalKyberPreKeyStore {

    public func loadKyberPreKey(id: UInt32, context: StoreContext) throws -> KyberPreKeyRecord {
        preconditionFailure("unimplemented")
    }

    public func storeKyberPreKey(_ record: KyberPreKeyRecord, id: UInt32, context: StoreContext) throws {
        preconditionFailure("unimplemented")
    }

    public func markKyberPreKeyUsed(id: UInt32, context: StoreContext) throws {
        preconditionFailure("unimplemented")
    }
}
