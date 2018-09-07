//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSSounds.h"
#import "OWSAudioPlayer.h"
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/OWSPrimaryStorage.h>
#import <SignalServiceKit/TSThread.h>
#import <SignalServiceKit/YapDatabaseConnection+OWS.h>
#import <YapDatabase/YapDatabase.h>

NSString *const kOWSSoundsStorageNotificationCollection = @"kOWSSoundsStorageNotificationCollection";
NSString *const kOWSSoundsStorageGlobalNotificationKey = @"kOWSSoundsStorageGlobalNotificationKey";

@interface OWSSystemSound : NSObject

@property (nonatomic, readonly) SystemSoundID soundID;
@property (nonatomic, readonly) NSURL *soundURL;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithURL:(NSURL *)url NS_DESIGNATED_INITIALIZER;

@end

@implementation OWSSystemSound

- (instancetype)initWithURL:(NSURL *)url
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSLogDebug(@"creating system sound for %@", url.lastPathComponent);
    _soundURL = url;

    SystemSoundID newSoundID;
    OSStatus status = AudioServicesCreateSystemSoundID((__bridge CFURLRef _Nonnull)(url), &newSoundID);
    OWSAssertDebug(status == kAudioServicesNoError);
    OWSAssertDebug(newSoundID);
    _soundID = newSoundID;

    return self;
}

- (void)dealloc
{
    OWSLogDebug(@"in dealloc disposing sound: %@", _soundURL.lastPathComponent);
    OSStatus status = AudioServicesDisposeSystemSoundID(_soundID);
    OWSAssertDebug(status == kAudioServicesNoError);
}

@end

@interface OWSSounds ()

@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;
@property (nonatomic, readonly) AnyLRUCache *cachedSystemSounds;

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
    OWSPrimaryStorage *primaryStorage = [OWSPrimaryStorage sharedManager];

    return [self initWithPrimaryStorage:primaryStorage];
}

- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssertDebug(primaryStorage);

    _dbConnection = primaryStorage.newDatabaseConnection;

    // Don't store too many sounds in memory. Most users will only use 1 or 2 sounds anyway.
    _cachedSystemSounds = [[AnyLRUCache alloc] initWithMaxSize:4];

    OWSSingletonAssert();

    return self;
}

+ (NSArray<NSNumber *> *)allNotificationSounds
{
    return @[
        // None and Note (default) should be first.
        @(OWSSound_None),
        @(OWSSound_Note),

        @(OWSSound_Aurora),
        @(OWSSound_Bamboo),
        @(OWSSound_Chord),
        @(OWSSound_Circles),
        @(OWSSound_Complete),
        @(OWSSound_Hello),
        @(OWSSound_Input),
        @(OWSSound_Keys),
        @(OWSSound_Popcorn),
        @(OWSSound_Pulse),
        @(OWSSound_SignalClassic),
        @(OWSSound_Synth),
    ];
}

