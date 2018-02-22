//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

typedef NS_ENUM(NSUInteger, OWSSound) {
    OWSSound_Default = 0,
    // Notification Sounds
    OWSSound_Aurora,
    OWSSound_Bamboo,
    OWSSound_Chord,
    OWSSound_Circles,
    OWSSound_Complete,
    OWSSound_Hello,
    OWSSound_Input,
    OWSSound_Keys,
    OWSSound_Note,
    OWSSound_Popcorn,
    OWSSound_Pulse,
    OWSSound_Synth,
    // Ringtone Sounds
    OWSSound_Apex,
    OWSSound_Beacon,
    OWSSound_Bulletin,
    OWSSound_By_The_Seaside,
    OWSSound_Chimes,
    OWSSound_Circuit,
    OWSSound_Constellation,
    OWSSound_Cosmic,
    OWSSound_Crystals,
    OWSSound_Hillside,
    OWSSound_Illuminate,
    OWSSound_Night_Owl,
    OWSSound_Opening,
    OWSSound_Playtime,
    OWSSound_Presto,
    OWSSound_Radar,
    OWSSound_Radiate,
    OWSSound_Ripples,
    OWSSound_Sencha,
    OWSSound_Signal,
    OWSSound_Silk,
    OWSSound_Slow_Rise,
    OWSSound_Stargaze,
    OWSSound_Summit,
    OWSSound_Twinkle,
    OWSSound_Uplift,
    OWSSound_Waves,
};

NS_ASSUME_NONNULL_BEGIN

@class TSThread;

@interface OWSSounds : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (NSString *)displayNameForSound:(OWSSound)sound;

+ (NSString *)filenameForSound:(OWSSound)sound;

+ (void)playSound:(OWSSound)sound;

#pragma mark - Notifications

+ (NSArray<NSNumber *> *)allNotificationSounds;

+ (OWSSound)globalNotificationSound;
+ (void)setGlobalNotificationSound:(OWSSound)sound;

+ (OWSSound)notificationSoundForThread:(TSThread *)thread;
+ (void)setNotificationSound:(OWSSound)sound forThread:(TSThread *)thread;

@end

NS_ASSUME_NONNULL_END
