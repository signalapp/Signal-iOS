//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageView.h"

NS_ASSUME_NONNULL_BEGIN

@class ContactShareViewModel;
@class OWSContact;
@class OWSLinkPreview;
@class OWSQuotedReplyModel;
@class StickerPackInfo;
@class TSAttachmentPointer;
@class TSAttachmentStream;
@class TSOutgoingMessage;

@protocol OWSMessageBubbleViewDelegate

- (void)didTapImageViewItem:(id<ConversationViewItem>)viewItem
           attachmentStream:(TSAttachmentStream *)attachmentStream
                  imageView:(UIView *)imageView;

- (void)didTapVideoViewItem:(id<ConversationViewItem>)viewItem
           attachmentStream:(TSAttachmentStream *)attachmentStream
                  imageView:(UIView *)imageView;

- (void)didTapAudioViewItem:(id<ConversationViewItem>)viewItem attachmentStream:(TSAttachmentStream *)attachmentStream;

- (void)didScrubAudioViewItem:(id<ConversationViewItem>)viewItem
                       toTime:(NSTimeInterval)time
             attachmentStream:(TSAttachmentStream *)attachmentStream;

- (void)didTapTruncatedTextMessage:(id<ConversationViewItem>)conversationItem;

- (void)didTapFailedIncomingAttachment:(id<ConversationViewItem>)viewItem;

- (void)didTapConversationItem:(id<ConversationViewItem>)viewItem quotedReply:(OWSQuotedReplyModel *)quotedReply;
- (void)didTapConversationItem:(id<ConversationViewItem>)viewItem
                                 quotedReply:(OWSQuotedReplyModel *)quotedReply
    failedThumbnailDownloadAttachmentPointer:(TSAttachmentPointer *)attachmentPointer;

- (void)didTapConversationItem:(id<ConversationViewItem>)viewItem linkPreview:(OWSLinkPreview *)linkPreview;

- (void)didTapContactShareViewItem:(id<ConversationViewItem>)viewItem;

- (void)didTapSendMessageToContactShare:(ContactShareViewModel *)contactShare
    NS_SWIFT_NAME(didTapSendMessage(toContactShare:));
- (void)didTapSendInviteToContactShare:(ContactShareViewModel *)contactShare
    NS_SWIFT_NAME(didTapSendInvite(toContactShare:));
- (void)didTapShowAddToContactUIForContactShare:(ContactShareViewModel *)contactShare
    NS_SWIFT_NAME(didTapShowAddToContactUI(forContactShare:));

- (void)didTapStickerPack:(StickerPackInfo *)stickerPackInfo NS_SWIFT_NAME(didTapStickerPack(_:));

@property (nonatomic, readonly, nullable) NSString *lastSearchedText;

@end

#pragma mark -

@interface OWSMessageBubbleView : OWSMessageView

@property (nonatomic, nullable, readonly) UIView *bodyMediaView;

@property (nonatomic, weak) id<OWSMessageBubbleViewDelegate> delegate;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithFrame:(CGRect)frame NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
