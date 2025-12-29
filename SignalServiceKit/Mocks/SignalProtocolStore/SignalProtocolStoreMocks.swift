//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#if TESTABLE_BUILD

import Foundation
import LibSignalClient

extension SignalProtocolStore {
    static func mock(identity: OWSIdentity, preKeyStore: PreKeyStore, recipientIdFinder: RecipientIdFinder, sessionStore: SessionStore) -> Self {
        return SignalProtocolStore(
            sessionStore: SessionManagerForIdentity(identity: identity, recipientIdFinder: recipientIdFinder, sessionStore: sessionStore),
            preKeyStore: PreKeyStoreImpl(for: identity, preKeyStore: preKeyStore),
            signedPreKeyStore: SignedPreKeyStoreImpl(for: identity, preKeyStore: preKeyStore),
            kyberPreKeyStore: KyberPreKeyStoreImpl(for: identity, dateProvider: Date.provider, preKeyStore: preKeyStore),
        )
    }
}

#endif
