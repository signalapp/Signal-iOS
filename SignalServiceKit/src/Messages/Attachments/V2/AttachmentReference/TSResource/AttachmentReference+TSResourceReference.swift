//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension AttachmentReference: TSResourceReference {
    public var resourceId: TSResourceId {
        fatalError("Unimplemented!")
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
}

extension AttachmentReference.RenderingFlag {

    var tsAttachmentType: TSAttachmentType {
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
