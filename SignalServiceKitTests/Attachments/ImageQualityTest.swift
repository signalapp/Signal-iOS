//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing

@testable import SignalServiceKit

struct ImageQualityTest {
    @Test(arguments: [
        ImageQualityLevel.one,
        ImageQualityLevel.two,
        ImageQualityLevel.three,
    ])
    func testMaxFileSize(imageQualityLevel: ImageQualityLevel) {
        #expect(imageQualityLevel.maxFileSize <= OWSMediaUtils.kMaxFileSizeImage)
    }
}
