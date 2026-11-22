//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import Testing

@testable import SignalServiceKit

struct SignalServiceProfileTests {
    private func parseProfile(capabilities: [String: Any]) throws -> SignalServiceProfile {
        let identityKey = IdentityKeyPair.generate().identityKey.serialize().base64EncodedString()
        return try SignalServiceProfile.fromResponse(
            serviceId: Aci.randomForTesting(),
            params: ParamParser([
                "identityKey": identityKey,
                "capabilities": capabilities,
            ]),
        )
    }

    @Test(arguments: [true, false])
    func testCapabilityPresent(isEnabled: Bool) throws {
        let profile = try parseProfile(capabilities: [
            "usernameChangeSyncMessage": true,
            "adminRemoveAndDelete": isEnabled,
        ])

        #expect(profile.capabilities == [
            .usernameChangeSyncMessage: true,
            .adminRemoveAndDelete: isEnabled,
        ])
    }

    @Test
    func testCapabilityMissingIsOmitted() throws {
        let profile = try parseProfile(capabilities: [
            "usernameChangeSyncMessage": true,
        ])

        #expect(profile.capabilities == [.usernameChangeSyncMessage: true])
    }
}
