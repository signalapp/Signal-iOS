//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "AppSetup.h"
#import "Environment.h"
#import "VersionMigrations.h"
#import <SignalUtilitiesKit/OWSDatabaseMigration.h>
#import <SessionMessagingKit/OWSBackgroundTask.h>
#import <SessionMessagingKit/OWSDisappearingMessagesJob.h>
#import <SessionMessagingKit/OWSOutgoingReceiptManager.h>
#import <SessionMessagingKit/OWSReadReceiptManager.h>
#import <SessionMessagingKit/OWSStorage.h>
#import <SessionMessagingKit/SSKEnvironment.h>
#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation AppSetup

+ (void)setupEnvironmentWithAppSpecificSingletonBlock:(dispatch_block_t)appSpecificSingletonBlock
                                  migrationCompletion:(OWSDatabaseMigrationCompletion)migrationCompletion
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

        TSAccountManager *tsAccountManager = [[TSAccountManager alloc] initWithPrimaryStorage:primaryStorage];
        OWSDisappearingMessagesJob *disappearingMessagesJob =
            [[OWSDisappearingMessagesJob alloc] initWithPrimaryStorage:primaryStorage];
        OWSReadReceiptManager *readReceiptManager =
            [[OWSReadReceiptManager alloc] initWithPrimaryStorage:primaryStorage];
        OWSOutgoingReceiptManager *outgoingReceiptManager =
            [[OWSOutgoingReceiptManager alloc] initWithPrimaryStorage:primaryStorage];
        id<SSKReachabilityManager> reachabilityManager = [SSKReachabilityManagerImpl new];
        id<OWSTypingIndicators> typingIndicators = [[OWSTypingIndicatorsImpl alloc] init];

        OWSAudioSession *audioSession = [OWSAudioSession new];
        id<OWSProximityMonitoringManager> proximityMonitoringManager = [OWSProximityMonitoringManagerImpl new];
        OWSWindowManager *windowManager = [[OWSWindowManager alloc] initDefault];
        
        [Environment setShared:[[Environment alloc] initWithAudioSession:audioSession
                                                             preferences:preferences
                                              proximityMonitoringManager:proximityMonitoringManager
                                                           windowManager:windowManager]];

        // TODO: Add this back
        // TODO: Refactor this file to Swift
        [SSKEnvironment setShared:[[SSKEnvironment alloc] initWithPrimaryStorage:primaryStorage
                                                                tsAccountManager:tsAccountManager
                                                             reachabilityManager:reachabilityManager
                                                                typingIndicators:typingIndicators]];
//        [SSKEnvironment setShared:[[SSKEnvironment alloc] initWithPrimaryStorage:primaryStorage
//                                                                tsAccountManager:tsAccountManager
//                                                         disappearingMessagesJob:disappearingMessagesJob
//                                                              readReceiptManager:readReceiptManager
//                                                          outgoingReceiptManager:outgoingReceiptManager
//                                                             reachabilityManager:reachabilityManager
//                                                                typingIndicators:typingIndicators]];

        appSpecificSingletonBlock();

        // TODO: Add this back?
//        OWSAssertDebug(SSKEnvironment.shared.isComplete);
        
        [SNConfiguration performMainSetup]; // Must happen before the performUpdateCheck call below

        // Register renamed classes.
        [NSKeyedUnarchiver setClass:[OWSUserProfile class] forClassName:[OWSUserProfile collection]];
        [NSKeyedUnarchiver setClass:[OWSDatabaseMigration class] forClassName:[OWSDatabaseMigration collection]];

        [OWSStorage registerExtensionsWithMigrationBlock:^() {
            dispatch_async(dispatch_get_main_queue(), ^{
                // Don't start database migrations until storage is ready.
                [VersionMigrations performUpdateCheckWithCompletion:^(BOOL successful, BOOL needsConfigSync) {
                    OWSAssertIsOnMainThread();

                    migrationCompletion(successful, needsConfigSync);

                    OWSAssertDebug(backgroundTask);
                    backgroundTask = nil;
                }];
            });
        }];
        
        // Must happen after the performUpdateCheck above to ensure all legacy database migrations have run
        [SNConfiguration performDatabaseSetup];
    });
}

@end

NS_ASSUME_NONNULL_END
