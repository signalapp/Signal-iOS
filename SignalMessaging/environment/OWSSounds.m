//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSSounds.h"
#import "OWSAudioPlayer.h"
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/TSStorageManager.h>
#import <SignalServiceKit/TSThread.h>
#import <SignalServiceKit/YapDatabaseConnection+OWS.h>
#import <YapDatabase/YapDatabase.h>

NSString *const kOWSSoundsStorageNotificationCollection = @"kOWSSoundsStorageNotificationCollection";
NSString *const kOWSSoundsStorageGlobalNotificationKey = @"kOWSSoundsStorageGlobalNotificationKey";

@interface OWSSounds ()

@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

@property (nonatomic, nullable) OWSAudioPlayer *audioPlayer;

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
        case OWSSound_Opening:
            return @"Opening";

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
                @"Label for the 'no sound' option that allows users to disable sounds for notifications, "
                @"etc.");
    }
}

+ (nullable NSString *)filenameForSound:(OWSSound)sound
{
    return [self filenameForSound:sound quiet:NO];
}

+ (nullable NSString *)filenameForSound:(OWSSound)sound quiet:(BOOL)quiet
{
    switch (sound) {
        case OWSSound_Default:
            OWSFail(@"%@ invalid argument.", self.logTag);
            return @"";

            // Notification Sounds
        case OWSSound_Aurora:
            return (quiet ? @"aurora-quiet.caf" : @"aurora.m4r");
        case OWSSound_Bamboo:
            return (quiet ? @"bamboo-quiet.caf" : @"bamboo.m4r");
        case OWSSound_Chord:
            return (quiet ? @"chord-quiet.caf" : @"chord.m4r");
        case OWSSound_Circles:
            return (quiet ? @"circles-quiet.caf" : @"circles.m4r");
        case OWSSound_Complete:
            return (quiet ? @"complete-quiet.caf" : @"complete.m4r");
        case OWSSound_Hello:
            return (quiet ? @"hello-quiet.caf" : @"hello.m4r");
        case OWSSound_Input:
            return (quiet ? @"input-quiet.caf" : @"input.m4r");
        case OWSSound_Keys:
            return (quiet ? @"keys-quiet.caf" : @"keys.m4r");
        case OWSSound_Note:
            return (quiet ? @"note-quiet.caf" : @"note.m4r");
        case OWSSound_Popcorn:
            return (quiet ? @"popcorn-quiet.caf" : @"popcorn.m4r");
        case OWSSound_Pulse:
            return (quiet ? @"pulse-quiet.caf" : @"pulse.m4r");
        case OWSSound_Synth:
            return (quiet ? @"synth-quiet.caf" : @"synth.m4r");
        case OWSSound_ClassicNotification:
            return (quiet ? @"messageReceivedClassic-quiet.caf" : @"messageReceivedClassic.aifc");

            // Ringtone Sounds
        case OWSSound_Opening:
            return @"Opening.m4r";

            // Calls
        case OWSSound_CallConnecting:
            return @"sonarping.mp3";
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

+ (nullable NSURL *)soundURLForSound:(OWSSound)sound quiet:(BOOL)quiet
{
    NSString *_Nullable filename = [self filenameForSound:sound quiet:quiet];
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
    [self.sharedManager playSound:sound quiet:NO];
}

+ (void)playSound:(OWSSound)sound quiet:(BOOL)quiet
{
    [self.sharedManager playSound:sound quiet:quiet];
}

- (void)playSound:(OWSSound)sound quiet:(BOOL)quiet
{
    [self.audioPlayer stop];
    self.audioPlayer = [OWSSounds audioPlayerForSound:sound quiet:quiet];
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
    // Fallback push notifications play a sound specified by the server, but we don't want to store this configuration
    // on the server. Instead, we create a file with the same name as the default to be played when receiving
    // a fallback notification.
    NSString *dirPath = [[OWSFileSystem appLibraryDirectoryPath] stringByAppendingPathComponent:@"Sounds"];
    [OWSFileSystem ensureDirectoryExists:dirPath];

    // This name is specified in the payload by the Signal Service when requesting fallback push notifications.
    NSString *kDefaultNotificationSoundFilename = @"NewMessage.aifc";
    NSString *defaultSoundPath = [dirPath stringByAppendingPathComponent:kDefaultNotificationSoundFilename];

    DDLogDebug(@"%@ writing new default sound to %@", self.logTag, defaultSoundPath);

    NSURL *_Nullable soundURL = [OWSSounds soundURLForSound:sound quiet:NO];
    OWSAssert(soundURL);

    // Quick way to achieve an atomic "copy" operation that allows overwriting if the user has previously specified
    // a default notification sound.
    NSData *soundData = [NSData dataWithContentsOfURL:soundURL];
    BOOL success = [soundData writeToFile:defaultSoundPath atomically:YES];

    // The globally configured sound the user has configured is unprotected, so that we can still play the sound if the
    // user hasn't authenticated after power-cycling their device.
    [OWSFileSystem protectFileOrFolderAtPath:defaultSoundPath fileProtectionType:NSFileProtectionNone];

    if (!success) {
        OWSProdLogAndFail(
            @"%@ Unable to write new default sound data from: %@ to :%@", self.logTag, soundURL, defaultSoundPath);
        return;
    }

    OWSSounds *instance = OWSSounds.sharedManager;
    [instance.dbConnection setObject:@(sound)
                              forKey:kOWSSoundsStorageGlobalNotificationKey
                        inCollection:kOWSSoundsStorageNotificationCollection];
}

+ (void)setGlobalNotificationSound:(OWSSound)sound transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(transaction);

    [transaction setObject:@(sound)
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

#pragma mark - AudioPlayer

+ (BOOL)shouldAudioPlayerLoopForSound:(OWSSound)sound
{
    return (sound == OWSSound_CallConnecting || sound == OWSSound_CallOutboundRinging);
}

+ (nullable OWSAudioPlayer *)audioPlayerForSound:(OWSSound)sound
{
    return [self audioPlayerForSound:sound quiet:NO];
}

+ (nullable OWSAudioPlayer *)audioPlayerForSound:(OWSSound)sound quiet:(BOOL)quiet
{
    NSURL *_Nullable soundURL = [OWSSounds soundURLForSound:sound quiet:(BOOL)quiet];
    if (!soundURL) {
        return nil;
    }
    OWSAudioPlayer *player = [[OWSAudioPlayer alloc] initWithMediaUrl:soundURL];
    if ([self shouldAudioPlayerLoopForSound:sound]) {
        player.isLooping = YES;
    }
    return player;
}

@end
