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
    let shouldRunNetworkTests = false

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testUrlSchemeValidation() {
        let testSuite: [String: String?] = [
            // Invalid: Explicit scheme is required
            "signal.org": nil,
            "www.signal.org": nil,
            "https.signal.org": nil,

            // Invalid: Scheme must be https
            "http://www.signal.org": nil,
            "ftp://www.signal.org": nil,

            // Valid
            "https://signal.org": "https://signal.org",
            "HTTPS://signal.org": "HTTPS://signal.org",
            "https://www.signal.org": "https://www.signal.org",
            "https://www.signal.org:443/blahh.html?query=value": "https://www.signal.org:443/blahh.html?query=value",
            "https://test.signal.org/": "https://test.signal.org/"
        ]
        testSuite.forEach { string, expectedString in
            let url = linkPreviewManager.findFirstValidUrl(in: string)
            XCTAssertEqual(url?.absoluteString, expectedString)
        }
    }

    // Ensure that we reject username+pass and invalid TLDs
    func testRejectedUrlFields() {
        let testSuite: [String: String?] = [
            // Invalid: Username/Password disallowed
            "https://mlin@www.signal.org": nil,
            "https://:pass@www.signal.org": nil,
            "https://mlin:mypass@www.signal.org": nil,

            // Invalid: .onion TLD explicitly disallowed
            "https://3g2upl4pq6kufc4m.onion": nil,
            "https://3g2upl4pq6kufc4m.ONION": nil,
            "https://3g2upl4pq6kufc4m....onion": nil,

            // Valid
            "https://3g2upl4pq6kufc4m.onion.com": "https://3g2upl4pq6kufc4m.onion.com",
            "https://3g2upl4pq6kufc4m.oniony": "https://3g2upl4pq6kufc4m.oniony",
            "https://3g2upl4pq6kufc4m.oonion": "https://3g2upl4pq6kufc4m.oonion",
            "https://3g2upl4pq6kufc4m.oniony/onion": "https://3g2upl4pq6kufc4m.oniony/onion",
            "https://3g2upl4pq6kufc4m.oniony#onion": "https://3g2upl4pq6kufc4m.oniony#onion"
        ]
        testSuite.forEach { string, expectedString in
            let url = linkPreviewManager.findFirstValidUrl(in: string)
            XCTAssertEqual(url?.absoluteString, expectedString)
        }
    }

    func testMixedCharacterSetUrls() {
        let testSuite: [String: String?] = [
            // Invalid, mixed-ASCII
            "https://www.wikipediа.org": nil, // (а is cyrillic)
            "https://www.wikipediä.org": nil,

            // This is a valid URL. Our heuristic is a little sensitive
            // If we relax our heuristic and this returns non-nil, that's okay
            "https://中国互联网络信息中心.cn": nil,

            // NSDataDetector parsing failures
            "https://中国互联网络信息中心。中国": nil,   // NSDataDetector does not parse a TLD of "。中国"

            // Valid, all ASCII or non-ASCII + period
            "https://中国互联网络信息中心.中国": "https://xn--fiqa61au8b7zsevnm8ak20mc4a87e.xn--fiqs8s",
            "https://中国互联网络信息中心.中国/nonASCIIPath": "https://xn--fiqa61au8b7zsevnm8ak20mc4a87e.xn--fiqs8s/nonASCIIPath",
            "https://中国互联网络信息中心.中国?nonASCIIQuery": "https://xn--fiqa61au8b7zsevnm8ak20mc4a87e.xn--fiqs8s?nonASCIIQuery",
            "https://中国互联网络信息中心.中国#fragment": "https://xn--fiqa61au8b7zsevnm8ak20mc4a87e.xn--fiqs8s#fragment",
            "https://signal.org/你好": "https://signal.org/%E4%BD%A0%E5%A5%BD",
            "https://signal.org?你好": "https://signal.org?%E4%BD%A0%E5%A5%BD",
            "https://signal.org#你好": "https://signal.org#%E4%BD%A0%E5%A5%BD"
        ]

        testSuite.forEach { string, expectedString in
            let url = linkPreviewManager.findFirstValidUrl(in: string)
            XCTAssertEqual(url?.absoluteString, expectedString)
        }
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

    var linkPreviewManager: OWSLinkPreviewManager {
        return SSKEnvironment.shared.linkPreviewManager
    }

    private func Assert(bodyText: String, extractsLink link: URL?, file: StaticString = #file, line: UInt = #line) {
        let actual = linkPreviewManager.findFirstValidUrl(in: bodyText)
        XCTAssertEqual(actual, link, file: file, line: line)
    }
}

// MARK: - Network dependent tests, disabled by default

extension OWSLinkPreviewTest {

