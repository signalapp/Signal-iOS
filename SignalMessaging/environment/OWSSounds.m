//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSSounds.h"
#import "Environment.h"
#import <SignalCoreKit/Cryptography.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSThread.h>

NSString *const kOWSSoundsStorageGlobalNotificationKey = @"kOWSSoundsStorageGlobalNotificationKey";
// This name is specified in the payload by the Signal Service when requesting fallback push notifications.
NSString *const kDefaultNotificationSoundFilename = @"NewMessage.aifc";

const NSUInteger OWSCustomSoundShift = 16;

@interface OWSSystemSound : NSObject

@property (nonatomic, readonly) SystemSoundID soundID;
@property (nonatomic, readonly) NSURL *soundURL;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithURL:(NSURL *)url NS_DESIGNATED_INITIALIZER;

@end

#pragma mark -

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

@property (nonatomic, readonly) AnyLRUCache *cachedSystemSounds;

@end

#pragma mark -

@implementation OWSSounds

- (instancetype)init
{
    self = [super init];

    if (!self) {
        return self;
    }

    // Don't store too many sounds in memory. Most users will only use 1 or 2 sounds anyway.
    _cachedSystemSounds = [[AnyLRUCache alloc] initWithMaxSize:4
                                                    nseMaxSize:0
                                    shouldEvacuateInBackground:NO];

    OWSSingletonAssert();

    AppReadinessRunNowOrWhenMainAppDidBecomeReadyAsync(^{
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [OWSSounds migrateLegacySounds];

            if (!CurrentAppContext().isNSE) {
                [OWSSounds cleanupOrphanedSounds];
            }
        });
    });

    return self;
}

+ (void)migrateLegacySounds
{
    OWSAssertDebug(CurrentAppContext().isMainApp);

    NSString *legacySoundsDirectory =
        [[OWSFileSystem appLibraryDirectoryPath] stringByAppendingPathComponent:@"Sounds"];
    if (![OWSFileSystem fileOrFolderExistsAtPath:legacySoundsDirectory]) {
        return;
    }

    NSError *error;
    NSArray *legacySoundFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:legacySoundsDirectory
                                                                                    error:&error];
    if (error) {
        OWSFailDebug(@"Failed looking up legacy sound files: %@", error.userErrorDescription);
        return;
    }

    for (NSString *soundFile in legacySoundFiles) {
        NSError *moveError;
        [[NSFileManager defaultManager] moveItemAtPath:[legacySoundsDirectory stringByAppendingPathComponent:soundFile]
                                                toPath:[[self soundsDirectory] stringByAppendingPathComponent:soundFile]
                                                 error:&moveError];
        if (moveError) {
            OWSFailDebug(@"Failed to migrate legacy sound file: %@", moveError.userErrorDescription);
            continue;
        }
    }

    if (![OWSFileSystem deleteFile:legacySoundsDirectory]) {
        OWSFailDebug(@"Failed to delete legacy sounds directory");
    }
}

+ (void)cleanupOrphanedSounds
{
    OWSAssertDebug(CurrentAppContext().isMainApp);

    NSSet<NSNumber *> *allCustomSounds = [NSSet setWithArray:[self allCustomNotificationSounds]];
    if (allCustomSounds.count == 0) {
        return;
    }

    __block NSSet<NSNumber *> *allInUseSounds;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        allInUseSounds = [NSSet setWithArray:[self.keyValueStore allValuesWithTransaction:transaction]];
    }];

    NSMutableSet *orphanedSounds = [allCustomSounds mutableCopy];
    [orphanedSounds minusSet:allInUseSounds];

    if (orphanedSounds.count == 0) {
        return;
    }

    NSUInteger deletedSoundCount = 0;
    for (NSNumber *soundNumber in orphanedSounds) {
        OWSSound sound = soundNumber.unsignedLongValue;
        if ([self deleteCustomSound:sound]) {
            deletedSoundCount++;
        } else {
            OWSFailDebug(@"Failed to delete orphaned sound.");
        }
    }

    OWSLogInfo(@"Cleaned up %lu orphaned custom sounds.", deletedSoundCount);
}

+ (SDSKeyValueStore *)keyValueStore
{
    NSString *const kOWSSoundsStorageNotificationCollection = @"kOWSSoundsStorageNotificationCollection";
    return [[SDSKeyValueStore alloc] initWithCollection:kOWSSoundsStorageNotificationCollection];
}

