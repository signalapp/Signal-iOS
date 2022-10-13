//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@interface ConversationScrollButton : UIButton

@property (nonatomic) NSUInteger unreadCount;

+ (CGFloat)buttonSize;

- (instancetype)initWithIconName:(NSString *)iconName;

@end

NS_ASSUME_NONNULL_END
