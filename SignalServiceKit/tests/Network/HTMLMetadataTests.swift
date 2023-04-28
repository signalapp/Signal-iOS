//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

@testable import SignalServiceKit

class HTMLMetadataTests: XCTestCase {

    func testEmptyBody() {
        let empty = HTMLMetadata.construct(parsing: "")
        XCTAssertEqual(empty, HTMLMetadata())
    }

    func testParseTitleTags() {
        let testSet: [String: String] = [
            "<title>Simple</title>": "Simple",
            "\nhello\n\t<title>Two Lines</title>\n\nblahhhh": "Two Lines",
            "<title>Title1</title><title>Title2</title>": "Title1",
            " \n\t <  title  \n>Oddly spaced<  /title  >": "Oddly spaced",
            "<title>&quotEntities&quot</title>": "\"Entities\""
        ]

        testSet.forEach { test, expectedResult in
            XCTAssertEqual(
                HTMLMetadata.construct(parsing: test),
                HTMLMetadata(titleTag: expectedResult)
            )
        }
    }

    func testParseFaviconUrlString() {
        let testSet: [String: String?] = [
            "<link rel=\"icon\" href=\"test.ico\"></link>": "test.ico",
            "<  link rel=\"  shortcut  icon \"   href=\"spacedddd\"  />": "spacedddd",
            "<link rel=\"apple-touch-icon\" href=\"incorrect tag\">": nil,
            """
            <link rel=\"icon\" href=\"first\">
            <link rel=\"icon\" href=\"second\">
            <link rel=\"icon\" href=\"third\">
            """: "first",
            "<link href=\"href first\" rel=\"icon\">": "href first"
        ]

        testSet.forEach { test, expectedResult in
            XCTAssertEqual(
                HTMLMetadata.construct(parsing: test),
                HTMLMetadata(faviconUrlString: expectedResult)
            )
        }
    }

    func testParseMetaDescription() {
        let testSet: [String: String?] = [
            "<meta name=\"description\" content=\"DescriptionText\" />": "DescriptionText",
            "<  meta  name  =  \"description\" \n\n\n content=\"Spaced Description\" />": "Spaced Description",
            "<meta name=\"description\" content=\"DescriptionText\" /><meta name=\"description\" content=\"Repeat\" />": "DescriptionText",
            "<meta property=\"description\" content=\"DescriptionText\" />": nil
        ]

        testSet.forEach { test, expectedResult in
            XCTAssertEqual(
                HTMLMetadata.construct(parsing: test),
                HTMLMetadata(description: expectedResult)
            )
        }
    }

    func testParseOpengraphTitle() {
        let testSet: [String: String?] = [
            "<meta property=\"og:title\" content=\"TestTitle\">": "TestTitle",
            "<meta content=\"FlippedTitle\" property=\"og:title\">": "FlippedTitle",
            "<meta garbage1\t=\ngarbage property=\"og:title\" garbage2 = garbage content=\"TitleWithGarbage\" garbage3=garbage kafdjadk>": "TitleWithGarbage",
            "<meta property=\"og:title\" content=\"Title\"><meta property=\"og:title\" content=\"Repeat\">": "Title"
        ]

        testSet.forEach { test, expectedResult in
            XCTAssertEqual(
                HTMLMetadata.construct(parsing: test),
                HTMLMetadata(ogTitle: expectedResult)
            )
        }
    }

    func testParseOneOfEach_Simple() {
        let testHTML = """
        <title>TitleString</title>
        <link rel="icon" href="FaviconString" />
        <meta name="description" content="DescriptionString" />
        <meta property="og:title" content="OpengraphTitle" />
        <meta property="og:description" content="OpengraphDescription" />
        <meta property="og:image" content="ImageURL" />
        <meta property="og:image:url" content="FallbackImageURL" />
        <meta property="og:published_time" content="PublishedDate" />
        <meta property="article:published_time" content="ArticlePublishedDate" />
        <meta property="og:modified_time" content="ModifiedDate" />
        <meta property="article:modified_time" content="ArticleModifiedDate" />
        """

        let testMetadata = HTMLMetadata.construct(parsing: testHTML)
        XCTAssertEqual(testMetadata, HTMLMetadata(
            titleTag: "TitleString",
            faviconUrlString: "FaviconString",
            description: "DescriptionString",
            ogTitle: "OpengraphTitle",
            ogDescription: "OpengraphDescription",
            ogImageUrlString: "ImageURL",
            ogPublishDateString: "PublishedDate",
            articlePublishDateString: "ArticlePublishedDate",
            ogModifiedDateString: "ModifiedDate",
            articleModifiedDateString: "ArticleModifiedDate"
        ))
    }

    func testParseFallbackImage() {
        let testHTML = """
        <title>TitleString</title>
        <link rel="icon" href="FaviconString" />
        <meta name="description" content="DescriptionString" />
        <meta property="og:image:url" content="FallbackImageURL" />
        """

        let testMetadata = HTMLMetadata.construct(parsing: testHTML)
        XCTAssertEqual(testMetadata, HTMLMetadata(
            titleTag: "TitleString",
            faviconUrlString: "FaviconString",
            description: "DescriptionString",
            ogImageUrlString: "FallbackImageURL"
        ))
    }

    func testLinkDataParsing() {
        let linkText = ("<meta property=\"og:title\" content=\"Randomness is Random - Numberphile\">" +
                        "<meta property=\"og:image\" content=\"https://i.ytimg.com/vi/tP-Ipsat90c/maxresdefault.jpg\">")

        let content = HTMLMetadata.construct(parsing: linkText)
        XCTAssertNotNil(content)

        XCTAssertEqual(content.ogTitle, "Randomness is Random - Numberphile")
        XCTAssertEqual(content.ogImageUrlString, "https://i.ytimg.com/vi/tP-Ipsat90c/maxresdefault.jpg")
    }
}