+ (NSArray<NSNumber *> *)allNotificationSounds
{
    return [@[
        // None and Note (default) should be first.
        @(OWSStandardSound_None),
        @(OWSStandardSound_Note),

        @(OWSStandardSound_Aurora),
        @(OWSStandardSound_Bamboo),
        @(OWSStandardSound_Chord),
        @(OWSStandardSound_Circles),
        @(OWSStandardSound_Complete),
        @(OWSStandardSound_Hello),
        @(OWSStandardSound_Input),
        @(OWSStandardSound_Keys),
        @(OWSStandardSound_Popcorn),
        @(OWSStandardSound_Pulse),
        @(OWSStandardSound_SignalClassic),
        @(OWSStandardSound_Synth),
    ] arrayByAddingObjectsFromArray:[OWSSounds allCustomNotificationSounds]];
}

+ (NSString *)displayNameForSound:(OWSSound)sound
{
    // TODO: Should we localize these sound names?
    switch (sound) {
        case OWSStandardSound_Default:
            OWSFailDebug(@"invalid argument.");
            return @"";

        // Notification Sounds
        case OWSStandardSound_Aurora:
            return @"Aurora";
        case OWSStandardSound_Bamboo:
            return @"Bamboo";
        case OWSStandardSound_Chord:
            return @"Chord";
        case OWSStandardSound_Circles:
            return @"Circles";
        case OWSStandardSound_Complete:
            return @"Complete";
        case OWSStandardSound_Hello:
            return @"Hello";
        case OWSStandardSound_Input:
            return @"Input";
        case OWSStandardSound_Keys:
            return @"Keys";
        case OWSStandardSound_Note:
            return @"Note";
        case OWSStandardSound_Popcorn:
            return @"Popcorn";
        case OWSStandardSound_Pulse:
            return @"Pulse";
        case OWSStandardSound_Synth:
            return @"Synth";
        case OWSStandardSound_SignalClassic:
            return @"Signal Classic";

        // Call Audio
        case OWSStandardSound_Reflection:
            return @"Opening";
        case OWSStandardSound_CallConnecting:
            return @"Call Connecting";
        case OWSStandardSound_CallOutboundRinging:
            return @"Call Outboung Ringing";
        case OWSStandardSound_CallBusy:
            return @"Call Busy";
        case OWSStandardSound_CallEnded:
            return @"Call Ended";
        case OWSStandardSound_MessageSent:
            return @"Message Sent";
        case OWSStandardSound_Silence:
            return @"Silence";

        // Group Calls
        case OWSStandardSound_GroupCallJoin:
            return @"Group Call Join";
        case OWSStandardSound_GroupCallLeave:
            return @"Group Call Leave";

        // Other
        case OWSStandardSound_None:
            return OWSLocalizedString(@"SOUNDS_NONE",
                @"Label for the 'no sound' option that allows users to disable sounds for notifications, "
                @"etc.");

        // Audio Playback
        case OWSStandardSound_BeginNextTrack:
            return @"Begin Next Track";
        case OWSStandardSound_EndLastTrack:
            return @"End Last Track";

        // Custom Sounds
        default:
            return [OWSSounds displayNameForCustomSound:sound];
    }
}

+ (nullable NSString *)filenameForSound:(OWSSound)sound
{
    return [self filenameForSound:sound quiet:NO];
}

+ (nullable NSString *)filenameForSound:(OWSSound)sound quiet:(BOOL)quiet
{
    switch (sound) {
        case OWSStandardSound_Default:
            OWSFailDebug(@"invalid argument.");
            return @"";

            // Notification Sounds
        case OWSStandardSound_Aurora:
            return (quiet ? @"aurora-quiet.aifc" : @"aurora.aifc");
        case OWSStandardSound_Bamboo:
            return (quiet ? @"bamboo-quiet.aifc" : @"bamboo.aifc");
        case OWSStandardSound_Chord:
            return (quiet ? @"chord-quiet.aifc" : @"chord.aifc");
        case OWSStandardSound_Circles:
            return (quiet ? @"circles-quiet.aifc" : @"circles.aifc");
        case OWSStandardSound_Complete:
            return (quiet ? @"complete-quiet.aifc" : @"complete.aifc");
        case OWSStandardSound_Hello:
            return (quiet ? @"hello-quiet.aifc" : @"hello.aifc");
        case OWSStandardSound_Input:
            return (quiet ? @"input-quiet.aifc" : @"input.aifc");
        case OWSStandardSound_Keys:
            return (quiet ? @"keys-quiet.aifc" : @"keys.aifc");
        case OWSStandardSound_Note:
            return (quiet ? @"note-quiet.aifc" : @"note.aifc");
        case OWSStandardSound_Popcorn:
            return (quiet ? @"popcorn-quiet.aifc" : @"popcorn.aifc");
        case OWSStandardSound_Pulse:
            return (quiet ? @"pulse-quiet.aifc" : @"pulse.aifc");
        case OWSStandardSound_Synth:
            return (quiet ? @"synth-quiet.aifc" : @"synth.aifc");
        case OWSStandardSound_SignalClassic:
            return (quiet ? @"classic-quiet.aifc" : @"classic.aifc");

            // Ringtone Sounds
        case OWSStandardSound_Reflection:
            return @"Reflection.m4r";

            // Calls
        case OWSStandardSound_CallConnecting:
            return @"ringback_tone_ansi.caf";
        case OWSStandardSound_CallOutboundRinging:
            return @"ringback_tone_ansi.caf";
        case OWSStandardSound_CallBusy:
            return @"busy_tone_ansi.caf";
        case OWSStandardSound_CallEnded:
            return @"end_call_tone_cept.caf";
        case OWSStandardSound_MessageSent:
            return @"message_sent.aiff";
        case OWSStandardSound_Silence:
            return @"silence.aiff";

        // Group Calls
        case OWSStandardSound_GroupCallJoin:
            return @"group_call_join.aiff";
        case OWSStandardSound_GroupCallLeave:
            return @"group_call_leave.aiff";

        // Audio Playback
        case OWSStandardSound_BeginNextTrack:
            return @"state-change_confirm-down.caf";
        case OWSStandardSound_EndLastTrack:
            return @"state-change_confirm-up.caf";

            // Other
        case OWSStandardSound_None:
            return nil;

            // Custom Sounds
        default:
            return [OWSSounds filenameForCustomSound:sound];
    }
}

