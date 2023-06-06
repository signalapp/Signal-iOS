//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

public protocol CVItemViewModel: AnyObject {
    var interaction: TSInteraction { get }
    var contactShare: ContactShareViewModel? { get }
    var linkPreview: OWSLinkPreview? { get }
    var linkPreviewAttachment: TSAttachment? { get }
    var stickerInfo: StickerInfo? { get }
    var stickerAttachment: TSAttachmentStream? { get }
    var stickerMetadata: StickerMetadata? { get }
    var isGiftBadge: Bool { get }
}
