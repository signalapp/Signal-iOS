//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSBubbleView.h"

NS_ASSUME_NONNULL_BEGIN

@class ConversationStyle;
@class DisplayableText;
@class OWSBubbleShapeView;
@class OWSQuotedReplyModel;
@class TSAttachmentPointer;
@class TSQuotedMessage;

@protocol OWSQuotedMessageViewDelegate

- (void)didTapQuotedReply:(OWSQuotedReplyModel *)quotedReply
    failedThumbnailDownloadAttachmentPointer:(TSAttachmentPointer *)attachmentPointer;

- (void)didCancelQuotedReply;

@end

// TODO: Remove this view.
@interface OWSQuotedMessageView : UIView

@property (nonatomic, nullable, weak) id<OWSQuotedMessageViewDelegate> delegate;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

// Only needs to be called if we're going to render this instance.
- (void)createContents;

// Measurement
- (CGSize)sizeForMaxWidth:(CGFloat)maxWidth;

// Factory method for "message bubble" views.
+ (OWSQuotedMessageView *)quotedMessageViewForConversation:(OWSQuotedReplyModel *)quotedMessage
                                     displayableQuotedText:(nullable DisplayableText *)displayableQuotedText
                                         conversationStyle:(ConversationStyle *)conversationStyle
                                                isOutgoing:(BOOL)isOutgoing
                                              sharpCorners:(OWSDirectionalRectCorner)sharpCorners;

// Factory method for "message compose" views.
+ (OWSQuotedMessageView *)quotedMessageViewForPreview:(OWSQuotedReplyModel *)quotedMessage
                                    conversationStyle:(ConversationStyle *)conversationStyle;

@end

NS_ASSUME_NONNULL_END
