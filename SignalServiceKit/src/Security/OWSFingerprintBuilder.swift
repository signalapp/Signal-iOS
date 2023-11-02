//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public class OWSFingerprintBuilder {
    public struct FingerprintResult {
        public let theirAci: Aci
        public let theirRecipientIdentity: OWSRecipientIdentity
        public let fingerprint: OWSFingerprint
    }

    private let contactsManager: ContactsManagerProtocol
    private let identityManager: OWSIdentityManager
    private let tsAccountManager: TSAccountManager

    public init(
        contactsManager: ContactsManagerProtocol,
        identityManager: OWSIdentityManager,
        tsAccountManager: TSAccountManager
    ) {
        self.contactsManager = contactsManager
        self.identityManager = identityManager
        self.tsAccountManager = tsAccountManager
    }

    /// Builds fingerprints combining your current credentials with a specified
    /// identity key. You can use these to present a new identity key for
    /// verification.
    public func fingerprints(
        theirAci: Aci,
        theirRecipientIdentity: OWSRecipientIdentity,
        tx: SDSAnyReadTransaction
    ) -> FingerprintResult? {
        guard
            let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx.asV2Read),
            let myAciIdentityKey = identityManager.identityKeyPair(for: .aci, tx: tx.asV2Read)?.publicKey
        else {
            owsFailDebug("Missing local properties!")
            return nil
        }
        let myAci = localIdentifiers.aci

        let theirAciIdentityKey = theirRecipientIdentity.identityKey
        let theirName = contactsManager.displayName(for: SignalServiceAddress(theirAci), transaction: tx)

        let aciFingerprint = OWSFingerprint(
            myAci: myAci,
            theirAci: theirAci,
            myAciIdentityKey: myAciIdentityKey,
            theirAciIdentityKey: theirAciIdentityKey,
            theirName: theirName
        )

        return FingerprintResult(
            theirAci: theirAci,
            theirRecipientIdentity: theirRecipientIdentity,
            fingerprint: aciFingerprint
        )
    }
}
