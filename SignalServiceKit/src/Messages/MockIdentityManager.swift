//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

#if TESTABLE_BUILD

final class MockIdentityManager: OWSIdentityManager {
    private let recipientIdFinder: RecipientIdFinder

    init(recipientIdFinder: RecipientIdFinder) {
        self.recipientIdFinder = recipientIdFinder
    }

    var recipientIdentities: [AccountId: OWSRecipientIdentity]!

    func recipientIdentity(for recipientId: AccountId, tx: DBReadTransaction) -> OWSRecipientIdentity? {
        return recipientIdentities[recipientId]
    }

    func removeRecipientIdentity(for recipientId: AccountId, tx: DBWriteTransaction) {
        recipientIdentities[recipientId] = nil
    }

    func identityKey(for serviceId: ServiceId, tx: DBReadTransaction) throws -> IdentityKey? {
        guard let recipientId = try recipientIdFinder.recipientId(for: serviceId, tx: tx)?.get() else { return nil }
        guard let recipientIdentity = recipientIdentities[recipientId] else { return nil}
        return try IdentityKey(publicKey: ECPublicKey(keyData: recipientIdentity.identityKey).key)
    }

    var identityChangeInfoMessages: [ServiceId]!
    func insertIdentityChangeInfoMessage(for serviceId: ServiceId, wasIdentityVerified: Bool, tx: DBWriteTransaction) {
        identityChangeInfoMessages.append(serviceId)
    }

    var sessionSwitchoverMessages: [(SignalRecipient, phoneNumber: String?)]!
    func insertSessionSwitchoverEvent(for recipient: SignalRecipient, phoneNumber: String?, tx: DBWriteTransaction) {
        sessionSwitchoverMessages.append((recipient, phoneNumber))
    }

    func mergeRecipient(_ recipient: SignalRecipient, into targetRecipient: SignalRecipient, tx: DBWriteTransaction) {
        guard let fromValue = recipientIdentities[recipient.uniqueId] else {
            return
        }
        if recipientIdentities[targetRecipient.uniqueId] == nil {
            recipientIdentities[targetRecipient.uniqueId] = OWSRecipientIdentity(
                accountId: targetRecipient.uniqueId,
                identityKey: fromValue.identityKey,
                isFirstKnownKey: fromValue.isFirstKnownKey,
                createdAt: fromValue.createdAt,
                verificationState: fromValue.verificationState
            )
        }
        recipientIdentities[recipient.uniqueId] = nil
    }

    func libSignalStore(for identity: OWSIdentity, tx: DBReadTransaction) throws -> IdentityStore { fatalError() }
    func groupContainsUnverifiedMember(_ groupUniqueID: String, tx: DBReadTransaction) -> Bool { fatalError() }
    func recipientIdentity(for address: SignalServiceAddress, tx: DBReadTransaction) -> OWSRecipientIdentity? { fatalError() }
    func fireIdentityStateChangeNotification(after tx: DBWriteTransaction) { fatalError() }
    func identityKeyPair(for identity: OWSIdentity, tx: DBReadTransaction) -> ECKeyPair? { fatalError() }
    func setIdentityKeyPair(_ keyPair: ECKeyPair?, for identity: OWSIdentity, tx: DBWriteTransaction) { fatalError() }
    func identityKey(for address: SignalServiceAddress, tx: DBReadTransaction) -> Data? { fatalError() }
    func saveIdentityKey(_ identityKey: Data, for serviceId: ServiceId, tx: DBWriteTransaction) -> Result<Bool, RecipientIdError> { fatalError() }
    func untrustedIdentityForSending(to address: SignalServiceAddress, untrustedThreshold: Date?, tx: DBReadTransaction) -> OWSRecipientIdentity? { fatalError() }
    func isTrustedIdentityKey(_ identityKey: Data, serviceId: ServiceId, direction: TSMessageDirection, tx: DBReadTransaction) -> Result<Bool, RecipientIdError> { fatalError() }
    func tryToSyncQueuedVerificationStates() { fatalError() }
    func verificationState(for address: SignalServiceAddress, tx: DBReadTransaction) -> VerificationState { fatalError() }
    func setVerificationState(_ verificationState: VerificationState, of identityKey: Data, for address: SignalServiceAddress, isUserInitiatedChange: Bool, tx: DBWriteTransaction) -> ChangeVerificationStateResult { fatalError() }
    func processIncomingVerifiedProto(_ verified: SSKProtoVerified, tx: DBWriteTransaction) throws { fatalError() }
    func processIncomingPniChangePhoneNumber(proto: SSKProtoSyncMessagePniChangeNumber, updatedPni updatedPniString: String?, preKeyManager: PreKeyManager, tx: DBWriteTransaction) { fatalError() }
    func shouldSharePhoneNumber(with serviceId: ServiceId, tx: DBReadTransaction) -> Bool { fatalError() }
    func setShouldSharePhoneNumber(with recipient: Aci, tx: DBWriteTransaction) { fatalError() }
    func clearShouldSharePhoneNumber(with recipient: Aci, tx: DBWriteTransaction) { fatalError() }
    func clearShouldSharePhoneNumberForEveryone(tx: DBWriteTransaction) { fatalError() }
    func batchUpdateIdentityKeys(for serviceIds: [ServiceId]) -> Promise<Void> { fatalError() }
}

#endif
