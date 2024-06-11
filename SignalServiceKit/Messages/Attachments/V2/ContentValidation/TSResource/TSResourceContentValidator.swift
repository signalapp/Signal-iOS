//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

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
}

#endif
