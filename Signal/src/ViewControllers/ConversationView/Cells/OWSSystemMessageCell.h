//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewCell.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSSystemMessageCell : ConversationViewCell <SelectableConversationCell>

+ (NSString *)cellReuseIdentifier;

- (instancetype)init NS_DESIGNATED_INITIALIZER;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
