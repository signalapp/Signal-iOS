//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewCell.h"

@class OWSMessageBubbleView;

NS_ASSUME_NONNULL_BEGIN

@interface OWSMessageCell : ConversationViewCell

@property (nonatomic, readonly) OWSMessageBubbleView *messageBubbleView;

+ (NSString *)cellReuseIdentifier;

@end

NS_ASSUME_NONNULL_END
