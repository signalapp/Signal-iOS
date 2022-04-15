//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import LibSignalClient

extension OWSIdentity: CustomStringConvertible {
    public var description: String {
        switch self {
        case .aci:
            return "ACI"
        case .pni:
            return "PNI"
        }
    }
}

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

extension LibSignalClient.IdentityKey {
    fileprivate func serializeAsData() -> Data {
        return Data(publicKey.keyBytes)
    }
}

public class IdentityStore: IdentityKeyStore {
    public let identityManager: OWSIdentityManager
    public let identityKeyPair: IdentityKeyPair

    fileprivate init(identityManager: OWSIdentityManager, identityKeyPair: IdentityKeyPair) {
        self.identityManager = identityManager
        self.identityKeyPair = identityKeyPair
    }

    public func identityKeyPair(context: StoreContext) throws -> IdentityKeyPair {
        return identityKeyPair
    }

    public func localRegistrationId(context: StoreContext) throws -> UInt32 {
        return UInt32(bitPattern: identityManager.localRegistrationId(with: context.asTransaction))
    }

    public func saveIdentity(_ identity: LibSignalClient.IdentityKey,
                             for address: ProtocolAddress,
                             context: StoreContext) throws -> Bool {
        identityManager.saveRemoteIdentity(identity.serializeAsData(),
                                           address: SignalServiceAddress(from: address),
                                           transaction: context.asTransaction)
    }

    public func isTrustedIdentity(_ identity: LibSignalClient.IdentityKey,
                                  for address: ProtocolAddress,
                                  direction: Direction,
                                  context: StoreContext) throws -> Bool {
        identityManager.isTrustedIdentityKey(identity.serializeAsData(),
                                             address: SignalServiceAddress(from: address),
                                             direction: TSMessageDirection(direction),
                                             transaction: context.asTransaction)
    }

    public func identity(for address: ProtocolAddress, context: StoreContext) throws -> LibSignalClient.IdentityKey? {
        guard let data = identityManager.identityKey(for: SignalServiceAddress(from: address),
                                                     transaction: context.asTransaction) else {
            return nil
        }
        return try LibSignalClient.IdentityKey(publicKey: ECPublicKey(keyData: data).key)
    }
}

extension OWSIdentityManager {
    public func store(for identity: OWSIdentity, transaction: SDSAnyReadTransaction) throws -> IdentityStore {
        guard let identityKeyPair = self.identityKeyPair(for: identity, transaction: transaction) else {
            throw OWSAssertionError("no identity key pair for \(identity)")
        }
        return IdentityStore(identityManager: self, identityKeyPair: identityKeyPair.identityKeyPair)
    }

    @objc
    public func groupContainsUnverifiedMember(_ groupUniqueID: String,
                                              transaction: SDSAnyReadTransaction) -> Bool {
        return OWSRecipientIdentity.groupContainsUnverifiedMember(groupUniqueID, transaction: transaction)
    }

    @objc
    public func processIncomingPniIdentityProto(_ pniIdentity: SSKProtoSyncMessagePniIdentity,
                                                transaction: SDSAnyWriteTransaction) {
        do {
            guard let publicKeyData = pniIdentity.publicKey, let privateKeyData = pniIdentity.privateKey else {
                throw OWSAssertionError("missing key data in PniIdentity message")
            }
            let publicKey = try PublicKey(publicKeyData)

            let previousKeyPair = identityKeyPair(for: .pni, transaction: transaction)
            guard previousKeyPair?.identityKeyPair.publicKey != publicKey else {
                // The identity key didn't change; we don't need to do anything.
                return
            }

            let privateKey = try PrivateKey(privateKeyData)
            let keyPair = ECKeyPair(IdentityKeyPair(publicKey: publicKey, privateKey: privateKey))
            storeIdentityKeyPair(keyPair, for: .pni, transaction: transaction)
            TSPreKeyManager.createPreKeys(for: .pni, success: {}, failure: { error in
                owsFailDebug("Failed to create PNI pre-keys after receiving PniIdentity sync message: \(error)")
            })
        } catch {
            owsFailDebug("Invalid PNI identity data: \(error)")
        }
    }
}
