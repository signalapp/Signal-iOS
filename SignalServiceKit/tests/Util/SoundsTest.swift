//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing
@testable import SignalServiceKit

struct SoundsTest {
    @Test(arguments: [
        ("Hello.m4a", 7562547131314274304),
        ("Goodbye.mp4", 10601446312307589120),
    ])
    func testCustomSoundId(testCase: (filename: String, id: UInt64)) {
        #expect(CustomSound.idFromFilename(testCase.filename) == testCase.id)
    }
}
