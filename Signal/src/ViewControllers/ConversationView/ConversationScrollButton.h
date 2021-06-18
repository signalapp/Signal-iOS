//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface ConversationScrollButton : UIButton

@property (nonatomic) NSUInteger unreadCount;

+ (CGFloat)buttonSize;

- (instancetype)initWithIconName:(NSString *)iconName;

@end

NS_ASSUME_NONNULL_END
