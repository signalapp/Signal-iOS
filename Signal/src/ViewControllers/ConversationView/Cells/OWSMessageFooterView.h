//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class ConversationStyle;

@protocol ConversationViewItem;

@interface OWSMessageFooterView : UIStackView

- (instancetype)init NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;

- (void)configureWithConversationViewItem:(id<ConversationViewItem>)viewItem
                        conversationStyle:(ConversationStyle *)conversationStyle
                               isIncoming:(BOOL)isIncoming
                        isOverlayingMedia:(BOOL)isOverlayingMedia
                          isOutsideBubble:(BOOL)isOutsideBubble;

- (CGSize)measureWithConversationViewItem:(id<ConversationViewItem>)viewItem;

- (void)prepareForReuse;

@end

NS_ASSUME_NONNULL_END
