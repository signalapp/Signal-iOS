//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/SSKEnvironment.h>

NS_ASSUME_NONNULL_BEGIN

// This should only be used in the tests.
#ifdef TESTABLE_BUILD

@interface SSKEnvironment (MockSSKEnvironment)

// Redeclare these properties as mutable so that tests can replace singletons.
@property (nonatomic) id<ContactsManagerProtocol> contactsManagerRef;
@property (nonatomic) MessageSender *messageSenderRef;
@property (nonatomic) id<ProfileManagerProtocol> profileManagerRef;
@property (nonatomic) TSNetworkManager *networkManagerRef;
@property (nonatomic) OWSMessageManager *messageManagerRef;
@property (nonatomic) OWSBlockingManager *blockingManagerRef;
@property (nonatomic) OWSIdentityManager *identityManagerRef;
@property (nonatomic) id<OWSUDManager> udManagerRef;
@property (nonatomic) OWSMessageDecrypter *messageDecrypterRef;
@property (nonatomic) TSSocketManager *socketManagerRef;
@property (nonatomic) TSAccountManager *tsAccountManagerRef;
@property (nonatomic) OWS2FAManager *ows2FAManagerRef;
@property (nonatomic) OWSDisappearingMessagesJob *disappearingMessagesJobRef;
@property (nonatomic) OWSReceiptManager *receiptManagerRef;
@property (nonatomic) OWSOutgoingReceiptManager *outgoingReceiptManagerRef;
@property (nonatomic) id<SyncManagerProtocol> syncManagerRef;
@property (nonatomic) id<SSKReachabilityManager> reachabilityManagerRef;
@property (nonatomic) id<OWSTypingIndicators> typingIndicatorsRef;
@property (nonatomic) OWSAttachmentDownloads *attachmentDownloadsRef;
@property (nonatomic) SignalServiceAddressCache *signalServiceAddressCacheRef;
@property (nonatomic) StickerManager *stickerManagerRef;
@property (nonatomic) SDSDatabaseStorage *databaseStorageRef;
@property (nonatomic) AccountServiceClient *accountServiceClientRef;
@property (nonatomic) id<GroupsV2> groupsV2Ref;
@property (nonatomic) id<Payments> paymentsRef;
@property (nonatomic) id<PaymentsCurrencies> paymentsCurrenciesRef;

@end

#pragma mark -

@interface MockSSKEnvironment : SSKEnvironment

+ (void)activate;

- (instancetype)init NS_DESIGNATED_INITIALIZER;

@end

#endif

NS_ASSUME_NONNULL_END
