//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class ConversationStyle;

@protocol ConversationViewItem;

@interface OWSMessageFooterView : UIStackView

- (void)configureWithConversationViewItem:(id<ConversationViewItem>)viewItem
                        conversationStyle:(ConversationStyle *)conversationStyle
                               isIncoming:(BOOL)isIncoming
                        isOverlayingMedia:(BOOL)isOverlayingMedia
                          isOutsideBubble:(BOOL)isOutsideBubble;

- (CGSize)measureWithConversationViewItem:(id<ConversationViewItem>)viewItem;

- (void)prepareForReuse;

@end

NS_ASSUME_NONNULL_END
