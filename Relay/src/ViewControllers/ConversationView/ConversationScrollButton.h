//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface ConversationScrollButton : UIButton

@property (nonatomic) BOOL hasUnreadMessages;

+ (CGFloat)buttonSize;

- (nullable instancetype)initWithIconText:(NSString *)iconText;

@end

NS_ASSUME_NONNULL_END
