//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
@testable import SignalServiceKit
@testable import SignalUI

func XCTAssertMatch(expectedPattern: String, actualText: String, file: StaticString = #filePath, line: UInt = #line) {
    let regex = try! NSRegularExpression(pattern: expectedPattern, options: [])
    XCTAssert(regex.hasMatch(input: actualText), "\(actualText) did not match pattern \(expectedPattern)", file: file, line: line)
}

class LinkPreviewFetcherTest: XCTestCase {
    let shouldRunNetworkTests = false

    private var linkPreviewFetcher: LinkPreviewFetcherImpl!

    override func setUp() {
        super.setUp()

        self.linkPreviewFetcher = LinkPreviewFetcherImpl(
            authCredentialManager: MockAuthCrededentialManager(),
            db: InMemoryDB(),
            groupsV2: MockGroupsV2(),
            linkPreviewSettingStore: LinkPreviewSettingStore.mock(),
            tsAccountManager: MockTSAccountManager(),
        )
    }

    func testLinkDownloadAndParsing() async throws {
        try XCTSkipUnless(shouldRunNetworkTests)

        let draft = try await linkPreviewFetcher.fetchLinkPreview(for: URL(string: "https://www.youtube.com/watch?v=tP-Ipsat90c")!)
        XCTAssertEqual(draft.title, "Randomness is Random - Numberphile")
        XCTAssertNotNil(draft.imageData)
    }

    func testLinkParsingWithRealData1() async throws {
        try XCTSkipUnless(shouldRunNetworkTests)

        guard case .string(_, let linkText) = try await linkPreviewFetcher.fetchStringOrImageResource(from: URL(string: "https://www.youtube.com/watch?v=tP-Ipsat90c")!) else {
            XCTFail("fetched page had an image content type")
            return
        }

        let content = HTMLMetadata.construct(parsing: linkText)
        XCTAssertNotNil(content)

        XCTAssertEqual(content.ogTitle, "Randomness is Random - Numberphile")
        XCTAssertEqual(content.ogImageUrlString, "https://i.ytimg.com/vi/tP-Ipsat90c/maxresdefault.jpg")
    }

    func testLinkParsingWithRealData2() async throws {
        try XCTSkipUnless(shouldRunNetworkTests)

        guard case .string(_, let linkText) = try await linkPreviewFetcher.fetchStringOrImageResource(from: URL(string: "https://youtu.be/tP-Ipsat90c")!) else {
            XCTFail("fetched page had an image content type")
            return
        }

        let content = HTMLMetadata.construct(parsing: linkText)
        XCTAssertNotNil(content)

        XCTAssertEqual(content.ogTitle, "Randomness is Random - Numberphile")
        XCTAssertEqual(content.ogImageUrlString, "https://i.ytimg.com/vi/tP-Ipsat90c/maxresdefault.jpg")
    }

    func testLinkParsingWithRealData3() async throws {
        try XCTSkipUnless(shouldRunNetworkTests)

        guard case .string(_, let linkText) = try await linkPreviewFetcher.fetchStringOrImageResource(from: URL(string: "https://www.reddit.com/r/memes/comments/c3p3dy/i_drew_all_the_boys_together_and_i_did_it_for_the/")!) else {
            XCTFail("fetched page had an image content type")
            return
        }

        let content = HTMLMetadata.construct(parsing: linkText)
        XCTAssertNotNil(content)

        XCTAssertEqual(content.ogTitle, "From the memes community on Reddit: I drew all the boys together and i did it for the internet")
        // This used to have a dynamic preview, but now it just shows the Reddit logo.
        XCTAssertEqual(content.ogImageUrlString, "https://i.redd.it/o0h58lzmax6a1.png")
    }

    func testLinkParsingWithRealData4() async throws {
        try XCTSkipUnless(shouldRunNetworkTests)

        guard case .string(_, let linkText) = try await linkPreviewFetcher.fetchStringOrImageResource(from: URL(string: "https://www.reddit.com/r/WhitePeopleTwitter/comments/a7j3mm/why/")!) else {
            XCTFail("fetched page had an image content type")
            return
        }

        let content = HTMLMetadata.construct(parsing: linkText)
        XCTAssertNotNil(content)

        XCTAssertEqual(content.ogTitle, "From the WhitePeopleTwitter community on Reddit: Why")
        XCTAssertEqual(content.ogImageUrlString, "https://share.redd.it/preview/post/a7j3mm")
    }

    func testLinkParsingWithRealData4_direct_image() async throws {
        try XCTSkipUnless(shouldRunNetworkTests)

        guard case .image(_, let contents) = try await linkPreviewFetcher.fetchStringOrImageResource(from: URL(string: "https://share.redd.it/preview/post/a7j3mm")!) else {
            XCTFail("fetched page had a non-image content type")
            return
        }

        XCTAssertFalse(contents.isEmpty)
    }

    func testLinkParsingWithRealData5() async throws {
        try XCTSkipUnless(shouldRunNetworkTests)

        guard case .string(_, let linkText) = try await linkPreviewFetcher.fetchStringOrImageResource(from: URL(string: "https://imgur.com/gallery/KFCL8fm")!) else {
            XCTFail("fetched page had an image content type")
            return
        }

        let content = HTMLMetadata.construct(parsing: linkText)
        XCTAssertNotNil(content)

        XCTAssertEqual(content.ogTitle, "imgur.com")

        // Actual URL can change based on network response
        //
        // It seems like some parts of the URL are stable, but if this continues to be brittle we may choose
        // to remove it or stub the network response
        XCTAssertTrue(content.ogImageUrlString!.hasPrefix("https://i.imgur.com/Y3wjlwY."))
    }