+ (NSString *)displayNameForSound:(OWSSound)sound
{
    // TODO: Should we localize these sound names?
    switch (sound) {
        case OWSSound_Default:
            OWSFailDebug(@"invalid argument.");
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
        case OWSSound_SignalClassic:
            return @"Signal Classic";

        // Call Audio
        case OWSSound_Opening:
            return @"Opening";
        case OWSSound_CallConnecting:
            return @"Call Connecting";
        case OWSSound_CallOutboundRinging:
            return @"Call Outboung Ringing";
        case OWSSound_CallBusy:
            return @"Call Busy";
        case OWSSound_CallFailure:
            return @"Call Failure";
        case OWSSound_MessageSent:
            return @"Message Sent";

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
            OWSFailDebug(@"invalid argument.");
            return @"";

            // Notification Sounds
        case OWSSound_Aurora:
            return (quiet ? @"aurora-quiet.aifc" : @"aurora.aifc");
        case OWSSound_Bamboo:
            return (quiet ? @"bamboo-quiet.aifc" : @"bamboo.aifc");
        case OWSSound_Chord:
            return (quiet ? @"chord-quiet.aifc" : @"chord.aifc");
        case OWSSound_Circles:
            return (quiet ? @"circles-quiet.aifc" : @"circles.aifc");
        case OWSSound_Complete:
            return (quiet ? @"complete-quiet.aifc" : @"complete.aifc");
        case OWSSound_Hello:
            return (quiet ? @"hello-quiet.aifc" : @"hello.aifc");
        case OWSSound_Input:
            return (quiet ? @"input-quiet.aifc" : @"input.aifc");
        case OWSSound_Keys:
            return (quiet ? @"keys-quiet.aifc" : @"keys.aifc");
        case OWSSound_Note:
            return (quiet ? @"note-quiet.aifc" : @"note.aifc");
        case OWSSound_Popcorn:
            return (quiet ? @"popcorn-quiet.aifc" : @"popcorn.aifc");
        case OWSSound_Pulse:
            return (quiet ? @"pulse-quiet.aifc" : @"pulse.aifc");
        case OWSSound_Synth:
            return (quiet ? @"synth-quiet.aifc" : @"synth.aifc");
        case OWSSound_SignalClassic:
            return (quiet ? @"classic-quiet.aifc" : @"classic.aifc");

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
        case OWSSound_MessageSent:
            return @"message_sent.aiff";

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
    OWSAssertDebug(url);
    return url;
}

+ (SystemSoundID)systemSoundIDForSound:(OWSSound)sound quiet:(BOOL)quiet
{
    return [self.sharedManager systemSoundIDForSound:(OWSSound)sound quiet:quiet];
}

- (SystemSoundID)systemSoundIDForSound:(OWSSound)sound quiet:(BOOL)quiet
{
    NSString *cacheKey = [NSString stringWithFormat:@"%lu:%d", (unsigned long)sound, quiet];
    OWSSystemSound *_Nullable cachedSound = (OWSSystemSound *)[self.cachedSystemSounds getWithKey:cacheKey];

    if (cachedSound) {
        OWSAssertDebug([cachedSound isKindOfClass:[OWSSystemSound class]]);
        return cachedSound.soundID;
    }

    NSURL *soundURL = [self.class soundURLForSound:sound quiet:quiet];
    OWSSystemSound *newSound = [[OWSSystemSound alloc] initWithURL:soundURL];
    [self.cachedSystemSounds setWithKey:cacheKey value:newSound];

    return newSound.soundID;
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
    [self.sharedManager setGlobalNotificationSound:sound];
}

- (void)setGlobalNotificationSound:(OWSSound)sound
{
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        [self setGlobalNotificationSound:sound transaction:transaction];
    }];
}

+ (void)setGlobalNotificationSound:(OWSSound)sound transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [self.sharedManager setGlobalNotificationSound:sound transaction:transaction];
}

- (void)setGlobalNotificationSound:(OWSSound)sound transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    OWSLogInfo(@"Setting global notification sound to: %@", [[self class] displayNameForSound:sound]);

    // Fallback push notifications play a sound specified by the server, but we don't want to store this configuration
    // on the server. Instead, we create a file with the same name as the default to be played when receiving
    // a fallback notification.
    NSString *dirPath = [[OWSFileSystem appLibraryDirectoryPath] stringByAppendingPathComponent:@"Sounds"];
    [OWSFileSystem ensureDirectoryExists:dirPath];

    // This name is specified in the payload by the Signal Service when requesting fallback push notifications.
    NSString *kDefaultNotificationSoundFilename = @"NewMessage.aifc";
    NSString *defaultSoundPath = [dirPath stringByAppendingPathComponent:kDefaultNotificationSoundFilename];

    OWSLogDebug(@"writing new default sound to %@", defaultSoundPath);

    NSURL *_Nullable soundURL = [OWSSounds soundURLForSound:sound quiet:NO];

    NSData *soundData = ^{
        if (soundURL) {
            return [NSData dataWithContentsOfURL:soundURL];
        } else {
            OWSAssertDebug(sound == OWSSound_None);
            return [NSData new];
        }
    }();

    // Quick way to achieve an atomic "copy" operation that allows overwriting if the user has previously specified
    // a default notification sound.
    BOOL success = [soundData writeToFile:defaultSoundPath atomically:YES];

    // The globally configured sound the user has configured is unprotected, so that we can still play the sound if the
    // user hasn't authenticated after power-cycling their device.
    [OWSFileSystem protectFileOrFolderAtPath:defaultSoundPath fileProtectionType:NSFileProtectionNone];

    if (!success) {
        OWSFailDebug(@"Unable to write new default sound data from: %@ to :%@", soundURL, defaultSoundPath);
        return;
    }

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
