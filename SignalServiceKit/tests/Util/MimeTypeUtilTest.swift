//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing

@testable import SignalServiceKit

struct MimeTypeUtilTest {

    // MARK: - Content type inference

    @Test(arguments: [
        // An explicit content type takes precedence over the filename.
        (MimeType.imageJpeg.rawValue, "image.png", MimeType.imageJpeg.rawValue),
        // Unrecognized content types are passed through as-is.
        ("not/a-real-mime-type", "image.jpg", "not/a-real-mime-type"),
        // A missing or empty content type is inferred from the file extension.
        (nil, "image.jpg", MimeType.imageJpeg.rawValue),
        ("", "image.jpg", MimeType.imageJpeg.rawValue),
        (nil, "doc.pdf", MimeType.applicationPdf.rawValue),
        // File extensions are matched case-insensitively.
        (nil, "image.JPG", MimeType.imageJpeg.rawValue),
        // A ".txt" file is plain text, not a message's oversize text.
        (nil, "long-message.txt", "text/plain"),
        // Anything else falls back to octet-stream.
        (nil, nil, MimeType.applicationOctetStream.rawValue),
        (nil, "", MimeType.applicationOctetStream.rawValue),
        (nil, "noextension", MimeType.applicationOctetStream.rawValue),
        (nil, "file.notarealextension", MimeType.applicationOctetStream.rawValue),
    ] as [(String?, String?, String)])
    func testMimeTypeOrInferredFromFileName(
        testCase: (contentType: String?, fileName: String?, expected: String),
    ) {
        let mimeType = MimeTypeUtil.mimeType(
            testCase.contentType,
            orInferredFrom: testCase.fileName,
        )
        #expect(mimeType == testCase.expected)
    }

    // MARK: - Attachment pointer protos

    @Test(arguments: [
        (MimeType.imageJpeg.rawValue, true),
        (MimeType.imagePng.rawValue, true),
        ("video/mp4", true),
        ("audio/aac", false),
        (MimeType.applicationPdf.rawValue, false),
        (MimeType.applicationOctetStream.rawValue, false),
        (MimeType.textXSignalPlain.rawValue, false),
    ] as [(String, Bool)])
    func testProtoIsVisualMedia(testCase: (contentType: String, expected: Bool)) {
        #expect(proto(contentType: testCase.contentType).isVisualMedia == testCase.expected)
    }

    @Test(arguments: [
        (MimeType.textXSignalPlain.rawValue, true),
        ("text/plain", false),
        (MimeType.imageJpeg.rawValue, false),
        (MimeType.applicationOctetStream.rawValue, false),
    ] as [(String, Bool)])
    func testProtoIsOversizeText(testCase: (contentType: String, expected: Bool)) {
        #expect(proto(contentType: testCase.contentType).isOversizeText == testCase.expected)
    }

    @Test
    func testProtoMimeType() {
        // Prefers the content type, falls back to the filename, then to
        // octet-stream.
        let withBoth = proto(contentType: MimeType.imageJpeg.rawValue, fileName: "doc.pdf")
        #expect(withBoth.mimeType == MimeType.imageJpeg.rawValue)
        #expect(proto(fileName: "image.JPG").mimeType == MimeType.imageJpeg.rawValue)
        #expect(proto().mimeType == MimeType.applicationOctetStream.rawValue)
    }

    @Test
    func testProtoClassifiedByInferredMimeType() {
        // Classification uses the inferred MIME type, not just the content type.
        #expect(proto(fileName: "image.jpg").isVisualMedia)
        #expect(!proto(fileName: "doc.pdf").isVisualMedia)
        #expect(!proto(fileName: "long-message.txt").isOversizeText)
    }

    // MARK: - Helpers

    private func proto(
        contentType: String? = nil,
        fileName: String? = nil,
    ) -> SSKProtoAttachmentPointer {
        let builder = SSKProtoAttachmentPointer.builder()
        if let contentType {
            builder.setContentType(contentType)
        }
        if let fileName {
            builder.setFileName(fileName)
        }
        return builder.buildInfallibly()
    }
}
