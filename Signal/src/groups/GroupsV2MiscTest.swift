//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import XCTest
import Contacts
import ZKGroup
@testable import Signal
@testable import SignalMessaging

final class GroupsV2MiscTest: SignalBaseTest {
    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }

    func testProfileKeyDerivation() {
        guard FeatureFlags.useZKGroups else {
            return
        }

        let count = 1000

        do {
            for _ in 0..<count {
                let profileKey0 = OWSAES256Key.generateRandom()
                let profileKey1: ProfileKey = try VersionedProfiles.parseProfileKey(profileKey: profileKey0)
                let profileKeyVersion = try profileKey1.getProfileKeyVersion()
                let profileKeyVersionString = try profileKeyVersion.asHexadecimalString()
                XCTAssert(profileKeyVersionString.count > 0)
            }
        } catch {
            XCTFail("Error: \(error)")
        }
    }
}
