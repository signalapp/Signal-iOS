//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
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

// PNI TODO: Maybe have a wrapper around OWSIdentityManager to change the behavior of identityKeyPair(context:)?
extension OWSIdentityManager: IdentityKeyStore {
    public func identityKeyPair(context: StoreContext) throws -> IdentityKeyPair {
        let transaction = context.asTransaction
        if let keyPair = self.identityKeyPair(for: .aci, transaction: transaction) {
            return keyPair.identityKeyPair
        }

        let newKeyPair = IdentityKeyPair.generate()
        self.storeIdentityKeyPair(ECKeyPair(newKeyPair), for: .aci, transaction: transaction)
        return newKeyPair
    }

    public func localRegistrationId(context: StoreContext) throws -> UInt32 {
        return UInt32(bitPattern: self.localRegistrationId(with: context.asTransaction))
    }

    public func saveIdentity(_ identity: SignalClient.IdentityKey,
                             for address: ProtocolAddress,
                             context: StoreContext) throws -> Bool {
        self.saveRemoteIdentity(identity.serializeAsData(),
                                address: SignalServiceAddress(from: address),
                                transaction: context.asTransaction)
    }

    public func isTrustedIdentity(_ identity: SignalClient.IdentityKey,
                                  for address: ProtocolAddress,
                                  direction: Direction,
                                  context: StoreContext) throws -> Bool {
        self.isTrustedIdentityKey(identity.serializeAsData(),
                                  address: SignalServiceAddress(from: address),
                                  direction: TSMessageDirection(direction),
                                  transaction: context.asTransaction)
    }

    public func identity(for address: ProtocolAddress, context: StoreContext) throws -> SignalClient.IdentityKey? {
        guard let data = self.identityKey(for: SignalServiceAddress(from: address),
                                          transaction: context.asTransaction) else {
            return nil
        }
        return try SignalClient.IdentityKey(publicKey: ECPublicKey(keyData: data).key)
    }

    @objc
    public func groupContainsUnverifiedMember(_ groupUniqueID: String,
                                              transaction: SDSAnyReadTransaction) -> Bool {
        return OWSRecipientIdentity.groupContainsUnverifiedMember(groupUniqueID, transaction: transaction)
    }
}
