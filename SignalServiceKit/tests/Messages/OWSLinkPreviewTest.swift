//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
@testable import SignalServiceKit
import XCTest

func XCTAssertMatch(expectedPattern: String, actualText: String, file: StaticString = #file, line: UInt = #line) {
    let regex = try! NSRegularExpression(pattern: expectedPattern, options: [])
    XCTAssert(regex.hasMatch(input: actualText), "\(actualText) did not match pattern \(expectedPattern)", file: file, line: line)
}

class OWSLinkPreviewTest: SSKBaseTestSwift {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testBuildValidatedLinkPreview_TitleAndImage() {
        let url = "https://www.youtube.com/watch?v=tP-Ipsat90c"
        let body = "\(url)"
        let previewBuilder = SSKProtoDataMessagePreview.builder(url: url)
        previewBuilder.setTitle("Some Youtube Video")
        let imageAttachmentBuilder = SSKProtoAttachmentPointer.builder(id: 1)
        imageAttachmentBuilder.setKey(Randomness.generateRandomBytes(32))
        imageAttachmentBuilder.setContentType(OWSMimeTypeImageJpeg)
        previewBuilder.setImage(try! imageAttachmentBuilder.build())
        let dataBuilder = SSKProtoDataMessage.builder()
        dataBuilder.addPreview(try! previewBuilder.build())

        self.readWrite { (transaction) in
            XCTAssertNotNil(try! OWSLinkPreview.buildValidatedLinkPreview(dataMessage: try! dataBuilder.build(),
                                                                     body: body,
                                                                     transaction: transaction))
        }
    }

    func testBuildValidatedLinkPreview_Title() {
        let url = "https://www.youtube.com/watch?v=tP-Ipsat90c"
        let body = "\(url)"
        let previewBuilder = SSKProtoDataMessagePreview.builder(url: url)
        previewBuilder.setTitle("Some Youtube Video")
        let dataBuilder = SSKProtoDataMessage.builder()
        dataBuilder.addPreview(try! previewBuilder.build())

        self.readWrite { (transaction) in
            XCTAssertNotNil(try! OWSLinkPreview.buildValidatedLinkPreview(dataMessage: try! dataBuilder.build(),
                                                                     body: body,
                                                                     transaction: transaction))
        }
    }

    func testBuildValidatedLinkPreview_Image() {
        let url = "https://www.youtube.com/watch?v=tP-Ipsat90c"
        let body = "\(url)"
        let previewBuilder = SSKProtoDataMessagePreview.builder(url: url)
        let imageAttachmentBuilder = SSKProtoAttachmentPointer.builder(id: 1)
        imageAttachmentBuilder.setKey(Randomness.generateRandomBytes(32))
        imageAttachmentBuilder.setContentType(OWSMimeTypeImageJpeg)
        previewBuilder.setImage(try! imageAttachmentBuilder.build())
        let dataBuilder = SSKProtoDataMessage.builder()
        dataBuilder.addPreview(try! previewBuilder.build())

        self.readWrite { (transaction) in
            XCTAssertNotNil(try! OWSLinkPreview.buildValidatedLinkPreview(dataMessage: try! dataBuilder.build(),
                                                                     body: body,
                                                                     transaction: transaction))
        }
    }

    func testBuildValidatedLinkPreview_NoTitleOrImage() {
        let url = "https://www.youtube.com/watch?v=tP-Ipsat90c"
        let body = "\(url)"
        let previewBuilder = SSKProtoDataMessagePreview.builder(url: url)
        let dataBuilder = SSKProtoDataMessage.builder()
        dataBuilder.addPreview(try! previewBuilder.build())

        self.readWrite { (transaction) in
            do {
                _ = try OWSLinkPreview.buildValidatedLinkPreview(dataMessage: try! dataBuilder.build(),
                                                                 body: body,
                                                                 transaction: transaction)
                XCTFail("Missing expected error.")
            } catch {
                // Do nothing.
            }
        }
    }

