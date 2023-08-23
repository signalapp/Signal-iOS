//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public class OWSFingerprintBuilder {
    public struct FingerprintResult {
        public let fingerprints: [OWSFingerprint]
        public let initialDisplayIndex: Int
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
        theirAddress: SignalServiceAddress,
        theirRecipientIdentity: OWSRecipientIdentity,
        tx: SDSAnyReadTransaction
    ) -> FingerprintResult? {
        guard
            let localIdentifiers = tsAccountManager.localIdentifiers(transaction: tx),
            let myE164 = E164(localIdentifiers.phoneNumber),
            let myAciIdentityKey = identityManager.identityKeyPair(for: .aci, transaction: tx)?.publicKey
        else {
            owsFailDebug("Missing local properties!")
            return nil
        }
        let myAci = localIdentifiers.aci

        guard let theirAci = theirAddress.aci else {
            Logger.warn("Missing their ACI!")
            return nil
        }
        let theirAciIdentityKey = theirRecipientIdentity.identityKey
        let theirE164 = theirAddress.e164
        let theirName = contactsManager.displayName(
            for: SignalServiceAddress(serviceId: theirAci, e164: theirE164),
            transaction: tx
        )

        let aciFingerprint = OWSFingerprint(
            source: .aci(myAci: myAci, theirAci: theirAci),
            myAciIdentityKey: myAciIdentityKey,
            theirAciIdentityKey: theirAciIdentityKey,
            theirName: theirName
        )

        let e164Fingerprint: OWSFingerprint? = theirE164.map { theirE164 in
            return OWSFingerprint(
                source: .e164(myE164: myE164, theirE164: theirE164),
                myAciIdentityKey: myAciIdentityKey,
                theirAciIdentityKey: theirAciIdentityKey,
                theirName: theirName
            )
        }

        if FeatureFlags.onlyAciSafetyNumbers {
            return FingerprintResult(
                fingerprints: [aciFingerprint],
                initialDisplayIndex: 0
            )
        } else if RemoteConfig.defaultToAciSafetyNumber, let e164Fingerprint {
            // We have both, but prefer the ACI.
            return FingerprintResult(
                fingerprints: [e164Fingerprint, aciFingerprint],
                initialDisplayIndex: 1
            )
        } else if RemoteConfig.defaultToAciSafetyNumber {
            // If we default to ACI safety number and don't have the e164,
            // that's fine. Just show the ACI one.
            return FingerprintResult(
                fingerprints: [aciFingerprint],
                initialDisplayIndex: 0
            )
        } else {
            guard let e164Fingerprint else {
                // We want to default to the e164 one, so we _require_ it.
                owsFailDebug("Needed e164, but it was missing!")
                return nil
            }

            return FingerprintResult(
                fingerprints: [e164Fingerprint, aciFingerprint],
                initialDisplayIndex: 0
            )
        }
    }
}
