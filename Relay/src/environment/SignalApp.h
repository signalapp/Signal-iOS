//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class AccountManager;
@class CallService;
@class CallUIAdapter;
@class HomeViewController;
@class NotificationsManager;
@class OWSMessageFetcherJob;
@class OWSNavigationController;
@class OWSWebRTCCallMessageHandler;
@class OutboundCallInitiator;
@class TSThread;

@interface SignalApp : NSObject

@property (nonatomic, nullable, weak) HomeViewController *homeViewController;
@property (nonatomic, nullable, weak) OWSNavigationController *signUpFlowNavigationController;

// TODO: Convert to singletons?
@property (nonatomic, readonly) OWSWebRTCCallMessageHandler *callMessageHandler;
@property (nonatomic, readonly) CallService *callService;
@property (nonatomic, readonly) CallUIAdapter *callUIAdapter;
@property (nonatomic, readonly) OutboundCallInitiator *outboundCallInitiator;
@property (nonatomic, readonly) OWSMessageFetcherJob *messageFetcherJob;
@property (nonatomic, readonly) NotificationsManager *notificationsManager;
@property (nonatomic, readonly) AccountManager *accountManager;

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)sharedApp;

#pragma mark - View Convenience Methods

- (void)presentConversationForRecipientId:(NSString *)recipientId;
- (void)presentConversationForRecipientId:(NSString *)recipientId action:(ConversationViewAction)action;
- (void)presentConversationForThreadId:(NSString *)threadId;
- (void)presentConversationForThread:(TSThread *)thread;
- (void)presentConversationForThread:(TSThread *)thread action:(ConversationViewAction)action;
- (void)presentConversationForThread:(TSThread *)thread
                              action:(ConversationViewAction)action
                      focusMessageId:(nullable NSString *)focusMessageId;

#pragma mark - Methods

+ (void)resetAppData;

+ (void)clearAllNotifications;

@end

NS_ASSUME_NONNULL_END
