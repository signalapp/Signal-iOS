//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class ConversationViewItem;
@class TSQuotedMessage;

@interface OWSQuotedMessageView : UIView

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithViewItem:(ConversationViewItem *)viewItem
                 //                   quotedMessage:(TSQuotedMessage *)quotedMessage
                 textMessageFont:(UIFont *)textMessageFont;

// Only needs to be called if we're going to render this instance.
- (void)createContents;

// Measurement
- (CGSize)sizeForMaxWidth:(CGFloat)maxWidth;

@end

NS_ASSUME_NONNULL_END
