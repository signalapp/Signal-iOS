//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import XCTest
import PromiseKit
//import SignalServiceKit
@testable import Signal

class GroupsV2MigrationTest: SignalBaseTest {

    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }

    private struct GroupIdVector {
        let groupIdV1String: String
        let masterKeyV2String: String

        var groupIdV1: Data {
            groupIdV1String.asHexadecimalData!
        }

        var masterKeyV2: Data {
            masterKeyV2String.asHexadecimalData!
        }
    }

    func testMasterKeyDerivation() {
        let vectors = [
            GroupIdVector(groupIdV1String: "00000000000000000000000000000000",
                        masterKeyV2String: "dbde68f4ee9169081f8814eabc65523fea1359235c8cfca32b69e31dce58b039"),
            GroupIdVector(groupIdV1String: "000102030405060708090a0b0c0d0e0f",
                        masterKeyV2String: "70884f78f07a94480ee36b67a4b5e975e92e4a774561e3df84c9076e3be4b9bf"),
            GroupIdVector(groupIdV1String: "7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f",
                        masterKeyV2String: "e69bf7c183b288b4ea5745b7c52b651a61e57769fafde683a6fdf1240f1905f2"),
            GroupIdVector(groupIdV1String: "ffffffffffffffffffffffffffffffff",
                        masterKeyV2String: "dd3a7de23d10f18b64457fbeedc76226c112a730e4b76112e62c36c4432eb37d")
        ]
        for vector in vectors {
            XCTAssertEqual(vector.groupIdV1String.lowercased(),
                           vector.groupIdV1.hexadecimalString.lowercased())
            XCTAssertEqual(vector.masterKeyV2String.lowercased(),
                           vector.masterKeyV2.hexadecimalString.lowercased())

            let groupIdV1 = vector.groupIdV1

            let masterKey = try! GroupsV2Migration.v2MasterKey(forV1GroupId: groupIdV1)
            XCTAssertEqual(vector.masterKeyV2, masterKey)

            let groupIdV2 = try! GroupsV2Migration.v2GroupId(forV1GroupId: groupIdV1)
            XCTAssertNotEqual(groupIdV1, groupIdV2)
        }
    }

    func testHexadecimalRoundtrip() {
        let values = [
            "00000000000000000000000000000000",
            "dbde68f4ee9169081f8814eabc65523fea1359235c8cfca32b69e31dce58b039",
            "000102030405060708090a0b0c0d0e0f",
            "70884f78f07a94480ee36b67a4b5e975e92e4a774561e3df84c9076e3be4b9bf",
            "7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f",
             "e69bf7c183b288b4ea5745b7c52b651a61e57769fafde683a6fdf1240f1905f2",
            "ffffffffffffffffffffffffffffffff",
             "dd3a7de23d10f18b64457fbeedc76226c112a730e4b76112e62c36c4432eb37d"
        ]
        for value in values {
            XCTAssertEqual(value, value.asHexadecimalData!.hexadecimalString)
        }
        for _ in 0..<16 {
            let bytes = Randomness.generateRandomBytes(256)
            XCTAssertEqual(bytes, bytes.hexadecimalString.asHexadecimalData)
        }
    }
}

// MARK: -

extension String {
    var asHexadecimalData: Data? {
        var data = Data()

        var remainder = self
        if remainder.hasPrefix("0x") {
            remainder = remainder.substring(from: "0x".count)
        }
        while !remainder.isEmpty {
            assert(remainder.count % 2 == 0)
            let byteString = remainder.substring(to: 2)
            remainder = remainder.substring(from: 2)

            let byte = UInt8(byteString, radix: 16)!
            data.append(byte)
        }
        return data
    }
}