    func testIsValidLinkUrl() {
        XCTAssertTrue(OWSLinkPreview.isValidLinkUrl("https://www.youtube.com/watch?v=tP-Ipsat90c"))
        XCTAssertTrue(OWSLinkPreview.isValidLinkUrl("https://youtube.com/watch?v=tP-Ipsat90c"))

        // Case shouldn't matter.
        XCTAssertTrue(OWSLinkPreview.isValidLinkUrl("https://WWW.YOUTUBE.COM/watch?v=tP-Ipsat90c"))

        // Don't allow arbitrary subdomains.
        XCTAssertFalse(OWSLinkPreview.isValidMediaUrl("https://some.random.subdomain.youtube.com/watch?v=tP-Ipsat90c"))

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

        // Allow all whitelisted domains.
        XCTAssertTrue(OWSLinkPreview.isValidLinkUrl("https://www.youtube.com/watch?v=tP-Ipsat90c"))
        XCTAssertTrue(OWSLinkPreview.isValidLinkUrl("https://youtu.be/tP-Ipsat90c"))
        XCTAssertTrue(OWSLinkPreview.isValidLinkUrl("https://www.reddit.com/r/androiddev/comments/a7gctz/androidx_release_notes_this_is_the_first_release/"))
        XCTAssertTrue(OWSLinkPreview.isValidLinkUrl("https://www.reddit.com/r/WhitePeopleTwitter/comments/a7j3mm/why/"))
        XCTAssertTrue(OWSLinkPreview.isValidLinkUrl("https://imgur.com/gallery/KFCL8fm"))
        XCTAssertTrue(OWSLinkPreview.isValidLinkUrl("https://imgur.com/gallery/FMdwTiV"))
        XCTAssertTrue(OWSLinkPreview.isValidLinkUrl("https://www.instagram.com/p/BrgpsUjF9Jo/?utm_source=ig_web_button_share_sheet"))
        XCTAssertTrue(OWSLinkPreview.isValidLinkUrl("https://www.instagram.com/p/BrgpsUjF9Jo/?utm_source=ig_share_sheet&igshid=94c7ihqjfmbm"))
        XCTAssertTrue(OWSLinkPreview.isValidLinkUrl("https://imgur.com/gallery/igHOwDM"))

        // Strip trailing commas.
        XCTAssertTrue(OWSLinkPreview.isValidLinkUrl("https://imgur.com/gallery/igHOwDM,"))

        // Ignore URLs with an empty path.
        XCTAssertFalse(OWSLinkPreview.isValidLinkUrl("https://imgur.com"))
        XCTAssertFalse(OWSLinkPreview.isValidLinkUrl("https://imgur.com/"))
        XCTAssertTrue(OWSLinkPreview.isValidLinkUrl("https://imgur.com/X"))
    }

