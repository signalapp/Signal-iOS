//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import XCTest

@testable import Signal

class ZkGroupIntegrationTest: XCTestCase {
    func testServerParamsAreUpToDate() {
        _ = GroupsV2Protos.serverPublicParams()
    }

    func testEncryptedAvatarMaximumLength() throws {
        let decryptedAvatar = Data(count: Int(kMaxAvatarSize))
        let groupParams = try GroupV2Params(groupSecretParams: .generate())
        let encryptedAvatar = try groupParams.encryptGroupAvatar(decryptedAvatar)
        XCTAssertEqual(encryptedAvatar.count, Int(kMaxEncryptedAvatarSize))
    }
}
