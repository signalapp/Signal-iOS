//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import SignalServiceKit

final class CRC32Test: XCTestCase {
    func testCrc() {
        // These tests are lifted from the following Go 1.19.3 code:
        //
        // ```
        // crc := crc32.NewIEEE()
        // fmt.Println(crc.Sum32())
        // crc.Write([]byte{})
        // fmt.Println(crc.Sum32())
        // crc.Write([]byte{1, 2, 3})
        // fmt.Println(crc.Sum32())
        // crc.Write([]byte{4, 5, 6})
        // fmt.Println(crc.Sum32())
        // ```
        var crc = CRC32()
        XCTAssertEqual(crc.value, 0)

        crc = crc.update(with: Data())
        XCTAssertEqual(crc.value, 0)

        crc = crc.update(with: Data([1, 2, 3]))
        XCTAssertEqual(crc.value, 1438416925)

        crc = crc.update(with: Data([4, 5, 6]))
        XCTAssertEqual(crc.value, 2180413220)
    }
}
