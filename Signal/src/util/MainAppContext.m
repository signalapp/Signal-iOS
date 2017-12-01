//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "MainAppContext.h"
#import "OWS100RemoveTSRecipientsMigration.h"
#import "OWS102MoveLoggingPreferenceToUserDefaults.h"
#import "OWS103EnableVideoCalling.h"
#import "OWS104CreateRecipientIdentities.h"
#import "OWS105AttachmentFilePaths.h"

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
    return @[
        [[OWS100RemoveTSRecipientsMigration alloc] initWithStorageManager:self.storageManager],
        [[OWS102MoveLoggingPreferenceToUserDefaults alloc] initWithStorageManager:self.storageManager],
        [[OWS103EnableVideoCalling alloc] initWithStorageManager:self.storageManager],
        // OWS104CreateRecipientIdentities is run separately. See runSafeBlockingMigrations.
        [[OWS105AttachmentFilePaths alloc] initWithStorageManager:self.storageManager],
        [[OWS106EnsureProfileComplete alloc] initWithStorageManager:self.storageManager]
    ];
}

- (UIViewController *)frontmostViewController
{
    return UIApplication.sharedApplication.frontmostViewController;
}

@end

NS_ASSUME_NONNULL_END
