//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import SignalServiceKit

final class URLPathComponentsTest: XCTestCase {
    // MARK: - URLPathComponents tests

    func testExpressibleByArrayLiteral() {
        let normal: URLPathComponents = .init(["foo", "bar"])
        let arraylike: URLPathComponents = ["foo", "bar"]
        XCTAssertEqual(arraylike, normal)
    }

    func testPercentEncoded() {
        XCTAssertTrue(URLPathComponents([]).percentEncoded.isEmpty)
        XCTAssertTrue(URLPathComponents([""]).percentEncoded.isEmpty)
        XCTAssertTrue(URLPathComponents(["", "", ""]).percentEncoded.isEmpty)

        let nasty = URLPathComponents(["foo", "", "~", "bar / baz?qúx"])
        XCTAssertEqual(nasty.percentEncoded, "foo/~/bar%20%2F%20baz%3Fq%C3%BAx")
    }

    // MARK: - URL extension

    func testUrlInit() {
        XCTAssertNil(URL(pathComponents: []))

        let fullUrl = URL(pathComponents: ["foo", "", "~", "bar / baz?qúx"])!
        XCTAssertEqual(fullUrl.relativeString, "foo/~/bar%20%2F%20baz%3Fq%C3%BAx")
    }
}
