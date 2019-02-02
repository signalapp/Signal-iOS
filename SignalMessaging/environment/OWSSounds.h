//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSAudioPlayer.h"
#import <AudioToolbox/AudioServices.h>

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
    OWSSound_SignalClassic,

    // Ringtone Sounds
    OWSSound_Opening,

    // Calls
    OWSSound_CallConnecting,
    OWSSound_CallOutboundRinging,
    OWSSound_CallBusy,
    OWSSound_CallFailure,

    // Other
    OWSSound_MessageSent,
    OWSSound_None,
    OWSSound_DefaultiOSIncomingRingtone = OWSSound_Opening,
};

@class OWSAudioPlayer;
@class OWSPrimaryStorage;
@class TSThread;
@class YapDatabaseReadWriteTransaction;

@interface OWSSounds : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage NS_DESIGNATED_INITIALIZER;

+ (NSString *)displayNameForSound:(OWSSound)sound;

+ (nullable NSString *)filenameForSound:(OWSSound)sound;
+ (nullable NSString *)filenameForSound:(OWSSound)sound quiet:(BOOL)quiet;

#pragma mark - Notifications

+ (NSArray<NSNumber *> *)allNotificationSounds;

+ (OWSSound)globalNotificationSound;
+ (void)setGlobalNotificationSound:(OWSSound)sound;
+ (void)setGlobalNotificationSound:(OWSSound)sound transaction:(YapDatabaseReadWriteTransaction *)transaction;

+ (OWSSound)notificationSoundForThread:(TSThread *)thread;
+ (SystemSoundID)systemSoundIDForSound:(OWSSound)sound quiet:(BOOL)quiet;
+ (void)setNotificationSound:(OWSSound)sound forThread:(TSThread *)thread;

#pragma mark - AudioPlayer

+ (nullable OWSAudioPlayer *)audioPlayerForSound:(OWSSound)sound
                                   audioBehavior:(OWSAudioBehavior)audioBehavior;

@end

NS_ASSUME_NONNULL_END
