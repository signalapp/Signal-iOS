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

    /**
     * Builds a fingerprint combining your current credentials with a specified identity key.
     * You can use this to present a new identity key for verification.
     *
     * If no identity key is provided, their most recently accepted identity key is used.
     * If no identity key is available, returns nil.
     */
    public func fingerprint(
        theirSignalAddress: SignalServiceAddress,
        theirIdentityKey: Data?
    ) -> OWSFingerprint? {
        let theirIdentityKey: Data? = theirIdentityKey ?? OWSIdentityManager.shared.identityKey(for: theirSignalAddress)
        guard let theirIdentityKey else {
            owsFailDebug("Missing their identity key")
            return nil
        }
        let theirName = self.contactsManager.displayName(for: theirSignalAddress)
        guard let mySignalAddress = accountManager.localAddress else {
            owsFailDebug("Missing local address")
            return nil
        }

        // PNI TODO: This should use the identity key associated with our PNI if we only have a PNI session with them.
        guard let myIdentityKey = OWSIdentityManager.shared.identityKeyPair(for: .aci)?.publicKey else {
            owsFailDebug("Missing local identity key")
            return nil
        }
        return OWSFingerprint(
            myStableAddress: mySignalAddress,
            myIdentityKey: myIdentityKey,
            theirStableAddress: theirSignalAddress,
            theirIdentityKey: theirIdentityKey,
            theirName: theirName
        )
    }
}
