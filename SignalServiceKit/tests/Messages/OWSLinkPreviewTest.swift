//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import XCTest

class OWSLinkPreviewTest: SSKBaseTestSwift {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testIsValidLinkUrl() {
        XCTAssertTrue(OWSLinkPreview.isValidLinkUrl("https://www.youtube.com/watch?v=tP-Ipsat90c"))
        XCTAssertTrue(OWSLinkPreview.isValidLinkUrl("https://youtube.com/watch?v=tP-Ipsat90c"))
        XCTAssertTrue(OWSLinkPreview.isValidLinkUrl("https://www.youtube.com"))

        // Allow arbitrary subdomains.
        XCTAssertTrue(OWSLinkPreview.isValidMediaUrl("https://some.random.subdomain.youtube.com/watch?v=tP-Ipsat90c"))

        // Don't allow HTTP, only HTTPS
        XCTAssertFalse(OWSLinkPreview.isValidLinkUrl("http://youtube.com/watch?v=tP-Ipsat90c"))
        XCTAssertFalse(OWSLinkPreview.isValidLinkUrl("mailto://youtube.com/watch?v=tP-Ipsat90c"))
        XCTAssertFalse(OWSLinkPreview.isValidLinkUrl("ftp://youtube.com/watch?v=tP-Ipsat90c"))

        // Don't allow similar domains.
        XCTAssertFalse(OWSLinkPreview.isValidLinkUrl("https://xyoutube.com/watch?v=tP-Ipsat90c"))
        XCTAssertFalse(OWSLinkPreview.isValidLinkUrl("https://youtubex.com/watch?v=tP-Ipsat90c"))
        XCTAssertFalse(OWSLinkPreview.isValidLinkUrl("https://youtube.comx/watch?v=tP-Ipsat90c"))
        XCTAssertFalse(OWSLinkPreview.isValidLinkUrl("https://www.xyoutube.com/watch?v=tP-Ipsat90c"))
        XCTAssertFalse(OWSLinkPreview.isValidLinkUrl("https://www.youtubex.com/watch?v=tP-Ipsat90c"))
        XCTAssertFalse(OWSLinkPreview.isValidLinkUrl("https://www.youtube.comx/watch?v=tP-Ipsat90c"))

        // Don't allow media domains.
        XCTAssertFalse(OWSLinkPreview.isValidLinkUrl("https://i.ytimg.com/vi/tP-Ipsat90c/maxresdefault.jpg"))
    }

    func testIsValidMediaUrl() {
        XCTAssertTrue(OWSLinkPreview.isValidMediaUrl("https://www.youtube.com/watch?v=tP-Ipsat90c"))
        XCTAssertTrue(OWSLinkPreview.isValidMediaUrl("https://youtube.com/watch?v=tP-Ipsat90c"))
        XCTAssertTrue(OWSLinkPreview.isValidMediaUrl("https://www.youtube.com"))

        // Allow arbitrary subdomains.
        XCTAssertTrue(OWSLinkPreview.isValidMediaUrl("https://some.random.subdomain.youtube.com/watch?v=tP-Ipsat90c"))

        // Don't allow HTTP, only HTTPS
        XCTAssertFalse(OWSLinkPreview.isValidMediaUrl("http://youtube.com/watch?v=tP-Ipsat90c"))
        XCTAssertFalse(OWSLinkPreview.isValidMediaUrl("mailto://youtube.com/watch?v=tP-Ipsat90c"))
        XCTAssertFalse(OWSLinkPreview.isValidMediaUrl("ftp://youtube.com/watch?v=tP-Ipsat90c"))

        // Don't allow similar domains.
        XCTAssertFalse(OWSLinkPreview.isValidMediaUrl("https://xyoutube.com/watch?v=tP-Ipsat90c"))
        XCTAssertFalse(OWSLinkPreview.isValidMediaUrl("https://youtubex.com/watch?v=tP-Ipsat90c"))
        XCTAssertFalse(OWSLinkPreview.isValidMediaUrl("https://youtube.comx/watch?v=tP-Ipsat90c"))
        XCTAssertFalse(OWSLinkPreview.isValidMediaUrl("https://www.xyoutube.com/watch?v=tP-Ipsat90c"))
        XCTAssertFalse(OWSLinkPreview.isValidMediaUrl("https://www.youtubex.com/watch?v=tP-Ipsat90c"))
        XCTAssertFalse(OWSLinkPreview.isValidMediaUrl("https://www.youtube.comx/watch?v=tP-Ipsat90c"))

        // Allow media domains.
        XCTAssertTrue(OWSLinkPreview.isValidMediaUrl("https://i.ytimg.com/vi/tP-Ipsat90c/maxresdefault.jpg"))
    }

    func testPreviewUrlForMessageBodyText() {
        XCTAssertNil(OWSLinkPreview.previewUrl(forMessageBodyText: ""))
        XCTAssertNil(OWSLinkPreview.previewUrl(forMessageBodyText: "alice bob jim"))
        XCTAssertNil(OWSLinkPreview.previewUrl(forMessageBodyText: "alice bob jim http://"))
        XCTAssertNil(OWSLinkPreview.previewUrl(forMessageBodyText: "alice bob jim http://a.com"))

        XCTAssertEqual(OWSLinkPreview.previewUrl(forMessageBodyText: "https://www.youtube.com/watch?v=tP-Ipsat90c"),
                       "https://www.youtube.com/watch?v=tP-Ipsat90c")
        XCTAssertEqual(OWSLinkPreview.previewUrl(forMessageBodyText: "alice bob https://www.youtube.com/watch?v=tP-Ipsat90c jim"),
                       "https://www.youtube.com/watch?v=tP-Ipsat90c")

        // If there are more than one, take the first.
        XCTAssertEqual(OWSLinkPreview.previewUrl(forMessageBodyText: "alice bob https://www.youtube.com/watch?v=tP-Ipsat90c jim https://www.youtube.com/watch?v=other-url carol"),
                       "https://www.youtube.com/watch?v=tP-Ipsat90c")
    }
}