+ (nullable NSURL *)soundURLForSound:(OWSSound)sound quiet:(BOOL)quiet
{
    if (sound < OWSStandardSound_CustomThreshold) {
        NSString *_Nullable filename = [self filenameForSound:sound quiet:quiet];
        if (!filename) {
            return nil;
        }
        NSURL *_Nullable url = [[NSBundle mainBundle] URLForResource:filename.stringByDeletingPathExtension
                                                       withExtension:filename.pathExtension];
        OWSAssertDebug(url);
        return url;
    } else {
        return [OWSSounds soundURLForCustomSound:sound];
    }
}

+ (SystemSoundID)systemSoundIDForSound:(OWSSound)sound quiet:(BOOL)quiet
{
    return [self.shared systemSoundIDForSound:(OWSSound)sound quiet:quiet];
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

+ (void)importSoundsAtURLs:(NSArray<NSURL *> *)urls
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSURL *url in urls) {
        NSError *error = NULL;
        NSString *filename = url.lastPathComponent;
        if (!filename)
            continue;

        NSString *destination = [NSString pathWithComponents:@[ [OWSSounds soundsDirectory], filename ]];

        if (![fileManager fileExistsAtPath:destination]) {
            [fileManager copyItemAtPath:[url path] toPath:destination error:&error];
        }

        if (error) {
            OWSFailDebug(@"Failed to import custom sound with error %@", [error localizedDescription]);
            error = NULL;
        }
    }
}

+ (BOOL)deleteCustomSound:(OWSSound)sound
{
    if (sound < OWSStandardSound_CustomThreshold) {
        OWSFailDebug(@"Can't delete built-in sound");
        return NO;
    } else {
        NSURL *url = [self soundURLForCustomSound:sound];
        NSError *error;
        [OWSFileSystem deleteFileIfExistsWithUrl:url error:&error];
        if (error) {
            OWSFailDebug(@"Failed to delete custom sound: %@", error);
        }
        return YES;
    }
}

#pragma mark - Notifications

+ (OWSSound)defaultNotificationSound
{
    return OWSStandardSound_Note;
}

+ (OWSSound)globalNotificationSound
{
    __block NSNumber *_Nullable value;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        value = [self.keyValueStore getNSNumber:kOWSSoundsStorageGlobalNotificationKey transaction:transaction];
    }];
    // Default to the global default.
    return (value ? (OWSSound)value.unsignedLongValue : [self defaultNotificationSound]);
}

+ (void)setGlobalNotificationSound:(OWSSound)sound
{
    [self.shared setGlobalNotificationSound:sound];
}

- (void)setGlobalNotificationSound:(OWSSound)sound
{
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self setGlobalNotificationSound:sound transaction:transaction];
    });
}

+ (void)setGlobalNotificationSound:(OWSSound)sound transaction:(SDSAnyWriteTransaction *)transaction
{
    [self.shared setGlobalNotificationSound:sound transaction:transaction];
}

