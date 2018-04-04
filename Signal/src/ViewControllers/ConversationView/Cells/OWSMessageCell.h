//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewCell.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSMessageCell : ConversationViewCell

+ (NSString *)cellReuseIdentifier;

+ (UIFont *)defaultTextMessageFont;

@end

NS_ASSUME_NONNULL_END
