//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import SignalClient

extension TSMessageDirection {
    fileprivate init(_ direction: Direction) {
        switch direction {
        case .receiving:
            self = .incoming
        case .sending:
            self = .outgoing
        }
    }
}

extension SignalClient.IdentityKey {
    fileprivate func serializeAsData() -> Data {
        return Data(publicKey.keyBytes)
    }
}

extension OWSIdentityManager: SignalClient.IdentityKeyStore {
    public func identityKeyPair(context: UnsafeMutableRawPointer?) throws -> IdentityKeyPair {
        let transaction = context!.load(as: SDSAnyWriteTransaction.self)
        if let keyPair = self.identityKeyPair(with: transaction) {
            return keyPair.identityKeyPair
        }

        let newKeyPair = IdentityKeyPair.generate()
        self.storeIdentityKeyPair(ECKeyPair(newKeyPair), transaction: transaction)
        return newKeyPair
    }

    public func localRegistrationId(context: UnsafeMutableRawPointer?) throws -> UInt32 {
        return UInt32(bitPattern: self.localRegistrationId(with: context!.load(as: SDSAnyWriteTransaction.self)))
    }

    public func saveIdentity(_ identity: SignalClient.IdentityKey,
                             for address: ProtocolAddress,
                             context: UnsafeMutableRawPointer?) throws -> Bool {
        self.saveRemoteIdentity(identity.serializeAsData(),
                                address: SignalServiceAddress(from: address),
                                transaction: context!.load(as: SDSAnyWriteTransaction.self))
    }

    public func isTrustedIdentity(_ identity: SignalClient.IdentityKey,
                                  for address: ProtocolAddress,
                                  direction: Direction,
                                  context: UnsafeMutableRawPointer?) throws -> Bool {
        self.isTrustedIdentityKey(identity.serializeAsData(),
                                  address: SignalServiceAddress(from: address),
                                  direction: TSMessageDirection(direction),
                                  transaction: context!.load(as: SDSAnyReadTransaction.self))
    }

    public func identity(for address: ProtocolAddress, context: UnsafeMutableRawPointer?) throws -> SignalClient.IdentityKey? {
        guard let data = self.identityKey(for: SignalServiceAddress(from: address),
                                          transaction: context!.load(as: SDSAnyReadTransaction.self)) else {
            return nil
        }
        return try SignalClient.IdentityKey(publicKey: ECPublicKey(keyData: data).key)
    }
}
