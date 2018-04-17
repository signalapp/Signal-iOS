//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSSocketManager.h"
#import "AppContext.h"
#import "AppReadiness.h"
#import "Cryptography.h"
#import "NSNotificationCenter+OWS.h"
#import "NSTimer+OWS.h"
#import "NotificationsProtocol.h"
#import "OWSBackgroundTask.h"
#import "OWSMessageManager.h"
#import "OWSMessageReceiver.h"
#import "OWSPrimaryStorage.h"
#import "OWSSignalService.h"
#import "OWSSignalServiceProtos.pb.h"
#import "OWSWebsocketSecurityPolicy.h"
#import "SubProtocol.pb.h"
#import "TSAccountManager.h"
#import "TSConstants.h"
#import "TSErrorMessage.h"
#import "TextSecureKitEnv.h"
#import "Threading.h"

static const CGFloat kSocketHeartbeatPeriodSeconds = 30.f;
static const CGFloat kSocketReconnectDelaySeconds = 5.f;

// If the app is in the background, it should keep the
// websocket open if:
//
// a) It has received a notification in the last 25 seconds.
static const CGFloat kBackgroundOpenSocketDurationSeconds = 25.f;
// b) It has received a message over the socket in the last 15 seconds.
static const CGFloat kBackgroundKeepSocketAliveDurationSeconds = 15.f;

NSString *const kNSNotification_SocketManagerStateDidChange = @"kNSNotification_SocketManagerStateDidChange";

// TSSocketManager's properties should only be accessed from the main thread.
@interface TSSocketManager ()

@property (nonatomic, readonly) OWSSignalService *signalService;
@property (nonatomic, readonly) OWSMessageReceiver *messageReceiver;

// This class has a few "tiers" of state.
//
// The first tier is the actual websocket and the timers used
// to keep it alive and connected.
@property (nonatomic) SRWebSocket *websocket;
@property (nonatomic) NSTimer *heartbeatTimer;
@property (nonatomic) NSTimer *reconnectTimer;

#pragma mark -

// The second tier is the state property.  We initiate changes
// to the websocket by changing this property's value, and delegate
// events from the websocket also update this value as the websocket's
// state changes.
//
// Due to concurrency, this property can fall out of sync with the
// websocket's actual state, so we're defensive and distrustful of
// this property.
@property (nonatomic) SocketManagerState state;

#pragma mark -

// The third tier is the state that is used to determine what the
// "desired" state of the websocket is.
//
// If we're keeping the socket open in the background, all three of these
// properties will be set.  Otherwise (if the app is active or if we're not
// trying to keep the socket open), all three should be clear.
//
// This represents how long we're trying to keep the socket open.
@property (nonatomic) NSDate *backgroundKeepAliveUntilDate;
// This timer is used to check periodically whether we should
// close the socket.
@property (nonatomic) NSTimer *backgroundKeepAliveTimer;
// This is used to manage the iOS "background task" used to
// keep the app alive in the background.
@property (nonatomic) OWSBackgroundTask *backgroundTask;

// We cache this value instead of consulting [UIApplication sharedApplication].applicationState,
// because UIKit only provides a "will resign active" notification, not a "did resign active"
// notification.
@property (nonatomic) BOOL appIsActive;

@property (nonatomic) BOOL hasObservedNotifications;

@end

#pragma mark -

@implementation TSSocketManager

- (instancetype)init
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssertIsOnMainThread();

    _signalService = [OWSSignalService sharedInstance];
    _messageReceiver = [OWSMessageReceiver sharedInstance];
    _state = SocketManagerStateClosed;

    OWSSingletonAssert();

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// We want to observe these notifications lazily to avoid accessing
// the data store in [application: didFinishLaunchingWithOptions:].
- (void)observeNotificationsIfNecessary
{
    if (self.hasObservedNotifications) {
        return;
    }
    self.hasObservedNotifications = YES;

    self.appIsActive = CurrentAppContext().isMainAppAndActive;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:OWSApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive:)
                                                 name:OWSApplicationWillResignActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(registrationStateDidChange:)
                                                 name:RegistrationStateDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(isCensorshipCircumventionActiveDidChange:)
                                                 name:kNSNotificationName_IsCensorshipCircumventionActiveDidChange
                                               object:nil];
}

+ (instancetype)sharedManager {
    static TSSocketManager *sharedMyManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMyManager = [self new];
    });
    return sharedMyManager;
}

#pragma mark - Manage Socket

