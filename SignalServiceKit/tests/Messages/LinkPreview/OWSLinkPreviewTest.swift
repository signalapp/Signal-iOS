//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
@testable import SignalServiceKit

class OWSLinkPreviewTest: XCTestCase {
    var linkPreviewManager: LinkPreviewManagerImpl!

    override func setUp() {
        super.setUp()

        linkPreviewManager = LinkPreviewManagerImpl(
            attachmentManager: AttachmentManagerMock(),
            attachmentStore: AttachmentStore(),
            attachmentValidator: AttachmentContentValidatorMock(),
            db: InMemoryDB(),
            linkPreviewSettingStore: LinkPreviewSettingStore.mock(),
        )
    }

    func testBuildValidatedLinkPreview_TitleAndImage() throws {
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

        _ = try linkPreviewManager.validateAndBuildLinkPreview(
            from: dataMessage.preview.first!,
            dataMessage: dataMessage,
        )
    }

    func testBuildValidatedLinkPreview_Title() throws {
        let url = "https://www.youtube.com/watch?v=tP-Ipsat90c"
        let body = "\(url)"
        let previewBuilder = SSKProtoPreview.builder(url: url)
        previewBuilder.setTitle("Some Youtube Video")
        let dataBuilder = SSKProtoDataMessage.builder()
        dataBuilder.addPreview(try! previewBuilder.build())
        dataBuilder.setBody(body)
        let dataMessage = try! dataBuilder.build()

        _ = try linkPreviewManager.validateAndBuildLinkPreview(
            from: dataMessage.preview.first!,
            dataMessage: dataMessage,
        )
    }

    func testBuildValidatedLinkPreview_Image() throws {
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

        _ = try linkPreviewManager.validateAndBuildLinkPreview(
            from: dataMessage.preview.first!,
            dataMessage: dataMessage,
        )
    }
}