    func testLinkDownloadAndParsing() {
        guard shouldRunNetworkTests else { return }

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

    func testLinkParsingWithRealData1() {
        guard shouldRunNetworkTests else { return }

        let expectation = self.expectation(description: "link download and parsing")

        linkPreviewManager.fetchStringResource(from: URL(string: "https://www.youtube.com/watch?v=tP-Ipsat90c")!)
            .done { _, linkText in
                let content = HTMLMetadata.construct(parsing: linkText)
                XCTAssertNotNil(content)

                XCTAssertEqual(content.ogTitle, "Randomness is Random - Numberphile")
                XCTAssertEqual(content.ogImageUrlString, "https://i.ytimg.com/vi/tP-Ipsat90c/maxresdefault.jpg")

                expectation.fulfill()
        }.catch { (error) in
            Logger.error("error: \(error)")
            XCTFail("Unexpected error: \(error)")
            expectation.fulfill()
        }

        self.waitForExpectations(timeout: 15.0, handler: nil)
    }

    func testLinkParsingWithRealData2() {
        guard shouldRunNetworkTests else { return }

        let expectation = self.expectation(description: "link download and parsing")

        linkPreviewManager.fetchStringResource(from: URL(string: "https://youtu.be/tP-Ipsat90c")!)
            .done { _, linkText in
                let content = HTMLMetadata.construct(parsing: linkText)
                XCTAssertNotNil(content)

                XCTAssertEqual(content.ogTitle, "Randomness is Random - Numberphile")
                XCTAssertEqual(content.ogImageUrlString, "https://i.ytimg.com/vi/tP-Ipsat90c/maxresdefault.jpg")

                expectation.fulfill()
        }.catch { (error) in
            Logger.error("error: \(error)")
            XCTFail("Unexpected error: \(error)")
            expectation.fulfill()
        }

        self.waitForExpectations(timeout: 15.0, handler: nil)
    }

    func testLinkParsingWithRealData3() {
        guard shouldRunNetworkTests else { return }

        let expectation = self.expectation(description: "link download and parsing")

        linkPreviewManager.fetchStringResource(from: URL(string:
            "https://www.reddit.com/r/memes/comments/c3p3dy/i_drew_all_the_boys_together_and_i_did_it_for_the/")!)
            .done { _, linkText in
                let content = HTMLMetadata.construct(parsing: linkText)
                XCTAssertNotNil(content)

                XCTAssertEqual(content.ogTitle, "r/memes - I drew all the boys together and i did it for the internet")
                XCTAssertEqual(content.ogImageUrlString, "https://preview.redd.it/yb3996njhw531.jpg?auto=webp&s=f8977087ab74e57063fff19c5df9534f22c0f521")

                expectation.fulfill()
        }.catch { (error) in
            Logger.error("error: \(error)")
            XCTFail("Unexpected error: \(error)")
            expectation.fulfill()
        }

        self.waitForExpectations(timeout: 15.0, handler: nil)
    }

    func testLinkParsingWithRealData4() {
        guard shouldRunNetworkTests else { return }

        let expectation = self.expectation(description: "link download and parsing")

        linkPreviewManager.fetchStringResource(from: URL(string: "https://www.reddit.com/r/WhitePeopleTwitter/comments/a7j3mm/why/")!)
            .done { _, linkText in
                let content = HTMLMetadata.construct(parsing: linkText)
                XCTAssertNotNil(content)

                XCTAssertEqual(content.ogTitle, "r/WhitePeopleTwitter - Why")
                XCTAssertEqual(content.ogImageUrlString, "https://preview.redd.it/ehakvm9vx5521.jpg?auto=webp&s=925fb2d8776ca7102b944ab00e0615ae20c1bd5a")

                expectation.fulfill()
        }.catch { (error) in
            Logger.error("error: \(error)")
            XCTFail("Unexpected error: \(error)")
            expectation.fulfill()
        }

        self.waitForExpectations(timeout: 15.0, handler: nil)
    }

    func testLinkParsingWithRealData5() {
        guard shouldRunNetworkTests else { return }

        let expectation = self.expectation(description: "link download and parsing")

        linkPreviewManager.fetchStringResource(from: URL(string: "https://imgur.com/gallery/KFCL8fm")!)
            .done { _, linkText in
                let content = HTMLMetadata.construct(parsing: linkText)
                XCTAssertNotNil(content)

                XCTAssertEqual(content.ogTitle, "imgur.com")

                // Actual URL can change based on network response
                //
                // It seems like some parts of the URL are stable, but if this continues to be brittle we may choose
                // to remove it or stub the network response
                XCTAssertTrue(content.ogImageUrlString!.hasPrefix("https://i.imgur.com/Y3wjlwY."))

                expectation.fulfill()
        }.catch { (error) in
            Logger.error("error: \(error)")
            XCTFail("Unexpected error: \(error)")
            expectation.fulfill()
        }

        self.waitForExpectations(timeout: 15.0, handler: nil)
    }

    func testLinkParsingWithRealData6() {
        guard shouldRunNetworkTests else { return }

        let expectation = self.expectation(description: "link download and parsing")

        linkPreviewManager.fetchStringResource(from: URL(string: "https://imgur.com/gallery/FMdwTiV")!)
            .done { _, linkText in
                let content = HTMLMetadata.construct(parsing: linkText)
                XCTAssertNotNil(content)

                XCTAssertEqual(content.ogTitle, "Freddy would be proud!")
                XCTAssertEqual(content.ogImageUrlString, "https://i.imgur.com/Vot3iHh.jpg?fbplay")

                expectation.fulfill()
        }.catch { (error) in
            Logger.error("error: \(error)")
            XCTFail("Unexpected error: \(error)")
            expectation.fulfill()
        }

        self.waitForExpectations(timeout: 15.0, handler: nil)
    }

    func testLinkParsingWithRealData_instagram_web_link() {
        guard shouldRunNetworkTests else { return }

        let expectation = self.expectation(description: "link download and parsing")

        linkPreviewManager.fetchStringResource(from: URL(string: "https://www.instagram.com/p/BtjTTyHnDKJ/?utm_source=ig_web_button_share_sheet")!)
            .done { _, linkText in
                let content = HTMLMetadata.construct(parsing: linkText)
                XCTAssertNotNil(content)

                XCTAssertEqual(content.ogTitle, "Signal on Instagram: “I link therefore I am: https://signal.org/blog/i-link-therefore-i-am/”")
                // Actual URL can change based on network response
                //
                // It seems like some parts of the URL are stable, so we can pattern match, but if this continues to be brittle we may choose
                // to remove it or stub the network response
                XCTAssertMatch(expectedPattern: "^https://.*.cdninstagram.com/.*/50654775_634096837020403_4737154112061769375_n.jpg\\?.*$",
                               actualText: content.ogImageUrlString!)
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
        guard shouldRunNetworkTests else { return }

        let expectation = self.expectation(description: "link download and parsing")

        linkPreviewManager.fetchStringResource(from: URL(string: "https://www.instagram.com/p/BtjTTyHnDKJ/?utm_source=ig_share_sheet&igshid=1bgo1ur9m9hi5")!)
            .done { _, linkText in
                let content = HTMLMetadata.construct(parsing: linkText)
                XCTAssertNotNil(content)

                XCTAssertEqual(content.ogTitle, "Signal on Instagram: “I link therefore I am: https://signal.org/blog/i-link-therefore-i-am/”")
                // Actual URL can change based on network response
                //
                // It seems like some parts of the URL are stable, so we can pattern match, but if this continues to be brittle we may choose
                // to remove it or stub the network response
                XCTAssertMatch(expectedPattern: "^https://.*.cdninstagram.com/.*/50654775_634096837020403_4737154112061769375_n.jpg\\?.*$",
                               actualText: content.ogImageUrlString!)
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
        guard shouldRunNetworkTests else { return }

        let expectation = self.expectation(description: "link download and parsing")

        linkPreviewManager.fetchStringResource(from: URL(string: "https://imgur.com/gallery/igHOwDM")!)
            .done { _, linkText in
                let content = HTMLMetadata.construct(parsing: linkText)
                XCTAssertNotNil(content)

                XCTAssertEqual(content.ogTitle, "Sheet dance")
                XCTAssertEqual(content.ogImageUrlString, "https://i.imgur.com/PYiyLv1.jpg?fbplay")

                expectation.fulfill()
        }.catch { (error) in
            Logger.error("error: \(error)")
            XCTFail("Unexpected error: \(error)")
            expectation.fulfill()
        }

        self.waitForExpectations(timeout: 15.0, handler: nil)
    }

    func testLinkParsingWithRealData10() {
        guard shouldRunNetworkTests else { return }

        let expectation = self.expectation(description: "link download and parsing")

        linkPreviewManager.fetchStringResource(from: URL(string: "https://www.pinterest.com/norat0464/test-board/")!)
            .done { _, linkText in
                let content = HTMLMetadata.construct(parsing: linkText)
                XCTAssertNotNil(content)

                XCTAssertEqual(content.ogTitle, "Test board")
                XCTAssertEqual(content.ogImageUrlString, "https://i.pinimg.com/200x150/3e/85/f8/3e85f88e7be0dd1418a5b430d2ee8a55.jpg")

                expectation.fulfill()
        }.catch { (error) in
            Logger.error("error: \(error)")
            XCTFail("Unexpected error: \(error)")
            expectation.fulfill()
        }

        self.waitForExpectations(timeout: 15.0, handler: nil)
    }
}
