//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

@class ConversationStyle;
@class ConversationViewItem;

NS_ASSUME_NONNULL_BEGIN

@interface OWSMessageFooterView : UIStackView

- (void)configureWithConversationViewItem:(ConversationViewItem *)viewItem
                        isOverlayingMedia:(BOOL)isOverlayingMedia
                        conversationStyle:(ConversationStyle *)conversationStyle
                               isIncoming:(BOOL)isIncoming;

- (CGSize)measureWithConversationViewItem:(ConversationViewItem *)viewItem;

- (void)prepareForReuse;

@end

NS_ASSUME_NONNULL_END