- (void)ensureWebsocketIsOpen
{
    OWSAssertIsOnMainThread();
    OWSAssert(!self.signalService.isCensorshipCircumventionActive);

    // Try to reuse the existing socket (if any) if it is in a valid state.
    if (self.websocket) {
        switch ([self.websocket readyState]) {
            case SR_OPEN:
                self.state = SocketManagerStateOpen;
                return;
            case SR_CONNECTING:
                DDLogVerbose(@"%@ WebSocket is already connecting", self.logTag);
                self.state = SocketManagerStateConnecting;
                return;
            default:
                break;
        }
    }

    DDLogWarn(@"%@ Creating new websocket", self.logTag);

    // If socket is not already open or connecting, connect now.
    //
    // First we need to close the existing websocket, if any.
    // The websocket delegate methods are invoked _after_ the websocket
    // state changes, so we may be just learning about a socket failure
    // or close event now.
    self.state = SocketManagerStateClosed;
    // Now open a new socket.
    self.state = SocketManagerStateConnecting;
}

- (NSString *)stringFromSocketManagerState:(SocketManagerState)state
{
    switch (state) {
        case SocketManagerStateClosed:
            return @"Closed";
        case SocketManagerStateOpen:
            return @"Open";
        case SocketManagerStateConnecting:
            return @"Connecting";
    }
}

// We need to keep websocket state and class state tightly aligned.
//
// Sometimes we'll need to update class state to reflect changes
// in socket state; sometimes we'll need to update socket state
// and class state to reflect changes in app state.
//
// We learn about changes to socket state through websocket
// delegate methods like [webSocketDidOpen:], [didFailWithError:...]
// and [didCloseWithCode:...].  These delegate methods are sometimes
// invoked _after_ web socket state changes, so we sometimes learn
// about changes to socket state in [ensureWebsocket].  Put another way,
// it's not safe to assume we'll learn of changes to websocket state
// in the websocket delegate methods.
//
// Therefore, we use the [setState:] setter to ensure alignment between
// websocket state and class state.
- (void)setState:(SocketManagerState)state
{
    OWSAssertIsOnMainThread();

    // If this state update is redundant, verify that
    // class state and socket state are aligned.
    //
    // Note: it's not safe to check the socket's readyState here as
    //       it may have been just updated on another thread. If so,
    //       we'll learn of that state change soon.
    if (_state == state) {
        switch (state) {
            case SocketManagerStateClosed:
                OWSAssert(!self.websocket);
                break;
            case SocketManagerStateOpen:
                OWSAssert(self.websocket);
                break;
            case SocketManagerStateConnecting:
                OWSAssert(self.websocket);
                break;
        }
        return;
    }

    DDLogWarn(@"%@ Socket state: %@ -> %@",
        self.logTag,
        [self stringFromSocketManagerState:_state],
        [self stringFromSocketManagerState:state]);

    // If this state update is _not_ redundant,
    // update class state to reflect the new state.
    switch (state) {
        case SocketManagerStateClosed: {
            [self resetSocket];
            break;
        }
        case SocketManagerStateOpen: {
            OWSAssert(self.state == SocketManagerStateConnecting);

            self.heartbeatTimer = [NSTimer timerWithTimeInterval:kSocketHeartbeatPeriodSeconds
                                                          target:self
                                                        selector:@selector(webSocketHeartBeat)
                                                        userInfo:nil
                                                         repeats:YES];

            // Additionally, we want the ping timer to work in the background too.
            [[NSRunLoop mainRunLoop] addTimer:self.heartbeatTimer forMode:NSDefaultRunLoopMode];

            // If the socket is open, we don't need to worry about reconnecting.
            [self clearReconnect];
            break;
        }
        case SocketManagerStateConnecting: {
            // Discard the old socket which is already closed or is closing.
            [self resetSocket];
            
            // Create a new web socket.
            NSString *webSocketConnect = [textSecureWebSocketAPI stringByAppendingString:[self webSocketAuthenticationString]];
            NSURL *webSocketConnectURL   = [NSURL URLWithString:webSocketConnect];
            NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:webSocketConnectURL];
            
            SRWebSocket *socket = [[SRWebSocket alloc] initWithURLRequest:request
                                                           securityPolicy:[OWSWebsocketSecurityPolicy sharedPolicy]];
            socket.delegate = self;
            
            [self setWebsocket:socket];

            // [SRWebSocket open] could hypothetically call a delegate method (e.g. if
            // the socket failed immediately for some reason), so we update the state
            // _before_ calling it, not after.
            _state = state;
            [socket open];
            return;
        }
    }

    _state = state;

    [self notifyStatusChange];
}

