//
// Copyright 2026
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

final class Updates2SecurityPolicyTest: XCTestCase {

    func testUpdates2DoesNotRequireSignalPinnedCertificate() {
        let info = SignalServiceType.updates2.signalServiceInfo()
        XCTAssertFalse(
            info.shouldUseSignalCertificate,
            "updates2 may be served via a custom CDN domain (e.g. beforeve); it must not require Signal's pinned certificate"
        )
    }
}
