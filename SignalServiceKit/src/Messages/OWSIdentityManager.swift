//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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
        identityManager.saveRemoteIdentity(
            identity.serializeAsData(),
            address: SignalServiceAddress(from: address),
            transaction: context.asTransaction
        )
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

    public func groupContainsUnverifiedMember(_ groupUniqueID: String, transaction: SDSAnyReadTransaction) -> Bool {
        return OWSRecipientIdentity.groupContainsUnverifiedMember(groupUniqueID, transaction: transaction)
    }
}

// MARK: - ObjC shim

extension OWSIdentityManager {
    @objc
    func archiveSessionsForAccountId(_ accountId: String, transaction: SDSAnyWriteTransaction) {
        // PNI TODO: this should end the PNI session if it was sent to our PNI.
        let sessionStore = DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: .aci).sessionStore
        sessionStore.archiveAllSessions(forAccountId: accountId, tx: transaction.asV2Write)
    }
}

// MARK: - Verified

extension OWSIdentityManager {
    @objc
    public func processIncomingVerifiedProto(_ verified: SSKProtoVerified, transaction: SDSAnyWriteTransaction) throws {
        guard let serviceId = UntypedServiceId(uuidString: verified.destinationUuid) else {
            return owsFailDebug("Verification state sync message missing destination.")
        }
        Logger.info("Received verification state message for \(serviceId)")
        guard let rawIdentityKey = verified.identityKey, rawIdentityKey.count == kIdentityKeyLength else {
            return owsFailDebug("Verification state sync message for \(serviceId) with malformed identityKey")
        }
        let identityKey = try rawIdentityKey.removeKeyType()

        switch verified.state {
        case .default:
            applyVerificationState(
                .default,
                serviceId: serviceId,
                identityKey: identityKey,
                overwriteOnConflict: false,
                transaction: transaction
            )
        case .verified:
            applyVerificationState(
                .verified,
                serviceId: serviceId,
                identityKey: identityKey,
                overwriteOnConflict: true,
                transaction: transaction
            )
        case .unverified:
            return owsFailDebug("Verification state sync message for \(serviceId) has unverified state")
        case .none:
            return owsFailDebug("Verification state sync message for \(serviceId) has no state")
        }
    }

    private func applyVerificationState(
        _ verificationState: OWSVerificationState,
        serviceId: UntypedServiceId,
        identityKey: Data,
        overwriteOnConflict: Bool,
        transaction: SDSAnyWriteTransaction
    ) {
        let recipientFetcher = DependenciesBridge.shared.recipientFetcher
        let recipientId = recipientFetcher.fetchOrCreate(serviceId: serviceId, tx: transaction.asV2Write).uniqueId
        var recipientIdentity = OWSRecipientIdentity.anyFetch(uniqueId: recipientId, transaction: transaction)

        let shouldSaveIdentityKey: Bool
        let shouldInsertChangeMessages: Bool

        if let recipientIdentity {
            if recipientIdentity.accountId != recipientId {
                return owsFailDebug("Unexpected recipientId for \(serviceId)")
            }
            let didChangeIdentityKey = recipientIdentity.identityKey != identityKey
            if didChangeIdentityKey, !overwriteOnConflict {
                // The conflict case where we receive a verification sync message whose
                // identity key disagrees with the local identity key for this recipient.
                Logger.warn("Non-matching identityKey for \(serviceId)")
                return
            }
            shouldSaveIdentityKey = didChangeIdentityKey
            shouldInsertChangeMessages = true
        } else {
            if verificationState == .default {
                // There's no point in creating a new recipient identity just to set its
                // verification state to default.
                return
            }
            shouldSaveIdentityKey = true
            shouldInsertChangeMessages = false
        }

        if shouldSaveIdentityKey {
            // Ensure a remote identity exists for this key. We may be learning about
            // it for the first time.
            saveRemoteIdentity(identityKey, address: SignalServiceAddress(serviceId), transaction: transaction)
            recipientIdentity = OWSRecipientIdentity.anyFetch(uniqueId: recipientId, transaction: transaction)
        }

        guard let recipientIdentity else {
            return owsFailDebug("Missing expected identity for \(serviceId)")
        }
        guard recipientIdentity.accountId == recipientId else {
            return owsFailDebug("Unexpected recipientId for \(serviceId)")
        }
        guard recipientIdentity.identityKey == identityKey else {
            return owsFailDebug("Unexpected identityKey for \(serviceId)")
        }

        if recipientIdentity.verificationState == verificationState {
            return
        }

        let oldVerificationState = OWSVerificationStateToString(recipientIdentity.verificationState)
        let newVerificationState = OWSVerificationStateToString(verificationState)
        Logger.info("for \(serviceId): \(oldVerificationState) -> \(newVerificationState)")

        recipientIdentity.update(with: verificationState, transaction: transaction)

        if shouldInsertChangeMessages {
            saveChangeMessages(
                address: SignalServiceAddress(serviceId),
                verificationState: verificationState,
                isLocalChange: false,
                transaction: transaction
            )
        }
    }

