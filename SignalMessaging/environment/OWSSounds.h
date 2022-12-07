//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <AudioToolbox/AudioServices.h>

NS_ASSUME_NONNULL_BEGIN

typedef NSUInteger OWSSound;

typedef NS_ENUM(NSUInteger, OWSStandardSound) {
    OWSStandardSound_Default = 0,

    // Notification Sounds
    OWSStandardSound_Aurora = 1,
    OWSStandardSound_Bamboo = 2,
    OWSStandardSound_Chord = 3,
    OWSStandardSound_Circles = 4,
    OWSStandardSound_Complete = 5,
    OWSStandardSound_Hello = 6,
    OWSStandardSound_Input = 7,
    OWSStandardSound_Keys = 8,
    OWSStandardSound_Note = 9,
    OWSStandardSound_Popcorn = 10,
    OWSStandardSound_Pulse = 11,
    OWSStandardSound_Synth = 12,
    OWSStandardSound_SignalClassic = 13,

    // Ringtone Sounds
    OWSStandardSound_Reflection = 14,

    // Calls
    OWSStandardSound_CallConnecting = 15,
    OWSStandardSound_CallOutboundRinging = 16,
    OWSStandardSound_CallBusy = 17,
    OWSStandardSound_CallEnded = 18,

    // Group Calls
    OWSStandardSound_GroupCallJoin = 19,
    OWSStandardSound_GroupCallLeave = 20,

    // Other
    OWSStandardSound_MessageSent = 21,
    OWSStandardSound_None = 22,
    OWSStandardSound_Silence = 23,

    // Audio Playback
    OWSStandardSound_BeginNextTrack = 24,
    OWSStandardSound_EndLastTrack = 25,

    OWSStandardSound_DefaultiOSIncomingRingtone = OWSStandardSound_Reflection,

    // Custom sound IDs begin at this threshold
    OWSStandardSound_CustomThreshold = 1 << 16, // 16 == OWSCustomSoundShift
};

@class SDSAnyWriteTransaction;
@class SDSKeyValueStore;
@class TSThread;

@interface OWSSounds : NSObject

+ (SDSKeyValueStore *)keyValueStore;

+ (NSString *)displayNameForSound:(OWSSound)sound;

+ (nullable NSString *)filenameForSound:(OWSSound)sound;
+ (nullable NSString *)filenameForSound:(OWSSound)sound quiet:(BOOL)quiet;

+ (nullable NSURL *)soundURLForSound:(OWSSound)sound quiet:(BOOL)quiet;

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

@end

NS_ASSUME_NONNULL_END
