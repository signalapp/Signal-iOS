//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

class SessionStoreTest2: XCTestCase {
    func testMaxUnacknowledgedSessionAge() throws {
        let alice_store = InMemorySignalProtocolStore()
        let bob_address = ProtocolAddress(
            Aci.constantForTesting("00000000-0000-4000-8000-0000000000B0"),
            deviceId: .primary,
        )

        try MockSessionStore.processPreKeyBundle(
            theirAddress: bob_address,
            now: Date(timeIntervalSinceReferenceDate: 0),
            sessionStore: alice_store,
            identityStore: alice_store,
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