    @objc
    func saveChangeMessages(
        address: SignalServiceAddress,
        verificationState: OWSVerificationState,
        isLocalChange: Bool,
        transaction: SDSAnyWriteTransaction
    ) {
        owsAssertDebug(address.isValid)

        var relevantThreads = [TSThread]()
        relevantThreads.append(TSContactThread.getOrCreateThread(withContactAddress: address, transaction: transaction))
        relevantThreads.append(contentsOf: TSGroupThread.groupThreads(with: address, transaction: transaction))

        for thread in relevantThreads {
            OWSVerificationStateChangeMessage(
                thread: thread,
                recipientAddress: address,
                verificationState: verificationState,
                isLocalChange: isLocalChange
            ).anyInsert(transaction: transaction)
        }
    }
}

// MARK: - PNIs

extension OWSIdentityManager {

    @objc
    public func processIncomingPniChangePhoneNumber(
        proto: SSKProtoSyncMessagePniChangeNumber,
        updatedPni updatedPniString: String?,
        transaction: SDSAnyWriteTransaction
    ) {
        guard
            let updatedPniString,
            let updatedPni = UUID(uuidString: updatedPniString)
        else {
            owsFailDebug("Missing or invalid updated PNI string while processing incoming PNI change-number sync message!")
            return
        }

        guard let localAci = tsAccountManager.localUuid(with: transaction) else {
            owsFailDebug("Missing ACI while processing incoming PNI change-number sync message!")
            return
        }

        guard let (
            pniIdentityKeyPair,
            pniSignedPreKey,
            pniRegistrationId,
            newE164
        ) = deserializeIncomingPniChangePhoneNumber(proto: proto) else {
            return
        }

        let pniProtocolStore = DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: .pni)

        // Store in the right places

        storeIdentityKeyPair(
            pniIdentityKeyPair,
            for: .pni,
            transaction: transaction
        )

        pniSignedPreKey.markAsAcceptedByService()
        pniProtocolStore.signedPreKeyStore.storeSignedPreKeyAsAcceptedAndCurrent(
            signedPreKeyId: pniSignedPreKey.id,
            signedPreKeyRecord: pniSignedPreKey,
            tx: transaction.asV2Write
        )

        tsAccountManager.setPniRegistrationId(
            newRegistrationId: pniRegistrationId,
            transaction: transaction
        )

        tsAccountManager.updateLocalPhoneNumber(
            E164ObjC(newE164),
            aci: localAci,
            pni: updatedPni,
            transaction: transaction
        )

        // Clean up thereafter

        // We need to refresh our one-time pre-keys, and should also refresh
        // our signed pre-key so we use the one generated on the primary for as
        // little time as possible.
        TSPreKeyManager.refreshOneTimePreKeys(
            forIdentity: .pni,
            alsoRefreshSignedPreKey: true
        )
    }

    private func deserializeIncomingPniChangePhoneNumber(
        proto: SSKProtoSyncMessagePniChangeNumber
    ) -> (ECKeyPair, SignalServiceKit.SignedPreKeyRecord, UInt32, E164)? {
        guard
            let pniIdentityKeyPairData = proto.identityKeyPair,
            let pniSignedPreKeyData = proto.signedPreKey,
            proto.hasRegistrationID, proto.registrationID > 0,
            let newE164 = E164(proto.newE164)
        else {
            owsFailDebug("Invalid PNI change number proto, missing fields!")
            return nil
        }

        do {
            let pniIdentityKeyPair = ECKeyPair(try IdentityKeyPair(bytes: pniIdentityKeyPairData))
            let pniSignedPreKey = try LibSignalClient.SignedPreKeyRecord(bytes: pniSignedPreKeyData).asSSKRecord()
            let pniRegistrationId = proto.registrationID

            return (
                pniIdentityKeyPair,
                pniSignedPreKey,
                pniRegistrationId,
                newE164
            )
        } catch let error {
            owsFailDebug("Error while deserializing PNI change-number proto: \(error)")
            return nil
        }
    }

    // MARK: - Phone number sharing

    private var shareMyPhoneNumberStore: SDSKeyValueStore {
        return SDSKeyValueStore(collection: "OWSIdentityManager.shareMyPhoneNumberStore")
    }

    @objc(shouldSharePhoneNumberWithAddress:transaction:)
    func shouldSharePhoneNumber(with recipient: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Bool {
        guard let serviceId = recipient.untypedServiceId else {
            return false
        }
        return shouldSharePhoneNumber(with: serviceId, transaction: transaction)
    }

    func shouldSharePhoneNumber(with serviceId: UntypedServiceId, transaction: SDSAnyReadTransaction) -> Bool {
        let uuidString = serviceId.uuidValue.uuidString
        return shareMyPhoneNumberStore.getBool(uuidString, defaultValue: false, transaction: transaction)
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
}

// MARK: - Batch Identity Lookup

extension OWSIdentityManager {

    @discardableResult
    public func batchUpdateIdentityKeys(addresses: [SignalServiceAddress]) -> Promise<Void> {
        guard !addresses.isEmpty else { return .value(()) }

        let addresses = Set(addresses)
        let batchAddresses = addresses.prefix(OWSRequestFactory.batchIdentityCheckElementsLimit)
        let remainingAddresses = Array(addresses.subtracting(batchAddresses))

        return firstly(on: DispatchQueue.global()) { () -> Promise<HTTPResponse> in
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
        }.done(on: DispatchQueue.global()) { response in
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

                    self.saveRemoteIdentity(
                        identityKey,
                        address: address,
                        transaction: transaction
                    )
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
