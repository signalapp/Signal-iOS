//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@testable import Signal

class SelfSignedIdentityTest: XCTestCase {
    func testCreate() throws {
        let identity = try SelfSignedIdentity.create(name: "DeviceTransfer", validForDays: 1)

        var certificate: SecCertificate?
        SecIdentityCopyCertificate(identity, &certificate)
        let summary = certificate.flatMap { SecCertificateCopySubjectSummary($0) } as String?
        XCTAssertEqual(summary, "DeviceTransfer")
    }
}
