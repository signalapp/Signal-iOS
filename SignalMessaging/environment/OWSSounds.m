//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSSounds.h"
#import <AVFoundation/AVFoundation.h>
#import <SignalServiceKit/TSStorageManager.h>
#import <SignalServiceKit/TSThread.h>
#import <SignalServiceKit/YapDatabaseConnection+OWS.h>

NSString *const kOWSSoundsStorageNotificationCollection = @"kOWSSoundsStorageNotificationCollection";
NSString *const kOWSSoundsStorageGlobalNotificationKey = @"kOWSSoundsStorageGlobalNotificationKey";

NSString *const kOWSSoundsStorageRingtoneCollection = @"kOWSSoundsStorageRingtoneCollection";
NSString *const kOWSSoundsStorageGlobalRingtoneKey = @"kOWSSoundsStorageGlobalRingtoneKey";

@interface OWSSounds ()

@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

@property (nonatomic, nullable) AVAudioPlayer *audioPlayer;

@end

#pragma mark -

@implementation OWSSounds

+ (instancetype)sharedManager
{
    static OWSSounds *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] initDefault];
    });
    return instance;
}

- (instancetype)initDefault
{
    TSStorageManager *storageManager = [TSStorageManager sharedManager];

    return [self initWithStorageManager:storageManager];
}

- (instancetype)initWithStorageManager:(TSStorageManager *)storageManager
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssert(storageManager);

    _dbConnection = storageManager.newDatabaseConnection;

    OWSSingletonAssert();

    return self;
}

+ (NSArray<NSNumber *> *)allNotificationSounds
{
    return @[
        // None should be first.
        @(OWSSound_None),

        @(OWSSound_Aurora),
        @(OWSSound_Bamboo),
        @(OWSSound_Chord),
        @(OWSSound_Circles),
        @(OWSSound_ClassicNotification),
        @(OWSSound_Complete),
        @(OWSSound_Hello),
        @(OWSSound_Input),
        @(OWSSound_Keys),
        @(OWSSound_Note),
        @(OWSSound_Popcorn),
        @(OWSSound_Pulse),
        @(OWSSound_Synth),
    ];
}

+ (NSArray<NSNumber *> *)allRingtoneSounds
{
    return @[
        // None should be first.
        @(OWSSound_None),

        @(OWSSound_Apex),
        @(OWSSound_Beacon),
        @(OWSSound_Bulletin),
        @(OWSSound_By_The_Seaside),
        @(OWSSound_Chimes),
        @(OWSSound_Circuit),
        @(OWSSound_ClassicRingtone),
        @(OWSSound_Constellation),
        @(OWSSound_Cosmic),
        @(OWSSound_Crystals),
        @(OWSSound_Hillside),
        @(OWSSound_Illuminate),
        @(OWSSound_Night_Owl),
        @(OWSSound_Opening),
        @(OWSSound_Playtime),
        @(OWSSound_Presto),
        @(OWSSound_Radar),
        @(OWSSound_Radiate),
        @(OWSSound_Ripples),
        @(OWSSound_Sencha),
        @(OWSSound_Signal),
        @(OWSSound_Silk),
        @(OWSSound_Slow_Rise),
        @(OWSSound_Stargaze),
        @(OWSSound_Summit),
        @(OWSSound_Twinkle),
        @(OWSSound_Uplift),
        @(OWSSound_Waves),
    ];
}

+ (NSString *)displayNameForSound:(OWSSound)sound
{
    // TODO: Should we localize these sound names?
    switch (sound) {
        case OWSSound_Default:
            OWSFail(@"%@ invalid argument.", self.logTag);
            return @"";

            // Notification Sounds
        case OWSSound_Aurora:
            return @"Aurora";
        case OWSSound_Bamboo:
            return @"Bamboo";
        case OWSSound_Chord:
            return @"Chord";
        case OWSSound_Circles:
            return @"Circles";
        case OWSSound_Complete:
            return @"Complete";
        case OWSSound_Hello:
            return @"Hello";
        case OWSSound_Input:
            return @"Input";
        case OWSSound_Keys:
            return @"Keys";
        case OWSSound_Note:
            return @"Note";
        case OWSSound_Popcorn:
            return @"Popcorn";
        case OWSSound_Pulse:
            return @"Pulse";
        case OWSSound_Synth:
            return @"Synth";
        case OWSSound_ClassicNotification:
            return @"Classic";

            // Ringtone Sounds
        case OWSSound_Apex:
            return @"Apex";
        case OWSSound_Beacon:
            return @"Beacon";
        case OWSSound_Bulletin:
            return @"Bulletin";
        case OWSSound_By_The_Seaside:
            return @"By The Seaside";
        case OWSSound_Chimes:
            return @"Chimes";
        case OWSSound_Circuit:
            return @"Circuit";
        case OWSSound_Constellation:
            return @"Constellation";
        case OWSSound_Cosmic:
            return @"Cosmic";
        case OWSSound_Crystals:
            return @"Crystals";
        case OWSSound_Hillside:
            return @"Hillside";
        case OWSSound_Illuminate:
            return @"Illuminate";
        case OWSSound_Night_Owl:
            return @"Night Owl";
        case OWSSound_Opening:
            return @"Opening";
        case OWSSound_Playtime:
            return @"Playtime";
        case OWSSound_Presto:
            return @"Presto";
        case OWSSound_Radar:
            return @"Radar";
        case OWSSound_Radiate:
            return @"Radiate";
        case OWSSound_Ripples:
            return @"Ripples";
        case OWSSound_Sencha:
            return @"Sencha";
        case OWSSound_Signal:
            return @"Signal";
        case OWSSound_Silk:
            return @"Silk";
        case OWSSound_Slow_Rise:
            return @"Slow Rise";
        case OWSSound_Stargaze:
            return @"Stargaze";
        case OWSSound_Summit:
            return @"Summit";
        case OWSSound_Twinkle:
            return @"Twinkle";
        case OWSSound_Uplift:
            return @"Uplift";
        case OWSSound_Waves:
            return @"Waves";
        case OWSSound_ClassicRingtone:
            return @"Classic";

            // Calls
        case OWSSound_CallConnecting:
            return @"Call Connecting";
        case OWSSound_CallOutboundRinging:
            return @"Call Outboung Ringing";
        case OWSSound_CallBusy:
            return @"Call Busy";
        case OWSSound_CallFailure:
            return @"Call Failure";

            // Other
        case OWSSound_None:
            return NSLocalizedString(@"SOUNDS_NONE",
                @"Label for the 'no sound' option that allows users to disable sounds for notifications, ringtones, "
                @"etc.");
    }
}

