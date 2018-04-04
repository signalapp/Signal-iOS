//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class DisplayableText;
@class OWSBubbleStrokeView;
@class TSQuotedMessage;

@interface OWSQuotedMessageView : UIView

@property (nonatomic, nullable, readonly) OWSBubbleStrokeView *boundsStrokeView;

- (instancetype)init NS_UNAVAILABLE;

// Only needs to be called if we're going to render this instance.
- (void)createContents;

// Measurement
- (CGSize)sizeForMaxWidth:(CGFloat)maxWidth;

+ (OWSQuotedMessageView *)quotedMessageViewForConversation:(TSQuotedMessage *)quotedMessage
                                     displayableQuotedText:(nullable DisplayableText *)displayableQuotedText;

+ (OWSQuotedMessageView *)quotedMessageViewForPreview:(TSQuotedMessage *)quotedMessage;

@end

NS_ASSUME_NONNULL_END
