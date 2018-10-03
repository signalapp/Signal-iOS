//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "AppSetup.h"
#import "Environment.h"
#import "VersionMigrations.h"
#import <AxolotlKit/SessionCipher.h>
#import <SignalMessaging/OWSDatabaseMigration.h>
#import <SignalMessaging/OWSProfileManager.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/OWSBackgroundTask.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/OWSIdentityManager.h>
#import <SignalServiceKit/OWSMessageManager.h>
#import <SignalServiceKit/OWSStorage.h>
#import <SignalServiceKit/SSKEnvironment.h>

NS_ASSUME_NONNULL_BEGIN

@implementation AppSetup

+ (void)setupEnvironmentWithAppSpecificSingletonBlock:(dispatch_block_t)appSpecificSingletonBlock
                                  migrationCompletion:(dispatch_block_t)migrationCompletion
{
    OWSAssertDebug(appSpecificSingletonBlock);
    OWSAssertDebug(migrationCompletion);

    __block OWSBackgroundTask *_Nullable backgroundTask =
        [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Order matters here.
        //
        // All of these "singletons" should have any dependencies used in their
        // initializers injected.
        [[OWSBackgroundTaskManager sharedManager] observeNotifications];

        OWSPrimaryStorage *primaryStorage = [[OWSPrimaryStorage alloc] initStorage];
        [OWSPrimaryStorage protectFiles];

        // AFNetworking (via CFNetworking) spools it's attachments to NSTemporaryDirectory().
        // If you receive a media message while the device is locked, the download will fail if the temporary directory
        // is NSFileProtectionComplete
        BOOL success = [OWSFileSystem protectFileOrFolderAtPath:NSTemporaryDirectory()
                                             fileProtectionType:NSFileProtectionCompleteUntilFirstUserAuthentication];
        OWSAssert(success);

        OWSPreferences *preferences = [OWSPreferences new];

        TSNetworkManager *networkManager = [[TSNetworkManager alloc] initDefault];
        OWSContactsManager *contactsManager = [[OWSContactsManager alloc] initWithPrimaryStorage:primaryStorage];
        ContactsUpdater *contactsUpdater = [ContactsUpdater new];
        OWSMessageSender *messageSender = [[OWSMessageSender alloc] initWithPrimaryStorage:primaryStorage];

        OWSProfileManager *profileManager = [[OWSProfileManager alloc] initWithPrimaryStorage:primaryStorage
                                                                                messageSender:messageSender
                                                                               networkManager:networkManager];

        OWSMessageManager *messageManager = [[OWSMessageManager alloc] initWithPrimaryStorage:primaryStorage];
        OWSBlockingManager *blockingManager = [[OWSBlockingManager alloc] initWithPrimaryStorage:primaryStorage];
        OWSIdentityManager *identityManager = [[OWSIdentityManager alloc] initWithPrimaryStorage:primaryStorage];

        [Environment setShared:[[Environment alloc] initWithPreferences:preferences]];

        [SSKEnvironment setShared:[[SSKEnvironment alloc] initWithContactsManager:contactsManager
                                                                    messageSender:messageSender
                                                                   profileManager:profileManager
                                                                   primaryStorage:primaryStorage
                                                                  contactsUpdater:contactsUpdater
                                                                   networkManager:networkManager
                                                                   messageManager:messageManager
                                                                  blockingManager:blockingManager
                                                                  identityManager:identityManager]];

        appSpecificSingletonBlock();

        OWSAssertDebug(SSKEnvironment.shared.isComplete);

        // Register renamed classes.
        [NSKeyedUnarchiver setClass:[OWSUserProfile class] forClassName:[OWSUserProfile collection]];
        [NSKeyedUnarchiver setClass:[OWSDatabaseMigration class] forClassName:[OWSDatabaseMigration collection]];

        [OWSStorage registerExtensionsWithMigrationBlock:^() {
            dispatch_async(dispatch_get_main_queue(), ^{
                // Don't start database migrations until storage is ready.
                [VersionMigrations performUpdateCheckWithCompletion:^() {
                    OWSAssertIsOnMainThread();

                    migrationCompletion();

                    OWSAssertDebug(backgroundTask);
                    backgroundTask = nil;
                }];
            });
        }];
    });
}

@end

NS_ASSUME_NONNULL_END
