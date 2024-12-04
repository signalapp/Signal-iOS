//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct OversizeTextDataSource {
    public let v2DataSource: AttachmentDataSource

    public var dataSource: TSResourceDataSource {
        return v2DataSource.tsDataSource
    }
}

public enum ValidatedTSMessageBody {
    /// The original body was small enough to send as-is.
    case inline(MessageBody)
    /// The original body was too large; we truncated and created an attachment with the untruncated text.
    case oversize(truncated: MessageBody, fullsize: OversizeTextDataSource)
}

public protocol TSResourceContentValidator {

    /// Prepare and possibly validate DataSource's contents, based on the provided mimetype.
    /// Returns a TSResourceDataSource, ready to be inserted.
    /// If using legacy attachments, contents will _not_ be validated.
    /// If using v2 attachments, contents _will_ be validated.
    /// Errors are thrown if data reading/parsing/cryptography fails but NOT if contents are invalid;
    /// invalid contents are still represented as `invalid` attachments.
    func validateContents(
        dataSource: DataSource,
        shouldConsume: Bool,
        mimeType: String,
        sourceFilename: String?,
        caption: MessageBody?,
        renderingFlag: AttachmentReference.RenderingFlag,
        ownerType: TSResourceOwnerType
    ) throws -> TSResourceDataSource

    /// Prepare and possibly validate Data's contents, based on the provided mimetype.
    /// Returns a TSResourceDataSource, ready to be inserted.
    /// If using legacy attachments, contents will _not_ be validated.
    /// If using v2 attachments, contents _will_ be validated.
    /// Errors are thrown if data parsing/cryptography fails but NOT if contents are invalid;
    /// invalid contents are still represented as `invalid` attachments.
    func validateContents(
        data: Data,
        mimeType: String,
        sourceFilename: String?,
        caption: MessageBody?,
        renderingFlag: AttachmentReference.RenderingFlag,
        ownerType: TSResourceOwnerType
    ) throws -> TSResourceDataSource

    /// If the provided message body is large enough to require an oversize text
    /// attachment, creates a pending one, alongside the truncated message body.
    /// If not, just returns the message body as is.
    func prepareOversizeTextIfNeeded(
        from messageBody: MessageBody
    ) throws -> ValidatedTSMessageBody?

    /// Build a `QuotedReplyTSResourceDataSource` for a reply to a message with the provided attachment.
    /// Throws an error if the provided attachment is non-visual, or if data reading/writing fails.
    func prepareQuotedReplyThumbnail(
        fromOriginalAttachment: AttachmentStream,
        originalReference: TSResourceReference,
        originalMessageRowId: Int64
    ) throws -> QuotedReplyTSResourceDataSource
}

public class TSResourceContentValidatorImpl: TSResourceContentValidator {

    private let attachmentValidator: AttachmentContentValidator

    public init(attachmentValidator: AttachmentContentValidator) {
        self.attachmentValidator = attachmentValidator
    }

    public func validateContents(
        dataSource: DataSource,
        shouldConsume: Bool,
        mimeType: String,
        sourceFilename: String?,
        caption: MessageBody?,
        renderingFlag: AttachmentReference.RenderingFlag,
        ownerType: TSResourceOwnerType
    ) throws -> TSResourceDataSource {
        let attachmentDataSource: AttachmentDataSource =
            try attachmentValidator.validateContents(
                dataSource: dataSource,
                shouldConsume: shouldConsume,
                mimeType: mimeType,
                renderingFlag: renderingFlag,
                sourceFilename: sourceFilename
            )
        return attachmentDataSource.tsDataSource
    }

    public func validateContents(
        data: Data,
        mimeType: String,
        sourceFilename: String?,
        caption: MessageBody?,
        renderingFlag: AttachmentReference.RenderingFlag,
        ownerType: TSResourceOwnerType
    ) throws -> TSResourceDataSource {
        let attachmentDataSource: AttachmentDataSource =
            try attachmentValidator.validateContents(
                data: data,
                mimeType: mimeType,
                renderingFlag: renderingFlag,
                sourceFilename: sourceFilename
            )
        return attachmentDataSource.tsDataSource
    }

    public func prepareOversizeTextIfNeeded(
        from messageBody: MessageBody
    ) throws -> ValidatedTSMessageBody? {
        let truncatedBody: MessageBody

        let v2DataSource: AttachmentDataSource
        let result = try attachmentValidator.prepareOversizeTextIfNeeded(
            from: messageBody
        )
        switch result {
        case nil:
            return nil
        case .inline(let messageBody):
            return .inline(messageBody)
        case .oversize(let truncated, let fullsize):
            truncatedBody = truncated
            v2DataSource = .from(pendingAttachment: fullsize)
        }
        let dataSource = OversizeTextDataSource.init(
            v2DataSource: v2DataSource
        )

        return .oversize(
            truncated: truncatedBody,
            fullsize: dataSource
        )
    }

    public func prepareQuotedReplyThumbnail(
        fromOriginalAttachment originalAttachment: AttachmentStream,
        originalReference: TSResourceReference,
        originalMessageRowId: Int64
    ) throws -> QuotedReplyTSResourceDataSource {
        return try attachmentValidator.prepareQuotedReplyThumbnail(
            fromOriginalAttachment: originalAttachment,
            originalReference: originalReference.concreteType
        ).tsDataSource
    }
}

#if DEBUG

open class TSResourceContentValidatorMock: TSResourceContentValidator {

    public init() {}

    open func validateContents(
        dataSource: DataSource,
        shouldConsume: Bool,
        mimeType: String,
        sourceFilename: String?,
        caption: MessageBody?,
        renderingFlag: AttachmentReference.RenderingFlag,
        ownerType: TSResourceOwnerType
    ) throws -> TSResourceDataSource {
        throw OWSAssertionError("Unimplemented")
    }

    open func validateContents(
        data: Data,
        mimeType: String,
        sourceFilename: String?,
        caption: MessageBody?,
        renderingFlag: AttachmentReference.RenderingFlag,
        ownerType: TSResourceOwnerType
    ) throws -> TSResourceDataSource {
        throw OWSAssertionError("Unimplemented")
    }

    open func prepareOversizeTextIfNeeded(
        from messageBody: MessageBody
    ) throws -> ValidatedTSMessageBody? {
        return .inline(messageBody)
    }

    open func prepareQuotedReplyThumbnail(
        fromOriginalAttachment originalAttachment: AttachmentStream,
        originalReference: TSResourceReference,
        originalMessageRowId: Int64
    ) throws -> QuotedReplyTSResourceDataSource {
        throw OWSAssertionError("Unimplemented")
    }
}

#endif