+ (nullable NSString *)filenameForSound:(OWSSound)sound
{
    switch (sound) {
        case OWSSound_Default:
            OWSFail(@"%@ invalid argument.", self.logTag);
            return @"";

            // Notification Sounds
        case OWSSound_Aurora:
            return @"aurora.m4r";
        case OWSSound_Bamboo:
            return @"bamboo.m4r";
        case OWSSound_Chord:
            return @"chord.m4r";
        case OWSSound_Circles:
            return @"circles.m4r";
        case OWSSound_Complete:
            return @"complete.m4r";
        case OWSSound_Hello:
            return @"hello.m4r";
        case OWSSound_Input:
            return @"input.m4r";
        case OWSSound_Keys:
            return @"keys.m4r";
        case OWSSound_Note:
            return @"note.m4r";
        case OWSSound_Popcorn:
            return @"popcorn.m4r";
        case OWSSound_Pulse:
            return @"pulse.m4r";
        case OWSSound_Synth:
            return @"synth.m4r";
        case OWSSound_ClassicNotification:
            return @"messageReceivedClassic.aifc";

            // Ringtone Sounds
        case OWSSound_Apex:
            return @"Apex.m4r";
        case OWSSound_Beacon:
            return @"Beacon.m4r";
        case OWSSound_Bulletin:
            return @"Bulletin.m4r";
        case OWSSound_By_The_Seaside:
            return @"By The Seaside.m4r";
        case OWSSound_Chimes:
            return @"Chimes.m4r";
        case OWSSound_Circuit:
            return @"Circuit.m4r";
        case OWSSound_Constellation:
            return @"Constellation.m4r";
        case OWSSound_Cosmic:
            return @"Cosmic.m4r";
        case OWSSound_Crystals:
            return @"Crystals.m4r";
        case OWSSound_Hillside:
            return @"Hillside.m4r";
        case OWSSound_Illuminate:
            return @"Illuminate.m4r";
        case OWSSound_Night_Owl:
            return @"Night Owl.m4r";
        case OWSSound_Opening:
            return @"Opening.m4r";
        case OWSSound_Playtime:
            return @"Playtime.m4r";
        case OWSSound_Presto:
            return @"Presto.m4r";
        case OWSSound_Radar:
            return @"Radar.m4r";
        case OWSSound_Radiate:
            return @"Radiate.m4r";
        case OWSSound_Ripples:
            return @"Ripples.m4r";
        case OWSSound_Sencha:
            return @"Sencha.m4r";
        case OWSSound_Signal:
            return @"Signal.m4r";
        case OWSSound_Silk:
            return @"Silk.m4r";
        case OWSSound_Slow_Rise:
            return @"Slow Rise.m4r";
        case OWSSound_Stargaze:
            return @"Stargaze.m4r";
        case OWSSound_Summit:
            return @"Summit.m4r";
        case OWSSound_Twinkle:
            return @"Twinkle.m4r";
        case OWSSound_Uplift:
            return @"Uplift.m4r";
        case OWSSound_Waves:
            return @"Waves.m4r";
        case OWSSound_ClassicRingtone:
            return @"ringtoneClassic.caf";

            // Calls
        case OWSSound_CallConnecting:
            return @"ringback_tone_cept.caf";
        case OWSSound_CallOutboundRinging:
            return @"ringback_tone_ansi.caf";
        case OWSSound_CallBusy:
            return @"busy_tone_ansi.caf";
        case OWSSound_CallFailure:
            return @"end_call_tone_cept.caf";

            // Other
        case OWSSound_None:
            return nil;
    }
}

