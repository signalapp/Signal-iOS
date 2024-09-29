//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

public protocol CVItemViewModel: AnyObject {
    var interaction: TSInteraction { get }
    var contactShare: ContactShareViewModel? { get }
    var linkPreview: OWSLinkPreview? { get }
    var linkPreviewAttachment: TSResource? { get }
    var stickerInfo: StickerInfo? { get }
    var stickerAttachment: TSResourceStream? { get }
    var stickerMetadata: (any StickerMetadata)? { get }
    var isGiftBadge: Bool { get }
    var hasRenderableContent: Bool { get }
}
