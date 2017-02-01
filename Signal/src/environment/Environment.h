//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Logging.h"
#import "PacketHandler.h"
#import "PropertyListPreferences.h"
#import "SecureEndPoint.h"
#import "TSGroupModel.h"
#import "TSStorageHeaders.h"

static NSString *const kRedphoneCallSegue = @"2.0_6.0_Call_Segue";

/**
 *
 * Environment is a data and data accessor class.
 * It handles application-level component wiring in order to support mocks for testing.
 * It also handles network configuration for testing/deployment server configurations.
 *
 **/

#define SAMPLE_RATE 8000

#define ENVIRONMENT_TESTING_OPTION_LOSE_CONF_ACK_ON_PURPOSE @"LoseConfAck"
#define ENVIRONMENT_TESTING_OPTION_ALLOW_NETWORK_STREAM_TO_NON_SECURE_END_POINTS @"AllowTcpWithoutTls"
#define ENVIRONMENT_LEGACY_OPTION_RTP_PADDING_BIT_IMPLIES_EXTENSION_BIT_AND_TWELVE_EXTRA_ZERO_BYTES_IN_HEADER \
    @"LegacyAndroidInterop_1"
#define TESTING_OPTION_USE_DH_FOR_HANDSHAKE @"DhKeyAgreementOnly"

@class UINavigationController;
@class RecentCallManager;
@class OWSContactsManager;
@class OutboundCallInitiator;
@class PhoneManager;
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
@class UINavigationController;

@interface Environment : NSObject

- (instancetype)initWithLogging:(id<Logging>)logging
                     errorNoter:(ErrorHandlerBlock)errorNoter
                     serverPort:(in_port_t)serverPort
           masterServerHostName:(NSString *)masterServerHostName
               defaultRelayName:(NSString *)defaultRelayName
      relayServerHostNameSuffix:(NSString *)relayServerHostNameSuffix
                    certificate:(Certificate *)certificate
 supportedKeyAgreementProtocols:(NSArray *)keyAgreementProtocolsInDescendingPriority
                   phoneManager:(PhoneManager *)phoneManager
              recentCallManager:(RecentCallManager *)recentCallManager
        testingAndLegacyOptions:(NSArray *)testingAndLegacyOptions
                   zrtpClientId:(NSData *)zrtpClientId
                  zrtpVersionId:(NSData *)zrtpVersionId
                contactsManager:(OWSContactsManager *)contactsManager
                contactsUpdater:(ContactsUpdater *)contactsUpdater
                 networkManager:(TSNetworkManager *)networkManager
                  messageSender:(OWSMessageSender *)messageSender;

@property (nonatomic, readonly) in_port_t serverPort;
@property (nonatomic, readonly) id<Logging> logging;
@property (nonatomic, readonly) SecureEndPoint *masterServerSecureEndPoint;
@property (nonatomic, readonly) NSString *defaultRelayName;
@property (nonatomic, readonly) Certificate *certificate;
@property (nonatomic, readonly) NSString *relayServerHostNameSuffix;
@property (nonatomic, readonly) NSArray *keyAgreementProtocolsInDescendingPriority;
@property (nonatomic, readonly) ErrorHandlerBlock errorNoter;
@property (nonatomic, readonly) PhoneManager *phoneManager;
@property (nonatomic, readonly) RecentCallManager *recentCallManager;
@property (nonatomic, readonly) NSArray *testingAndLegacyOptions;
@property (nonatomic, readonly) NSData *zrtpClientId;
@property (nonatomic, readonly) NSData *zrtpVersionId;
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

+ (SecureEndPoint *)getMasterServerSecureEndPoint;
+ (SecureEndPoint *)getSecureEndPointToDefaultRelayServer;
+ (SecureEndPoint *)getSecureEndPointToSignalingServerNamed:(NSString *)name;

+ (Environment *)getCurrent;
+ (void)setCurrent:(Environment *)curEnvironment;
+ (id<Logging>)logging;
+ (NSString *)relayServerNameToHostName:(NSString *)name;
+ (ErrorHandlerBlock)errorNoter;
+ (bool)hasEnabledTestingOrLegacyOption:(NSString *)flag;
+ (PhoneManager *)phoneManager;

+ (PropertyListPreferences *)preferences;

+ (BOOL)isRedPhoneRegistered;
+ (void)resetAppData;

- (void)initCallListener;
- (void)setSignalsViewController:(SignalsViewController *)signalsViewController;
- (void)setSignUpFlowNavigationController:(UINavigationController *)signUpFlowNavigationController;

+ (void)messageThreadId:(NSString *)threadId;
+ (void)messageIdentifier:(NSString *)identifier withCompose:(BOOL)compose;
+ (void)messageGroup:(TSGroupThread *)groupThread;

@end
