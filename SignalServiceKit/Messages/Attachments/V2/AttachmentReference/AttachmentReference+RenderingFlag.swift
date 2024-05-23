//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension AttachmentReference {

    /// A flag set by the sender of an attachment _on_ a message (or story message)
    /// that gives rendering hints to the receiver.
    ///
    /// Not all flags are valid on all attachment/message types. See documentation
    /// of cases and ``AttachmentReference.Owner`` for more information.
    ///
    /// NOTE: these are non-mutually exclusive on the proto, but are mutually exclusive
    /// in practice; this may change in the future if a new type is added (but we are unlikely
    /// to add a new flag type).
    public enum RenderingFlag: Int, Codable, Equatable {
        /// Set implicitly by default on all attachments unless another value is provided.
        case `default` = 0

        /// Should be rendered as a voice message; typically recorded by the sender in-app.
        /// Only valid for audio attachments.
        case voiceMessage = 1

        /// Should be rendered inline in chat without any border.
        /// Only valid for images. Invalid for story messages.
        case borderless = 2

        /// The video or animated image should loop when finished playing.
        /// Only valid for videos and animated images.
        ///
        /// (Originally named ``SSKProtoAttachmentPointerFlags``.gif, but that's somewhat
        /// of a misnomer; it is orthogonal to whether the file type is gif.)
        case shouldLoop = 3

        init(rawValue: UInt32) throws {
            guard
                let rawValue = Int(exactly: rawValue),
                let value = AttachmentReference.RenderingFlag(rawValue: rawValue)
            else {
                throw OWSAssertionError("Invalid rendering flag")
            }
            self = value
        }
    }
}

extension AttachmentReference.RenderingFlag {

    public static func fromProto(_ proto: SSKProtoAttachmentPointer) -> Self {
        guard
            proto.hasFlags,
            let rawValue = Int32.init(exactly: proto.flags)
        else {
            return .default
        }

        return .fromProto(.init(rawValue: rawValue))
    }

    public static func fromProto(_ proto: SSKProtoAttachmentPointerFlags?) -> Self {
        switch proto {
        case nil:
            return .default
        case .voiceMessage:
            return .voiceMessage
        case .borderless:
            return .borderless
        case .gif:
            return .shouldLoop
        }
    }

    public func toProto() -> SSKProtoAttachmentPointerFlags? {
        switch self {
        case .default:
            return nil
        case .voiceMessage:
            return .voiceMessage
        case .borderless:
            return .borderless
        case .shouldLoop:
            return .gif
        }
    }
}
