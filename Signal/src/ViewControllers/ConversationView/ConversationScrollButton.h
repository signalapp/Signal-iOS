//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface ConversationScrollButton : UIButton

@property (nonatomic) NSUInteger unreadCount;

+ (CGFloat)buttonSize;

- (nullable instancetype)initWithIconName:(NSString *)iconName;

@end

NS_ASSUME_NONNULL_END
