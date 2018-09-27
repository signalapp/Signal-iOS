//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSAudioPlayer.h"

NS_ASSUME_NONNULL_BEGIN

@class ConversationStyle;
@class TSAttachmentStream;

@protocol ConversationViewItem;

@interface OWSAudioMessageView : UIStackView

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachmentStream
                        isIncoming:(BOOL)isIncoming
                          viewItem:(id<ConversationViewItem>)viewItem
                 conversationStyle:(ConversationStyle *)conversationStyle;

- (void)createContents;

+ (CGFloat)bubbleHeight;

- (void)updateContents;

@end

NS_ASSUME_NONNULL_END
