//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "SSKEnvironment.h"

NS_ASSUME_NONNULL_BEGIN

// This should only be used in the tests.
#ifdef TESTABLE_BUILD

@interface SSKEnvironment (MockSSKEnvironment)

// Redeclare these properties as mutable so that tests can replace singletons.
@property (nonatomic) id<ContactsManagerProtocol> contactsManager;
@property (nonatomic) MessageSender *messageSender;
@property (nonatomic) id<ProfileManagerProtocol> profileManager;
@property (nonatomic, nullable) OWSPrimaryStorage *primaryStorage;
@property (nonatomic) TSNetworkManager *networkManager;
@property (nonatomic) OWSMessageManager *messageManager;
@property (nonatomic) OWSBlockingManager *blockingManager;
@property (nonatomic) OWSIdentityManager *identityManager;
@property (nonatomic) id<OWSUDManager> udManager;
@property (nonatomic) OWSMessageDecrypter *messageDecrypter;
@property (nonatomic) OWSBatchMessageProcessor *batchMessageProcessor;
@property (nonatomic) OWSMessageReceiver *messageReceiver;
@property (nonatomic) TSSocketManager *socketManager;
@property (nonatomic) TSAccountManager *tsAccountManager;
@property (nonatomic) OWS2FAManager *ows2FAManager;
@property (nonatomic) OWSDisappearingMessagesJob *disappearingMessagesJob;
@property (nonatomic) OWSReadReceiptManager *readReceiptManager;
@property (nonatomic) OWSOutgoingReceiptManager *outgoingReceiptManager;
@property (nonatomic) id<SyncManagerProtocol> syncManager;
@property (nonatomic) id<SSKReachabilityManager> reachabilityManager;
@property (nonatomic) id<OWSTypingIndicators> typingIndicators;
@property (nonatomic) OWSAttachmentDownloads *attachmentDownloads;
@property (nonatomic) SignalServiceAddressCache *signalServiceAddressCache;
@property (nonatomic) StickerManager *stickerManager;
@property (nonatomic) SDSDatabaseStorage *databaseStorage;
@property (nonatomic) AccountServiceClient *accountServiceClient;
@property (nonatomic) id<GroupsV2> groupsV2;

@end

#pragma mark -

@interface MockSSKEnvironment : SSKEnvironment

+ (void)activate;

- (instancetype)init NS_DESIGNATED_INITIALIZER;

@end

#endif

NS_ASSUME_NONNULL_END
