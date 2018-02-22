//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

typedef NS_ENUM(NSUInteger, NotificationSound) {
    NotificationSound_Default = 0,
    NotificationSound_Aurora,
    NotificationSound_Bamboo,
    NotificationSound_Chord,
    NotificationSound_Circles,
    NotificationSound_Complete,
    NotificationSound_Hello,
    NotificationSound_Input,
    NotificationSound_Keys,
    NotificationSound_Note,
    NotificationSound_Popcorn,
    NotificationSound_Pulse,
    NotificationSound_Synth,
};

NS_ASSUME_NONNULL_BEGIN

@class TSThread;

@interface NotificationSounds : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (NSArray<NSNumber *> *)allNotificationSounds;

+ (NSString *)displayNameForNotificationSound:(NotificationSound)notificationSound;

+ (NSString *)filenameForNotificationSound:(NotificationSound)notificationSound;

+ (void)playNotificationSound:(NotificationSound)notificationSound;

+ (NotificationSound)globalNotificationSound;
+ (void)setGlobalNotificationSound:(NotificationSound)notificationSound;

+ (NotificationSound)notificationSoundForThread:(TSThread *)thread;
+ (void)setNotificationSound:(NotificationSound)notificationSound forThread:(TSThread *)thread;

@end

NS_ASSUME_NONNULL_END