    func testIsValidMediaUrl() {
        // Only allow domains on the media whitelist.
        XCTAssertFalse(OWSLinkPreview.isValidMediaUrl("https://www.youtube.com/watch?v=tP-Ipsat90c"))
        XCTAssertFalse(OWSLinkPreview.isValidMediaUrl("https://youtube.com/watch?v=tP-Ipsat90c"))

        // Allow arbitrary subdomains.
        XCTAssertTrue(OWSLinkPreview.isValidMediaUrl("https://ytimg.com/something"))
        XCTAssertTrue(OWSLinkPreview.isValidMediaUrl("https://something.ytimg.com/something"))

        // Don't allow HTTP, only HTTPS
        XCTAssertFalse(OWSLinkPreview.isValidMediaUrl("http://ytimg.com/watch?v=tP-Ipsat90c"))
        XCTAssertFalse(OWSLinkPreview.isValidMediaUrl("mailto://ytimg.com/watch?v=tP-Ipsat90c"))
        XCTAssertFalse(OWSLinkPreview.isValidMediaUrl("ftp://ytimg.com/watch?v=tP-Ipsat90c"))

        // Don't allow similar domains.
        XCTAssertFalse(OWSLinkPreview.isValidMediaUrl("https://xytimg.com/watch?v=tP-Ipsat90c"))
        XCTAssertFalse(OWSLinkPreview.isValidMediaUrl("https://youtubex.com/watch?v=tP-Ipsat90c"))
        XCTAssertFalse(OWSLinkPreview.isValidMediaUrl("https://ytimg.comx/watch?v=tP-Ipsat90c"))
        XCTAssertFalse(OWSLinkPreview.isValidMediaUrl("https://www.xytimg.com/watch?v=tP-Ipsat90c"))
        XCTAssertFalse(OWSLinkPreview.isValidMediaUrl("https://www.ytimgx.com/watch?v=tP-Ipsat90c"))
        XCTAssertFalse(OWSLinkPreview.isValidMediaUrl("https://www.ytimg.comx/watch?v=tP-Ipsat90c"))

        // Allow media domains.
        XCTAssertTrue(OWSLinkPreview.isValidMediaUrl("https://i.ytimg.com/vi/tP-Ipsat90c/maxresdefault.jpg"))
        XCTAssertTrue(OWSLinkPreview.isValidMediaUrl("https://external-preview.redd.it/j5lhdY0huShdzyrbSEdKzOb09BKhNreyEZOLDu1UzBA.jpg?auto=webp&s=2cb8bdb5ac5b54fc9514719030c0c9f08a03f684"))
        XCTAssertTrue(OWSLinkPreview.isValidMediaUrl("https://preview.redd.it/ehakvm9vx5521.jpg?auto=webp&s=925fb2d8776ca7102b944ab00e0615ae20c1bd5a"))
        XCTAssertTrue(OWSLinkPreview.isValidMediaUrl("https://i.imgur.com/Y3wjlwY.jpg?fb"))
        XCTAssertTrue(OWSLinkPreview.isValidMediaUrl("https://i.imgur.com/Vot3iHh.jpg?fbplay"))
        XCTAssertTrue(OWSLinkPreview.isValidMediaUrl("https://scontent-mia3-2.cdninstagram.com/vp/9035a7d6b32e6f840856661e4a11e3cf/5CFC285B/t51.2885-15/e35/47690175_2275988962411653_1145978227188801192_n.jpg?_nc_ht=scontent-mia3-2.cdninstagram.com"))
        XCTAssertTrue(OWSLinkPreview.isValidMediaUrl("https://scontent-mia3-2.cdninstagram.com/vp/9035a7d6b32e6f840856661e4a11e3cf/5CFC285B/t51.2885-15/e35/47690175_2275988962411653_1145978227188801192_n.jpg?_nc_ht=scontent-mia3-2.cdninstagram.com"))
        XCTAssertTrue(OWSLinkPreview.isValidMediaUrl("https://i.imgur.com/PYiyLv1.jpg?fbplay"))
    }

    func testPreviewUrlForMessageBodyText() {
        Assert(bodyText: "", extractsLink: nil)
        Assert(bodyText: "alice bob jim", extractsLink: nil)
        Assert(bodyText: "alice bob jim http://", extractsLink: nil)
        Assert(bodyText: "alice bob jim http://a.com", extractsLink: nil)

        Assert(bodyText: "https://www.youtube.com/watch?v=tP-Ipsat90c",
               extractsLink: "https://www.youtube.com/watch?v=tP-Ipsat90c")

        Assert(bodyText: "alice bob https://www.youtube.com/watch?v=tP-Ipsat90c jim",
               extractsLink: "https://www.youtube.com/watch?v=tP-Ipsat90c")

        // If there are more than one, take the first.
        Assert(bodyText: "alice bob https://www.youtube.com/watch?v=tP-Ipsat90c jim https://www.youtube.com/watch?v=other-url carol",
               extractsLink: "https://www.youtube.com/watch?v=tP-Ipsat90c")
    }

