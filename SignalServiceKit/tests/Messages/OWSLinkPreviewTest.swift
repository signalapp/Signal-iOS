//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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
        let imageAttachmentBuilder = SSKProtoAttachmentPointer.builder()
        imageAttachmentBuilder.setCdnID(1)
        imageAttachmentBuilder.setKey(Randomness.generateRandomBytes(32))
        imageAttachmentBuilder.setContentType(OWSMimeTypeImageJpeg)
        previewBuilder.setImage(try! imageAttachmentBuilder.build())
        let dataBuilder = SSKProtoDataMessage.builder()
        dataBuilder.addPreview(try! previewBuilder.build())

        self.write { (transaction) in
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

        self.write { (transaction) in
            XCTAssertNotNil(try! OWSLinkPreview.buildValidatedLinkPreview(dataMessage: try! dataBuilder.build(),
                                                                     body: body,
                                                                     transaction: transaction))
        }
    }

    func testBuildValidatedLinkPreview_Image() {
        let url = "https://www.youtube.com/watch?v=tP-Ipsat90c"
        let body = "\(url)"
        let previewBuilder = SSKProtoDataMessagePreview.builder(url: url)
        let imageAttachmentBuilder = SSKProtoAttachmentPointer.builder()
        imageAttachmentBuilder.setCdnID(1)
        imageAttachmentBuilder.setKey(Randomness.generateRandomBytes(32))
        imageAttachmentBuilder.setContentType(OWSMimeTypeImageJpeg)
        previewBuilder.setImage(try! imageAttachmentBuilder.build())
        let dataBuilder = SSKProtoDataMessage.builder()
        dataBuilder.addPreview(try! previewBuilder.build())

        self.write { (transaction) in
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

        self.write { (transaction) in
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

    func testPreviewUrlForMessageBodyText() {
        Assert(bodyText: "", extractsLink: nil)
        Assert(bodyText: "alice bob jim", extractsLink: nil)
        Assert(bodyText: "alice bob jim http://", extractsLink: nil)
        Assert(bodyText: "alice bob jim http://a.com", extractsLink: nil)

        Assert(bodyText: "https://www.youtube.com/watch?v=tP-Ipsat90c",
               extractsLink: URL(string: "https://www.youtube.com/watch?v=tP-Ipsat90c")!)

        Assert(bodyText: "alice bob https://www.youtube.com/watch?v=tP-Ipsat90c jim",
               extractsLink: URL(string: "https://www.youtube.com/watch?v=tP-Ipsat90c")!)

        // If there are more than one, take the first.
        Assert(bodyText: "alice bob https://www.youtube.com/watch?v=tP-Ipsat90c jim https://www.youtube.com/watch?v=other-url carol",
               extractsLink: URL(string: "https://www.youtube.com/watch?v=tP-Ipsat90c")!)
    }

    func testLinkDownloadAndParsing() {
        let expectation = self.expectation(description: "link download and parsing")

        linkPreviewManager.fetchLinkPreview(for: URL(string: "https://www.youtube.com/watch?v=tP-Ipsat90c")!)
            .done { (draft: OWSLinkPreviewDraft) in
                XCTAssertNotNil(draft)

                XCTAssertEqual(draft.title, "Randomness is Random - Numberphile")
                XCTAssertNotNil(draft.imageData)

                expectation.fulfill()
            }.catch { (error) in
                Logger.error("error: \(error)")
                XCTFail("Unexpected error: \(error)")
                expectation.fulfill()
            }

        self.waitForExpectations(timeout: 15.0, handler: nil)
    }

    func testLinkDataParsing_Empty() {
        let linkText = ""

        let content = OpenGraphContent(parsing: linkText)
        XCTAssertNotNil(content)

        XCTAssertNil(content.title)
        XCTAssertNil(content.imageUrl)
    }

    func testLinkDataParsing() {
        let linkText = ("<meta property=\"og:title\" content=\"Randomness is Random - Numberphile\">" +
                        "<meta property=\"og:image\" content=\"https://i.ytimg.com/vi/tP-Ipsat90c/maxresdefault.jpg\">")

        let content = OpenGraphContent(parsing: linkText)
        XCTAssertNotNil(content)

        XCTAssertEqual(content.title, "Randomness is Random - Numberphile")
        XCTAssertEqual(content.imageUrl, "https://i.ytimg.com/vi/tP-Ipsat90c/maxresdefault.jpg")
    }

    func testLinkParsingWithRealData1() {
        let expectation = self.expectation(description: "link download and parsing")

        linkPreviewManager.fetchStringResource(from: URL(string: "https://www.youtube.com/watch?v=tP-Ipsat90c")!)
            .done { linkText in
                let content = OpenGraphContent(parsing: linkText)
                XCTAssertNotNil(content)

                XCTAssertEqual(content.title, "Randomness is Random - Numberphile")
                XCTAssertEqual(content.imageUrl, "https://i.ytimg.com/vi/tP-Ipsat90c/maxresdefault.jpg")

                expectation.fulfill()
            }.catch { (error) in
                Logger.error("error: \(error)")
                XCTFail("Unexpected error: \(error)")
                expectation.fulfill()
            }

        self.waitForExpectations(timeout: 15.0, handler: nil)
    }

    func testLinkParsingWithRealData2() {
        let expectation = self.expectation(description: "link download and parsing")

        linkPreviewManager.fetchStringResource(from: URL(string: "https://youtu.be/tP-Ipsat90c")!)
            .done { linkText in
                let content = OpenGraphContent(parsing: linkText)
                XCTAssertNotNil(content)

                XCTAssertEqual(content.title, "Randomness is Random - Numberphile")
                XCTAssertEqual(content.imageUrl, "https://i.ytimg.com/vi/tP-Ipsat90c/maxresdefault.jpg")

                expectation.fulfill()
            }.catch { (error) in
                Logger.error("error: \(error)")
                XCTFail("Unexpected error: \(error)")
                expectation.fulfill()
            }

        self.waitForExpectations(timeout: 15.0, handler: nil)
    }

    func testLinkParsingWithRealData3() {
        let expectation = self.expectation(description: "link download and parsing")

        linkPreviewManager.fetchStringResource(from: URL(string:
            "https://www.reddit.com/r/memes/comments/c3p3dy/i_drew_all_the_boys_together_and_i_did_it_for_the/")!)
            .done { linkText in
                let content = OpenGraphContent(parsing: linkText)
                XCTAssertNotNil(content)

                XCTAssertEqual(content.title, "r/memes - I drew all the boys together and i did it for the internet")
                XCTAssertEqual(content.imageUrl, "https://preview.redd.it/yb3996njhw531.jpg?auto=webp&s=f8977087ab74e57063fff19c5df9534f22c0f521")

                expectation.fulfill()
            }.catch { (error) in
                Logger.error("error: \(error)")
                XCTFail("Unexpected error: \(error)")
                expectation.fulfill()
            }

        self.waitForExpectations(timeout: 15.0, handler: nil)
    }

    func testLinkParsingWithRealData4() {
        let expectation = self.expectation(description: "link download and parsing")

        linkPreviewManager.fetchStringResource(from: URL(string: "https://www.reddit.com/r/WhitePeopleTwitter/comments/a7j3mm/why/")!)
            .done { linkText in
                let content = OpenGraphContent(parsing: linkText)
                XCTAssertNotNil(content)

                XCTAssertEqual(content.title, "r/WhitePeopleTwitter - Why")
                XCTAssertEqual(content.imageUrl, "https://preview.redd.it/ehakvm9vx5521.jpg?auto=webp&s=925fb2d8776ca7102b944ab00e0615ae20c1bd5a")

                expectation.fulfill()
            }.catch { (error) in
                Logger.error("error: \(error)")
                XCTFail("Unexpected error: \(error)")
                expectation.fulfill()
            }

        self.waitForExpectations(timeout: 15.0, handler: nil)
    }

    func testLinkParsingWithRealData5() {
        let expectation = self.expectation(description: "link download and parsing")

        linkPreviewManager.fetchStringResource(from: URL(string: "https://imgur.com/gallery/KFCL8fm")!)
            .done { linkText in
                let content = OpenGraphContent(parsing: linkText)
                XCTAssertNotNil(content)

                XCTAssertEqual(content.title, "imgur.com")

                // Actual URL can change based on network response
                //
                // It seems like some parts of the URL are stable, but if this continues to be brittle we may choose
                // to remove it or stub the network response
                XCTAssertTrue(content.imageUrl!.hasPrefix("https://i.imgur.com/Y3wjlwY."))

                expectation.fulfill()
            }.catch { (error) in
                Logger.error("error: \(error)")
                XCTFail("Unexpected error: \(error)")
                expectation.fulfill()
            }

        self.waitForExpectations(timeout: 15.0, handler: nil)
    }

    func testLinkParsingWithRealData6() {
        let expectation = self.expectation(description: "link download and parsing")

        linkPreviewManager.fetchStringResource(from: URL(string: "https://imgur.com/gallery/FMdwTiV")!)
            .done { linkText in
                let content = OpenGraphContent(parsing: linkText)
                XCTAssertNotNil(content)

                XCTAssertEqual(content.title, "Freddy would be proud!")
                XCTAssertEqual(content.imageUrl, "https://i.imgur.com/Vot3iHh.jpg?fbplay")

                expectation.fulfill()
            }.catch { (error) in
                Logger.error("error: \(error)")
                XCTFail("Unexpected error: \(error)")
                expectation.fulfill()
            }

        self.waitForExpectations(timeout: 15.0, handler: nil)
    }

    func testLinkParsingWithRealData_instagram_web_link() {
        let expectation = self.expectation(description: "link download and parsing")

        linkPreviewManager.fetchStringResource(from: URL(string: "https://www.instagram.com/p/BtjTTyHnDKJ/?utm_source=ig_web_button_share_sheet")!)
            .done { linkText in
                let content = OpenGraphContent(parsing: linkText)
                XCTAssertNotNil(content)

                XCTAssertEqual(content.title, "Signal on Instagram: “I link therefore I am: https://signal.org/blog/i-link-therefore-i-am/”")
                // Actual URL can change based on network response
                //
                // It seems like some parts of the URL are stable, so we can pattern match, but if this continues to be brittle we may choose
                // to remove it or stub the network response
                XCTAssertMatch(expectedPattern: "^https://.*.cdninstagram.com/.*/50654775_634096837020403_4737154112061769375_n.jpg\\?.*$",
                               actualText: content.imageUrl!)
//                XCTAssertEqual(content.imageUrl, "https://scontent-iad3-1.cdninstagram.com/vp/88656d9c10074b97b503d3b7b86eba84/5D774562/t51.2885-15/e35/50654775_634096837020403_4737154112061769375_n.jpg?_nc_ht=scontent-iad3-1.cdninstagram.com")

                expectation.fulfill()
            }.catch { (error) in
                Logger.error("error: \(error)")
                XCTFail("Unexpected error: \(error)")
                expectation.fulfill()
            }

        self.waitForExpectations(timeout: 15.0, handler: nil)
    }

    func testLinkParsingWithRealData_instagram_app_sharesheet() {
        let expectation = self.expectation(description: "link download and parsing")

        linkPreviewManager.fetchStringResource(from: URL(string: "https://www.instagram.com/p/BtjTTyHnDKJ/?utm_source=ig_share_sheet&igshid=1bgo1ur9m9hi5")!)
            .done { linkText in
                let content = OpenGraphContent(parsing: linkText)
                XCTAssertNotNil(content)

                XCTAssertEqual(content.title, "Signal on Instagram: “I link therefore I am: https://signal.org/blog/i-link-therefore-i-am/”")
                // Actual URL can change based on network response
                //
                // It seems like some parts of the URL are stable, so we can pattern match, but if this continues to be brittle we may choose
                // to remove it or stub the network response
                XCTAssertMatch(expectedPattern: "^https://.*.cdninstagram.com/.*/50654775_634096837020403_4737154112061769375_n.jpg\\?.*$",
                               actualText: content.imageUrl!)
                //                XCTAssertEqual(content.imageUrl, "https://scontent-iad3-1.cdninstagram.com/vp/88656d9c10074b97b503d3b7b86eba84/5D774562/t51.2885-15/e35/50654775_634096837020403_4737154112061769375_n.jpg?_nc_ht=scontent-iad3-1.cdninstagram.com")

                expectation.fulfill()
            }.catch { (error) in
                Logger.error("error: \(error)")
                XCTFail("Unexpected error: \(error)")
                expectation.fulfill()
            }

        self.waitForExpectations(timeout: 15.0, handler: nil)
    }

    func testLinkParsingWithRealData9() {
        let expectation = self.expectation(description: "link download and parsing")

        linkPreviewManager.fetchStringResource(from: URL(string: "https://imgur.com/gallery/igHOwDM")!)
            .done { linkText in
                let content = OpenGraphContent(parsing: linkText)
                XCTAssertNotNil(content)

                XCTAssertEqual(content.title, "Sheet dance")
                XCTAssertEqual(content.imageUrl, "https://i.imgur.com/PYiyLv1.jpg?fbplay")

                expectation.fulfill()
            }.catch { (error) in
                Logger.error("error: \(error)")
                XCTFail("Unexpected error: \(error)")
                expectation.fulfill()
            }

        self.waitForExpectations(timeout: 15.0, handler: nil)
    }

    func testLinkParsingWithRealData10() {
        let expectation = self.expectation(description: "link download and parsing")

        linkPreviewManager.fetchStringResource(from: URL(string: "https://www.pinterest.com/norat0464/test-board/")!)
            .done { linkText in
                let content = OpenGraphContent(parsing: linkText)
                XCTAssertNotNil(content)

                XCTAssertEqual(content.title, "Test board")
                XCTAssertEqual(content.imageUrl, "https://i.pinimg.com/200x150/3e/85/f8/3e85f88e7be0dd1418a5b430d2ee8a55.jpg")

                expectation.fulfill()
            }.catch { (error) in
                Logger.error("error: \(error)")
                XCTFail("Unexpected error: \(error)")
                expectation.fulfill()
            }

        self.waitForExpectations(timeout: 15.0, handler: nil)
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

    var linkPreviewManager: OWSLinkPreviewManager {
        return SSKEnvironment.shared.linkPreviewManager
    }

    private func Assert(bodyText: String, extractsLink link: URL?, file: StaticString = #file, line: UInt = #line) {
        let actual = linkPreviewManager.findFirstValidUrl(in: bodyText)
        XCTAssertEqual(actual, link, file: file, line: line)
    }
}
