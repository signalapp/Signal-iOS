//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A DataSource for an attachment to be created locally, with
/// additional required metadata.
public enum AttachmentDataSource {

    case existingAttachment(ExistingAttachmentSource)
    case pendingAttachment(PendingAttachment)

    /// Reference to an existing attachment to use as the source of a new one.
    public struct ExistingAttachmentSource {
        public let id: Attachment.IDType
        public let mimeType: String
        /// Note: these come from the AttachmentReference we are sourcing from.
        public private(set) var renderingFlag: AttachmentReference.RenderingFlag
        public let sourceFilename: String?
        public let sourceUnencryptedByteCount: UInt32?
        public let sourceMediaSizePixels: CGSize?

        mutating func removeBorderlessRenderingFlagIfPresent() {
            switch renderingFlag {
            case .borderless:
                self.renderingFlag = .default
            default:
                return
            }
        }
    }

    public var mimeType: String {
        switch self {
        case .existingAttachment(let existingAttachmentSource):
            return existingAttachmentSource.mimeType
        case .pendingAttachment(let pendingAttachment):
            return pendingAttachment.mimeType
        }
    }

    public var sourceFilename: String? {
        switch self {
        case .existingAttachment(let existingAttachmentSource):
            return existingAttachmentSource.sourceFilename
        case .pendingAttachment(let pendingAttachment):
            return pendingAttachment.sourceFilename
        }
    }

    public var renderingFlag: AttachmentReference.RenderingFlag {
        switch self {
        case .existingAttachment(let existingAttachmentSource):
            return existingAttachmentSource.renderingFlag
        case .pendingAttachment(let pendingAttachment):
            return pendingAttachment.renderingFlag
        }
    }

    public static func forwarding(
        existingAttachment: AttachmentStream,
        with reference: AttachmentReference
    ) -> AttachmentDataSource {
        return .existingAttachment(.init(
            id: existingAttachment.attachment.id,
            mimeType: existingAttachment.mimeType,
            renderingFlag: reference.renderingFlag,
            sourceFilename: reference.sourceFilename,
            sourceUnencryptedByteCount: reference.sourceUnencryptedByteCount,
            sourceMediaSizePixels: reference.sourceMediaSizePixels
        ))
    }

    public static func from(
        pendingAttachment: PendingAttachment
    ) -> AttachmentDataSource {
        return .pendingAttachment(pendingAttachment)
    }

    public func removeBorderlessRenderingFlagIfPresent() -> Self {
        switch self {
        case .existingAttachment(var existingAttachmentSource):
            existingAttachmentSource.removeBorderlessRenderingFlagIfPresent()
            return .existingAttachment(existingAttachmentSource)
        case .pendingAttachment(var pendingAttachment):
            pendingAttachment.removeBorderlessRenderingFlagIfPresent()
            return .pendingAttachment(pendingAttachment)
        }
    }
}

public struct OwnedAttachmentDataSource {
    public let source: AttachmentDataSource
    public let owner: AttachmentReference.OwnerBuilder

    public var mimeType: String { source.mimeType }

    public init(dataSource: AttachmentDataSource, owner: AttachmentReference.OwnerBuilder) {
        self.source = dataSource
        self.owner = owner
    }
}
