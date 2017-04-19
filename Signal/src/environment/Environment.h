//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PropertyListPreferences.h"
#import "TSGroupModel.h"
#import "TSStorageHeaders.h"

/**
 *
 * Environment is a data and data accessor class.
 * It handles application-level component wiring in order to support mocks for testing.
 * It also handles network configuration for testing/deployment server configurations.
 *
 **/

@class UINavigationController;
@class OWSContactsManager;
@class OutboundCallInitiator;
@class SignalsViewController;
@class TSGroupThread;
@class ContactsUpdater;
@class TSNetworkManager;
@class AccountManager;
@class OWSWebRTCCallMessageHandler;
@class CallUIAdapter;
@class CallService;
@class OWSMessageSender;
@class NotificationsManager;

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
@property (nonatomic, readonly) PropertyListPreferences *preferences;


@property (nonatomic, readonly) SignalsViewController *signalsViewController;
@property (nonatomic, readonly, weak) UINavigationController *signUpFlowNavigationController;

+ (Environment *)getCurrent;
+ (void)setCurrent:(Environment *)curEnvironment;

+ (PropertyListPreferences *)preferences;

+ (void)resetAppData;

- (void)setSignalsViewController:(SignalsViewController *)signalsViewController;
- (void)setSignUpFlowNavigationController:(UINavigationController *)signUpFlowNavigationController;

+ (void)messageThreadId:(NSString *)threadId;
+ (void)messageIdentifier:(NSString *)identifier withCompose:(BOOL)compose;
+ (void)callUserWithIdentifier:(NSString *)identifier;
+ (void)messageGroup:(TSGroupThread *)groupThread;

@end
