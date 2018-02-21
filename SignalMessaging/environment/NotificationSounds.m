//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "NotificationSounds.h"
#import <AudioToolbox/AudioServices.h>

@interface NotificationSounds ()

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
    self = [super init];

    if (!self) {
        return self;
    }

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

@end
