//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
@testable import SignalServiceKit
import XCTest

func XCTAssertMatch(expectedPattern: String, actualText: String, file: StaticString = #file, line: UInt = #line) {
    let regex = try! NSRegularExpression(pattern: expectedPattern, options: [])
    XCTAssert(regex.hasMatch(input: actualText), "\(actualText) did not match pattern \(expectedPattern)", file: file, line: line)
}

class MockSSKPreferences: LinkPreviewManagerImpl.Shims.SSKPreferences {

    init() {}

    func areLinkPreviewsEnabled(tx: DBReadTransaction) -> Bool {
        return true
    }
}

class OWSLinkPreviewTest: SSKBaseTest {
    let shouldRunNetworkTests = false

    var mockDB: MockDB!
    var linkPreviewManager: LinkPreviewManagerImpl!

    override func setUp() {
        super.setUp()

        mockDB = MockDB()
        linkPreviewManager = LinkPreviewManagerImpl(
            attachmentManager: TSResourceManagerMock(),
            attachmentStore: TSResourceStoreMock(),
            attachmentValidator: AttachmentContentValidatorMock(),
            db: mockDB,
            groupsV2: LinkPreviewManagerImpl.Wrappers.GroupsV2(MockGroupsV2()),
            sskPreferences: MockSSKPreferences()
        )
    }

    func testBuildValidatedLinkPreview_TitleAndImage() {
        let url = "https://www.youtube.com/watch?v=tP-Ipsat90c"
        let body = "\(url)"
        let previewBuilder = SSKProtoPreview.builder(url: url)
        previewBuilder.setTitle("Some Youtube Video")
        let imageAttachmentBuilder = SSKProtoAttachmentPointer.builder()
        imageAttachmentBuilder.setCdnID(1)
        imageAttachmentBuilder.setKey(Randomness.generateRandomBytes(32))
        imageAttachmentBuilder.setContentType(MimeType.imageJpeg.rawValue)
        previewBuilder.setImage(imageAttachmentBuilder.buildInfallibly())
        let dataBuilder = SSKProtoDataMessage.builder()
        dataBuilder.addPreview(try! previewBuilder.build())
        dataBuilder.setBody(body)
        let dataMessage = try! dataBuilder.build()

        mockDB.write { tx in
            let linkPreviewBuilder = try! linkPreviewManager.validateAndBuildLinkPreview(
                from: dataMessage.preview.first!,
                dataMessage: dataMessage,
                ownerType: .message,
                tx: tx
            )
            XCTAssertNotNil(linkPreviewBuilder)
            try! linkPreviewBuilder.finalize(
                owner: .messageLinkPreview(.init(
                    messageRowId: 0,
                    receivedAtTimestamp: 1000,
                    threadRowId: 0
                )),
                tx: tx
            )
        }
    }

    func testBuildValidatedLinkPreview_Title() {
        let url = "https://www.youtube.com/watch?v=tP-Ipsat90c"
        let body = "\(url)"
        let previewBuilder = SSKProtoPreview.builder(url: url)
        previewBuilder.setTitle("Some Youtube Video")
        let dataBuilder = SSKProtoDataMessage.builder()
        dataBuilder.addPreview(try! previewBuilder.build())
        dataBuilder.setBody(body)
        let dataMessage = try! dataBuilder.build()

        mockDB.write { tx in
            let linkPreviewBuilder = try! linkPreviewManager.validateAndBuildLinkPreview(
                from: dataMessage.preview.first!,
                dataMessage: dataMessage,
                ownerType: .message,
                tx: tx
            )
            XCTAssertNotNil(linkPreviewBuilder)
            try! linkPreviewBuilder.finalize(
                owner: .messageLinkPreview(.init(
                    messageRowId: 0,
                    receivedAtTimestamp: 100,
                    threadRowId: 0
                )),
                tx: tx
            )
        }
    }

