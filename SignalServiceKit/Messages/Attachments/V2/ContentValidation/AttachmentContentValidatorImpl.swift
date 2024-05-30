//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class AttachmentContentValidatorImpl: AttachmentContentValidator {

    public init() {}

    public func validateContents(
        data: Data,
        mimeType: String
    ) throws -> Attachment.ContentType {
        return try validateContents(input: .inMemory(data), mimeType: mimeType)
    }

    public func validateContents(
        fileUrl: URL,
        mimeType: String
    ) throws -> Attachment.ContentType {
        return try validateContents(input: .unencryptedFile(fileUrl), mimeType: mimeType)
    }

    public func validateContents(
        encryptedFileAt fileUrl: URL,
        encryptionKey: Data,
        plaintextLength: UInt32,
        mimeType: String
    ) throws -> Attachment.ContentType {
        return try validateContents(
            input: .encryptedFile(
                fileUrl,
                encryptionKey: encryptionKey,
                plaintextLength: plaintextLength
            ),
            mimeType: mimeType
        )
    }

    // MARK: - Private

    // MARK: Genericizing inputs

    private enum Input {
        case inMemory(Data)
        case unencryptedFile(URL)
        case encryptedFile(URL, encryptionKey: Data, plaintextLength: UInt32)
    }

    private func rawContentType(mimeType: String) -> Attachment.ContentTypeRaw {
        if MimeTypeUtil.isSupportedVideoMimeType(mimeType) {
            return .video
        } else if MimeTypeUtil.isSupportedAudioMimeType(mimeType) {
            return .audio
        } else if MimeTypeUtil.isSupportedDefinitelyAnimatedMimeType(mimeType) {
            return .animatedImage
        } else if MimeTypeUtil.isSupportedImageMimeType(mimeType) {
            return .image
        } else if MimeTypeUtil.isSupportedMaybeAnimatedMimeType(mimeType) {
            return .animatedImage
        } else {
            return .file
        }
    }

    private func validateContents(
        input: Input,
        mimeType: String
    ) throws -> Attachment.ContentType {
        switch rawContentType(mimeType: mimeType) {
        case .invalid:
            return .invalid
        case .file:
            return .file
        case .image, .animatedImage:
            return try validateImageType(input, mimeType: mimeType)
        case .video:
            return try validateVideoType(input, mimeType: mimeType)
        case .audio:
            return try validateAudioType(input, mimeType: mimeType)
        }
    }

    // MARK: Image/Animated

    // Includes static and animated image validation.
    private func validateImageType(_ input: Input, mimeType: String) throws -> Attachment.ContentType {
        fatalError("Unimplemented")
    }

    // MARK: Video

    private func validateVideoType(_ input: Input, mimeType: String) throws -> Attachment.ContentType {
        fatalError("Unimplemented")
    }

    // MARK: Audio

    private func validateAudioType(_ input: Input, mimeType: String) throws -> Attachment.ContentType {
        fatalError("Unimplemented")
    }
}