    func testLinkParsingWithRealData6() async throws {
        try XCTSkipUnless(shouldRunNetworkTests)

        guard case .string(_, let linkText) = try await linkPreviewFetcher.fetchStringOrImageResource(from: URL(string: "https://imgur.com/gallery/FMdwTiV")!) else {
            XCTFail("fetched page had an image content type")
            return
        }

        let content = HTMLMetadata.construct(parsing: linkText)
        XCTAssertNotNil(content)

        XCTAssertEqual(content.ogTitle, "Freddy would be proud!")
        XCTAssertEqual(content.ogImageUrlString, "https://i.imgur.com/Vot3iHh.jpg?fbplay")
    }

    func testLinkParsingWithRealData_instagram_web_link() async throws {
        try XCTSkipUnless(shouldRunNetworkTests)

        guard case .string(_, let linkText) = try await linkPreviewFetcher.fetchStringOrImageResource(from: URL(string: "https://www.instagram.com/p/BtjTTyHnDKJ/?utm_source=ig_web_button_share_sheet")!) else {
            XCTFail("fetched page had an image content type")
            return
        }

        let content = HTMLMetadata.construct(parsing: linkText)
        XCTAssertNotNil(content)

        XCTAssertEqual(content.ogTitle, "Signal Messenger on Instagram: \"I link therefore I am: https://signal.org/blog/i-link-therefore-i-am/\"")
        // Actual URL can change based on network response
        //
        // It seems like some parts of the URL are stable, so we can pattern match, but if this continues to be brittle we may choose
        // to remove it or stub the network response
        XCTAssertMatch(
            expectedPattern: "^https://.*.cdninstagram.com/.*/50654775_634096837020403_4737154112061769375_n.jpg\\?.*$",
            actualText: content.ogImageUrlString!,
        )
        //                XCTAssertEqual(content.imageUrl, "https://scontent-iad3-1.cdninstagram.com/vp/88656d9c10074b97b503d3b7b86eba84/5D774562/t51.2885-15/e35/50654775_634096837020403_4737154112061769375_n.jpg?_nc_ht=scontent-iad3-1.cdninstagram.com")
    }

    func testLinkParsingWithRealData_instagram_app_sharesheet() async throws {
        try XCTSkipUnless(shouldRunNetworkTests)

        guard case .string(_, let linkText) = try await linkPreviewFetcher.fetchStringOrImageResource(from: URL(string: "https://www.instagram.com/p/BtjTTyHnDKJ/?utm_source=ig_share_sheet&igshid=1bgo1ur9m9hi5")!) else {
            XCTFail("fetched page had an image content type")
            return
        }

        let content = HTMLMetadata.construct(parsing: linkText)
        XCTAssertNotNil(content)

        XCTAssertEqual(content.ogTitle, "Signal Messenger on Instagram: \"I link therefore I am: https://signal.org/blog/i-link-therefore-i-am/\"")
        // Actual URL can change based on network response
        //
        // It seems like some parts of the URL are stable, so we can pattern match, but if this continues to be brittle we may choose
        // to remove it or stub the network response
        XCTAssertMatch(
            expectedPattern: "^https://.*.cdninstagram.com/.*/50654775_634096837020403_4737154112061769375_n.jpg\\?.*$",
            actualText: content.ogImageUrlString!,
        )
        //                XCTAssertEqual(content.imageUrl, "https://scontent-iad3-1.cdninstagram.com/vp/88656d9c10074b97b503d3b7b86eba84/5D774562/t51.2885-15/e35/50654775_634096837020403_4737154112061769375_n.jpg?_nc_ht=scontent-iad3-1.cdninstagram.com")
    }

    func testLinkParsingWithRealData9() async throws {
        try XCTSkipUnless(shouldRunNetworkTests)

        guard case .string(_, let linkText) = try await linkPreviewFetcher.fetchStringOrImageResource(from: URL(string: "https://imgur.com/gallery/igHOwDM")!) else {
            XCTFail("fetched page had an image content type")
            return
        }

        let content = HTMLMetadata.construct(parsing: linkText)
        XCTAssertNotNil(content)

        XCTAssertEqual(content.ogTitle, "Sheet dance")
        XCTAssertEqual(content.ogImageUrlString, "https://i.imgur.com/PYiyLv1.jpg?fbplay")
    }

    func testLinkParsingWithRealData10() async throws {
        try XCTSkipUnless(shouldRunNetworkTests)

        guard case .string(_, let linkText) = try await linkPreviewFetcher.fetchStringOrImageResource(from: URL(string: "https://www.pinterest.com/norat0464/test-board/")!) else {
            XCTFail("fetched page had an image content type")
            return
        }

        let content = HTMLMetadata.construct(parsing: linkText)
        XCTAssertNotNil(content)

        XCTAssertEqual(content.ogTitle, "Test Board")
        XCTAssertEqual(content.ogImageUrlString, "https://i.pinimg.com/200x150/3e/85/f8/3e85f88e7be0dd1418a5b430d2ee8a55.jpg")
    }
}