    func testUtils() {
        XCTAssertNil(OWSLinkPreview.fileExtension(forImageUrl: ""))
        XCTAssertNil(OWSLinkPreview.fileExtension(forImageUrl: "https://www.some.host/path/imagename"))
        XCTAssertNil(OWSLinkPreview.fileExtension(forImageUrl: "https://www.some.host/path/imagename."))

        XCTAssertEqual(OWSLinkPreview.fileExtension(forImageUrl: "https://www.some.host/path/imagename.jpg"), "jpg")
        XCTAssertEqual(OWSLinkPreview.fileExtension(forImageUrl: "https://www.some.host/path/imagename.gif"), "gif")
        XCTAssertEqual(OWSLinkPreview.fileExtension(forImageUrl: "https://www.some.host/path/imagename.png"), "png")
        XCTAssertEqual(OWSLinkPreview.fileExtension(forImageUrl: "https://www.some.host/path/imagename.boink"), "boink")

        XCTAssertNil(OWSLinkPreview.mimetype(forImageFileExtension: ""))
        XCTAssertNil(OWSLinkPreview.mimetype(forImageFileExtension: "boink"))
        XCTAssertNil(OWSLinkPreview.mimetype(forImageFileExtension: "tiff"))
        XCTAssertNil(OWSLinkPreview.mimetype(forImageFileExtension: "gif"))

        XCTAssertEqual(OWSLinkPreview.mimetype(forImageFileExtension: "jpg"), OWSMimeTypeImageJpeg)
        XCTAssertEqual(OWSLinkPreview.mimetype(forImageFileExtension: "png"), OWSMimeTypeImagePng)
    }

    func testLinkDownloadAndParsing() {
        let expectation = self.expectation(description: "link download and parsing")

        OWSLinkPreview.tryToBuildPreviewInfo(previewUrl: "https://www.youtube.com/watch?v=tP-Ipsat90c")
            .done { (draft) in
                XCTAssertNotNil(draft)

                XCTAssertEqual(draft.title, "Randomness is Random - Numberphile")
                XCTAssertNotNil(draft.imageFilePath)

                expectation.fulfill()
            }.catch { (error) in
                Logger.error("error: \(error)")
                XCTFail("Unexpected error: \(error)")
                expectation.fulfill()
            }.retainUntilComplete()

        self.waitForExpectations(timeout: 5.0, handler: nil)
    }

    func testLinkDataParsing_Empty() {
        let linkText = ""
        let linkData = linkText.data(using: .utf8)!

        let content = try! OWSLinkPreview.parse(linkData: linkData)
        XCTAssertNotNil(content)

        XCTAssertNil(content.title)
        XCTAssertNil(content.imageUrl)
    }

    func testLinkDataParsing() {
        let linkText = ("<meta property=\"og:title\" content=\"Randomness is Random - Numberphile\">" +
                        "<meta property=\"og:image\" content=\"https://i.ytimg.com/vi/tP-Ipsat90c/maxresdefault.jpg\">")
        let linkData = linkText.data(using: .utf8)!

        let content = try! OWSLinkPreview.parse(linkData: linkData)
        XCTAssertNotNil(content)

        XCTAssertEqual(content.title, "Randomness is Random - Numberphile")
        XCTAssertEqual(content.imageUrl, "https://i.ytimg.com/vi/tP-Ipsat90c/maxresdefault.jpg")
    }

    func testLinkParsingWithRealData1() {
        let expectation = self.expectation(description: "link download and parsing")

        OWSLinkPreview.downloadLink(url: "https://www.youtube.com/watch?v=tP-Ipsat90c")
            .done { (linkData) in
                let content = try! OWSLinkPreview.parse(linkData: linkData)
                XCTAssertNotNil(content)

                XCTAssertEqual(content.title, "Randomness is Random - Numberphile")
                XCTAssertEqual(content.imageUrl, "https://i.ytimg.com/vi/tP-Ipsat90c/maxresdefault.jpg")

                expectation.fulfill()
            }.catch { (error) in
                Logger.error("error: \(error)")
                XCTFail("Unexpected error: \(error)")
                expectation.fulfill()
            }.retainUntilComplete()

        self.waitForExpectations(timeout: 5.0, handler: nil)
    }

