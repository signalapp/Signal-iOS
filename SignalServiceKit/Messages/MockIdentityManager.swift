//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

#if TESTABLE_BUILD

open class MockIdentityManager: OWSIdentityManager {
    private let recipientIdFinder: RecipientIdFinder

    init(recipientIdFinder: RecipientIdFinder) {
        self.recipientIdFinder = recipientIdFinder
    }

    var recipientIdentities: [RecipientUniqueId: OWSRecipientIdentity]!

    open func recipientIdentity(for recipientUniqueId: RecipientUniqueId, tx: DBReadTransaction) -> OWSRecipientIdentity? {
        return recipientIdentities[recipientUniqueId]
    }

    open func removeRecipientIdentity(for recipientUniqueId: RecipientUniqueId, tx: DBWriteTransaction) {
        recipientIdentities[recipientUniqueId] = nil
    }

    open func identityKey(for serviceId: ServiceId, tx: DBReadTransaction) throws -> IdentityKey? {
        guard let recipientUniqueId = try recipientIdFinder.recipientUniqueId(for: serviceId, tx: tx)?.get() else { return nil }
        guard let recipientIdentity = recipientIdentities[recipientUniqueId] else { return nil }
        return try IdentityKey(publicKey: PublicKey(keyData: recipientIdentity.identityKey))
    }

    var identityChangeInfoMessages: [ServiceId]!
    open func insertIdentityChangeInfoMessage(for serviceId: ServiceId, wasIdentityVerified: Bool, tx: DBWriteTransaction) {
        identityChangeInfoMessages.append(serviceId)
    }

    var sessionSwitchoverMessages: [(SignalRecipient, phoneNumber: String?)]!
    open func insertSessionSwitchoverEvent(for recipient: SignalRecipient, phoneNumber: String?, tx: DBWriteTransaction) {
        sessionSwitchoverMessages.append((recipient, phoneNumber))
    }

    open func mergeRecipient(_ recipient: SignalRecipient, into targetRecipient: SignalRecipient, tx: DBWriteTransaction) {
        guard let fromValue = recipientIdentities[recipient.uniqueId] else {
            return
        }
        if recipientIdentities[targetRecipient.uniqueId] == nil {
            recipientIdentities[targetRecipient.uniqueId] = OWSRecipientIdentity(
                recipientUniqueId: targetRecipient.uniqueId,
                identityKey: fromValue.identityKey,
                isFirstKnownKey: fromValue.isFirstKnownKey,
                createdAt: fromValue.createdAt,
                verificationState: fromValue.verificationState
            )
        }
        recipientIdentities[recipient.uniqueId] = nil
    }

    open func libSignalStore(for identity: OWSIdentity, tx: DBReadTransaction) throws -> IdentityStore { fatalError() }
    open func groupContainsUnverifiedMember(_ groupUniqueID: String, tx: DBReadTransaction) -> Bool { fatalError() }
    open func recipientIdentity(for address: SignalServiceAddress, tx: DBReadTransaction) -> OWSRecipientIdentity? { fatalError() }
    open func fireIdentityStateChangeNotification(after tx: DBWriteTransaction) { fatalError() }
    var identityKeyPairs = [OWSIdentity: ECKeyPair]()
    open func identityKeyPair(for identity: OWSIdentity, tx: DBReadTransaction) -> ECKeyPair? {
        return identityKeyPairs[identity]
    }
    open func setIdentityKeyPair(_ keyPair: ECKeyPair?, for identity: OWSIdentity, tx: DBWriteTransaction) {
        identityKeyPairs[identity] = keyPair
    }
    open func identityKey(for address: SignalServiceAddress, tx: DBReadTransaction) -> Data? { fatalError() }
    open func saveIdentityKey(_ identityKey: Data, for serviceId: ServiceId, tx: DBWriteTransaction) -> Result<Bool, RecipientIdError> { fatalError() }
    open func untrustedIdentityForSending(to address: SignalServiceAddress, untrustedThreshold: Date?, tx: DBReadTransaction) -> OWSRecipientIdentity? { fatalError() }
    open func tryToSyncQueuedVerificationStates() { fatalError() }
    open func verificationState(for address: SignalServiceAddress, tx: DBReadTransaction) -> VerificationState { fatalError() }
    open func setVerificationState(_ verificationState: VerificationState, of identityKey: Data, for address: SignalServiceAddress, isUserInitiatedChange: Bool, tx: DBWriteTransaction) -> ChangeVerificationStateResult { fatalError() }
    open func processIncomingVerifiedProto(_ verified: SSKProtoVerified, tx: DBWriteTransaction) throws { fatalError() }
    open func processIncomingPniChangePhoneNumber(proto: SSKProtoSyncMessagePniChangeNumber, updatedPni updatedPniString: String?, preKeyManager: PreKeyManager, tx: DBWriteTransaction) { fatalError() }
    open func shouldSharePhoneNumber(with serviceId: ServiceId, tx: DBReadTransaction) -> Bool { fatalError() }
    open func setShouldSharePhoneNumber(with recipient: Aci, tx: DBWriteTransaction) { fatalError() }
    open func clearShouldSharePhoneNumber(with recipient: Aci, tx: DBWriteTransaction) { fatalError() }
    open func clearShouldSharePhoneNumberForEveryone(tx: DBWriteTransaction) { fatalError() }
    open func batchUpdateIdentityKeys(for serviceIds: [ServiceId]) -> Promise<Void> { fatalError() }
}

#endif
