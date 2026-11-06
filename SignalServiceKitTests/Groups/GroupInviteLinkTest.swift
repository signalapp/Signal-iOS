//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import Testing

@testable import SignalServiceKit

struct GroupInviteLinkTest {
    /// Ensure `generateInviteLinkPassword` produces a valid password.
    @Test
    func testRandomValid() throws {
        let secretParams = try GroupSecretParams.generate()
        _ = try GroupInviteLink(
            masterKey: secretParams.getMasterKey(),
            inviteLinkPassword: GroupInviteLink.generateInviteLinkPassword(),
        )
    }

    /// Ensure encoded URLs can be decoded.
    @Test
    func testEncodeDecode() throws {
        let secretParams = try GroupSecretParams.generate()
        let inviteLinkPassword = GroupInviteLink.generateInviteLinkPassword()
        let groupLink1 = try GroupInviteLink(masterKey: secretParams.getMasterKey(), inviteLinkPassword: inviteLinkPassword)
        let groupLinkUrl1 = groupLink1.url()
        let groupLinkUrl2 = try #require(PossibleGroupInviteLinkUrl.parseFrom(groupLinkUrl1))
        let groupLink2 = try GroupInviteLink.parseFrom(groupLinkUrl2)
        #expect(groupLink1 == groupLink2)
    }
}