- (void)notifyStatusChange
{
    [[NSNotificationCenter defaultCenter] postNotificationNameAsync:kNSNotification_SocketManagerStateDidChange
                                                             object:nil
                                                           userInfo:nil];
}

#pragma mark -

- (void)resetSocket {
    OWSAssertIsOnMainThread();

    self.websocket.delegate = nil;
    [self.websocket close];
    self.websocket = nil;
    [self.heartbeatTimer invalidate];
    self.heartbeatTimer = nil;
}

- (void)closeWebSocket
{
    OWSAssertIsOnMainThread();

    if (self.websocket) {
        DDLogWarn(@"%@ closeWebSocket.", self.logTag);
    }

    self.state = SocketManagerStateClosed;
}

#pragma mark - Delegate methods

- (void)webSocketDidOpen:(SRWebSocket *)webSocket {
    OWSAssertIsOnMainThread();
    OWSAssert(webSocket);
    if (webSocket != self.websocket) {
        // Ignore events from obsolete web sockets.
        return;
    }

    self.state = SocketManagerStateOpen;
}

- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error {
    OWSAssertIsOnMainThread();
    OWSAssert(webSocket);
    if (webSocket != self.websocket) {
        // Ignore events from obsolete web sockets.
        return;
    }

    DDLogError(@"Websocket did fail with error: %@", error);

    [self handleSocketFailure];
}

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(NSData *)data {
    OWSAssertIsOnMainThread();
    OWSAssert(webSocket);
    if (webSocket != self.websocket) {
        // Ignore events from obsolete web sockets.
        return;
    }

    WebSocketMessage *wsMessage = [WebSocketMessage parseFromData:data];

    if (wsMessage.type == WebSocketMessageTypeRequest) {
        [self processWebSocketRequestMessage:wsMessage.request];
    } else if (wsMessage.type == WebSocketMessageTypeResponse) {
        [self processWebSocketResponseMessage:wsMessage.response];
    } else {
        DDLogWarn(@"Got a WebSocketMessage of unknown type");
    }
}

- (void)processWebSocketRequestMessage:(WebSocketRequestMessage *)message {
    OWSAssertIsOnMainThread();

    DDLogInfo(@"%@ Got message with verb: %@ and path: %@", self.logTag, message.verb, message.path);

    // If we receive a message over the socket while the app is in the background,
    // prolong how long the socket stays open.
    [self requestSocketAliveForAtLeastSeconds:kBackgroundKeepSocketAliveDurationSeconds];

    if ([message.path isEqualToString:@"/api/v1/message"] && [message.verb isEqualToString:@"PUT"]) {

        __block OWSBackgroundTask *backgroundTask = [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            @try {
                NSData *decryptedPayload = [Cryptography decryptAppleMessagePayload:message.body
                                                                   withSignalingKey:TSAccountManager.signalingKey];

                if (!decryptedPayload) {
                    DDLogWarn(@"%@ Failed to decrypt incoming payload or bad HMAC", self.logTag);
                    [self sendWebSocketMessageAcknowledgement:message];
                    backgroundTask = nil;
                    return;
                }

                OWSSignalServiceProtosEnvelope *envelope =
                    [OWSSignalServiceProtosEnvelope parseFromData:decryptedPayload];

                [self.messageReceiver handleReceivedEnvelope:envelope];
            } @catch (NSException *exception) {
                OWSProdLogAndFail(@"%@ Received an invalid envelope: %@", self.logTag, exception.debugDescription);
                // TODO: Add analytics.

                [[OWSPrimaryStorage.sharedManager newDatabaseConnection] readWriteWithBlock:^(
                    YapDatabaseReadWriteTransaction *transaction) {
                    TSErrorMessage *errorMessage = [TSErrorMessage corruptedMessageInUnknownThread];
                    [[TextSecureKitEnv sharedEnv].notificationsManager notifyUserForThreadlessErrorMessage:errorMessage
                                                                                               transaction:transaction];
                }];
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                [self sendWebSocketMessageAcknowledgement:message];
                backgroundTask = nil;
            });
        });
    } else if ([message.path isEqualToString:@"/api/v1/queue/empty"]) {
        // Queue is drained.

        [self sendWebSocketMessageAcknowledgement:message];
    } else {
        DDLogWarn(@"%@ Unsupported WebSocket Request", self.logTag);

        [self sendWebSocketMessageAcknowledgement:message];
    }
}

