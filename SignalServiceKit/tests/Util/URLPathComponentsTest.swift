//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import SignalServiceKit

final class URLPathComponentsTest: XCTestCase {
    func testNoComponents() {
        XCTAssertNil(URL(pathComponents: []))
        XCTAssertNil(URL(pathComponents: [""]))
        XCTAssertNil(URL(pathComponents: ["", "", ""]))
    }

    func testFilteringAndEncodingComponents() {
        let url = URL(pathComponents: ["foo", "", "~", "bar / baz?qúx"])!
        XCTAssertEqual(url.relativeString, "foo/~/bar%20%2F%20baz%3Fq%C3%BAx")
    }
}
