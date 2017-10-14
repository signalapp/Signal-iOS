//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSPreferences.h"
#import "TSStorageHeaders.h"

/**
 *
 * Environment is a data and data accessor class.
 * It handles application-level component wiring in order to support mocks for testing.
 * It also handles network configuration for testing/deployment server configurations.
 *
 **/

@class TSThread;
@class UINavigationController;
@class OWSContactsManager;
@class OutboundCallInitiator;
@class HomeViewController;
@class TSGroupThread;
@class ContactsUpdater;
@class TSNetworkManager;
@class AccountManager;
@class OWSWebRTCCallMessageHandler;
@class CallUIAdapter;
@class CallService;
@class OWSMessageSender;
@class NotificationsManager;
@class OWSMessageFetcherJob;

@interface Environment : NSObject

- (instancetype)initWithContactsManager:(OWSContactsManager *)contactsManager
                        contactsUpdater:(ContactsUpdater *)contactsUpdater
                         networkManager:(TSNetworkManager *)networkManager
                          messageSender:(OWSMessageSender *)messageSender;

@property (nonatomic, readonly) AccountManager *accountManager;
@property (nonatomic, readonly) OWSWebRTCCallMessageHandler *callMessageHandler;
@property (nonatomic, readonly) CallUIAdapter *callUIAdapter;
@property (nonatomic, readonly) CallService *callService;
@property (nonatomic, readonly) OWSContactsManager *contactsManager;
@property (nonatomic, readonly) OutboundCallInitiator *outboundCallInitiator;
@property (nonatomic, readonly) ContactsUpdater *contactsUpdater;
@property (nonatomic, readonly) TSNetworkManager *networkManager;
@property (nonatomic, readonly) NotificationsManager *notificationsManager;
@property (nonatomic, readonly) OWSMessageSender *messageSender;
@property (nonatomic, readonly) OWSPreferences *preferences;
@property (nonatomic, readonly) OWSMessageFetcherJob *messageFetcherJob;

@property (nonatomic, readonly) HomeViewController *homeViewController;
@property (nonatomic, readonly, weak) UINavigationController *signUpFlowNavigationController;

+ (Environment *)getCurrent;
+ (void)setCurrent:(Environment *)curEnvironment;

+ (OWSPreferences *)preferences;

+ (void)resetAppData;

- (void)setHomeViewController:(HomeViewController *)homeViewController;
- (void)setSignUpFlowNavigationController:(UINavigationController *)signUpFlowNavigationController;

+ (void)presentConversationForRecipientId:(NSString *)recipientId;
+ (void)presentConversationForRecipientId:(NSString *)recipientId withCompose:(BOOL)compose;
+ (void)callRecipientId:(NSString *)recipientId;
+ (void)presentConversationForThreadId:(NSString *)threadId;
+ (void)presentConversationForThread:(TSThread *)thread;
+ (void)presentConversationForThread:(TSThread *)thread withCompose:(BOOL)compose;

@end
