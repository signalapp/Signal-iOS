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

    public enum Fingerprints {
        // Show a single fingerprint.
        case singleFingerprint(OWSFingerprint)
        // Show multiple fingerprints in the provided order. The fingerprint at the provided
        // index should be shown by default.
        // (There will only be two: e164 fingerprint and aci fingerprint).
        case multiFingerprint([OWSFingerprint], defaultIndex: Int)
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
    ) -> Fingerprints? {
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
            return .singleFingerprint(aciFingerprint)
        } else if !FeatureFlags.aciSafetyNumbers {
            // ACI safety number disabled; just do e164
            guard let e164Fingerprint = self.e164Fingerprint(
                theirSignalAddress: theirSignalAddress,
                theirIdentityKey: theirIdentityKey,
                myIdentityKey: myIdentityKey,
                theirName: theirName
            ) else {
                owsFailDebug("Unable to build e164 fingerprint")
                return nil
            }
            return .singleFingerprint(e164Fingerprint)
        } else {
            // Need both.
            guard
                let aciFingerprint = self.aciFingerprint(
                    theirSignalAddress: theirSignalAddress,
                    theirIdentityKey: theirIdentityKey,
                    myIdentityKey: myIdentityKey,
                    theirName: theirName
                ),
                let e164Fingerprint = self.e164Fingerprint(
                    theirSignalAddress: theirSignalAddress,
                    theirIdentityKey: theirIdentityKey,
                    myIdentityKey: myIdentityKey,
                    theirName: theirName
                )
            else {
                owsFailDebug("Unable to build fingerprints")
                return nil
            }
            return .multiFingerprint(
                [e164Fingerprint, aciFingerprint],
                defaultIndex: RemoteConfig.defaultToAciSafetyNumber ? 1 : 0
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
            let myAci = accountManager.localAddress?.serviceId,
            // TODO(PNP): We should fail if this is a PNI and not an ACI.
            let theirAci = theirSignalAddress.serviceId
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
