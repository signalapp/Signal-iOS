//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension AttachmentReference: TSResourceReference {
    public var resourceId: TSResourceId {
        return .v2(rowId: attachmentRowId)
    }

    public var concreteType: ConcreteTSResourceReference { .v2(self) }

    public var renderingFlag: RenderingFlag {
        switch owner {
        case .message(.bodyAttachment(let metadata)):
            return metadata.renderingFlag
        case .message(.quotedReply(let metadata)):
            return metadata.renderingFlag
        case .storyMessage(.media(let metadata)):
            return metadata.shouldLoop ? .shouldLoop : .default
        default:
            return .default
        }
    }

    public var storyMediaCaption: StyleOnlyMessageBody? {
        switch owner {
        case .storyMessage(.media(let metadata)):
            return metadata.caption
        default:
            return nil
        }
    }

    public var legacyMessageCaption: String? {
        switch owner {
        case .message(.bodyAttachment(let metadata)):
            return metadata.caption
        default:
            return nil
        }
    }

    public func hasSameOwner(as other: TSResourceReference) -> Bool {
        guard let other = other as? AttachmentReference else {
            return false
        }
        return self.owner.id == other.owner.id
    }

    public func fetchOwningMessage(tx: SDSAnyReadTransaction) -> TSMessage? {
        switch owner {
        case .message(let messageSource):
            return InteractionFinder.fetch(rowId: messageSource.messageRowId, transaction: tx) as? TSMessage
        case .storyMessage, .thread:
            return nil
        }
    }

    public func orderInOwningMessage(_ message: TSMessage) -> UInt32? {
        switch owner {
        case .message(.bodyAttachment(let metadata)):
            return metadata.orderInOwner
        default:
            return nil
        }
    }

    public func knownIdInOwningMessage(_ message: TSMessage) -> UUID? {
        switch owner {
        case .message(.bodyAttachment(let metadata)):
            return metadata.idInOwner
        default:
            return nil
        }
    }
}

extension AttachmentReference.RenderingFlag {

    public var tsAttachmentType: TSAttachmentType {
        switch self {
        case .default:
            return .default
        case .voiceMessage:
            return .voiceMessage
        case .borderless:
            return .borderless
        case .shouldLoop:
            return .GIF
        }
    }
}
