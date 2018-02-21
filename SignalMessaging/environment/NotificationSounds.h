//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

typedef NS_ENUM(NSUInteger, NotificationSound) {
    NotificationSound_Aurora = 0,
    NotificationSound_Default = NotificationSound_Aurora
};

NS_ASSUME_NONNULL_BEGIN

@interface NotificationSounds : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (NSArray<NSNumber *> *)allNotificationSounds;

+ (NSString *)displayNameForNotificationSound:(NotificationSound)notificationSound;

+ (void)playNotificationSound:(NotificationSound)notificationSound;

@end

NS_ASSUME_NONNULL_END