- (void)setGlobalNotificationSound:(OWSSound)sound transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    OWSLogInfo(@"Setting global notification sound to: %@", [[self class] displayNameForSound:sound]);

    // Fallback push notifications play a sound specified by the server, but we don't want to store this configuration
    // on the server. Instead, we create a file with the same name as the default to be played when receiving
    // a fallback notification.
    NSString *dirPath = [OWSSounds soundsDirectory];

    NSString *defaultSoundPath = [dirPath stringByAppendingPathComponent:kDefaultNotificationSoundFilename];

    OWSLogDebug(@"writing new default sound to %@", defaultSoundPath);

    NSURL *_Nullable soundURL = [OWSSounds soundURLForSound:sound quiet:NO];

    NSData *soundData = ^{
        if (soundURL) {
            return [NSData dataWithContentsOfURL:soundURL];
        } else {
            OWSAssertDebug(sound == OWSStandardSound_None);
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

    [OWSSounds.keyValueStore setUInt:sound key:kOWSSoundsStorageGlobalNotificationKey transaction:transaction];
}

+ (OWSSound)notificationSoundForThread:(TSThread *)thread
{
    __block NSNumber *_Nullable value;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        value = [self.keyValueStore getNSNumber:thread.uniqueId transaction:transaction];
    }];
    // Default to the "global" notification sound, which in turn will default to the global default.
    return (value ? (OWSSound)value.unsignedLongValue : [self globalNotificationSound]);
}

+ (void)setNotificationSound:(OWSSound)sound forThread:(TSThread *)thread
{
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.keyValueStore setUInt:sound key:thread.uniqueId transaction:transaction];
    });
}

#pragma mark - Custom Sounds

+ (NSString *)displayNameForCustomSound:(OWSSound)sound
{
    NSString *filename = [OWSSounds filenameForCustomSound:sound];
    NSString *fileNameWithoutExtension = [[filename lastPathComponent] stringByDeletingPathExtension];
    if (!fileNameWithoutExtension) {
        OWSFailDebug(@"Unable to retrieve custom sound display name from: %lu", sound);
        return @"Custom Sound";
    }

    return [fileNameWithoutExtension capitalizedString];
}

+ (nullable NSString *)filenameForCustomSound:(OWSSound)sound
{
    NSError *error = NULL;
    NSArray *customSoundFilenames =
        [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[OWSSounds soundsDirectory] error:&error];
    if (error) {
        OWSFailDebug(@"Failed retrieving custom sound files: %@", error.userErrorDescription);
        return NULL;
    }

    NSUInteger index =
        [customSoundFilenames indexOfObjectPassingTest:^BOOL(id _Nonnull obj, NSUInteger idx, BOOL *_Nonnull stop) {
            return [OWSSounds customSoundForFilename:obj] == sound;
        }];
    return index == NSNotFound ? NULL : [customSoundFilenames objectAtIndex:index];
}

+ (NSArray<NSNumber *> *)allCustomNotificationSounds
{
    NSError *error = NULL;
    NSArray *customSoundFilenames =
        [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[OWSSounds soundsDirectory] error:&error];
    if (error) {
        OWSFailDebug(@"Failed retrieving custom sound files: %@", error.userErrorDescription);
        return @[];
    }

    NSMutableArray<NSNumber *> *sounds = [[NSMutableArray alloc] initWithCapacity:customSoundFilenames.count];
    for (NSString *filename in customSoundFilenames) {
        if ([filename isEqualToString:kDefaultNotificationSoundFilename]) {
            continue;
        }
        [sounds addObject:[NSNumber numberWithUnsignedLong:[OWSSounds customSoundForFilename:filename]]];
    }
    return sounds;
}

+ (nullable NSURL *)soundURLForCustomSound:(OWSSound)sound
{
    NSString *path =
        [[OWSSounds soundsDirectory] stringByAppendingPathComponent:[OWSSounds filenameForCustomSound:sound]];
    return [NSURL fileURLWithPath:path];
}

+ (OWSSound)customSoundForFilename:(NSString *)filename
{
    NSUInteger hashValue = 0;
    NSData *_Nullable filenameData = [filename dataUsingEncoding:NSUTF8StringEncoding];
    if (!filenameData) {
        OWSFailDebug(@"could not get data from filename.");
        return OWSStandardSound_Default;
    }
    NSData *_Nullable hashData = [Cryptography computeSHA256Digest:filenameData truncatedToBytes:sizeof(hashValue)];
    if (!hashData) {
        OWSFailDebug(@"could not get hash from filename.");
        return OWSStandardSound_Default;
    }
    [hashData getBytes:&hashValue length:sizeof(hashValue)];

    return hashValue << OWSCustomSoundShift;
}

+ (NSString *)soundsDirectory
{
    NSString *directory = [[OWSFileSystem appSharedDataDirectoryPath] stringByAppendingPathComponent:@"Library/Sounds"];
    [OWSFileSystem ensureDirectoryExists:directory];
    return directory;
}

@end
