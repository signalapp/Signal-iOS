//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "NotificationSounds.h"
#import <AudioToolbox/AudioServices.h>
#import <SignalServiceKit/TSStorageManager.h>
#import <SignalServiceKit/TSThread.h>
#import <SignalServiceKit/YapDatabaseConnection+OWS.h>

NSString *const kNotificationSoundsStorageNotificationCollection = @"kNotificationSoundsStorageNotificationCollection";
NSString *const kNotificationSoundsStorageGlobalNotificationKey = @"kNotificationSoundsStorageGlobalNotificationKey";

@interface NotificationSounds ()

@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

@property (nonatomic) NSMutableDictionary<NSNumber *, NSNumber *> *systemSoundIDMap;

@end

#pragma mark -

@implementation NotificationSounds

+ (instancetype)sharedManager
{
    static NotificationSounds *instance = nil;
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
        @(NotificationSound_Aurora),
        @(NotificationSound_Bamboo),
        @(NotificationSound_Chord),
        @(NotificationSound_Circles),
        @(NotificationSound_Complete),
        @(NotificationSound_Hello),
        @(NotificationSound_Input),
        @(NotificationSound_Keys),
        @(NotificationSound_Note),
        @(NotificationSound_Popcorn),
        @(NotificationSound_Pulse),
        @(NotificationSound_Synth),
    ];
}

+ (NSString *)displayNameForNotificationSound:(NotificationSound)notificationSound
{
    // TODO: Should we localize these sound names?
    switch (notificationSound) {
        case NotificationSound_Aurora:
            return @"Aurora";
        case NotificationSound_Bamboo:
            return @"Bamboo";
        case NotificationSound_Chord:
            return @"Chord";
        case NotificationSound_Circles:
            return @"Circles";
        case NotificationSound_Complete:
            return @"Complete";
        case NotificationSound_Hello:
            return @"Hello";
        case NotificationSound_Input:
            return @"Input";
        case NotificationSound_Keys:
            return @"Keys";
        case NotificationSound_Default:
        case NotificationSound_Note:
            return @"Note";
        case NotificationSound_Popcorn:
            return @"Popcorn";
        case NotificationSound_Pulse:
            return @"Pulse";
        case NotificationSound_Synth:
            return @"Synth";
    }
}

+ (NSString *)filenameForNotificationSound:(NotificationSound)notificationSound
{
    // TODO: Should we localize these sound names?
    switch (notificationSound) {
        case NotificationSound_Aurora:
            return @"aurora.m4r";
        case NotificationSound_Bamboo:
            return @"bamboo.m4r";
        case NotificationSound_Chord:
            return @"chord.m4r";
        case NotificationSound_Circles:
            return @"circles.m4r";
        case NotificationSound_Complete:
            return @"complete.m4r";
        case NotificationSound_Hello:
            return @"hello.m4r";
        case NotificationSound_Input:
            return @"input.m4r";
        case NotificationSound_Keys:
            return @"keys.m4r";
        case NotificationSound_Default:
        case NotificationSound_Note:
            return @"note.m4r";
        case NotificationSound_Popcorn:
            return @"popcorn.m4r";
        case NotificationSound_Pulse:
            return @"pulse.m4r";
        case NotificationSound_Synth:
            return @"synth.m4r";
    }
}

+ (NSURL *)soundURLForNotificationSound:(NotificationSound)notificationSound
{
    NSString *filename = [self filenameForNotificationSound:notificationSound];

    NSURL *_Nullable url = [[NSBundle mainBundle] URLForResource:filename.stringByDeletingPathExtension
                                                   withExtension:filename.pathExtension];
    OWSAssert(url);
    return url;
}

+ (void)playNotificationSound:(NotificationSound)notificationSound
{
    [self.sharedManager playNotificationSound:notificationSound];
}

- (SystemSoundID)systemSoundIDForNotificationSound:(NotificationSound)notificationSound
{
    @synchronized(self)
    {
        if (!self.systemSoundIDMap) {
            self.systemSoundIDMap = [NSMutableDictionary new];
        }
        NSNumber *_Nullable systemSoundID = self.systemSoundIDMap[@(notificationSound)];
        if (!systemSoundID) {
            NSURL *soundURL = [NotificationSounds soundURLForNotificationSound:notificationSound];
            SystemSoundID newSystemSoundID;
            OSStatus error = AudioServicesCreateSystemSoundID((__bridge CFURLRef)soundURL, &newSystemSoundID);
            if (error) {
                OWSFail(@"%@ could not load sound.", self.logTag);
            }
            systemSoundID = @(newSystemSoundID);
            self.systemSoundIDMap[@(notificationSound)] = systemSoundID;
        }
        return (SystemSoundID)systemSoundID.unsignedIntegerValue;
    }
}

- (void)playNotificationSound:(NotificationSound)notificationSound
{
    SystemSoundID systemSoundID = [self systemSoundIDForNotificationSound:notificationSound];
    AudioServicesPlayAlertSound(systemSoundID);
}

+ (NotificationSound)defaultNotificationSound
{
    return NotificationSound_Note;
}

+ (NotificationSound)globalNotificationSound
{
    NotificationSounds *notificationSounds = NotificationSounds.sharedManager;
    NSNumber *_Nullable value =
        [notificationSounds.dbConnection objectForKey:kNotificationSoundsStorageGlobalNotificationKey
                                         inCollection:kNotificationSoundsStorageNotificationCollection];
    // Default to the global default.
    return (value ? (NotificationSound)value.intValue : [self defaultNotificationSound]);
}

+ (void)setGlobalNotificationSound:(NotificationSound)notificationSound
{
    NotificationSounds *notificationSounds = NotificationSounds.sharedManager;
    [notificationSounds.dbConnection setObject:@(notificationSound)
                                        forKey:kNotificationSoundsStorageGlobalNotificationKey
                                  inCollection:kNotificationSoundsStorageNotificationCollection];
}

+ (NotificationSound)notificationSoundForThread:(TSThread *)thread
{
    NotificationSounds *notificationSounds = NotificationSounds.sharedManager;
    NSNumber *_Nullable value =
        [notificationSounds.dbConnection objectForKey:thread.uniqueId
                                         inCollection:kNotificationSoundsStorageNotificationCollection];
    // Default to the "global" notification sound, which in turn will default to the global default.
    return (value ? (NotificationSound)value.intValue : [self globalNotificationSound]);
}

+ (void)setNotificationSound:(NotificationSound)notificationSound forThread:(TSThread *)thread
{
    NotificationSounds *notificationSounds = NotificationSounds.sharedManager;
    [notificationSounds.dbConnection setObject:@(notificationSound)
                                        forKey:thread.uniqueId
                                  inCollection:kNotificationSoundsStorageNotificationCollection];
}

@end
