//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

final public class OWSFingerprintBuilder {
    public struct FingerprintResult {
        public let theirAci: Aci
        public let theirRecipientIdentity: OWSRecipientIdentity
        public let fingerprint: OWSFingerprint
    }

    private let contactsManager: any ContactManager
    private let identityManager: OWSIdentityManager
    private let tsAccountManager: TSAccountManager

    public init(
        contactsManager: any ContactManager,
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
        tx: DBReadTransaction
    ) -> FingerprintResult? {
        guard
            let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx),
            let myAciIdentityKey = identityManager.identityKeyPair(for: .aci, tx: tx)?.keyPair.identityKey,
            let theirAciIdentityKey = try? theirRecipientIdentity.identityKeyObject
        else {
            owsFailDebug("Missing local properties!")
            return nil
        }
        let myAci = localIdentifiers.aci

        let theirName = contactsManager.displayName(for: SignalServiceAddress(theirAci), tx: tx).resolvedValue()

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
