//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing

@testable import SignalServiceKit

struct MessageBodyAttachmentLimitsTest {
    private let limits = MessageBodyAttachmentLimits()

    // MARK: - Allowed combinations

    @Test
    func testEmpty() throws {
        let validated = try limits.validateMessageBodyProtos([])
        #expect(validated.isEmpty)
        #expect(validated.wrapped.isEmpty)
    }

    @Test
    func testProtosPassedThroughUnchanged() throws {
        let protos = [oversizeTextProto(), visualMediaProto(), visualMediaProto()]
        let validated = try limits.validateMessageBodyProtos(protos)
        #expect(!validated.isEmpty)
        #expect(validated.wrapped.count == protos.count)
        #expect(zip(validated.wrapped, protos).allSatisfy { $0 === $1 })
    }

    @Test
    func testMaxVisualMedia() throws {
        let protos = visualMediaProtos(count: MessageBodyAttachmentLimits.maxAllowedVisualMedia)
        let validated = try limits.validateMessageBodyProtos(protos)
        #expect(validated.wrapped.count == MessageBodyAttachmentLimits.maxAllowedVisualMedia)
    }

    @Test
    func testMaxVisualMediaWithOversizeText() throws {
        let protos =
            visualMediaProtos(count: MessageBodyAttachmentLimits.maxAllowedVisualMedia)
                + [oversizeTextProto()]
        #expect(protos.count == MessageBodyAttachmentLimits.maxAllowedOverall)
        let validated = try limits.validateMessageBodyProtos(protos)
        #expect(validated.wrapped.count == MessageBodyAttachmentLimits.maxAllowedOverall)
    }

    @Test(arguments: [
        MimeType.applicationPdf.rawValue,
        "audio/aac",
        MimeType.applicationOctetStream.rawValue,
    ])
    func testSingleNonVisualMedia(mimeType: String) throws {
        let validated = try limits.validateMessageBodyProtos([proto(contentType: mimeType)])
        #expect(validated.wrapped.count == 1)
    }

    @Test
    func testNonVisualMediaWithOversizeText() throws {
        let protos = [oversizeTextProto(), proto(contentType: MimeType.applicationPdf.rawValue)]
        let validated = try limits.validateMessageBodyProtos(protos)
        #expect(validated.wrapped.count == 2)
    }

    // MARK: - Rejected combinations

    @Test
    func testTooManyOverall() {
        let protos = visualMediaProtos(count: MessageBodyAttachmentLimits.maxAllowedOverall + 1)
        #expect(throws: OWSGenericError.self) {
            try limits.validateMessageBodyProtos(protos)
        }
    }

    @Test
    func testTooManyVisualMedia() {
        // Under the overall limit, but over the visual-media limit.
        let protos = visualMediaProtos(count: MessageBodyAttachmentLimits.maxAllowedVisualMedia + 1)
        #expect(protos.count <= MessageBodyAttachmentLimits.maxAllowedOverall)
        #expect(throws: OWSGenericError.self) {
            try limits.validateMessageBodyProtos(protos)
        }
    }

    @Test
    func testTooManyOversizeText() {
        #expect(throws: OWSGenericError.self) {
            try limits.validateMessageBodyProtos([oversizeTextProto(), oversizeTextProto()])
        }
    }

    @Test
    func testTooManyNonVisualMedia() {
        let protos = [
            proto(contentType: MimeType.applicationPdf.rawValue),
            proto(contentType: "audio/aac"),
        ]
        #expect(throws: OWSGenericError.self) {
            try limits.validateMessageBodyProtos(protos)
        }
    }

    @Test
    func testMixedVisualAndNonVisualMedia() {
        let protos = [visualMediaProto(), proto(contentType: MimeType.applicationPdf.rawValue)]
        #expect(throws: OWSGenericError.self) {
            try limits.validateMessageBodyProtos(protos)
        }
        #expect(throws: OWSGenericError.self) {
            try limits.validateMessageBodyProtos(protos.reversed())
        }
    }

    // MARK: - Content type inference

    @Test
    func testContentTypeInferredFromFileName() throws {
        // Two visual-media protos are allowed, so this only validates if the
        // missing content type is inferred from the filename.
        let protos = [proto(fileName: "image.jpg"), proto(fileName: "image.jpg")]
        let validated = try limits.validateMessageBodyProtos(protos)
        #expect(validated.wrapped.count == 2)
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

    private func visualMediaProto() -> SSKProtoAttachmentPointer {
        return proto(contentType: MimeType.imageJpeg.rawValue)
    }

    private func visualMediaProtos(count: Int) -> [SSKProtoAttachmentPointer] {
        return (0..<count).map { _ in visualMediaProto() }
    }

    private func oversizeTextProto() -> SSKProtoAttachmentPointer {
        return proto(contentType: MimeType.textXSignalPlain.rawValue)
    }
}
