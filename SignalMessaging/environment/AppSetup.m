//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "AppSetup.h"
#import "Environment.h"
#import "OWSProfileManager.h"
#import "VersionMigrations.h"
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/OWS2FAManager.h>
#import <SignalServiceKit/OWSBackgroundTask.h>
#import <SignalServiceKit/OWSDisappearingMessagesJob.h>
#import <SignalServiceKit/OWSIdentityManager.h>
#import <SignalServiceKit/OWSMessageManager.h>
#import <SignalServiceKit/OWSOutgoingReceiptManager.h>
#import <SignalServiceKit/OWSReceiptManager.h>
#import <SignalServiceKit/SSKEnvironment.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation AppSetup

+ (void)setupEnvironmentWithPaymentsEvents:(id<PaymentsEvents>)paymentsEvents
                          mobileCoinHelper:(id<MobileCoinHelper>)mobileCoinHelper
                          webSocketFactory:(id)webSocketFactory
                 appSpecificSingletonBlock:(NS_NOESCAPE dispatch_block_t)appSpecificSingletonBlock
                       migrationCompletion:(void (^)(NSError *_Nullable error))migrationCompletion
{
    OWSAssertDebug(appSpecificSingletonBlock);
    OWSAssertDebug(migrationCompletion);

    [self suppressUnsatisfiableConstraintLogging];

    __block OWSBackgroundTask *_Nullable backgroundTask =
        [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Order matters here.
        //
        // All of these "singletons" should have any dependencies used in their
        // initializers injected.
        [[OWSBackgroundTaskManager shared] observeNotifications];

        StorageCoordinator *storageCoordinator = [StorageCoordinator new];
        SDSDatabaseStorage *databaseStorage = storageCoordinator.databaseStorage;

        // AFNetworking (via CFNetworking) spools it's attachments to NSTemporaryDirectory().
        // If you receive a media message while the device is locked, the download will fail if the temporary directory
        // is NSFileProtectionComplete
        BOOL success;
        NSString *temporaryDirectory = NSTemporaryDirectory();
        success = [OWSFileSystem ensureDirectoryExists:temporaryDirectory];
        OWSAssert(success);
        success = [OWSFileSystem protectFileOrFolderAtPath:temporaryDirectory
                                        fileProtectionType:NSFileProtectionCompleteUntilFirstUserAuthentication];
        OWSAssert(success);

        // MARK: DependenciesBridge

        AccountServiceClient *accountServiceClient = [AccountServiceClient new];
        OWSIdentityManager *identityManager = [[OWSIdentityManager alloc] initWithDatabaseStorage:databaseStorage];
        MessageProcessor *messageProcessor = [MessageProcessor new];
        MessageSender *messageSender = [MessageSender new];
        NetworkManager *networkManager = [NetworkManager new];
        OWS2FAManager *ows2FAManager = [OWS2FAManager new];
        SignalProtocolStore *pniSignalProtocolStore = [[SignalProtocolStore alloc] initForIdentity:OWSIdentityPNI];
        id<OWSSignalServiceProtocol> signalService = [OWSSignalService new];
        OWSStorageServiceManager *storageServiceManager = OWSStorageServiceManager.shared;
        id<SyncManagerProtocol> syncManager = (id<SyncManagerProtocol>)[[OWSSyncManager alloc] initDefault];
        TSAccountManager *tsAccountManager = [TSAccountManager new];

        [DependenciesBridgeSetup setupSingletonWithAccountServiceClient:accountServiceClient
                                                        databaseStorage:databaseStorage
                                                        identityManager:identityManager
                                                       messageProcessor:messageProcessor
                                                          messageSender:messageSender
                                                         networkManager:networkManager
                                                          ows2FAManager:ows2FAManager
                                                       pniProtocolStore:pniSignalProtocolStore
                                                          signalService:signalService
                                                  storageServiceManager:storageServiceManager
                                                            syncManager:syncManager
                                                       tsAccountManager:tsAccountManager];

        // MARK: SignalMessaging environment properties

        LaunchJobs *launchJobs = [LaunchJobs new];
        OWSPreferences *preferences = [OWSPreferences new];
        id<OWSProximityMonitoringManager> proximityMonitoringManager = [OWSProximityMonitoringManagerImpl new];
        OWSSounds *sounds = [OWSSounds new];
        OWSOrphanDataCleaner *orphanDataCleaner = [OWSOrphanDataCleaner new];
        AvatarBuilder *avatarBuilder = [AvatarBuilder new];
        SignalMessagingJobQueues *smJobQueues = [SignalMessagingJobQueues new];

        // MARK: SSK environment properties

        OWSContactsManager *contactsManager = [[OWSContactsManager alloc]
            initWithSwiftValues:[OWSContactsManagerSwiftValues makeWithValuesFromDependenciesBridge]];
        OWSLinkPreviewManager *linkPreviewManager = [OWSLinkPreviewManager new];
        id<PendingReceiptRecorder> pendingReceiptRecorder = [MessageRequestPendingReceipts new];
        OWSProfileManager *profileManager = [[OWSProfileManager alloc] initWithDatabaseStorage:databaseStorage];
        OWSMessageManager *messageManager = [OWSMessageManager new];
        BlockingManager *blockingManager = [BlockingManager new];
        id<RemoteConfigManager> remoteConfigManager = [ServiceRemoteConfigManager new];
        SignalProtocolStore *aciSignalProtocolStore = [[SignalProtocolStore alloc] initForIdentity:OWSIdentityACI];
        id<OWSUDManager> udManager = [OWSUDManagerImpl new];
        OWSMessageDecrypter *messageDecrypter = [OWSMessageDecrypter new];
        GroupsV2MessageProcessor *groupsV2MessageProcessor = [GroupsV2MessageProcessor new];
        SocketManager *socketManager = [[SocketManager alloc] init];
        OWSDisappearingMessagesJob *disappearingMessagesJob = [OWSDisappearingMessagesJob new];
        OWSReceiptManager *receiptManager = [OWSReceiptManager new];
        OWSOutgoingReceiptManager *outgoingReceiptManager = [OWSOutgoingReceiptManager new];
        id<SSKReachabilityManager> reachabilityManager = [SSKReachabilityManagerImpl new];
        id<OWSTypingIndicators> typingIndicators = [[OWSTypingIndicatorsImpl alloc] init];
        OWSAttachmentDownloads *attachmentDownloads = [[OWSAttachmentDownloads alloc] init];
        StickerManager *stickerManager = [[StickerManager alloc] init];
        SignalServiceAddressCache *signalServiceAddressCache = [SignalServiceAddressCache new];
        SSKPreferences *sskPreferences = [SSKPreferences new];
        id<GroupsV2> groupsV2 = [GroupsV2Impl new];
        id<GroupV2Updates> groupV2Updates = [[GroupV2UpdatesImpl alloc] init];
        MessageFetcherJob *messageFetcherJob = [MessageFetcherJob new];
        BulkProfileFetch *bulkProfileFetch = [BulkProfileFetch new];
        id<VersionedProfiles> versionedProfiles = [VersionedProfilesImpl new];
        ModelReadCaches *modelReadCaches =
            [[ModelReadCaches alloc] initWithModelReadCacheFactory:[ModelReadCacheFactory new]];
        EarlyMessageManager *earlyMessageManager = [EarlyMessageManager new];
        OWSMessagePipelineSupervisor *messagePipelineSupervisor =
            [OWSMessagePipelineSupervisor createStandardSupervisor];
        AppExpiry *appExpiry = [AppExpiry new];
        id<PaymentsHelper> paymentsHelper = [PaymentsHelperImpl new];
        id<PaymentsCurrencies> paymentsCurrencies = [PaymentsCurrenciesImpl new];
        SpamChallengeResolver *spamChallengeResolver = [SpamChallengeResolver new];
        SenderKeyStore *senderKeyStore = [[SenderKeyStore alloc] init];
        PhoneNumberUtil *phoneNumberUtil = [PhoneNumberUtil new];
        ChangePhoneNumber *changePhoneNumber = [ChangePhoneNumber new];
        SubscriptionManagerImpl *subscriptionManager = [SubscriptionManagerImpl new];
        SystemStoryManager *systemStoryManager = [SystemStoryManager new];
        RemoteMegaphoneFetcher *remoteMegaphoneFetcher = [RemoteMegaphoneFetcher new];
        SSKJobQueues *sskJobQueues = [SSKJobQueues new];
        id contactDiscoveryManager = [ContactDiscoveryManagerImpl new];

        [Environment setShared:[[Environment alloc] initWithLaunchJobs:launchJobs
                                                           preferences:preferences
                                            proximityMonitoringManager:proximityMonitoringManager
                                                                sounds:sounds
                                                     orphanDataCleaner:orphanDataCleaner
                                                         avatarBuilder:avatarBuilder
                                                           smJobQueues:smJobQueues]];

        [SSKEnvironment setShared:[[SSKEnvironment alloc] initWithContactsManager:contactsManager
                                                               linkPreviewManager:linkPreviewManager
                                                                    messageSender:messageSender
                                                           pendingReceiptRecorder:pendingReceiptRecorder
                                                                   profileManager:profileManager
                                                                   networkManager:networkManager
                                                                   messageManager:messageManager
                                                                  blockingManager:blockingManager
                                                                  identityManager:identityManager
                                                              remoteConfigManager:remoteConfigManager
                                                           aciSignalProtocolStore:aciSignalProtocolStore
                                                           pniSignalProtocolStore:pniSignalProtocolStore
                                                                        udManager:udManager
                                                                 messageDecrypter:messageDecrypter
                                                         groupsV2MessageProcessor:groupsV2MessageProcessor
                                                                    socketManager:socketManager
                                                                 tsAccountManager:tsAccountManager
                                                                    ows2FAManager:ows2FAManager
                                                          disappearingMessagesJob:disappearingMessagesJob
                                                                   receiptManager:receiptManager
                                                           outgoingReceiptManager:outgoingReceiptManager
                                                              reachabilityManager:reachabilityManager
                                                                      syncManager:syncManager
                                                                 typingIndicators:typingIndicators
                                                              attachmentDownloads:attachmentDownloads
                                                                   stickerManager:stickerManager
                                                                  databaseStorage:databaseStorage
                                                        signalServiceAddressCache:signalServiceAddressCache
                                                                    signalService:signalService
                                                             accountServiceClient:accountServiceClient
                                                            storageServiceManager:storageServiceManager
                                                               storageCoordinator:storageCoordinator
                                                                   sskPreferences:sskPreferences
                                                                         groupsV2:groupsV2
                                                                   groupV2Updates:groupV2Updates
                                                                messageFetcherJob:messageFetcherJob
                                                                 bulkProfileFetch:bulkProfileFetch
                                                                versionedProfiles:versionedProfiles
                                                                  modelReadCaches:modelReadCaches
                                                              earlyMessageManager:earlyMessageManager
                                                        messagePipelineSupervisor:messagePipelineSupervisor
                                                                        appExpiry:appExpiry
                                                                 messageProcessor:messageProcessor
                                                                   paymentsHelper:paymentsHelper
                                                               paymentsCurrencies:paymentsCurrencies
                                                                   paymentsEvents:paymentsEvents
                                                                 mobileCoinHelper:mobileCoinHelper
                                                            spamChallengeResolver:spamChallengeResolver
                                                                   senderKeyStore:senderKeyStore
                                                                  phoneNumberUtil:phoneNumberUtil
                                                                 webSocketFactory:webSocketFactory
                                                                changePhoneNumber:changePhoneNumber
                                                              subscriptionManager:subscriptionManager
                                                               systemStoryManager:systemStoryManager
                                                           remoteMegaphoneFetcher:remoteMegaphoneFetcher
                                                                     sskJobQueues:sskJobQueues
                                                          contactDiscoveryManager:contactDiscoveryManager]];

        appSpecificSingletonBlock();

        OWSAssertDebug(SSKEnvironment.shared.isComplete);

        // Register renamed classes.
        [NSKeyedUnarchiver setClass:[OWSUserProfile class] forClassName:[OWSUserProfile collection]];
        [NSKeyedUnarchiver setClass:[OWSGroupInfoRequestMessage class] forClassName:@"OWSSyncGroupsRequestMessage"];
        [NSKeyedUnarchiver setClass:[TSGroupModelV2 class] forClassName:@"TSGroupModelV2"];

        // Prevent device from sleeping during migrations.
        // This protects long migrations from the iOS 13 background crash.
        //
        // We can use any object.
        NSObject *sleepBlockObject = [NSObject new];
        [DeviceSleepManager.shared addBlockWithBlockObject:sleepBlockObject];

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            if (AppSetup.shouldTruncateGrdbWal) {
                // Try to truncate GRDB WAL before any readers or writers are
                // active.
                NSError *_Nullable error;
                [databaseStorage.grdbStorage syncTruncatingCheckpointAndReturnError:&error];
                if (error != nil) {
                    OWSFailDebug(@"Failed to truncate database: %@", error);
                }
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                [storageCoordinator markStorageSetupAsComplete];

                // Don't start database migrations until storage is ready.
                [VersionMigrations performUpdateCheckWithCompletion:^() {
                    OWSAssertIsOnMainThread();

                    [DeviceSleepManager.shared removeBlockWithBlockObject:sleepBlockObject];

                    [SSKEnvironment.shared warmCaches];
                    migrationCompletion(nil);

                    OWSAssertDebug(backgroundTask);
                    backgroundTask = nil;

                    // Do this after we've finished running database migrations.
                    if (SSKDebugFlags.internalLogging) {
                        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                            ^{ [SDSKeyValueStore logCollectionStatistics]; });
                    }
                }];
            });
        });
    });
}

+ (void)suppressUnsatisfiableConstraintLogging
{
    [[NSUserDefaults standardUserDefaults] setValue:@(SSKDebugFlags.internalLogging)
                                             forKey:@"_UIConstraintBasedLayoutLogUnsatisfiable"];
}

+ (BOOL)shouldTruncateGrdbWal
{
    if (!CurrentAppContext().isMainApp) {
        return NO;
    }
    if (CurrentAppContext().mainApplicationStateOnLaunch == UIApplicationStateBackground) {
        return NO;
    }
    return YES;
}

@end

NS_ASSUME_NONNULL_END
