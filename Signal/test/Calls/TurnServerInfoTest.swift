//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

@testable import Signal

final class TurnServerInfoTest: XCTestCase {
    private func turnServerInfo() -> [String: AnyObject] {
        return [
            "username": "user",
            "password": "pass",
            "hostname": "host",
            "urlsWithIps": ["123.123.123.123"],
            "urls": ["turn:example.com"],
        ] as [String: AnyObject]
    }

    func testNullable() {
        var infoMap = turnServerInfo()
        var info = TurnServerInfo(attributes: infoMap)!
        XCTAssertEqual(info.username, "user")
        XCTAssertEqual(info.password, "pass")
        XCTAssertEqual(info.hostname, "host")
        XCTAssertEqual(info.urls, ["turn:example.com"])
        XCTAssertEqual(info.urlsWithIps, ["123.123.123.123"])

        infoMap["urls"] = NSNull()
        info = TurnServerInfo(attributes: infoMap)!
        XCTAssertEqual(info.username, "user")
        XCTAssertEqual(info.password, "pass")
        XCTAssertEqual(info.hostname, "host")
        XCTAssertEqual(info.urls, [])
        XCTAssertEqual(info.urlsWithIps, ["123.123.123.123"])

        infoMap["urlsWithIps"] = NSNull()
        info = TurnServerInfo(attributes: infoMap)!
        XCTAssertEqual(info.username, "user")
        XCTAssertEqual(info.password, "pass")
        XCTAssertEqual(info.hostname, "host")
        XCTAssertEqual(info.urls, [])
        XCTAssertEqual(info.urlsWithIps, [])

        infoMap["hostname"] = NSNull()
        info = TurnServerInfo(attributes: infoMap)!
        XCTAssertEqual(info.username, "user")
        XCTAssertEqual(info.password, "pass")
        XCTAssertEqual(info.hostname, "")
        XCTAssertEqual(info.urls, [])
        XCTAssertEqual(info.urlsWithIps, [])
    }
}
