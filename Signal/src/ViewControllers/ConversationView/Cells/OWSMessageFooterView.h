//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

@class ConversationViewItem;

NS_ASSUME_NONNULL_BEGIN

@interface OWSMessageFooterView : UIStackView

- (void)configureWithConversationViewItem:(ConversationViewItem *)viewItem isOverlayingMedia:(BOOL)isOverlayingMedia;

- (CGSize)measureWithConversationViewItem:(ConversationViewItem *)viewItem;

- (void)prepareForReuse;

@end

NS_ASSUME_NONNULL_END
