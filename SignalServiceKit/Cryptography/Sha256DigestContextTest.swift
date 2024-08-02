//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import SignalServiceKit
import XCTest

final class Sha256DigestContextTest: XCTestCase {

    /// Run a subset of the NIST SHA-256 short message test vectors.
    func testNistSha256ShortMsg() throws {
        let testVectors: [(String, String)] = [
            ("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", ""),
            ("28969cdfa74a12c82f3bad960b0b000aca2ac329deea5c2328ebc6f2ba9802c1", "d3"),
            ("5ca7133fa735326081558ac312c620eeca9970d1e70a4b95533d956f072d1f98", "11af"),
            ("dff2e73091f6c05e528896c4c831b9448653dc2ff043528f6769437bc7b975c2", "b4190e"),
            ("b16aa56be3880d18cd41e68384cf1ec8c17680c45a02b1575dc1518923ae8b0e", "74ba2521"),
            ("3fd877e27450e6bbd5d74bb82f9870c64c66e109418baa8e6bbcff355e287926", "06e076f5a442d5"),
            ("feeb4b2b59fec8fdb1e55194a493d8c871757b5723675e93d3ac034b380b7fc9", "47991301156d1d977c0338efbcad41004133aefbca6bcf7e"),
            ("a4139b74b102cf1e2fce229a6cd84c87501f50afa4c80feacf7d8cf5ed94f042", "95a765809caf30ada90ad6d61c2b4b30250df0a7ce23b7753c9187f4319ce2"),
            ("725e6f8d888ebaf908b7692259ab8839c3248edd22ca115bb13e025808654700", "b7c79d7e5f1eeccdfedf0e7bf43e730d447e607d8d1489823d09e11201a0b1258039e7bd4875b1"),
            ("cfb88d6faf2de3a69d36195acec2e255e2af2b7d933997f348e09f6ce5758360", "2d52447d1244d2ebc28650e7b05654bad35b3a68eedc7f8515306b496d75f3e73385dd1b002625024b81a02f2fd6dffb6e6d561cb7d0bd7a"),
            ("42e61e174fbb3897d6dd6cef3dd2802fe67b331953b06114a65c772859dfc1aa", "5a86b737eaea8ee976a0a24da63e7ed7eefad18a101c1211e2b3650c5187c2a8a650547208251f6d4237e661c7bf4c77f335390394c37fa1a9f9be836ac28509"),
        ]

        for testVector in testVectors {
            let expectedValue = try XCTUnwrap(Data.data(fromHex: testVector.0))
            let input = try XCTUnwrap(Data.data(fromHex: testVector.1))

            var context = Sha256DigestContext()
            try context.update(input)
            let result = try context.finalize()
            XCTAssertEqual(result, expectedValue)
        }
    }
}
