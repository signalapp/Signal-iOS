//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewCell.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSSystemMessageCell : ConversationViewCell <SelectableConversationCell>

+ (NSString *)cellReuseIdentifier;

@end

NS_ASSUME_NONNULL_END
