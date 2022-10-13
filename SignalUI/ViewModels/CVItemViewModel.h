//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@class ContactShareViewModel;
@class OWSLinkPreview;
@class StickerInfo;
@class StickerMetadata;
@class TSAttachment;
@class TSAttachmentStream;
@class TSInteraction;

@protocol CVItemViewModel <NSObject>

@property (nonatomic, readonly) TSInteraction *interaction;
@property (nonatomic, readonly, nullable) ContactShareViewModel *contactShare;
@property (nonatomic, readonly, nullable) OWSLinkPreview *linkPreview;
@property (nonatomic, readonly, nullable) TSAttachment *linkPreviewAttachment;
@property (nonatomic, readonly, nullable) StickerInfo *stickerInfo;
@property (nonatomic, readonly, nullable) TSAttachmentStream *stickerAttachment;
@property (nonatomic, readonly, nullable) StickerMetadata *stickerMetadata;
@property (nonatomic, readonly) BOOL isGiftBadge;

@end

NS_ASSUME_NONNULL_END
