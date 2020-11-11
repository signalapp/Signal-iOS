//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class ConversationStyle;

@protocol ConversationViewItem;

@interface OWSMessageFooterView : UIStackView

- (void)configureWithConversationViewItem:(id<ConversationViewItem>)viewItem
                        isOverlayingMedia:(BOOL)isOverlayingMedia
                        conversationStyle:(ConversationStyle *)conversationStyle
                               isIncoming:(BOOL)isIncoming;

- (CGSize)measureWithConversationViewItem:(id<ConversationViewItem>)viewItem;

- (void)prepareForReuse;

@end

NS_ASSUME_NONNULL_END
