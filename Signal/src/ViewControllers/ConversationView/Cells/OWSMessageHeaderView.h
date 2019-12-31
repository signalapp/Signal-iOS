//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

@class ConversationStyle;

@protocol ConversationViewItem;

NS_ASSUME_NONNULL_BEGIN

@interface OWSMessageHeaderView : UIStackView

- (void)loadForDisplayWithViewItem:(id<ConversationViewItem>)viewItem
                 conversationStyle:(ConversationStyle *)conversationStyle;

- (CGSize)measureWithConversationViewItem:(id<ConversationViewItem>)viewItem
                        conversationStyle:(ConversationStyle *)conversationStyle;

@end

NS_ASSUME_NONNULL_END