    func testBuildValidatedLinkPreview_Image() {
        let url = "https://www.youtube.com/watch?v=tP-Ipsat90c"
        let body = "\(url)"
        let previewBuilder = SSKProtoPreview.builder(url: url)
        let imageAttachmentBuilder = SSKProtoAttachmentPointer.builder()
        imageAttachmentBuilder.setCdnID(1)
        imageAttachmentBuilder.setKey(Randomness.generateRandomBytes(32))
        imageAttachmentBuilder.setContentType(MimeType.imageJpeg.rawValue)
        previewBuilder.setImage(imageAttachmentBuilder.buildInfallibly())
        let dataBuilder = SSKProtoDataMessage.builder()
        dataBuilder.addPreview(try! previewBuilder.build())
        dataBuilder.setBody(body)
        let dataMessage = try! dataBuilder.build()

        mockDB.write { tx in
            let linkPreviewBuilder = try! linkPreviewManager.validateAndBuildLinkPreview(
                from: dataMessage.preview.first!,
                dataMessage: dataMessage,
                ownerType: .message,
                tx: tx
            )
            XCTAssertNotNil(linkPreviewBuilder)
            try! linkPreviewBuilder.finalize(
                owner: .messageLinkPreview(.init(
                    messageRowId: 0,
                    receivedAtTimestamp: 300,
                    threadRowId: 1
                )),
                tx: tx
            )
        }
    }
}

// MARK: - Network dependent tests, disabled by default

extension OWSLinkPreviewTest {

    func testLinkDownloadAndParsing() async throws {
        try XCTSkipUnless(shouldRunNetworkTests)

        let draft = try await linkPreviewManager.fetchLinkPreview(for: URL(string: "https://www.youtube.com/watch?v=tP-Ipsat90c")!)
        XCTAssertEqual(draft.title, "Randomness is Random - Numberphile")
        XCTAssertNotNil(draft.imageData)
    }

    func testLinkParsingWithRealData1() async throws {
        try XCTSkipUnless(shouldRunNetworkTests)

        let (_, linkText) = try await linkPreviewManager.fetchStringResource(from: URL(string: "https://www.youtube.com/watch?v=tP-Ipsat90c")!)

        let content = HTMLMetadata.construct(parsing: linkText)
        XCTAssertNotNil(content)

        XCTAssertEqual(content.ogTitle, "Randomness is Random - Numberphile")
        XCTAssertEqual(content.ogImageUrlString, "https://i.ytimg.com/vi/tP-Ipsat90c/maxresdefault.jpg")
    }

    func testLinkParsingWithRealData2() async throws {
        try XCTSkipUnless(shouldRunNetworkTests)

        let (_, linkText) = try await linkPreviewManager.fetchStringResource(from: URL(string: "https://youtu.be/tP-Ipsat90c")!)

        let content = HTMLMetadata.construct(parsing: linkText)
        XCTAssertNotNil(content)

        XCTAssertEqual(content.ogTitle, "Randomness is Random - Numberphile")
        XCTAssertEqual(content.ogImageUrlString, "https://i.ytimg.com/vi/tP-Ipsat90c/maxresdefault.jpg")
    }

    func testLinkParsingWithRealData3() async throws {
        try XCTSkipUnless(shouldRunNetworkTests)

        let (_, linkText) = try await linkPreviewManager.fetchStringResource(from: URL(string: "https://www.reddit.com/r/memes/comments/c3p3dy/i_drew_all_the_boys_together_and_i_did_it_for_the/")!)

        let content = HTMLMetadata.construct(parsing: linkText)
        XCTAssertNotNil(content)

        XCTAssertEqual(content.ogTitle, "From the memes community on Reddit: I drew all the boys together and i did it for the internet")
        XCTAssertEqual(content.ogImageUrlString, "https://preview.redd.it/yb3996njhw531.jpg?width=1080&crop=smart&auto=webp&s=0f0c60355dcb7d051fdb2cf068aca3b669d7dbda")
    }

    func testLinkParsingWithRealData4() async throws {
        try XCTSkipUnless(shouldRunNetworkTests)

        let (_, linkText) = try await linkPreviewManager.fetchStringResource(from: URL(string: "https://www.reddit.com/r/WhitePeopleTwitter/comments/a7j3mm/why/")!)

        let content = HTMLMetadata.construct(parsing: linkText)
        XCTAssertNotNil(content)

        XCTAssertEqual(content.ogTitle, "From the WhitePeopleTwitter community on Reddit: Why")
        XCTAssertEqual(content.ogImageUrlString, "https://share.redd.it/preview/post/a7j3mm")
    }

