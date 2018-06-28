//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSAudioPlayer.h"

NS_ASSUME_NONNULL_BEGIN

@class ConversationViewItem;
@class TSAttachmentStream;

@interface OWSAudioMessageView : UIStackView

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachmentStream
                        isIncoming:(BOOL)isIncoming
                          viewItem:(ConversationViewItem *)viewItem;

- (void)createContents;

+ (CGFloat)bubbleHeight;

- (void)updateContents;

@end

NS_ASSUME_NONNULL_END
