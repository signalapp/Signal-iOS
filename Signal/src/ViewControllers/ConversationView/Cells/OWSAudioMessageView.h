//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSAudioAttachmentPlayer.h"

NS_ASSUME_NONNULL_BEGIN

@class ConversationViewItem;
@class TSAttachmentStream;

@interface OWSAudioMessageView : UIView

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachmentStream
                        isIncoming:(BOOL)isIncoming
                          viewItem:(ConversationViewItem *)viewItem;

- (void)createContents;

+ (CGFloat)bubbleHeight;

- (void)updateContents;

@end

NS_ASSUME_NONNULL_END
