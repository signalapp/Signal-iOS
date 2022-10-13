//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
@testable import SignalServiceKit

class OWSURLBuilderUtilTest: SSKBaseTestSwift {

    func test_buildUrl() {
        // No base url
        XCTAssertEqual(
            URL(string: "https://e.f.com")!,
            OWSURLBuilderUtil.joinUrl(
                urlString: "https://e.f.com",
                baseUrl: nil
            )!
        )
        XCTAssertEqual(
            URL(string: "https://e.f.com/")!,
            OWSURLBuilderUtil.joinUrl(
                urlString: "https://e.f.com/",
                baseUrl: nil
            )!
        )
        XCTAssertEqual(
            URL(string: "https://e.f.com/a/b/c")!,
            OWSURLBuilderUtil.joinUrl(
                urlString: "https://e.f.com/a/b/c",
                baseUrl: nil
            )!
        )

        // * baseUrl with just host, no trailing /.
        XCTAssertEqual(
            URL(string: "https://e.f.com/a/b/c")!,
            OWSURLBuilderUtil.joinUrl(
                urlString: "a/b/c",
                baseUrl: URL(string: "https://e.f.com")
            )
        )
        XCTAssertEqual(
            URL(string: "https://e.f.com/a/b/c")!,
            OWSURLBuilderUtil.joinUrl(
                urlString: "/a/b/c",
                baseUrl: URL(string: "https://e.f.com")
            )
        )
        XCTAssertEqual(
            URL(string: "https://e.f.com/a/b/c")!,
            OWSURLBuilderUtil.joinUrl(
                urlString: "http://g.h.com/a/b/c",
                baseUrl: URL(string: "https://e.f.com")
            )
        )

        // * baseUrl with host & trailing /.
        XCTAssertEqual(
            URL(string: "https://e.f.com/a/b/c")!,
            OWSURLBuilderUtil.joinUrl(
                urlString: "a/b/c",
                baseUrl: URL(string: "https://e.f.com/")
            )
        )
        XCTAssertEqual(
            URL(string: "https://e.f.com/a/b/c")!,
            OWSURLBuilderUtil.joinUrl(
                urlString: "/a/b/c",
                baseUrl: URL(string: "https://e.f.com/")
            )
        )
        XCTAssertEqual(
            URL(string: "https://e.f.com/a/b/c")!,
            OWSURLBuilderUtil.joinUrl(
                urlString: "http://g.h.com/a/b/c",
                baseUrl: URL(string: "https://e.f.com/")
            )
        )

        // * baseUrl with host and path, no trailing /.
        XCTAssertEqual(
            URL(string: "https://e.f.com/x/a/b/c")!,
            OWSURLBuilderUtil.joinUrl(
                urlString: "a/b/c",
                baseUrl: URL(string: "https://e.f.com/x")
            )
        )
        XCTAssertEqual(
            URL(string: "https://e.f.com/x/a/b/c")!,
            OWSURLBuilderUtil.joinUrl(
                urlString: "/a/b/c",
                baseUrl: URL(string: "https://e.f.com/x")
            )
        )
        XCTAssertEqual(
            URL(string: "https://e.f.com/x/a/b/c")!,
            OWSURLBuilderUtil.joinUrl(
                urlString: "http://g.h.com/a/b/c",
                baseUrl: URL(string: "https://e.f.com/x")
            )
        )

        // * baseUrl with host and path & trailing /.
        XCTAssertEqual(
            URL(string: "https://e.f.com/x/a/b/c")!,
            OWSURLBuilderUtil.joinUrl(
                urlString: "a/b/c",
                baseUrl: URL(string: "https://e.f.com/x/")
            )
        )
        XCTAssertEqual(
            URL(string: "https://e.f.com/x/a/b/c")!,
            OWSURLBuilderUtil.joinUrl(
                urlString: "/a/b/c",
                baseUrl: URL(string: "https://e.f.com/x/")
            )
        )
        XCTAssertEqual(
            URL(string: "https://e.f.com/x/a/b/c")!,
            OWSURLBuilderUtil.joinUrl(
                urlString: "http://g.h.com/a/b/c",
                baseUrl: URL(string: "https://e.f.com/x/")
            )
        )

        // Querystring
        XCTAssertEqual(
            URL(string: "https://e.f.com/x/a/b/c?i=j&k=l")!,
            OWSURLBuilderUtil.joinUrl(
                urlString: "http://g.h.com/a/b/c?i=j&k=l",
                baseUrl: URL(string: "https://e.f.com/x/")
            )
        )
        XCTAssertEqual(
            URL(string: "https://e.f.com/x/a/b/c?i=j&k=l")!,
            OWSURLBuilderUtil.joinUrl(
                urlString: "http://g.h.com/a/b/c?i=j&k=l",
                baseUrl: URL(string: "https://e.f.com/x/?m=m")
            )
        )
        XCTAssertEqual(
            URL(string: "https://e.f.com/x/a/b/c")!,
            OWSURLBuilderUtil.joinUrl(
                urlString: "http://g.h.com/a/b/c",
                baseUrl: URL(string: "https://e.f.com/x/?m=m")
            )
        )

        // Fragment
        XCTAssertEqual(
            URL(string: "https://e.f.com/x/a/b/c#ooo")!,
            OWSURLBuilderUtil.joinUrl(
                urlString: "http://g.h.com/a/b/c#ooo",
                baseUrl: URL(string: "https://e.f.com/x/")
            )
        )
        XCTAssertEqual(
            URL(string: "https://e.f.com/x/a/b/c#ooo")!,
            OWSURLBuilderUtil.joinUrl(
                urlString: "http://g.h.com/a/b/c#ooo",
                baseUrl: URL(string: "https://e.f.com/x/#ppp")
            )
        )
        XCTAssertEqual(
            URL(string: "https://e.f.com/x/a/b/c")!,
            OWSURLBuilderUtil.joinUrl(
                urlString: "http://g.h.com/a/b/c",
                baseUrl: URL(string: "https://e.f.com/x/#ppp")
            )
        )
    }
}
