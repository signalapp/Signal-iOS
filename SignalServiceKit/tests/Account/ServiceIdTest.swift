//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class ServiceIdTest: XCTestCase {
    func testAciString() {
        let expectedValue = Aci.constantForTesting("00000000-0000-4000-A000-000000000000")
        XCTAssertEqual(Aci.parseFrom(aciString: "00000000-0000-4000-A000-000000000000"), expectedValue)
        XCTAssertEqual(Aci.parseFrom(aciString: "00000000-0000-4000-a000-000000000000"), expectedValue)
        XCTAssertNil(Aci.parseFrom(aciString: "PNI:00000000-0000-4000-A000-000000000000"))
        XCTAssertNil(Aci.parseFrom(aciString: "PNI:00000000-0000-4000-a000-000000000000"))
    }

    func testPniString() {
        let expectedValue = Pni.constantForTesting("PNI:00000000-0000-4000-A000-000000000000")
        XCTAssertEqual(Pni.parseFrom(pniString: "00000000-0000-4000-A000-000000000000"), expectedValue)
        XCTAssertEqual(Pni.parseFrom(pniString: "00000000-0000-4000-a000-000000000000"), expectedValue)
        XCTAssertNil(Pni.parseFrom(pniString: "PNI:00000000-0000-4000-A000-000000000000"))
        XCTAssertNil(Pni.parseFrom(pniString: "PNI:00000000-0000-4000-a000-000000000000"))
    }

    func testAmbiguousString() {
        let expectedValue = Pni.constantForTesting("PNI:00000000-0000-4000-A000-000000000000")
        XCTAssertEqual(Pni.parseFrom(ambiguousString: "00000000-0000-4000-A000-000000000000"), expectedValue)
        XCTAssertEqual(Pni.parseFrom(ambiguousString: "00000000-0000-4000-a000-000000000000"), expectedValue)
        XCTAssertEqual(Pni.parseFrom(ambiguousString: "PNI:00000000-0000-4000-A000-000000000000"), expectedValue)
        XCTAssertEqual(Pni.parseFrom(ambiguousString: "PNI:00000000-0000-4000-a000-000000000000"), expectedValue)
    }
}