- (void)processWebSocketResponseMessage:(WebSocketResponseMessage *)message {
    OWSAssertIsOnMainThread();

    DDLogWarn(@"Client should not receive WebSocket Respond messages");
}

- (void)sendWebSocketMessageAcknowledgement:(WebSocketRequestMessage *)request {
    OWSAssertIsOnMainThread();

    WebSocketResponseMessageBuilder *response = [WebSocketResponseMessage builder];
    [response setStatus:200];
    [response setMessage:@"OK"];
    [response setId:request.id];

    WebSocketMessageBuilder *message = [WebSocketMessage builder];
    [message setResponse:response.build];
    [message setType:WebSocketMessageTypeResponse];

    NSError *error;
    [self.websocket sendDataNoCopy:message.build.data error:&error];
    if (error) {
        DDLogWarn(@"Error while trying to write on websocket %@", error);
        [self handleSocketFailure];
    }
}

- (void)handleSocketFailure
{
    OWSAssertIsOnMainThread();

    [self closeWebSocket];

    if ([self shouldSocketBeOpen]) {
        // If we should retry, use `ensureReconnect` to
        // reconnect after a delay.
        [self ensureReconnect];
    } else {
        // Otherwise clean up and align state.
        [self applyDesiredSocketState];
    }
}

- (void)webSocket:(SRWebSocket *)webSocket
 didCloseWithCode:(NSInteger)code
           reason:(NSString *)reason
         wasClean:(BOOL)wasClean {
    OWSAssertIsOnMainThread();
    OWSAssert(webSocket);
    if (webSocket != self.websocket) {
        // Ignore events from obsolete web sockets.
        return;
    }

    DDLogWarn(@"Websocket did close with code: %ld", (long)code);

    [self handleSocketFailure];
}

- (void)webSocketHeartBeat {
    OWSAssertIsOnMainThread();

    if ([self shouldSocketBeOpen]) {
        NSError *error;
        [self.websocket sendPing:nil error:&error];
        if (error) {
            DDLogWarn(@"Error in websocket heartbeat: %@", error.localizedDescription);
            [self handleSocketFailure];
        }
    } else {
        DDLogWarn(@"webSocketHeartBeat closing web socket");
        [self closeWebSocket];
        [self applyDesiredSocketState];
    }
}