    func testLinkParsingWithRealData2() {
        let expectation = self.expectation(description: "link download and parsing")

        OWSLinkPreview.downloadLink(url: "https://youtu.be/tP-Ipsat90c")
            .done { (linkData) in
                let content = try! OWSLinkPreview.parse(linkData: linkData)
                XCTAssertNotNil(content)

                XCTAssertEqual(content.title, "Randomness is Random - Numberphile")
                XCTAssertEqual(content.imageUrl, "https://i.ytimg.com/vi/tP-Ipsat90c/maxresdefault.jpg")

                expectation.fulfill()
            }.catch { (error) in
                Logger.error("error: \(error)")
                XCTFail("Unexpected error: \(error)")
                expectation.fulfill()
            }.retainUntilComplete()

        self.waitForExpectations(timeout: 5.0, handler: nil)
    }

    func testLinkParsingWithRealData3() {
        let expectation = self.expectation(description: "link download and parsing")

        OWSLinkPreview.downloadLink(url: "https://www.reddit.com/r/androiddev/comments/a7gctz/androidx_release_notes_this_is_the_first_release/")
            .done { (linkData) in
                let content = try! OWSLinkPreview.parse(linkData: linkData)
                XCTAssertNotNil(content)

                XCTAssertEqual(content.title, "r/androiddev - AndroidX release notes | This is the first release of SavedState")
                XCTAssertEqual(content.imageUrl, "https://external-preview.redd.it/j5lhdY0huShdzyrbSEdKzOb09BKhNreyEZOLDu1UzBA.jpg?auto=webp&s=2cb8bdb5ac5b54fc9514719030c0c9f08a03f684")

                expectation.fulfill()
            }.catch { (error) in
                Logger.error("error: \(error)")
                XCTFail("Unexpected error: \(error)")
                expectation.fulfill()
            }.retainUntilComplete()

        self.waitForExpectations(timeout: 5.0, handler: nil)
    }

    func testLinkParsingWithRealData4() {
        let expectation = self.expectation(description: "link download and parsing")

        OWSLinkPreview.downloadLink(url: "https://www.reddit.com/r/WhitePeopleTwitter/comments/a7j3mm/why/")
            .done { (linkData) in
                let content = try! OWSLinkPreview.parse(linkData: linkData)
                XCTAssertNotNil(content)

                XCTAssertEqual(content.title, "r/WhitePeopleTwitter - Why")
                XCTAssertEqual(content.imageUrl, "https://preview.redd.it/ehakvm9vx5521.jpg?auto=webp&s=925fb2d8776ca7102b944ab00e0615ae20c1bd5a")

                expectation.fulfill()
            }.catch { (error) in
                Logger.error("error: \(error)")
                XCTFail("Unexpected error: \(error)")
                expectation.fulfill()
            }.retainUntilComplete()

        self.waitForExpectations(timeout: 5.0, handler: nil)
    }

    func testLinkParsingWithRealData5() {
        let expectation = self.expectation(description: "link download and parsing")

        OWSLinkPreview.downloadLink(url: "https://imgur.com/gallery/KFCL8fm")
            .done { (linkData) in
                let content = try! OWSLinkPreview.parse(linkData: linkData)
                XCTAssertNotNil(content)

                XCTAssertNil(content.title)
                XCTAssertEqual(content.imageUrl, "https://i.imgur.com/Y3wjlwY.jpg?fb")

                expectation.fulfill()
            }.catch { (error) in
                Logger.error("error: \(error)")
                XCTFail("Unexpected error: \(error)")
                expectation.fulfill()
            }.retainUntilComplete()

        self.waitForExpectations(timeout: 5.0, handler: nil)
    }

    func testLinkParsingWithRealData6() {
        let expectation = self.expectation(description: "link download and parsing")

        OWSLinkPreview.downloadLink(url: "https://imgur.com/gallery/FMdwTiV")
            .done { (linkData) in
                let content = try! OWSLinkPreview.parse(linkData: linkData)
                XCTAssertNotNil(content)

                XCTAssertEqual(content.title, "Freddy would be proud!")
                XCTAssertEqual(content.imageUrl, "https://i.imgur.com/Vot3iHh.jpg?fbplay")

                expectation.fulfill()
            }.catch { (error) in
                Logger.error("error: \(error)")
                XCTFail("Unexpected error: \(error)")
                expectation.fulfill()
            }.retainUntilComplete()

        self.waitForExpectations(timeout: 5.0, handler: nil)
    }

