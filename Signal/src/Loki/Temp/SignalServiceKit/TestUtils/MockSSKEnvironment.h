//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SSKEnvironment.h"

NS_ASSUME_NONNULL_BEGIN

// This should only be used in the tests.
#ifdef DEBUG

@interface SSKEnvironment (MockSSKEnvironment)

// Redeclare these properties as mutable so that tests can replace singletons.
@property (nonatomic) id<ContactsManagerProtocol> contactsManager;
@property (nonatomic) OWSMessageSender *messageSender;
@property (nonatomic) id<ProfileManagerProtocol> profileManager;
@property (nonatomic) OWSPrimaryStorage *primaryStorage;
@property (nonatomic) ContactsUpdater *contactsUpdater;
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
@property (nonatomic) ContactDiscoveryService *contactDiscoveryService;
@property (nonatomic) OWSReadReceiptManager *readReceiptManager;
@property (nonatomic) OWSOutgoingReceiptManager *outgoingReceiptManager;

@end

#pragma mark -

@interface MockSSKEnvironment : SSKEnvironment

+ (void)activate;

- (instancetype)init;

@end

#endif

NS_ASSUME_NONNULL_END
