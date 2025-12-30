//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

class SessionStoreTest2: XCTestCase {
    func testMaxUnacknowledgedSessionAge() throws {
        let bob_address = try ProtocolAddress(name: "+14155550100", deviceId: 1)

        let alice_store = InMemorySignalProtocolStore()
        let bob_store = InMemorySignalProtocolStore()

        let bob_pre_key = PrivateKey.generate()
        let bob_signed_pre_key = PrivateKey.generate()
        let bob_signed_pre_key_public = bob_signed_pre_key.publicKey.serialize()
        let bob_kyber_pre_key = KEMKeyPair.generate()
        let bob_kyber_pre_key_public = bob_kyber_pre_key.publicKey.serialize()
        let bob_identity_key = try! bob_store.identityKeyPair(context: NullContext())
        let bob_signed_pre_key_signature = bob_identity_key.privateKey.generateSignature(message: bob_signed_pre_key_public)
        let bob_kyber_pre_key_signature = bob_identity_key.privateKey.generateSignature(message: bob_kyber_pre_key_public)

        let prekey_id: UInt32 = 4570
        let signed_prekey_id: UInt32 = 3006
        let kyber_prekey_id: UInt32 = 7777

        let bob_bundle = try PreKeyBundle(
            registrationId: bob_store.localRegistrationId(context: NullContext()),
            deviceId: 9,
            prekeyId: prekey_id,
            prekey: bob_pre_key.publicKey,
            signedPrekeyId: signed_prekey_id,
            signedPrekey: bob_signed_pre_key.publicKey,
            signedPrekeySignature: bob_signed_pre_key_signature,
            identity: bob_identity_key.identityKey,
            kyberPrekeyId: kyber_prekey_id,
            kyberPrekey: bob_kyber_pre_key.publicKey,
            kyberPrekeySignature: bob_kyber_pre_key_signature,
        )

        // Alice processes the bundle:
        try processPreKeyBundle(
            bob_bundle,
            for: bob_address,
            sessionStore: alice_store,
            identityStore: alice_store,
            now: Date(timeIntervalSinceReferenceDate: 0),
            context: NullContext(),
        )

        // If these assertions fail, it likely means that
        // MAX_UNACKNOWLEDGED_SESSION_AGE has been changed. If the value has been
        // decreased, we should decrease maxUnacknowledgedSessionAge after a 90-day
        // rollout. If the value has been increased, we should have increased
        // maxUnacknowledgedSessionAge 90 days ago.

        let initial_session = try alice_store.loadSession(for: bob_address, context: NullContext())!
        XCTAssertTrue(initial_session.hasCurrentState(now: Date(timeIntervalSinceReferenceDate: PreKeyManagerImpl.Constants.maxUnacknowledgedSessionAge)))
        XCTAssertFalse(initial_session.hasCurrentState(now: Date(timeIntervalSinceReferenceDate: PreKeyManagerImpl.Constants.maxUnacknowledgedSessionAge + 1)))
    }
}