- (NSString *)webSocketAuthenticationString {
    return [NSString stringWithFormat:@"?login=%@&password=%@",
                     [[TSAccountManager localNumber] stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"],
                     [TSAccountManager serverAuthToken]];
}

#pragma mark - Socket LifeCycle

- (BOOL)shouldSocketBeOpen
{
    OWSAssertIsOnMainThread();

    // Don't open socket in app extensions.
    if (!CurrentAppContext().isMainApp) {
        return NO;
    }

    if (![TSAccountManager isRegistered]) {
        return NO;
    }

    if (self.signalService.isCensorshipCircumventionActive) {
        DDLogWarn(@"%@ Skipping opening of websocket due to censorship circumvention.", self.logTag);
        return NO;
    }

    if (self.appIsActive) {
        // If app is active, keep web socket alive.
        return YES;
    } else if (self.backgroundKeepAliveUntilDate && [self.backgroundKeepAliveUntilDate timeIntervalSinceNow] > 0.f) {
        OWSAssert(self.backgroundKeepAliveTimer);
        // If app is doing any work in the background, keep web socket alive.
        return YES;
    } else {
        return NO;
    }
}

- (void)requestSocketAliveForAtLeastSeconds:(CGFloat)durationSeconds
{
    OWSAssertIsOnMainThread();
    OWSAssert(durationSeconds > 0.f);

    if (self.appIsActive) {
        // If app is active, clean up state used to keep socket alive in background.
        [self clearBackgroundState];
    } else if (!self.backgroundKeepAliveUntilDate) {
        OWSAssert(!self.backgroundKeepAliveUntilDate);
        OWSAssert(!self.backgroundKeepAliveTimer);

        DDLogInfo(@"%s activating socket in the background", __PRETTY_FUNCTION__);

        // Set up state used to keep socket alive in background.
        self.backgroundKeepAliveUntilDate = [NSDate dateWithTimeIntervalSinceNow:durationSeconds];

        // To be defensive, clean up any existing backgroundKeepAliveTimer.
        [self.backgroundKeepAliveTimer invalidate];
        // Start a new timer that will fire every second while the socket is open in the background.
        // This timer will ensure we close the websocket when the time comes.
        self.backgroundKeepAliveTimer = [NSTimer weakScheduledTimerWithTimeInterval:1.f
                                                                             target:self
                                                                           selector:@selector(backgroundKeepAliveFired)
                                                                           userInfo:nil
                                                                            repeats:YES];
        // Additionally, we want the reconnect timer to work in the background too.
        [[NSRunLoop mainRunLoop] addTimer:self.backgroundKeepAliveTimer forMode:NSDefaultRunLoopMode];

        __weak typeof(self) weakSelf = self;
        self.backgroundTask =
            [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__
                                          completionBlock:^(BackgroundTaskState backgroundTaskState) {
                                              OWSAssertIsOnMainThread();
                                              __strong typeof(self) strongSelf = weakSelf;
                                              if (!strongSelf) {
                                                  return;
                                              }

                                              if (backgroundTaskState == BackgroundTaskState_Expired) {
                                                  [strongSelf clearBackgroundState];
                                              }
                                              [strongSelf applyDesiredSocketState];
                                          }];
    } else {
        OWSAssert(self.backgroundKeepAliveUntilDate);
        OWSAssert(self.backgroundKeepAliveTimer);
        OWSAssert([self.backgroundKeepAliveTimer isValid]);

        if ([self.backgroundKeepAliveUntilDate timeIntervalSinceNow] < durationSeconds) {
            // Update state used to keep socket alive in background.
            self.backgroundKeepAliveUntilDate = [NSDate dateWithTimeIntervalSinceNow:durationSeconds];
        }
    }

    [self applyDesiredSocketState];
}

- (void)backgroundKeepAliveFired
{
    OWSAssertIsOnMainThread();

    [self applyDesiredSocketState];
}

+ (void)requestSocketOpen
{
    DispatchMainThreadSafe(^{
        [[self sharedManager] observeNotificationsIfNecessary];

        // If the app is active and the user is registered, this will
        // simply open the websocket.
        //
        // If the app is inactive, it will open the websocket for a
        // period of time.
        [[self sharedManager] requestSocketAliveForAtLeastSeconds:kBackgroundOpenSocketDurationSeconds];
    });
}

// This method aligns the socket state with the "desired" socket state.
- (void)applyDesiredSocketState
{
    OWSAssertIsOnMainThread();

    if (!AppReadiness.isAppReady) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            [AppReadiness runNowOrWhenAppIsReady:^{
                [self applyDesiredSocketState];
            }];
        });
        return;
    }

    if ([self shouldSocketBeOpen]) {
        if (self.state != SocketManagerStateOpen) {
            // If we want the socket to be open and it's not open,
            // start up the reconnect timer immediately (don't wait for an error).
            // There's little harm in it and this will make us more robust to edge
            // cases.
            [self ensureReconnect];
        }
        [self ensureWebsocketIsOpen];
    } else {
        [self clearBackgroundState];
        [self clearReconnect];
        [self closeWebSocket];
    }
}

- (void)clearBackgroundState
{
    OWSAssertIsOnMainThread();

    self.backgroundKeepAliveUntilDate = nil;
    [self.backgroundKeepAliveTimer invalidate];
    self.backgroundKeepAliveTimer = nil;
    self.backgroundTask = nil;
}

#pragma mark - Reconnect

- (void)ensureReconnect
{
    OWSAssertIsOnMainThread();
    OWSAssert([self shouldSocketBeOpen]);

    if (self.reconnectTimer) {
        OWSAssert([self.reconnectTimer isValid]);
    } else {
        // TODO: It'd be nice to do exponential backoff.
        self.reconnectTimer = [NSTimer timerWithTimeInterval:kSocketReconnectDelaySeconds
                                                      target:self
                                                    selector:@selector(applyDesiredSocketState)
                                                    userInfo:nil
                                                     repeats:YES];
        // Additionally, we want the reconnect timer to work in the background too.
        [[NSRunLoop mainRunLoop] addTimer:self.reconnectTimer forMode:NSDefaultRunLoopMode];
    }
}

- (void)clearReconnect
{
    OWSAssertIsOnMainThread();

    [self.reconnectTimer invalidate];
    self.reconnectTimer = nil;
}

#pragma mark - Notifications

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    self.appIsActive = YES;
    [self applyDesiredSocketState];
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    self.appIsActive = NO;
    // TODO: It might be nice to use `requestSocketAliveForAtLeastSeconds:` to
    //       keep the socket open for a few seconds after the app is
    //       inactivated.
    [self applyDesiredSocketState];
}

- (void)registrationStateDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self applyDesiredSocketState];
}

- (void)isCensorshipCircumventionActiveDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self applyDesiredSocketState];
}

@end