+ (nullable NSURL *)soundURLForSound:(OWSSound)sound
{
    NSString *_Nullable filename = [self filenameForSound:sound];
    if (!filename) {
        return nil;
    }
    NSURL *_Nullable url = [[NSBundle mainBundle] URLForResource:filename.stringByDeletingPathExtension
                                                   withExtension:filename.pathExtension];
    OWSAssert(url);
    return url;
}

+ (void)playSound:(OWSSound)sound
{
    [self.sharedManager playSound:sound];
}

- (void)playSound:(OWSSound)sound
{
    [self.audioPlayer stop];
    self.audioPlayer = [OWSSounds audioPlayerForSound:sound];
    [self.audioPlayer play];
}

#pragma mark - Notifications

+ (OWSSound)defaultNotificationSound
{
    return OWSSound_Note;
}

+ (OWSSound)globalNotificationSound
{
    OWSSounds *instance = OWSSounds.sharedManager;
    NSNumber *_Nullable value = [instance.dbConnection objectForKey:kOWSSoundsStorageGlobalNotificationKey
                                                       inCollection:kOWSSoundsStorageNotificationCollection];
    // Default to the global default.
    return (value ? (OWSSound)value.intValue : [self defaultNotificationSound]);
}

+ (void)setGlobalNotificationSound:(OWSSound)sound
{
    OWSSounds *instance = OWSSounds.sharedManager;
    [instance.dbConnection setObject:@(sound)
                              forKey:kOWSSoundsStorageGlobalNotificationKey
                        inCollection:kOWSSoundsStorageNotificationCollection];
}

+ (OWSSound)notificationSoundForThread:(TSThread *)thread
{
    OWSSounds *instance = OWSSounds.sharedManager;
    NSNumber *_Nullable value =
        [instance.dbConnection objectForKey:thread.uniqueId inCollection:kOWSSoundsStorageNotificationCollection];
    // Default to the "global" notification sound, which in turn will default to the global default.
    return (value ? (OWSSound)value.intValue : [self globalNotificationSound]);
}

+ (void)setNotificationSound:(OWSSound)sound forThread:(TSThread *)thread
{
    OWSSounds *instance = OWSSounds.sharedManager;
    [instance.dbConnection setObject:@(sound)
                              forKey:thread.uniqueId
                        inCollection:kOWSSoundsStorageNotificationCollection];
}

#pragma mark - Ringtones

+ (OWSSound)defaultRingtoneSound
{
    return OWSSound_Opening;
}

+ (OWSSound)globalRingtoneSound
{
    OWSSounds *instance = OWSSounds.sharedManager;
    NSNumber *_Nullable value = [instance.dbConnection objectForKey:kOWSSoundsStorageGlobalRingtoneKey
                                                       inCollection:kOWSSoundsStorageRingtoneCollection];
    // Default to the global default.
    return (value ? (OWSSound)value.intValue : [self defaultRingtoneSound]);
}

+ (void)setGlobalRingtoneSound:(OWSSound)sound
{
    OWSSounds *instance = OWSSounds.sharedManager;
    [instance.dbConnection setObject:@(sound)
                              forKey:kOWSSoundsStorageGlobalRingtoneKey
                        inCollection:kOWSSoundsStorageRingtoneCollection];
}

+ (OWSSound)ringtoneSoundForThread:(TSThread *)thread
{
    OWSSounds *instance = OWSSounds.sharedManager;
    NSNumber *_Nullable value =
        [instance.dbConnection objectForKey:thread.uniqueId inCollection:kOWSSoundsStorageRingtoneCollection];
    // Default to the "global" ringtone sound, which in turn will default to the global default.
    return (value ? (OWSSound)value.intValue : [self globalRingtoneSound]);
}

+ (void)setRingtoneSound:(OWSSound)sound forThread:(TSThread *)thread
{
    OWSSounds *instance = OWSSounds.sharedManager;
    [instance.dbConnection setObject:@(sound) forKey:thread.uniqueId inCollection:kOWSSoundsStorageRingtoneCollection];
}

#pragma mark - Calls

+ (BOOL)shouldAudioPlayerLoopForSound:(OWSSound)sound
{
    return (sound == OWSSound_CallConnecting || sound == OWSSound_CallOutboundRinging ||
        [self.allRingtoneSounds containsObject:@(sound)]);
}

+ (nullable AVAudioPlayer *)audioPlayerForSound:(OWSSound)sound
{
    NSURL *_Nullable soundURL = [OWSSounds soundURLForSound:sound];
    if (!soundURL) {
        return nil;
    }
    NSError *error;
    AVAudioPlayer *_Nullable player = [[AVAudioPlayer alloc] initWithContentsOfURL:soundURL error:&error];
    if (error || !player) {
        OWSFail(@"%@ audioPlayerForSound failed with error: %@.", self.logTag, error);
        return nil;
    }
    if ([self shouldAudioPlayerLoopForSound:sound]) {
        player.numberOfLoops = -1;
    }
    return player;
}

@end