    func testLinkParsingWithRealData5() async throws {
        try XCTSkipUnless(shouldRunNetworkTests)

        let (_, linkText) = try await linkPreviewManager.fetchStringResource(from: URL(string: "https://imgur.com/gallery/KFCL8fm")!)

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

        let (_, linkText) = try await linkPreviewManager.fetchStringResource(from: URL(string: "https://imgur.com/gallery/FMdwTiV")!)

        let content = HTMLMetadata.construct(parsing: linkText)
        XCTAssertNotNil(content)

        XCTAssertEqual(content.ogTitle, "Freddy would be proud!")
        XCTAssertEqual(content.ogImageUrlString, "https://i.imgur.com/Vot3iHh.jpg?fbplay")
    }

    func testLinkParsingWithRealData_instagram_web_link() async throws {
        try XCTSkipUnless(shouldRunNetworkTests)

        let (_, linkText) = try await linkPreviewManager.fetchStringResource(from: URL(string: "https://www.instagram.com/p/BtjTTyHnDKJ/?utm_source=ig_web_button_share_sheet")!)

        let content = HTMLMetadata.construct(parsing: linkText)
        XCTAssertNotNil(content)

        XCTAssertEqual(content.ogTitle, "Signal Messenger on Instagram: \"I link therefore I am: https://signal.org/blog/i-link-therefore-i-am/\"")
        // Actual URL can change based on network response
        //
        // It seems like some parts of the URL are stable, so we can pattern match, but if this continues to be brittle we may choose
        // to remove it or stub the network response
        XCTAssertMatch(expectedPattern: "^https://.*.cdninstagram.com/.*/50654775_634096837020403_4737154112061769375_n.jpg\\?.*$",
                       actualText: content.ogImageUrlString!)
        //                XCTAssertEqual(content.imageUrl, "https://scontent-iad3-1.cdninstagram.com/vp/88656d9c10074b97b503d3b7b86eba84/5D774562/t51.2885-15/e35/50654775_634096837020403_4737154112061769375_n.jpg?_nc_ht=scontent-iad3-1.cdninstagram.com")
    }

    func testLinkParsingWithRealData_instagram_app_sharesheet() async throws {
        try XCTSkipUnless(shouldRunNetworkTests)

        let (_, linkText) = try await linkPreviewManager.fetchStringResource(from: URL(string: "https://www.instagram.com/p/BtjTTyHnDKJ/?utm_source=ig_share_sheet&igshid=1bgo1ur9m9hi5")!)

        let content = HTMLMetadata.construct(parsing: linkText)
        XCTAssertNotNil(content)

        XCTAssertEqual(content.ogTitle, "Signal Messenger on Instagram: \"I link therefore I am: https://signal.org/blog/i-link-therefore-i-am/\"")
        // Actual URL can change based on network response
        //
        // It seems like some parts of the URL are stable, so we can pattern match, but if this continues to be brittle we may choose
        // to remove it or stub the network response
        XCTAssertMatch(expectedPattern: "^https://.*.cdninstagram.com/.*/50654775_634096837020403_4737154112061769375_n.jpg\\?.*$",
                       actualText: content.ogImageUrlString!)
        //                XCTAssertEqual(content.imageUrl, "https://scontent-iad3-1.cdninstagram.com/vp/88656d9c10074b97b503d3b7b86eba84/5D774562/t51.2885-15/e35/50654775_634096837020403_4737154112061769375_n.jpg?_nc_ht=scontent-iad3-1.cdninstagram.com")
    }

    func testLinkParsingWithRealData9() async throws {
        try XCTSkipUnless(shouldRunNetworkTests)

        let (_, linkText) = try await linkPreviewManager.fetchStringResource(from: URL(string: "https://imgur.com/gallery/igHOwDM")!)

        let content = HTMLMetadata.construct(parsing: linkText)
        XCTAssertNotNil(content)

        XCTAssertEqual(content.ogTitle, "Sheet dance")
        XCTAssertEqual(content.ogImageUrlString, "https://i.imgur.com/PYiyLv1.jpg?fbplay")
    }

    func testLinkParsingWithRealData10() async throws {
        try XCTSkipUnless(shouldRunNetworkTests)

        let (_, linkText) = try await linkPreviewManager.fetchStringResource(from: URL(string: "https://www.pinterest.com/norat0464/test-board/")!)

        let content = HTMLMetadata.construct(parsing: linkText)
        XCTAssertNotNil(content)

        XCTAssertEqual(content.ogTitle, "Test board")
        XCTAssertEqual(content.ogImageUrlString, "https://i.pinimg.com/200x150/3e/85/f8/3e85f88e7be0dd1418a5b430d2ee8a55.jpg")
    }
}
