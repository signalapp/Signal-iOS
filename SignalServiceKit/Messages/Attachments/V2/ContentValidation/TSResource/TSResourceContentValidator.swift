//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct OversizeTextDataSource {
    public let v2DataSource: AttachmentDataSource?
    public let legacyDataSource: TSAttachmentDataSource

    public var dataSource: TSResourceDataSource {
        if let v2DataSource {
            return v2DataSource.tsDataSource
        } else {
            return legacyDataSource.tsDataSource
        }
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
        fromOriginalAttachment: TSResourceStream,
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
        let legacyOnly = Self.prepareLegacyOversizeTextIfNeeded(from: messageBody)

        let truncatedBody: MessageBody
        let legacyDataSource: TSAttachmentDataSource
        switch legacyOnly {
        case nil:
            return nil
        case .inline(let messageBody):
            return .inline(messageBody)
        case .oversize(let truncated, let fullsize):
            truncatedBody = truncated
            legacyDataSource = fullsize.legacyDataSource
        }

        let v2DataSource: AttachmentDataSource?
        let result = try attachmentValidator.prepareOversizeTextIfNeeded(
            from: messageBody
        )
        switch result {
        case .inline, nil:
            owsFailDebug("Got no oversize text for v2 even though we have one for v1")
            v2DataSource = nil
        case .oversize(_, let fullsize):
            v2DataSource = .from(pendingAttachment: fullsize)
        }
        let dataSource = OversizeTextDataSource.init(
            v2DataSource: v2DataSource,
            legacyDataSource: legacyDataSource
        )

        return .oversize(
            truncated: truncatedBody,
            fullsize: dataSource
        )
    }

    // For legacy attachments, don't validate but still truncate.
    public static func prepareLegacyOversizeTextIfNeeded(
        from messageBody: MessageBody
    ) -> ValidatedTSMessageBody? {
        guard !messageBody.text.isEmpty else {
            return nil
        }
        let truncatedText = messageBody.text.trimmedIfNeeded(maxByteCount: Int(kOversizeTextMessageSizeThreshold))
        guard let truncatedText else {
            // No need to truncate
            return .inline(messageBody)
        }
        let truncatedBody = MessageBody(text: truncatedText, ranges: messageBody.ranges)

        let dataSource = OversizeTextDataSource.init(
            v2DataSource: nil,
            legacyDataSource: .init(
                mimeType: MimeType.textXSignalPlain.rawValue,
                caption: nil,
                renderingFlag: .default,
                sourceFilename: nil,
                dataSource: .dataSource(
                    DataSourceValue(oversizeText: messageBody.text),
                    shouldCopy: false
                )
            )
        )

        return .oversize(
            truncated: truncatedBody,
            fullsize: dataSource
        )
    }

    public func prepareQuotedReplyThumbnail(
        fromOriginalAttachment originalAttachment: TSResourceStream,
        originalReference: TSResourceReference,
        originalMessageRowId: Int64
    ) throws -> QuotedReplyTSResourceDataSource {
        switch (originalAttachment.concreteStreamType, originalReference.concreteType) {
        case (.v2, .legacy), (.legacy, .v2):
            throw OWSAssertionError("Invalid attachment + reference combination")

        case (.v2(let attachment), .v2(let attachmentReference)):
            return try attachmentValidator.prepareQuotedReplyThumbnail(
                fromOriginalAttachment: attachment,
                originalReference: attachmentReference
            ).tsDataSource
        case (.legacy(let tsAttachment), .legacy):
            // We have a legacy attachment, but we want to clone it as a v2 attachment.
            // This is doable; we can read the attachment data in and clone that directly.
            return try prepareV2QuotedReplyThumbnail(
                fromLegacyAttachment: tsAttachment,
                originalMessageRowId: originalMessageRowId
            ).tsDataSource
        }
    }

    private func prepareV2QuotedReplyThumbnail(
        fromLegacyAttachment originalAttachment: TSAttachment,
        originalMessageRowId: Int64
    ) throws -> QuotedReplyAttachmentDataSource {
        let isVisualMedia: Bool = {
            if let contentType = originalAttachment.asResourceStream()?.cachedContentType {
                return contentType.isVisualMedia
            } else {
                return MimeTypeUtil.isSupportedVisualMediaMimeType(originalAttachment.mimeType)
            }
        }()
        guard isVisualMedia else {
            throw OWSAssertionError("Non visual media target")
        }
        guard let stream = originalAttachment as? TSAttachmentStream else {
            // If we don't have a stream, the best we can do is try to create
            // a pointer proto out of the cdn info of the original.
            if let phonyThumbnailAttachmentProto = TSResourceManagerImpl.buildProtoAsIfWeReceivedThisAttachment(originalAttachment) {
                return .fromQuotedAttachmentProto(
                    thumbnail: phonyThumbnailAttachmentProto,
                    originalAttachmentMimeType: originalAttachment.mimeType,
                    originalAttachmentSourceFilename: originalAttachment.sourceFilename
                )
            } else {
                Logger.error("Unable to create v2 quote attachment from v1 attachment")
                class CannotCreateV2FromV1AttachmentError: Error {}
                throw CannotCreateV2FromV1AttachmentError()
            }
        }

        guard
            let imageData = stream
                .thumbnailImageSmallSync()?
                .resized(maxDimensionPoints: AttachmentThumbnailQuality.thumbnailDimensionPointsForQuotedReply)?
                .jpegData(compressionQuality: 0.8)
        else {
            throw OWSAssertionError("Unable to create thumbnail")
        }

        let renderingFlagForThumbnail: AttachmentReference.RenderingFlag
        switch originalAttachment.attachmentType.asRenderingFlag {
        case .borderless:
            // Preserve borderless flag from the original
            renderingFlagForThumbnail = .borderless
        case .default, .voiceMessage, .shouldLoop:
            // Other cases become default for the still image.
            renderingFlagForThumbnail = .default
        }

        let pendingAttachment: PendingAttachment = try attachmentValidator.validateContents(
            data: imageData,
            mimeType: MimeType.imageJpeg.rawValue,
            renderingFlag: renderingFlagForThumbnail,
            sourceFilename: originalAttachment.sourceFilename
        )

        return .fromPendingAttachment(
            pendingAttachment,
            originalAttachmentMimeType: originalAttachment.mimeType,
            originalAttachmentSourceFilename: originalAttachment.sourceFilename,
            originalMessageRowId: originalMessageRowId
        )
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
        return TSAttachmentDataSource(
            mimeType: mimeType,
            caption: caption,
            renderingFlag: renderingFlag,
            sourceFilename: dataSource.sourceFilename,
            dataSource: .dataSource(dataSource, shouldCopy: !shouldConsume)
        ).tsDataSource
    }

    open func validateContents(
        data: Data,
        mimeType: String,
        sourceFilename: String?,
        caption: MessageBody?,
        renderingFlag: AttachmentReference.RenderingFlag,
        ownerType: TSResourceOwnerType
    ) throws -> TSResourceDataSource {
        return TSAttachmentDataSource(
            mimeType: mimeType,
            caption: caption,
            renderingFlag: renderingFlag,
            sourceFilename: sourceFilename,
            dataSource: .data(data)
        ).tsDataSource
    }

    open func prepareOversizeTextIfNeeded(
        from messageBody: MessageBody
    ) throws -> ValidatedTSMessageBody? {
        return .inline(messageBody)
    }

    open func prepareQuotedReplyThumbnail(
        fromOriginalAttachment originalAttachment: TSResourceStream,
        originalReference: TSResourceReference,
        originalMessageRowId: Int64
    ) throws -> QuotedReplyTSResourceDataSource {
        switch originalAttachment.concreteType {
        case .legacy(let tsAttachment):
            return .fromLegacyOriginalAttachment(tsAttachment, originalMessageRowId: originalMessageRowId)
        case .v2(_):
            switch originalReference.concreteType {
            case .legacy(_):
                fatalError("Invalid combination")
            case .v2(_):
                throw OWSAssertionError("Unimplemented")
            }
        }
    }
}

#endif
