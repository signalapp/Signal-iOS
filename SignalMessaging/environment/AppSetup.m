//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "AppSetup.h"
#import "Environment.h"
#import "VersionMigrations.h"
#import <SessionAxolotlKit/SessionCipher.h>
#import <SignalMessaging/OWSDatabaseMigration.h>
#import <SignalMessaging/OWSProfileManager.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SessionServiceKit/ContactDiscoveryService.h>
#import <SessionServiceKit/OWS2FAManager.h>
#import <SessionServiceKit/OWSAttachmentDownloads.h>
#import <SessionServiceKit/OWSBackgroundTask.h>
#import <SessionServiceKit/OWSBatchMessageProcessor.h>
#import <SessionServiceKit/OWSBlockingManager.h>
#import <SessionServiceKit/OWSDisappearingMessagesJob.h>
#import <SessionServiceKit/OWSIdentityManager.h>
#import <SessionServiceKit/OWSMessageDecrypter.h>
#import <SessionServiceKit/OWSMessageManager.h>
#import <SessionServiceKit/OWSMessageReceiver.h>
#import <SessionServiceKit/OWSOutgoingReceiptManager.h>
#import <SessionServiceKit/OWSReadReceiptManager.h>
#import <SessionServiceKit/OWSStorage.h>
#import <SessionServiceKit/SSKEnvironment.h>
#import <SessionServiceKit/SessionServiceKit-Swift.h>
#import <SessionServiceKit/TSSocketManager.h>

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
        SSKMessageSenderJobQueue *messageSenderJobQueue = [SSKMessageSenderJobQueue new];
        OWSProfileManager *profileManager = [[OWSProfileManager alloc] initWithPrimaryStorage:primaryStorage];
        OWSMessageManager *messageManager = [[OWSMessageManager alloc] initWithPrimaryStorage:primaryStorage];
        OWSBlockingManager *blockingManager = [[OWSBlockingManager alloc] initWithPrimaryStorage:primaryStorage];
        OWSIdentityManager *identityManager = [[OWSIdentityManager alloc] initWithPrimaryStorage:primaryStorage];
        id<OWSUDManager> udManager = [[OWSUDManagerImpl alloc] initWithPrimaryStorage:primaryStorage];
        OWSMessageDecrypter *messageDecrypter = [[OWSMessageDecrypter alloc] initWithPrimaryStorage:primaryStorage];
        OWSBatchMessageProcessor *batchMessageProcessor =
            [[OWSBatchMessageProcessor alloc] initWithPrimaryStorage:primaryStorage];
        OWSMessageReceiver *messageReceiver = [[OWSMessageReceiver alloc] initWithPrimaryStorage:primaryStorage];
        TSSocketManager *socketManager = [[TSSocketManager alloc] init];
        TSAccountManager *tsAccountManager = [[TSAccountManager alloc] initWithPrimaryStorage:primaryStorage];
        OWS2FAManager *ows2FAManager = [[OWS2FAManager alloc] initWithPrimaryStorage:primaryStorage];
        OWSDisappearingMessagesJob *disappearingMessagesJob =
            [[OWSDisappearingMessagesJob alloc] initWithPrimaryStorage:primaryStorage];
        ContactDiscoveryService *contactDiscoveryService = [[ContactDiscoveryService alloc] initDefault];
        OWSReadReceiptManager *readReceiptManager =
            [[OWSReadReceiptManager alloc] initWithPrimaryStorage:primaryStorage];
        OWSOutgoingReceiptManager *outgoingReceiptManager =
            [[OWSOutgoingReceiptManager alloc] initWithPrimaryStorage:primaryStorage];
        OWSSyncManager *syncManager = [[OWSSyncManager alloc] initDefault];
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

        [SSKEnvironment setShared:[[SSKEnvironment alloc] initWithContactsManager:contactsManager
                                                                    messageSender:messageSender
                                                            messageSenderJobQueue:messageSenderJobQueue
                                                                   profileManager:profileManager
                                                                   primaryStorage:primaryStorage
                                                                  contactsUpdater:contactsUpdater
                                                                   networkManager:networkManager
                                                                   messageManager:messageManager
                                                                  blockingManager:blockingManager
                                                                  identityManager:identityManager
                                                                        udManager:udManager
                                                                 messageDecrypter:messageDecrypter
                                                            batchMessageProcessor:batchMessageProcessor
                                                                  messageReceiver:messageReceiver
                                                                    socketManager:socketManager
                                                                 tsAccountManager:tsAccountManager
                                                                    ows2FAManager:ows2FAManager
                                                          disappearingMessagesJob:disappearingMessagesJob
                                                          contactDiscoveryService:contactDiscoveryService
                                                               readReceiptManager:readReceiptManager
                                                           outgoingReceiptManager:outgoingReceiptManager
                                                              reachabilityManager:reachabilityManager
                                                                      syncManager:syncManager
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
