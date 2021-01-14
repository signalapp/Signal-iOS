//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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

@end

NS_ASSUME_NONNULL_END
