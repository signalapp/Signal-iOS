//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

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
    
    // Calls
    OWSSound_CallConnecting,
    OWSSound_CallOutboundRinging,
    OWSSound_CallBusy,
    OWSSound_CallFailure,
};

@class AVAudioPlayer;
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

#pragma mark - Ringtones

+ (NSArray<NSNumber *> *)allRingtoneSounds;

+ (OWSSound)globalRingtoneSound;
+ (void)setGlobalRingtoneSound:(OWSSound)sound;

+ (OWSSound)ringtoneSoundForThread:(TSThread *)thread;
+ (void)setRingtoneSound:(OWSSound)sound forThread:(TSThread *)thread;

#pragma mark - Calls

+ (nullable AVAudioPlayer *)audioPlayerForSound:(OWSSound)sound;

@end

NS_ASSUME_NONNULL_END
