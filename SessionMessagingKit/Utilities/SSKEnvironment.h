//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class ContactDiscoveryService;
@class ContactsUpdater;
@class OWS2FAManager;
@class OWSAttachmentDownloads;
@class OWSBatchMessageProcessor;
@class OWSDisappearingMessagesJob;
@class OWSIdentityManager;
@class OWSMessageDecrypter;
@class OWSMessageManager;
@class OWSMessageReceiver;
@class OWSMessageSender;
@class OWSOutgoingReceiptManager;
@class OWSPrimaryStorage;
@class OWSReadReceiptManager;
@class SSKMessageSenderJobQueue;
@class TSAccountManager;
@class TSSocketManager;
@class YapDatabaseConnection;

@protocol ContactsManagerProtocol;
@protocol NotificationsProtocol;
@protocol OWSCallMessageHandler;
@protocol ProfileManagerProtocol;
@protocol OWSUDManager;
@protocol SSKReachabilityManager;
@protocol OWSSyncManagerProtocol;
@protocol OWSTypingIndicators;

@interface SSKEnvironment : NSObject

- (instancetype)initWithProfileManager:(id<ProfileManagerProtocol>)profileManager
                        primaryStorage:(OWSPrimaryStorage *)primaryStorage
                       identityManager:(OWSIdentityManager *)identityManager
                      tsAccountManager:(TSAccountManager *)tsAccountManager
               disappearingMessagesJob:(OWSDisappearingMessagesJob *)disappearingMessagesJob
                    readReceiptManager:(OWSReadReceiptManager *)readReceiptManager
                outgoingReceiptManager:(OWSOutgoingReceiptManager *)outgoingReceiptManager
                   reachabilityManager:(id<SSKReachabilityManager>)reachabilityManager
                      typingIndicators:(id<OWSTypingIndicators>)typingIndicators NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly, class) SSKEnvironment *shared;

+ (void)setShared:(SSKEnvironment *)env;

#ifdef DEBUG
// Should only be called by tests.
+ (void)clearSharedForTests;
#endif

@property (nonatomic, readonly) id<ProfileManagerProtocol> profileManager;
@property (nonatomic, readonly) OWSPrimaryStorage *primaryStorage;
@property (nonatomic, readonly) OWSIdentityManager *identityManager;
@property (nonatomic, readonly) TSAccountManager *tsAccountManager;
@property (nonatomic, readonly) OWSDisappearingMessagesJob *disappearingMessagesJob;
@property (nonatomic, readonly) OWSReadReceiptManager *readReceiptManager;
@property (nonatomic, readonly) OWSOutgoingReceiptManager *outgoingReceiptManager;
@property (nonatomic, readonly) id<SSKReachabilityManager> reachabilityManager;
@property (nonatomic, readonly) id<OWSTypingIndicators> typingIndicators;

// This property is configured after Environment is created.
@property (atomic, nullable) id<NotificationsProtocol> notificationsManager;

@property (atomic, readonly) YapDatabaseConnection *objectReadWriteConnection;
@property (atomic, readonly) YapDatabaseConnection *sessionStoreDBConnection;
@property (atomic, readonly) YapDatabaseConnection *migrationDBConnection;
@property (atomic, readonly) YapDatabaseConnection *analyticsDBConnection;

- (BOOL)isComplete;

@end

NS_ASSUME_NONNULL_END
