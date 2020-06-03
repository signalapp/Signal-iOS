//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewCell.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSContactOffersCell : ConversationViewCell

+ (NSString *)cellReuseIdentifier;

- (instancetype)init;
- (nullable instancetype)initWithCoder:(NSCoder *)coder;
- (instancetype)initWithFrame:(CGRect)frame NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
