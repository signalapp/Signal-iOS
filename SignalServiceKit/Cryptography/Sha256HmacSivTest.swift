//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import SignalServiceKit
import XCTest

final class Sha256HmacSivTest: XCTestCase {

    func test_SHA256HMACSIV() throws {
        let key = Data.data(fromHex: "000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F")!
        let data = Data.data(fromHex: "202122232425262728292A2B2C2D2E2F303132333435363738393A3B3C3D3E3F")!

        let (iv, cipherText) = try Sha256HmacSiv.encrypt(data: data, key: key)
        let decryptedData = try Sha256HmacSiv.decrypt(iv: iv, cipherText: cipherText, key: key)

        XCTAssertEqual(data, decryptedData)
        XCTAssertEqual(iv, Data.data(fromHex: "f27036915a60d704b04d452ef0d55a5d")!)
        XCTAssertEqual(cipherText, Data.data(fromHex: "1668e7d91339daba9c950d985b7556471d13cc609e59eec62fb1ce27f5c5a342")!)
    }
}
