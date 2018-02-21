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

- (NSURL *)soundURLForNotificationSound:(NotificationSound)notificationSound
{
    NSURL *_Nullable url;
    switch (notificationSound) {
        case NotificationSound_Aurora:
            url = [[NSBundle mainBundle] URLForResource:@"aurora" withExtension:@"m4r"];
            break;
        case NotificationSound_Bamboo:
            url = [[NSBundle mainBundle] URLForResource:@"bamboo" withExtension:@"m4r"];
            break;
        case NotificationSound_Chord:
            url = [[NSBundle mainBundle] URLForResource:@"chord" withExtension:@"m4r"];
            break;
        case NotificationSound_Circles:
            url = [[NSBundle mainBundle] URLForResource:@"circles" withExtension:@"m4r"];
            break;
        case NotificationSound_Complete:
            url = [[NSBundle mainBundle] URLForResource:@"complete" withExtension:@"m4r"];
            break;
        case NotificationSound_Hello:
            url = [[NSBundle mainBundle] URLForResource:@"hello" withExtension:@"m4r"];
            break;
        case NotificationSound_Input:
            url = [[NSBundle mainBundle] URLForResource:@"input" withExtension:@"m4r"];
            break;
        case NotificationSound_Keys:
            url = [[NSBundle mainBundle] URLForResource:@"keys" withExtension:@"m4r"];
            break;
        case NotificationSound_Note:
            url = [[NSBundle mainBundle] URLForResource:@"note" withExtension:@"m4r"];
            break;
        case NotificationSound_Popcorn:
            url = [[NSBundle mainBundle] URLForResource:@"popcorn" withExtension:@"m4r"];
            break;
        case NotificationSound_Pulse:
            url = [[NSBundle mainBundle] URLForResource:@"pulse" withExtension:@"m4r"];
            break;
        case NotificationSound_Synth:
            url = [[NSBundle mainBundle] URLForResource:@"synth" withExtension:@"m4r"];
            break;
    }
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
            NSURL *soundURL = [self soundURLForNotificationSound:notificationSound];
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
