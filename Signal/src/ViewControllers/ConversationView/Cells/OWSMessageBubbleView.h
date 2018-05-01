//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class ConversationViewItem;
@class OWSQuotedReplyModel;
@class TSAttachmentPointer;
@class TSAttachmentStream;
@class TSOutgoingMessage;

typedef NS_ENUM(NSUInteger, OWSMessageGestureLocation) {
    // Message text, etc.
    OWSMessageGestureLocation_Default,
    OWSMessageGestureLocation_OversizeText,
    OWSMessageGestureLocation_Media,
    OWSMessageGestureLocation_QuotedReply,
};

@protocol OWSMessageBubbleViewDelegate

- (void)didTapImageViewItem:(ConversationViewItem *)viewItem
           attachmentStream:(TSAttachmentStream *)attachmentStream
                  imageView:(UIView *)imageView;

- (void)didTapVideoViewItem:(ConversationViewItem *)viewItem
           attachmentStream:(TSAttachmentStream *)attachmentStream
                  imageView:(UIView *)imageView;

- (void)didTapAudioViewItem:(ConversationViewItem *)viewItem attachmentStream:(TSAttachmentStream *)attachmentStream;

- (void)didTapTruncatedTextMessage:(ConversationViewItem *)conversationItem;

- (void)didTapFailedIncomingAttachment:(ConversationViewItem *)viewItem
                     attachmentPointer:(TSAttachmentPointer *)attachmentPointer;

- (void)didTapConversationItem:(ConversationViewItem *)viewItem quotedReply:(OWSQuotedReplyModel *)quotedReply;
- (void)didTapConversationItem:(ConversationViewItem *)viewItem
                                 quotedReply:(OWSQuotedReplyModel *)quotedReply
    failedThumbnailDownloadAttachmentPointer:(TSAttachmentPointer *)attachmentPointer;

- (void)didTapContactShareViewItem:(ConversationViewItem *)viewItem;

@end

@interface OWSMessageBubbleView : UIView

@property (nonatomic, nullable) ConversationViewItem *viewItem;

@property (nonatomic) int contentWidth;

@property (nonatomic) NSCache *cellMediaCache;

@property (nonatomic, nullable, readonly) UIView *bodyMediaView;

@property (nonatomic) BOOL alwaysShowBubbleTail;

@property (nonatomic, weak) id<OWSMessageBubbleViewDelegate> delegate;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithFrame:(CGRect)frame NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

- (void)configureViews;

- (void)loadContent;
- (void)unloadContent;

- (CGSize)sizeForContentWidth:(int)contentWidth;

- (void)prepareForReuse;

#pragma mark - Gestures

- (OWSMessageGestureLocation)gestureLocationForLocation:(CGPoint)locationInMessageBubble;

// This only needs to be called when we use the cell _outside_ the context
// of a conversation view message cell.
- (void)addTapGestureHandler;

- (void)handleTapGesture:(UITapGestureRecognizer *)sender;

@end

NS_ASSUME_NONNULL_END
