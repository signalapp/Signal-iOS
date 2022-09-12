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
    /// Don't trust an identity for sending to unless they've been around for at least this long
    @objc
    public static let minimumUntrustedThreshold: TimeInterval = 5

    @objc
    public static let maximumUntrustedThreshold: TimeInterval = kHourInterval

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

    @objc
    public func checkForPniIdentity() {
        // This entire operation is about old devices coming into a PNI-capable world.
        // Once everybody has a PNI identity key (that won't be reset), this won't be necessary any longer.
        guard tsAccountManager.isRegistered, let pni = tsAccountManager.localPni else {
            return
        }

        guard tsAccountManager.isPrimaryDevice else {
            // Linked devices can ask the primary for the PNI identity key pair if they don't have it.
            if identityKeyPair(for: .pni) == nil {
                syncManager.sendPniIdentitySyncRequestMessage()
            }
            return
        }

        firstly(on: .global()) { () -> Promise<Bool> in
            // If we haven't generated an identity key yet, we should do so now.
            guard let currentPniIdentityKey = self.identityKeyPair(for: .pni) else {
                Logger.info("Creating PNI identity keys for the first time")
                return .value(true)
            }
            // If we have, we still check it against the server, in case the initial upload got interrupted.
            // (But only in the main app.)
            let fetchedProfilePromise = ProfileFetcherJob.fetchProfilePromise(address: SignalServiceAddress(uuid: pni),
                                                                              mainAppOnly: true,
                                                                              ignoreThrottling: true,
                                                                              shouldUpdateStore: false,
                                                                              fetchType: .unversioned)
            return fetchedProfilePromise.map { fetchedProfile in
                // Check that the key is actually up to date.
                if fetchedProfile.profile.identityKey == currentPniIdentityKey.publicKey {
                    Logger.debug("PNI identity key is up to date on the server")
                    return false
                }
                Logger.info("PNI identity key is out of date on the server; re-uploading")
                return true
            }.recover { error -> Promise<Bool> in
                switch error {
                case ParamParser.ParseError.missingField("identityKey"):
                    // The server does not have an identity key for us at all.
                    Logger.info("Server does not have our PNI identity key; uploading now")
                    return .value(true)
                case ProfileFetchError.notMainApp:
                    return .value(false)
                default:
                    throw error
                }
            }
        }.done(on: .global()) { (needsUpdate: Bool) in
            guard needsUpdate else {
                return
            }
            TSPreKeyManager.createPreKeys(for: .pni, success: {
                self.syncManager.sendPniIdentitySyncMessage()
            }, failure: { error in
                owsFailDebug("failed to create PNI identity and pre-keys: \(error)")
            })
        }.catch(on: .global()) { error in
            Logger.warn("failed to check PNI identity key: \(error)")
        }
    }

    // MARK: - Phone number sharing

    private var shareMyPhoneNumberStore: SDSKeyValueStore {
        return SDSKeyValueStore(collection: "OWSIdentityManager.shareMyPhoneNumberStore")
    }

    @objc(shouldSharePhoneNumberWithAddress:transaction:)
    func shouldSharePhoneNumber(with recipient: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Bool {
        guard let recipientUuid = recipient.uuidString else {
            return false
        }
        return shareMyPhoneNumberStore.getBool(recipientUuid, defaultValue: false, transaction: transaction)
    }

    func setShouldSharePhoneNumber(with recipient: SignalServiceAddress, transaction: SDSAnyWriteTransaction) {
        guard let recipientUuid = recipient.uuidString else {
            owsFailDebug("recipient has no UUID, should not be trying to share phone number with them")
            return
        }
        shareMyPhoneNumberStore.setBool(true, key: recipientUuid, transaction: transaction)
    }

    @objc(clearShouldSharePhoneNumberWithAddress:transaction:)
    func clearShouldSharePhoneNumber(with recipient: SignalServiceAddress, transaction: SDSAnyWriteTransaction) {
        guard let recipientUuid = recipient.uuidString else {
            return
        }
        shareMyPhoneNumberStore.removeValue(forKey: recipientUuid, transaction: transaction)
    }

    @objc(clearShouldSharePhoneNumberForEveryoneWithTransaction:)
    public func clearShouldSharePhoneNumberForEveryone(transaction: SDSAnyWriteTransaction) {
        shareMyPhoneNumberStore.removeAll(transaction: transaction)
    }

    // MARK: - Batch Identity Lookup

    @discardableResult
    public func batchUpdateIdentityKeys(addresses: [SignalServiceAddress]) -> Promise<Void> {
        guard !addresses.isEmpty else { return .value(()) }

        let addresses = Set(addresses)
        let batchAddresses = addresses.prefix(OWSRequestFactory.batchIdentityCheckElementsLimit)
        let remainingAddresses = Array(addresses.subtracting(batchAddresses))

        return firstly(on: .global()) { () -> Promise<HTTPResponse> in
            Logger.info("Performing batch identity key lookup for \(batchAddresses.count) addresses. \(remainingAddresses.count) remaining.")

            let elements = self.databaseStorage.read { transaction in
                batchAddresses.compactMap { address -> [String: String]? in
                    guard let uuid = address.uuid else { return nil }
                    guard let identityKey = self.identityKey(for: address, transaction: transaction) else { return nil }

                    let rawIdentityKey = (identityKey as NSData).prependKeyType()
                    guard let identityKeyDigest = Cryptography.computeSHA256Digest(rawIdentityKey as Data) else {
                        owsFailDebug("Failed to calculate SHA-256 digest for batch identity key update")
                        return nil
                    }

                    return ["uuid": uuid.uuidString, "fingerprint": Data(identityKeyDigest.prefix(4)).base64EncodedString()]
                }
            }

            let request = OWSRequestFactory.batchIdentityCheckRequest(elements: elements)

            return self.networkManager.makePromise(request: request)
        }.done(on: .global()) { response in
            guard response.responseStatusCode == 200 else {
                throw OWSAssertionError("Unexpected response from batch identity request \(response.responseStatusCode)")
            }

            guard let json = response.responseBodyJson, let responseDictionary = json as? [String: AnyObject] else {
                throw OWSAssertionError("Missing or invalid JSON")
            }

            guard let responseElements = responseDictionary["elements"] as? [[String: String]], !responseElements.isEmpty else {
                return // No safety number changes
            }

            Logger.info("Detected \(responseElements.count) identity key changes via batch request")

            self.databaseStorage.write { transaction in
                for element in responseElements {
                    guard let uuidString = element["uuid"], let uuid = UUID(uuidString: uuidString) else {
                        owsFailDebug("Invalid uuid in batch identity response")
                        continue
                    }

                    guard let encodedRawIdentityKey = element["identityKey"], let rawIdentityKey = Data(base64Encoded: encodedRawIdentityKey) else {
                        owsFailDebug("Missing identityKey in batch identity response")
                        continue
                    }

                    guard rawIdentityKey.count == kIdentityKeyLength else {
                        owsFailDebug("identityKey with invalid length \(rawIdentityKey.count) in batch identity response")
                        continue
                    }

                    guard let identityKey = try? (rawIdentityKey as NSData).removeKeyType() as Data else {
                        owsFailDebug("Failed to remove type byte from identity key in batch identity response")
                        continue
                    }

                    let address = SignalServiceAddress(uuid: uuid)
                    Logger.info("Identity key changed via batch request for address \(address)")

                    self.saveRemoteIdentity(identityKey, address: address, transaction: transaction)
                }
            }
        }.then { () -> Promise<Void> in
            guard !remainingAddresses.isEmpty else { return .value(()) }
            return self.batchUpdateIdentityKeys(addresses: remainingAddresses)
        }.catch { error in
            owsFailDebug("Batch identity key update failed with error \(error)")
        }
    }
}
