//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSAudioPlayer.h"
#import <AudioToolbox/AudioServices.h>

NS_ASSUME_NONNULL_BEGIN

typedef NSUInteger OWSSound;

typedef NS_ENUM(NSUInteger, OWSStandardSound) {
    OWSStandardSound_Default = 0,

    // Notification Sounds
    OWSStandardSound_Aurora,
    OWSStandardSound_Bamboo,
    OWSStandardSound_Chord,
    OWSStandardSound_Circles,
    OWSStandardSound_Complete,
    OWSStandardSound_Hello,
    OWSStandardSound_Input,
    OWSStandardSound_Keys,
    OWSStandardSound_Note,
    OWSStandardSound_Popcorn,
    OWSStandardSound_Pulse,
    OWSStandardSound_Synth,
    OWSStandardSound_SignalClassic,

    // Ringtone Sounds
    OWSStandardSound_Reflection,

    // Calls
    OWSStandardSound_CallConnecting,
    OWSStandardSound_CallOutboundRinging,
    OWSStandardSound_CallBusy,
    OWSStandardSound_CallEnded,

    // Group Calls
    OWSStandardSound_GroupCallJoin,
    OWSStandardSound_GroupCallLeave,

    // Other
    OWSStandardSound_MessageSent,
    OWSStandardSound_None,
    OWSStandardSound_Silence,
    OWSStandardSound_DefaultiOSIncomingRingtone = OWSStandardSound_Reflection,

    // Custom sound IDs begin at this threshold
    OWSStandardSound_CustomThreshold = 1 << 16, // 16 == OWSCustomSoundShift
};

@class OWSAudioPlayer;
@class SDSAnyWriteTransaction;
@class SDSKeyValueStore;
@class TSThread;

@interface OWSSounds : NSObject

+ (SDSKeyValueStore *)keyValueStore;

+ (NSString *)displayNameForSound:(OWSSound)sound;

+ (nullable NSString *)filenameForSound:(OWSSound)sound;
+ (nullable NSString *)filenameForSound:(OWSSound)sound quiet:(BOOL)quiet;

+ (void)importSoundsAtURLs:(NSArray<NSURL *> *)urls;
+ (NSString *)soundsDirectory;

#pragma mark - Notifications

+ (NSArray<NSNumber *> *)allNotificationSounds;

+ (OWSSound)globalNotificationSound;
+ (void)setGlobalNotificationSound:(OWSSound)sound;
+ (void)setGlobalNotificationSound:(OWSSound)sound transaction:(SDSAnyWriteTransaction *)transaction;

+ (OWSSound)notificationSoundForThread:(TSThread *)thread;
+ (SystemSoundID)systemSoundIDForSound:(OWSSound)sound quiet:(BOOL)quiet;
+ (void)setNotificationSound:(OWSSound)sound forThread:(TSThread *)thread;

#pragma mark - AudioPlayer

+ (nullable OWSAudioPlayer *)audioPlayerForSound:(OWSSound)sound
                                   audioBehavior:(OWSAudioBehavior)audioBehavior;

@end

NS_ASSUME_NONNULL_END
