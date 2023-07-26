//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class OWSFingerprintBuilder {

    private let accountManager: TSAccountManager
    private let contactsManager: ContactsManagerProtocol

    public init(
        accountManager: TSAccountManager,
        contactsManager: ContactsManagerProtocol
    ) {
        self.accountManager = accountManager
        self.contactsManager = contactsManager
    }

    public struct FingerprintResult {
        public let fingerprints: [OWSFingerprint]
        public let defaultIndex: Int
    }

    /**
     * Builds fingerprints combining your current credentials with a specified identity key.
     * You can use these to present a new identity key for verification.
     *
     * Building can fail if required information is missing; e.g. depending on flag state an ACI
     * may be required and not having one (as happens when sending a message to someone's
     * PNI before receiving a response) results in failure and returns nil.
     * In these cases the user should be shown an error and told to retry once messages have been exchanged.
     *
     * If no identity key is provided, their most recently accepted identity key is used.
     * If no identity key is available, returns nil.
     */
    public func fingerprints(
        theirSignalAddress: SignalServiceAddress,
        theirIdentityKey: Data?
    ) -> FingerprintResult? {
        let theirIdentityKey: Data? = theirIdentityKey ?? OWSIdentityManager.shared.identityKey(for: theirSignalAddress)
        guard let theirIdentityKey else {
            owsFailDebug("Missing their identity key")
            return nil
        }
        let theirName = self.contactsManager.displayName(for: theirSignalAddress)

        // PNI TODO: This should use the identity key associated with our PNI if we only have a PNI session with them.
        guard let myIdentityKey = OWSIdentityManager.shared.identityKeyPair(for: .aci)?.publicKey else {
            owsFailDebug("Missing local identity key")
            return nil
        }

        if FeatureFlags.onlyAciSafetyNumbers {
            guard let aciFingerprint = self.aciFingerprint(
                theirSignalAddress: theirSignalAddress,
                theirIdentityKey: theirIdentityKey,
                myIdentityKey: myIdentityKey,
                theirName: theirName
            ) else {
                owsFailDebug("Unable to build aci fingerprint")
                return nil
            }
            return .init(fingerprints: [aciFingerprint], defaultIndex: 0)
        } else {
            // Need both.
            guard
                let aciFingerprint = self.aciFingerprint(
                    theirSignalAddress: theirSignalAddress,
                    theirIdentityKey: theirIdentityKey,
                    myIdentityKey: myIdentityKey,
                    theirName: theirName
                )
            else {
                owsFailDebug("Unable to build aci fingerprint")
                return nil
            }
            let e164Fingerprint = self.e164Fingerprint(
                theirSignalAddress: theirSignalAddress,
                theirIdentityKey: theirIdentityKey,
                myIdentityKey: myIdentityKey,
                theirName: theirName
            )
            if RemoteConfig.defaultToAciSafetyNumber {
                // If we default to ACI safety number and don't have the e164,
                // that's fine. Just show the aci one.
                return .init(fingerprints: [e164Fingerprint, aciFingerprint].compacted(), defaultIndex: e164Fingerprint == nil ? 0 : 1)
            }
            // Otherwise, we want to default to the e164 one so we _require_ it.
            guard let e164Fingerprint else {
                owsFailDebug("Unable to build e164 fingerprint")
                return nil
            }
            return .init(
                fingerprints: [e164Fingerprint, aciFingerprint],
                defaultIndex: 0
            )
        }
    }

    private func aciFingerprint(
        theirSignalAddress: SignalServiceAddress,
        theirIdentityKey: Data,
        myIdentityKey: Data,
        theirName: String
    ) -> OWSFingerprint? {
        if
            let myAci = accountManager.localAddress?.untypedServiceId,
            // TODO(PNP): We should fail if this is a PNI and not an ACI.
            let theirAci = theirSignalAddress.untypedServiceId
        {
            return OWSFingerprint(
                source: .aci(myAci: myAci, theirAci: theirAci),
                myIdentityKey: myIdentityKey,
                theirIdentityKey: theirIdentityKey,
                theirName: theirName
            )
        }
        return nil
    }

    private func e164Fingerprint(
        theirSignalAddress: SignalServiceAddress,
        theirIdentityKey: Data,
        myIdentityKey: Data,
        theirName: String
    ) -> OWSFingerprint? {
        if
            let myE164 = accountManager.localAddress?.e164,
            let theirE164 = theirSignalAddress.e164
        {
            return OWSFingerprint(
                source: .e164(myE164: myE164, theirE164: theirE164),
                myIdentityKey: myIdentityKey,
                theirIdentityKey: theirIdentityKey,
                theirName: theirName
            )
        }
        return nil
    }
}
