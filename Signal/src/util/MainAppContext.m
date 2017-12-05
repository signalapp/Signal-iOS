//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "MainAppContext.h"
#import "OWS100RemoveTSRecipientsMigration.h"
#import "OWS102MoveLoggingPreferenceToUserDefaults.h"
#import "OWS103EnableVideoCalling.h"
#import "OWS105AttachmentFilePaths.h"
#import "Signal-Swift.h"
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSProfileManager.h>
#import <SignalServiceKit/OWSIdentityManager.h>

NS_ASSUME_NONNULL_BEGIN

@implementation MainAppContext

- (BOOL)isMainApp
{
    return YES;
}

- (BOOL)isMainAppAndActive
{
    return [UIApplication sharedApplication].applicationState == UIApplicationStateActive;
}

- (BOOL)isRTL
{
    return
        [[UIApplication sharedApplication] userInterfaceLayoutDirection] == UIUserInterfaceLayoutDirectionRightToLeft;
}

- (UIApplicationState)mainApplicationState
{
    return [UIApplication sharedApplication].applicationState;
}

- (UIBackgroundTaskIdentifier)beginBackgroundTaskWithExpirationHandler:
    (BackgroundTaskExpirationHandler)expirationHandler
{
    return [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:expirationHandler];
}

- (void)endBackgroundTask:(UIBackgroundTaskIdentifier)backgroundTaskIdentifier
{
    [UIApplication.sharedApplication endBackgroundTask:backgroundTaskIdentifier];
}

- (void)setMainAppBadgeNumber:(NSInteger)value
{
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:value];
}

- (NSArray<OWSDatabaseMigration *> *)allMigrations
{
    TSStorageManager *storageManager = TSStorageManager.sharedManager;
    return @[
        [[OWS100RemoveTSRecipientsMigration alloc] initWithStorageManager:storageManager],
        [[OWS102MoveLoggingPreferenceToUserDefaults alloc] initWithStorageManager:storageManager],
        [[OWS103EnableVideoCalling alloc] initWithStorageManager:storageManager],
        // OWS104CreateRecipientIdentities is run separately. See runSafeBlockingMigrations.
        [[OWS105AttachmentFilePaths alloc] initWithStorageManager:storageManager],
        [[OWS106EnsureProfileComplete alloc] initWithStorageManager:storageManager]
    ];
}

- (nullable UIViewController *)frontmostViewController
{
    return UIApplication.sharedApplication.frontmostViewControllerIgnoringAlerts;
}

- (void)openSystemSettings
{
    [UIApplication.sharedApplication openSystemSettings];
}

- (void)doMultiDeviceUpdateWithProfileKey:(OWSAES256Key *)profileKey
{
    OWSAssert(profileKey);

    [MultiDeviceProfileKeyUpdateJob runWithProfileKey:profileKey
                                      identityManager:OWSIdentityManager.sharedManager
                                        messageSender:Environment.current.messageSender
                                       profileManager:OWSProfileManager.sharedManager];
}

@end

NS_ASSUME_NONNULL_END
