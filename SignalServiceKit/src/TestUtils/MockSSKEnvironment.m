//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "MockSSKEnvironment.h"
#import "OWS2FAManager.h"
#import "OWSAttachmentDownloads.h"
#import "OWSBatchMessageProcessor.h"
#import "OWSBlockingManager.h"
#import "OWSDisappearingMessagesJob.h"
#import "OWSFakeCallMessageHandler.h"
#import "OWSFakeContactsUpdater.h"
#import "OWSFakeMessageSender.h"
#import "OWSFakeNetworkManager.h"
#import "OWSFakeProfileManager.h"
#import "OWSIdentityManager.h"
#import "OWSMessageDecrypter.h"
#import "OWSMessageManager.h"
#import "OWSMessageReceiver.h"
#import "OWSOutgoingReceiptManager.h"
#import "OWSPrimaryStorage.h"
#import "OWSReadReceiptManager.h"
#import "SSKPreKeyStore.h"
#import "SSKSessionStore.h"
#import "SSKSignedPreKeyStore.h"
#import "TSAccountManager.h"
#import "TSSocketManager.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef DEBUG

@interface OWSPrimaryStorage (Tests)

@property (atomic) BOOL areAsyncRegistrationsComplete;
@property (atomic) BOOL areSyncRegistrationsComplete;

@end

#pragma mark -

@implementation MockSSKEnvironment

+ (void)activate
{
    MockSSKEnvironment *instance = [self new];
    [self setShared:instance];
    [instance configure];
}

- (instancetype)init
{
    SDSDatabaseStorage *databaseStorage = [SDSDatabaseStorage new];
    OWSPrimaryStorage *primaryStorage = databaseStorage.yapPrimaryStorage;
    [OWSPrimaryStorage protectFiles];

    id<ContactsManagerProtocol> contactsManager = [OWSFakeContactsManager new];
    OWSLinkPreviewManager *linkPreviewManager = [OWSLinkPreviewManager new];
    TSNetworkManager *networkManager = [OWSFakeNetworkManager new];
    OWSMessageSender *messageSender = [OWSFakeMessageSender new];
    MessageSenderJobQueue *messageSenderJobQueue = [MessageSenderJobQueue new];

    OWSMessageManager *messageManager = [OWSMessageManager new];
    OWSBlockingManager *blockingManager = [[OWSBlockingManager alloc] initWithPrimaryStorage:primaryStorage];
    OWSIdentityManager *identityManager = [[OWSIdentityManager alloc] initWithDatabaseStorage:databaseStorage];
    SSKSessionStore *sessionStore = [SSKSessionStore new];
    SSKPreKeyStore *preKeyStore = [SSKPreKeyStore new];
    SSKSignedPreKeyStore *signedPreKeyStore = [SSKSignedPreKeyStore new];
    id<OWSUDManager> udManager = [[OWSUDManagerImpl alloc] initWithPrimaryStorage:primaryStorage];
    OWSMessageDecrypter *messageDecrypter = [OWSMessageDecrypter new];
    SSKMessageDecryptJobQueue *messageDecryptJobQueue = [SSKMessageDecryptJobQueue new];
    OWSBatchMessageProcessor *batchMessageProcessor = [OWSBatchMessageProcessor new];
    OWSMessageReceiver *messageReceiver = [OWSMessageReceiver new];
    TSSocketManager *socketManager = [[TSSocketManager alloc] init];
    TSAccountManager *tsAccountManager = [TSAccountManager new];
    OWS2FAManager *ows2FAManager = [[OWS2FAManager alloc] initWithPrimaryStorage:primaryStorage];
    OWSDisappearingMessagesJob *disappearingMessagesJob = [OWSDisappearingMessagesJob new];
    OWSReadReceiptManager *readReceiptManager = [OWSReadReceiptManager new];
    OWSOutgoingReceiptManager *outgoingReceiptManager =
        [[OWSOutgoingReceiptManager alloc] initWithPrimaryStorage:primaryStorage];
    id<SSKReachabilityManager> reachabilityManager = [SSKReachabilityManagerImpl new];
    id<OWSSyncManagerProtocol> syncManager = [[OWSMockSyncManager alloc] init];
    id<OWSTypingIndicators> typingIndicators = [[OWSTypingIndicatorsImpl alloc] init];
    OWSAttachmentDownloads *attachmentDownloads = [[OWSAttachmentDownloads alloc] init];
    StickerManager *stickerManager = [[StickerManager alloc] init];
    SignalServiceAddressCache *signalServiceAddressCache = [SignalServiceAddressCache new];

    self = [super initWithContactsManager:contactsManager
                       linkPreviewManager:linkPreviewManager
                            messageSender:messageSender
                    messageSenderJobQueue:messageSenderJobQueue
                           profileManager:[OWSFakeProfileManager new]
                           primaryStorage:primaryStorage
                          contactsUpdater:[OWSFakeContactsUpdater new]
                           networkManager:networkManager
                           messageManager:messageManager
                          blockingManager:blockingManager
                          identityManager:identityManager
                             sessionStore:sessionStore
                        signedPreKeyStore:signedPreKeyStore
                              preKeyStore:preKeyStore
                                udManager:udManager
                         messageDecrypter:messageDecrypter
                   messageDecryptJobQueue:messageDecryptJobQueue
                    batchMessageProcessor:batchMessageProcessor
                          messageReceiver:messageReceiver
                            socketManager:socketManager
                         tsAccountManager:tsAccountManager
                            ows2FAManager:ows2FAManager
                  disappearingMessagesJob:disappearingMessagesJob
                       readReceiptManager:readReceiptManager
                   outgoingReceiptManager:outgoingReceiptManager
                      reachabilityManager:reachabilityManager
                              syncManager:syncManager
                         typingIndicators:typingIndicators
                      attachmentDownloads:attachmentDownloads
                           stickerManager:stickerManager
                          databaseStorage:databaseStorage
                signalServiceAddressCache:signalServiceAddressCache];

    if (!self) {
        return nil;
    }

    self.callMessageHandler = [OWSFakeCallMessageHandler new];
    self.notificationsManager = [NoopNotificationsManager new];
    return self;
}

- (void)configure
{
    [self.databaseStorage clearGRDBStorageForTests];

    __block dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [OWSStorage registerExtensionsWithMigrationBlock:^() {
        dispatch_semaphore_signal(semaphore);
    }];

    // Registering extensions is a complicated process than can move
    // on and off the main thread.  While we wait for it to complete,
    // we need to process the run loop so that the work on the main
    // thread can be completed.
    while (YES) {
        // Wait up to 10 ms.
        BOOL success
            = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_MSEC))) == 0;
        if (success) {
            break;
        }

        // Process a single "source" (e.g. item) on the default run loop.
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.0, false);
    }
}

@end

#endif

NS_ASSUME_NONNULL_END
