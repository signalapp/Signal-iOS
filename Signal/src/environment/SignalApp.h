//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

@class AccountManager;
@class CallService;
@class CallUIAdapter;
@class HomeViewController;
@class NotificationsManager;
@class OWSMessageFetcherJob;
@class OWSWebRTCCallMessageHandler;
@class OutboundCallInitiator;
@class TSThread;

@interface SignalApp : NSObject

@property (nonatomic) HomeViewController *homeViewController;
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
- (void)presentConversationForRecipientId:(NSString *)recipientId withCompose:(BOOL)compose;
- (void)callRecipientId:(NSString *)recipientId;
- (void)presentConversationForThreadId:(NSString *)threadId;
- (void)presentConversationForThread:(TSThread *)thread;
- (void)presentConversationForThread:(TSThread *)thread withCompose:(BOOL)compose;

#pragma mark - Methods

+ (void)resetAppData;

@end
