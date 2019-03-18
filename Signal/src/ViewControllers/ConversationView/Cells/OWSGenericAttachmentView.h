//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class ConversationStyle;
@class TSAttachment;

@interface OWSGenericAttachmentView : UIStackView

- (instancetype)initWithAttachment:(TSAttachment *)attachment isIncoming:(BOOL)isIncoming;

- (void)createContentsWithConversationStyle:(ConversationStyle *)conversationStyle;

- (CGSize)measureSizeWithMaxMessageWidth:(CGFloat)maxMessageWidth;

@end

NS_ASSUME_NONNULL_END