    func testLinkParsingWithRealData7() {
        let expectation = self.expectation(description: "link download and parsing")

        OWSLinkPreview.downloadLink(url: "https://www.instagram.com/p/BrgpsUjF9Jo/?utm_source=ig_web_button_share_sheet")
            .done { (linkData) in
                let content = try! OWSLinkPreview.parse(linkData: linkData)
                XCTAssertNotNil(content)

                XCTAssertEqual(content.title, "Walter \"MFPallytime\" on Instagram: “Lol gg”")
                // Actual URL can change based on network response
                //     https://scontent-mia3-2.cdninstagram.com/vp/9035a7d6b32e6f840856661e4a11e3cf/5CFC285B/t51.2885-15/e35/47690175_2275988962411653_1145978227188801192_n.jpg?_nc_ht=scontent-mia3-2.cdninstagram.com
                // It seems like some parts of the URL are stable, so we can pattern match, but if this continues to be brittle we may choose
                // to remove it or stub the network response
                XCTAssertMatch(expectedPattern: "^https://.*.cdninstagram.com/.*/47690175_2275988962411653_1145978227188801192_n.jpg\\?.*$",
                               actualText: content.imageUrl!)
//                XCTAssertEqual(content.imageUrl, "https://scontent-mia3-2.cdninstagram.com/vp/9035a7d6b32e6f840856661e4a11e3cf/5CFC285B/t51.2885-15/e35/47690175_2275988962411653_1145978227188801192_n.jpg?_nc_ht=scontent-mia3-2.cdninstagram.com")

                expectation.fulfill()
            }.catch { (error) in
                Logger.error("error: \(error)")
                XCTFail("Unexpected error: \(error)")
                expectation.fulfill()
            }.retainUntilComplete()

        self.waitForExpectations(timeout: 5.0, handler: nil)
    }

    func testLinkParsingWithRealData8() {
        let expectation = self.expectation(description: "link download and parsing")

        OWSLinkPreview.downloadLink(url: "https://www.instagram.com/p/BrgpsUjF9Jo/?utm_source=ig_share_sheet&igshid=94c7ihqjfmbm")
            .done { (linkData) in
                let content = try! OWSLinkPreview.parse(linkData: linkData)
                XCTAssertNotNil(content)

                XCTAssertEqual(content.title, "Walter \"MFPallytime\" on Instagram: “Lol gg”")
                // Actual URL can change based on network response
                //     https://scontent-mia3-2.cdninstagram.com/vp/9035a7d6b32e6f840856661e4a11e3cf/5CFC285B/t51.2885-15/e35/47690175_2275988962411653_1145978227188801192_n.jpg?_nc_ht=scontent-mia3-2.cdninstagram.com
                // It seems like some parts of the URL are stable, so we can pattern match, but if this continues to be brittle we may choose
                // to remove it or stub the network response
                XCTAssertMatch(expectedPattern: "^https://.*.cdninstagram.com/.*/47690175_2275988962411653_1145978227188801192_n.jpg\\?.*$",
                               actualText: content.imageUrl!)

                expectation.fulfill()
            }.catch { (error) in
                Logger.error("error: \(error)")
                XCTFail("Unexpected error: \(error)")
                expectation.fulfill()
            }.retainUntilComplete()

        self.waitForExpectations(timeout: 5.0, handler: nil)
    }

    func testLinkParsingWithRealData9() {
        let expectation = self.expectation(description: "link download and parsing")

        OWSLinkPreview.downloadLink(url: "https://imgur.com/gallery/igHOwDM")
            .done { (linkData) in
                let content = try! OWSLinkPreview.parse(linkData: linkData)
                XCTAssertNotNil(content)

                XCTAssertEqual(content.title, "Sheet dance")
                XCTAssertEqual(content.imageUrl, "https://i.imgur.com/PYiyLv1.jpg?fbplay")

                expectation.fulfill()
            }.catch { (error) in
                Logger.error("error: \(error)")
                XCTFail("Unexpected error: \(error)")
                expectation.fulfill()
            }.retainUntilComplete()

        self.waitForExpectations(timeout: 5.0, handler: nil)
    }

