//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class ConversationStyle;
@class TSAttachmentStream;

@interface OWSGenericAttachmentView : UIStackView

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachmentStream isIncoming:(BOOL)isIncoming;

- (void)createContentsWithConversationStyle:(ConversationStyle *)conversationStyle;

- (CGSize)measureSizeWithMaxMessageWidth:(CGFloat)maxMessageWidth;

@end

NS_ASSUME_NONNULL_END
