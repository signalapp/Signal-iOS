//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class DisplayableText;
@class OWSBubbleStrokeView;
@class OWSQuotedReplyModel;
@class TSAttachmentPointer;
@class TSQuotedMessage;

@protocol OWSQuotedMessageViewDelegate

- (void)didTapQuotedReply:(OWSQuotedReplyModel *)quotedReply
    failedThumbnailDownloadAttachmentPointer:(TSAttachmentPointer *)attachmentPointer;

@end

@interface OWSQuotedMessageView : UIView

@property (nonatomic, nullable, readonly) OWSBubbleStrokeView *boundsStrokeView;
@property (nonatomic, nullable, weak) id<OWSQuotedMessageViewDelegate> delegate;

- (instancetype)init NS_UNAVAILABLE;

// Only needs to be called if we're going to render this instance.
- (void)createContents;

// Measurement
- (CGSize)sizeForMaxWidth:(CGFloat)maxWidth;

// Factory method for "message bubble" views.
+ (OWSQuotedMessageView *)quotedMessageViewForConversation:(OWSQuotedReplyModel *)quotedMessage
                                     displayableQuotedText:(nullable DisplayableText *)displayableQuotedText
                                                isOutgoing:(BOOL)isOutgoing;

// Factory method for "message compose" views.
+ (OWSQuotedMessageView *)quotedMessageViewForPreview:(OWSQuotedReplyModel *)quotedMessage;

@end

NS_ASSUME_NONNULL_END