    // When using regular expressions to parse link titles, we need to use
    // String.utf16.count, not String.count in the range.
    func testRegexRanges() {
        let regex = try! NSRegularExpression(pattern: "bob", options: [])
        var text = "bob"
        XCTAssertNotNil(regex.firstMatch(in: text,
                                         options: [],
                                         range: NSRange(location: 0, length: text.count)))
        XCTAssertNotNil(regex.firstMatch(in: text,
                                         options: [],
                                         range: NSRange(location: 0, length: text.utf16.count)))
        text = "😂😘🙂 bob"
        XCTAssertNil(regex.firstMatch(in: text,
                                         options: [],
                                         range: NSRange(location: 0, length: text.count)))
        XCTAssertNotNil(regex.firstMatch(in: text,
                                         options: [],
                                         range: NSRange(location: 0, length: text.utf16.count)))
    }

    func testCursorPositions() {
        // sanity check
        Assert(bodyText: "https://www.youtube.com/watch?v=testCursorPositionsa",
               extractsLink: "https://www.youtube.com/watch?v=testCursorPositionsa",
               selectedRange: nil)

        // Don't extract link if cursor is touching text
        let text2 = "https://www.youtube.com/watch?v=testCursorPositionsb"
        XCTAssertEqual(text2.count, 52)
        Assert(bodyText: text2,
               extractsLink: nil,
               selectedRange: NSRange(location: 51, length: 0))

        Assert(bodyText: text2,
               extractsLink: nil,
               selectedRange: NSRange(location: 51, length: 10))

        Assert(bodyText: text2,
               extractsLink: nil,
               selectedRange: NSRange(location: 0, length: 0))

        // Unless the cursor is at the end of the text
        Assert(bodyText: text2,
               extractsLink: "https://www.youtube.com/watch?v=testCursorPositionsb",
               selectedRange: NSRange(location: 52, length: 0))

        // Once extracted, keep the existing link preview, even if the cursor moves back.
        Assert(bodyText: text2,
               extractsLink: "https://www.youtube.com/watch?v=testCursorPositionsb",
               selectedRange: NSRange(location: 51, length: 0))

        let text3 = "foo https://www.youtube.com/watch?v=testCursorPositionsc bar"
        XCTAssertEqual(text3.count, 60)

        // front edge
        Assert(bodyText: text3,
               extractsLink: nil,
               selectedRange: NSRange(location: 4, length: 0))

        // middle
        Assert(bodyText: text3,
               extractsLink: nil,
               selectedRange: NSRange(location: 4, length: 0))

        // rear edge
        Assert(bodyText: text3,
               extractsLink: nil,
               selectedRange: NSRange(location: 56, length: 0))

        // extract link if selecting after link
        Assert(bodyText: text3,
               extractsLink: "https://www.youtube.com/watch?v=testCursorPositionsc",
               selectedRange: NSRange(location: 57, length: 0))

        let text4 = "bar https://www.youtube.com/watch?v=testCursorPositionsd foo"
        XCTAssertEqual(text4.count, 60)

        // front edge
        Assert(bodyText: text4,
               extractsLink: nil,
               selectedRange: NSRange(location: 4, length: 0))

        // middle
        Assert(bodyText: text4,
               extractsLink: nil,
               selectedRange: NSRange(location: 20, length: 0))

        // rear edge
        Assert(bodyText: text4,
               extractsLink: nil,
               selectedRange: NSRange(location: 56, length: 0))

        // extract link if selecting before link
        Assert(bodyText: text4,
               extractsLink: "https://www.youtube.com/watch?v=testCursorPositionsd",
               selectedRange: NSRange(location: 3, length: 0))
    }

    private func Assert(bodyText: String, extractsLink link: String?, selectedRange: NSRange? = nil, file: StaticString = #file, line: UInt = #line) {
        let actual = OWSLinkPreview.previewUrl(forMessageBodyText: bodyText, selectedRange: selectedRange)
        XCTAssertEqual(actual, link, file: file, line: line)
    }
}
