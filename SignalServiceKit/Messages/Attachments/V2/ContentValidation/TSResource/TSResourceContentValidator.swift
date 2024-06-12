//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct OversizeTextDataSource {
    public let v2DataSource: AttachmentDataSource?
    public let legacyDataSource: TSAttachmentDataSource

    public var dataSource: TSResourceDataSource {
            if FeatureFlags.newAttachmentsUseV2, let v2DataSource {
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
        renderingFlag: AttachmentReference.RenderingFlag
    ) throws -> TSResourceDataSource

    /// If the provided message body is large enough to require an oversize text
    /// attachment, creates a pending one, alongside the truncated message body.
    /// If not, just returns the message body as is.
    func prepareOversizeTextIfNeeded(
        from messageBody: MessageBody
    ) throws -> ValidatedTSMessageBody?
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
        renderingFlag: AttachmentReference.RenderingFlag
    ) throws -> TSResourceDataSource {
        if FeatureFlags.newAttachmentsUseV2 {
            let attachmentDataSource: AttachmentDataSource =
                try attachmentValidator.validateContents(
                    dataSource: dataSource,
                    shouldConsume: shouldConsume,
                    mimeType: mimeType,
                    sourceFilename: sourceFilename
                )
            return attachmentDataSource.tsDataSource
        } else {
            // We don't do validation up front for legacy attachments.
            return .from(
                dataSource: dataSource,
                mimeType: mimeType,
                caption: caption,
                renderingFlag: renderingFlag,
                shouldCopyDataSource: !shouldConsume
            )
        }
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
        if FeatureFlags.newAttachmentsUseV2 {
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
        } else {
            v2DataSource = nil
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
                    DataSourceValue.dataSource(withOversizeText: messageBody.text),
                    shouldCopy: false
                )
            )
        )

        return .oversize(
            truncated: truncatedBody,
            fullsize: dataSource
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
        renderingFlag: AttachmentReference.RenderingFlag
    ) throws -> TSResourceDataSource {
        return .from(
            dataSource: dataSource,
            mimeType: mimeType,
            caption: caption,
            renderingFlag: renderingFlag,
            shouldCopyDataSource: !shouldConsume
        )
    }

    open func prepareOversizeTextIfNeeded(
        from messageBody: MessageBody
    ) throws -> ValidatedTSMessageBody? {
        return .inline(messageBody)
    }
}

#endif
