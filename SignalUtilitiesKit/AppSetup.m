//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "AppSetup.h"
#import "Environment.h"
#import "VersionMigrations.h"
#import <SignalUtilitiesKit/OWSDatabaseMigration.h>
#import <SignalUtilitiesKit/OWSProfileManager.h>
#import <SessionProtocolKit/SessionProtocolKit-Swift.h>


#import <SignalUtilitiesKit/OWSAttachmentDownloads.h>
#import <SignalUtilitiesKit/OWSBackgroundTask.h>
#import <SignalUtilitiesKit/OWSBlockingManager.h>
#import <SignalUtilitiesKit/OWSDisappearingMessagesJob.h>
#import <SignalUtilitiesKit/OWSIdentityManager.h>
#import <SignalUtilitiesKit/OWSOutgoingReceiptManager.h>
#import <SignalUtilitiesKit/OWSReadReceiptManager.h>
#import <SignalUtilitiesKit/OWSSounds.h>
#import <SignalUtilitiesKit/OWSStorage.h>
#import <SignalUtilitiesKit/SSKEnvironment.h>
#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>


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

        OWSProfileManager *profileManager = [[OWSProfileManager alloc] initWithPrimaryStorage:primaryStorage];
        OWSBlockingManager *blockingManager = [[OWSBlockingManager alloc] initWithPrimaryStorage:primaryStorage];
        OWSIdentityManager *identityManager = [[OWSIdentityManager alloc] initWithPrimaryStorage:primaryStorage];
        id<OWSUDManager> udManager = [[OWSUDManagerImpl alloc] initWithPrimaryStorage:primaryStorage];
        TSAccountManager *tsAccountManager = [[TSAccountManager alloc] initWithPrimaryStorage:primaryStorage];
        OWSDisappearingMessagesJob *disappearingMessagesJob =
            [[OWSDisappearingMessagesJob alloc] initWithPrimaryStorage:primaryStorage];
        OWSReadReceiptManager *readReceiptManager =
            [[OWSReadReceiptManager alloc] initWithPrimaryStorage:primaryStorage];
        OWSOutgoingReceiptManager *outgoingReceiptManager =
            [[OWSOutgoingReceiptManager alloc] initWithPrimaryStorage:primaryStorage];
        id<SSKReachabilityManager> reachabilityManager = [SSKReachabilityManagerImpl new];
        id<OWSTypingIndicators> typingIndicators = [[OWSTypingIndicatorsImpl alloc] init];
        OWSAttachmentDownloads *attachmentDownloads = [[OWSAttachmentDownloads alloc] init];

        OWSAudioSession *audioSession = [OWSAudioSession new];
        OWSSounds *sounds = [[OWSSounds alloc] initWithPrimaryStorage:primaryStorage];
        id<OWSProximityMonitoringManager> proximityMonitoringManager = [OWSProximityMonitoringManagerImpl new];
        OWSWindowManager *windowManager = [[OWSWindowManager alloc] initDefault];
        
        [Environment setShared:[[Environment alloc] initWithAudioSession:audioSession
                                                             preferences:preferences
                                              proximityMonitoringManager:proximityMonitoringManager
                                                                  sounds:sounds
                                                           windowManager:windowManager]];

        [SSKEnvironment setShared:[[SSKEnvironment alloc] initWithProfileManager:profileManager
                                                                  primaryStorage:primaryStorage
                                                                 blockingManager:blockingManager
                                                                 identityManager:identityManager
                                                                       udManager:udManager
                                                                tsAccountManager:tsAccountManager
                                                         disappearingMessagesJob:disappearingMessagesJob
                                                              readReceiptManager:readReceiptManager
                                                          outgoingReceiptManager:outgoingReceiptManager
                                                             reachabilityManager:reachabilityManager
                                                                typingIndicators:typingIndicators
                                                             attachmentDownloads:attachmentDownloads]];

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
