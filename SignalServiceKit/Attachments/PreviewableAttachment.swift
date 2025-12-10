//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Represents an attachment the user *might* choose to send.
///
/// See also ``SendableAttachment``.
///
/// These are attachments that are valid enough that we believe we can make
/// them fully valid if the user chooses to send them.
///
/// For example, if the user selects an image we can't decode, we can't make
/// a `PreviewableAttachment`. However, if the user selects an image whose
/// file size is too large, we *can* make a `PreviewableAttachment`. If the
/// user chooses to send it, we can re-encode the image with lower quality
/// and/or dimensions to fit within the limit.
///
/// On the other hand, if the user selects a PDF document that's too large,
/// we can't make it valid (e.g., we don't delete or re-encode pages), so we
/// can't make a `PreviewableAttachment` for it.
public struct PreviewableAttachment {
    public let rawValue: SignalAttachment

    public init(rawValue: SignalAttachment) {
        self.rawValue = rawValue
    }

    public var dataSource: DataSourcePath { self.rawValue.dataSource }

    public var dataUTI: String { self.rawValue.dataUTI }
    public var mimeType: String { self.rawValue.mimeType }
    public var renderingFlag: AttachmentReference.RenderingFlag { self.rawValue.renderingFlag }

    public var isImage: Bool { self.rawValue.isImage }
    public var isAnimatedImage: Bool { self.rawValue.isAnimatedImage }
    public var isVideo: Bool { self.rawValue.isVideo }
    public var isVisualMedia: Bool { self.rawValue.isVisualMedia }
    public var isAudio: Bool { self.rawValue.isAudio }
}
