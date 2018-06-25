//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

@class ConversationViewItem;

NS_ASSUME_NONNULL_BEGIN

@interface OWSMessageFooterView : UIView

- (void)configureWithConversationViewItem:(ConversationViewItem *)viewItem;

- (CGSize)measureWithConversationViewItem:(ConversationViewItem *)viewItem;

@end

NS_ASSUME_NONNULL_END
