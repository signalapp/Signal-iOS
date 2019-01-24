//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
@testable import SignalServiceKit
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
        XCTAssertTrue(OWSLinkPreview.isValidMediaUrl("https://www.youtube.com/watch?v=tP-Ipsat90c"))
        XCTAssertTrue(OWSLinkPreview.isValidMediaUrl("https://youtube.com/watch?v=tP-Ipsat90c"))

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
}
