//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A DataSource for an attachment to be created locally, with
/// additional required metadata.
public struct AttachmentDataSource {
    let mimeType: String
    /// If we have it, the precomputed content hash.
    /// Otherwise will be computed at insertion time.
    let contentHash: Data?
    let sourceFilename: String?

    let dataSource: Source

    public enum Source {
        // If shouldCopy=true, the data source will be copied instead of moved.
        case dataSource(DataSource, shouldCopy: Bool)
        case data(Data)
        case existingAttachment(Attachment.IDType)
        case pendingAttachment(PendingAttachment)
    }

    internal init(
        mimeType: String,
        // TODO: we can precompute this in more cases.
        contentHash: Data?,
        sourceFilename: String?,
        dataSource: Source
    ) {
        self.mimeType = mimeType
        self.contentHash = contentHash
        self.dataSource = dataSource
        self.sourceFilename = sourceFilename
    }

    public static func from(
        dataSource: DataSource,
        mimeType: String,
        shouldCopyDataSource: Bool = false
    ) -> AttachmentDataSource {
        return .init(
            mimeType: mimeType,
            contentHash: nil,
            sourceFilename: dataSource.sourceFilename,
            dataSource: .dataSource(dataSource, shouldCopy: shouldCopyDataSource)
        )
    }

    public static func from(
        data: Data,
        mimeType: String,
        sourceFilename: String? = nil
    ) -> AttachmentDataSource {
        return .init(
            mimeType: mimeType,
            contentHash: nil,
            sourceFilename: sourceFilename,
            dataSource: .data(data)
        )
    }

    public static func forwarding(
        existingAttachment: AttachmentStream,
        with reference: AttachmentReference
    ) -> AttachmentDataSource {
        return .init(
            mimeType: existingAttachment.mimeType,
            contentHash: existingAttachment.contentHash,
            sourceFilename: reference.sourceFilename,
            dataSource: .existingAttachment(existingAttachment.attachment.id)
        )
    }

    public static func from(
        pendingAttachment: PendingAttachment
    ) -> AttachmentDataSource {
        return .init(
            mimeType: pendingAttachment.mimeType,
            contentHash: pendingAttachment.sha256ContentHash,
            sourceFilename: pendingAttachment.sourceFilename,
            dataSource: .pendingAttachment(pendingAttachment)
        )
    }
}

public struct OwnedAttachmentDataSource {
    public let source: AttachmentDataSource
    public let owner: AttachmentReference.OwnerBuilder

    public var mimeType: String { source.mimeType }
    public var contentHash: Data? { source.contentHash }
    public var dataSource: AttachmentDataSource.Source { source.dataSource }

    public init(dataSource: AttachmentDataSource, owner: AttachmentReference.OwnerBuilder) {
        self.source = dataSource
        self.owner = owner
    }
}
