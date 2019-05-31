//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class ConversationStyle;
@class TSAttachment;

@protocol ConversationViewItem;

@interface OWSAudioMessageView : UIStackView

- (instancetype)initWithAttachment:(TSAttachment *)attachment
                        isIncoming:(BOOL)isIncoming
                          viewItem:(id<ConversationViewItem>)viewItem
                 conversationStyle:(ConversationStyle *)conversationStyle;

- (void)createContents;

+ (CGFloat)bubbleHeight;

- (void)updateContents;

- (BOOL)canScrubToLocation:(CGPoint)location;
- (NSTimeInterval)scrubToLocation:(CGPoint)location;

@end

NS_ASSUME_NONNULL_END
