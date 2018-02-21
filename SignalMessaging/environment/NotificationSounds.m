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
    ];
}

+ (NSString *)displayNameForNotificationSound:(NotificationSound)notificationSound
{
    // TODO: Should we localize these sound names?
    switch (notificationSound) {
        case NotificationSound_Aurora:
            return @"Aurora";
    }
}

- (NSURL *)soundURLForNotificationSound:(NotificationSound)notificationSound
{
    NSString *bundlePath = [NSBundle mainBundle].bundlePath;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSString *filename in [fileManager contentsOfDirectoryAtPath:bundlePath error:nil]) {
        DDLogInfo(@"%@ filename: %@", self.logTag, filename);
    }
    [DDLog flushLog];

    NSURL *_Nullable url;
    switch (notificationSound) {
        case NotificationSound_Aurora:
            url = [[NSBundle mainBundle] URLForResource:@"aurora" withExtension:@"m4r"];
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
