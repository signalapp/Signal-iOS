//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "SubProtocol.pb.h"

#import "Cryptography.h"
#import "OWSSignalService.h"
#import "OWSWebsocketSecurityPolicy.h"
#import "TSAccountManager.h"
#import "TSConstants.h"
#import "TSMessagesManager.h"
#import "TSSocketManager.h"
#import "TSStorageManager+keyingMaterial.h"
#import "Threading.h"

#define kWebSocketHeartBeat 30
#define kWebSocketReconnectTry 5
#define kBackgroundConnectTimer 25
#define kBackgroundConnectKeepAlive 15

NSString *const SocketOpenedNotification     = @"SocketOpenedNotification";
NSString *const SocketClosedNotification     = @"SocketClosedNotification";
NSString *const SocketConnectingNotification = @"SocketConnectingNotification";

// TSSocketManager's properties should only be accessed from the main thread.
@interface TSSocketManager ()

@property (nonatomic, readonly) OWSSignalService *signalService;

@property (nonatomic) NSTimer *pingTimer;
@property (nonatomic) NSTimer *reconnectTimer;


@property (nonatomic) SRWebSocket *websocket;
@property (nonatomic) SocketStatus status;

@property (nonatomic) UIBackgroundTaskIdentifier fetchingTaskIdentifier;

@property (nonatomic) NSTimer *backgroundKeepAliveTimer;
@property (nonatomic) NSTimer *backgroundConnectTimer;

@end

#pragma mark -

@implementation TSSocketManager

- (instancetype)init
{
    self = [super init];

    if (!self) {
        return self;
    }
    
    OWSAssert([NSThread isMainThread]);

    _signalService = [OWSSignalService new];
    _status = kSocketStatusClosed;

    [self addObserver:self forKeyPath:@"status" options:0 context:kSocketStatusObservationContext];

    OWSSingletonAssert();

    return self;
}

+ (instancetype)sharedManager {
    static TSSocketManager *sharedMyManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      sharedMyManager                        = [[self alloc] init];
      sharedMyManager.fetchingTaskIdentifier = UIBackgroundTaskInvalid;
    });
    return sharedMyManager;
}

#pragma mark - Manage Socket

+ (void)becomeActive
{
    [[self sharedManager] becomeActive];
}

- (void)becomeActive
{
    OWSAssert([NSThread isMainThread]);

    DispatchMainThreadSafe(^{
        [self ensureWebsocket];
    });
}

- (void)ensureWebsocket
{
    OWSAssert([NSThread isMainThread]);
    
    if (self.signalService.isCensored) {
        DDLogWarn(@"%@ Refusing to start websocket in `becomeActive`.", self.tag);
        return;
    }

    // Try to reuse the existing socket (if any) if it is in a valid state.
    if (self.websocket) {
        switch ([self.websocket readyState]) {
            case SR_OPEN:
                DDLogVerbose(@"WebSocket already open on connection request");
                self.status = kSocketStatusOpen;
                return;
            case SR_CONNECTING:
                DDLogVerbose(@"WebSocket is already connecting");
                self.status = kSocketStatusConnecting;
                return;
            default:
                break;
        }
    }

    DDLogWarn(@"Creating new websocket");

    // If socket is not already open or connecting, connect now.
    //
    // First we need to close the existing websocket, if any.
    // The websocket delegate methods are invoked _after_ the websocket
    // state changes, so we may be just learning about a socket failure
    // or close event now.
    self.status = kSocketStatusClosed;
    // Now open a new socket.
    self.status = kSocketStatusConnecting;
}

- (NSString *)stringFromSocketStatus:(SocketStatus)status {
    switch (status) {
        case kSocketStatusClosed:
            return @"Closed";
        case kSocketStatusOpen:
            return @"Open";
        case kSocketStatusConnecting:
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
// Therefore, we use the [setStatus:] setter to ensure alignment between
// websocket state and class state.
- (void)setStatus:(SocketStatus)status {
    OWSAssert([NSThread isMainThread]);

    // If this status update is redundant, verify that
    // class state and socket state are aligned.
    //
    // Note: it's not safe to check the socket's readyState here as
    //       it may have been just updated on another thread. If so,
    //       we'll learn of that state change soon.
    if (_status == status) {
        switch (status) {
            case kSocketStatusClosed:
                OWSAssert(!self.websocket);
                break;
            case kSocketStatusOpen:
                OWSAssert(self.websocket);
                break;
            case kSocketStatusConnecting:
                OWSAssert(self.websocket);
                break;
        }
        return;
    }
    
    DDLogWarn(@"%@ Socket status change: %@ -> %@",
              self.tag,
              [self stringFromSocketStatus:_status],
              [self stringFromSocketStatus:status]);
    
    // If this status update is _not_ redundant,
    // update class state to reflect the new status.
    switch (status) {
        case kSocketStatusClosed: {
            [self resetSocket];
            break;
        }
        case kSocketStatusOpen: {
            OWSAssert(self.status == kSocketStatusConnecting);

            self.pingTimer = [NSTimer timerWithTimeInterval:kWebSocketHeartBeat
                                                     target:self
                                                   selector:@selector(webSocketHeartBeat)
                                                   userInfo:nil
                                                    repeats:YES];
            
            // Additionally, we want the ping timer to work in the background too.
            [[NSRunLoop mainRunLoop] addTimer:self.pingTimer forMode:NSDefaultRunLoopMode];
            
            [self.reconnectTimer invalidate];
            self.reconnectTimer = nil;
            break;
        }
        case kSocketStatusConnecting: {
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
            // the socket failed immediately for some reason), so we update the status
            // _before_ calling it, not after.
            _status = status;
            [socket open];
            return;
        }
    }

    _status = status;
}

- (void)resetSocket {
    OWSAssert([NSThread isMainThread]);

    self.websocket.delegate = nil;
    [self.websocket close];
    self.websocket = nil;
    [self.pingTimer invalidate];
    self.pingTimer = nil;
}

+ (void)resignActivity {
    OWSAssert([NSThread isMainThread]);

    DDLogWarn(@"resignActivity closing web socket");
    [[self sharedManager] closeWebSocket];
}

- (void)closeWebSocket
{
    OWSAssert([NSThread isMainThread]);

    if (self.websocket) {
        DDLogWarn(@"%@ closeWebSocket.", self.tag);
    }

    self.status = kSocketStatusClosed;
}

#pragma mark - Delegate methods

- (void)webSocketDidOpen:(SRWebSocket *)webSocket {
    OWSAssert([NSThread isMainThread]);
    OWSAssert(webSocket);
    if (webSocket != self.websocket) {
        // Ignore events from obsolete web sockets.
        return;
    }

    self.status = kSocketStatusOpen;
}

- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error {
    OWSAssert([NSThread isMainThread]);
    OWSAssert(webSocket);
    if (webSocket != self.websocket) {
        // Ignore events from obsolete web sockets.
        return;
    }

    DDLogError(@"Websocket did fail with error: %@", error);

    [self closeWebSocket];

    [self scheduleRetry];
}

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(NSData *)data {
    OWSAssert([NSThread isMainThread]);
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
    OWSAssert([NSThread isMainThread]);

    DDLogInfo(@"Got message with verb: %@ and path: %@", message.verb, message.path);

    [self sendWebSocketMessageAcknowledgement:message];
    [self keepAliveBackground];

    if ([message.path isEqualToString:@"/api/v1/message"] && [message.verb isEqualToString:@"PUT"]) {

        NSData *decryptedPayload =
            [Cryptography decryptAppleMessagePayload:message.body withSignalingKey:TSStorageManager.signalingKey];

        if (!decryptedPayload) {
            DDLogWarn(@"Failed to decrypt incoming payload or bad HMAC");
            return;
        }

        OWSSignalServiceProtosEnvelope *envelope = [OWSSignalServiceProtosEnvelope parseFromData:decryptedPayload];

        [[TSMessagesManager sharedManager] handleReceivedEnvelope:envelope];

    } else {
        DDLogWarn(@"Unsupported WebSocket Request");
    }
}

- (void)keepAliveBackground {
    OWSAssert([NSThread isMainThread]);
    
    [self.backgroundConnectTimer invalidate];

    if (self.fetchingTaskIdentifier) {
        [self.backgroundKeepAliveTimer invalidate];

        self.backgroundKeepAliveTimer = [NSTimer timerWithTimeInterval:kBackgroundConnectKeepAlive
                                                                target:self
                                                              selector:@selector(backgroundTimeExpired)
                                                              userInfo:nil
                                                               repeats:NO];
        // Additionally, we want the reconnect timer to work in the background too.
        [[NSRunLoop mainRunLoop] addTimer:self.backgroundKeepAliveTimer forMode:NSDefaultRunLoopMode];
    }
}

- (void)processWebSocketResponseMessage:(WebSocketResponseMessage *)message {
    OWSAssert([NSThread isMainThread]);

    DDLogWarn(@"Client should not receive WebSocket Respond messages");
}

- (void)sendWebSocketMessageAcknowledgement:(WebSocketRequestMessage *)request {
    OWSAssert([NSThread isMainThread]);

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
        [self scheduleRetry];
    }
}

- (void)webSocket:(SRWebSocket *)webSocket
 didCloseWithCode:(NSInteger)code
           reason:(NSString *)reason
         wasClean:(BOOL)wasClean {
    OWSAssert([NSThread isMainThread]);
    OWSAssert(webSocket);
    if (webSocket != self.websocket) {
        // Ignore events from obsolete web sockets.
        return;
    }

    DDLogWarn(@"Websocket did close with code: %ld", (long)code);

    [self closeWebSocket];

    if (!wasClean && [self shouldKeepWebSocketAlive]) {
        [self scheduleRetry];
    }
}

- (void)webSocketHeartBeat {
    OWSAssert([NSThread isMainThread]);

    if ([self shouldKeepWebSocketAlive]) {
        NSError *error;
        [self.websocket sendPing:nil error:&error];
        if (error) {
            DDLogWarn(@"Error in websocket heartbeat: %@", error.localizedDescription);
            [self scheduleRetry];
        }
    } else {
        DDLogWarn(@"webSocketHeartBeat closing web socket");
        [self closeWebSocket];
    }
}

- (NSString *)webSocketAuthenticationString {
    return [NSString
        stringWithFormat:@"?login=%@&password=%@",
                         [[TSStorageManager localNumber] stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"],
                         [TSStorageManager serverAuthToken]];
}

- (BOOL)shouldKeepWebSocketAlive {
    OWSAssert([NSThread isMainThread]);

    if ([UIApplication sharedApplication].applicationState == UIApplicationStateActive) {
        // If app is active, keep web socket alive.
        return YES;
    } else if (self.backgroundKeepAliveTimer ||
               self.backgroundConnectTimer ||
               self.fetchingTaskIdentifier != UIBackgroundTaskInvalid) {
        // If app is doing any work in the background, keep web socket alive.
        return YES;
    } else {
        return NO;
    }
}

- (void)scheduleRetry {
    OWSAssert([NSThread isMainThread]);
   
    if (![self shouldKeepWebSocketAlive]) {
        // Don't bother retrying if app is inactive and not doing any background activity.
        [self.reconnectTimer invalidate];
        self.reconnectTimer = nil;
    } else if (![self.reconnectTimer isValid]) {
        // TODO: It'd be nice to do exponential backoff.
        self.reconnectTimer = [NSTimer timerWithTimeInterval:kWebSocketReconnectTry
                                                      target:[self class]
                                                    selector:@selector(becomeActive)
                                                    userInfo:nil
                                                     repeats:YES];
        // Additionally, we want the reconnect timer to work in the background too.
        [[NSRunLoop mainRunLoop] addTimer:self.reconnectTimer forMode:NSDefaultRunLoopMode];
    } else {
        DDLogWarn(@"Not scheduling retry, valid timer");
    }
}

#pragma mark - Background Connect

+ (void)becomeActiveFromForeground {
    DispatchMainThreadSafe(^{
        [[self sharedManager] becomeActiveFromForeground];
    });
}

- (void)becomeActiveFromForeground {
    OWSAssert([NSThread isMainThread]);
    
    if (self.fetchingTaskIdentifier != UIBackgroundTaskInvalid) {
        [self closeBackgroundTask];
    }
    
    [self becomeActive];
}

+ (void)becomeActiveFromBackgroundExpectMessage:(BOOL)expected {
    DispatchMainThreadSafe(^{
        [[TSSocketManager sharedManager] becomeActiveFromBackgroundExpectMessage:expected];
    });
}

- (void)becomeActiveFromBackgroundExpectMessage:(BOOL)expected {
    OWSAssert([NSThread isMainThread]);
    
    if (self.fetchingTaskIdentifier == UIBackgroundTaskInvalid) {
        [self.backgroundConnectTimer invalidate];
        self.backgroundConnectTimer = [NSTimer timerWithTimeInterval:kBackgroundConnectTimer
                                                              target:self
                                                            selector:@selector(backgroundConnectTimerExpired)
                                                            userInfo:nil
                                                             repeats:NO];
        NSRunLoop *loop = [NSRunLoop mainRunLoop];
        [loop addTimer:[TSSocketManager sharedManager].backgroundConnectTimer forMode:NSDefaultRunLoopMode];
        
        [self.backgroundKeepAliveTimer invalidate];
        self.backgroundKeepAliveTimer = nil;
        self.fetchingTaskIdentifier =
        [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
            OWSAssert([NSThread isMainThread]);
            
            [TSSocketManager resignActivity];
            [[TSSocketManager sharedManager] closeBackgroundTask];
        }];
        
        [self becomeActive];
    } else {
        DDLogWarn(@"Got called to become active in the background but there was already a background task running.");
    }
}

- (void)backgroundConnectTimerExpired {
    OWSAssert([NSThread isMainThread]);

    [self.backgroundConnectTimer invalidate];
    self.backgroundConnectTimer = nil;
    
    [self backgroundTimeExpired];
}

- (void)backgroundTimeExpired {
    OWSAssert([NSThread isMainThread]);
    
    if (![self shouldKeepWebSocketAlive]) {
        [[self class] resignActivity];
    }
    [self closeBackgroundTask];
}

- (void)closeBackgroundTask {
    OWSAssert([NSThread isMainThread]);

    [self.backgroundKeepAliveTimer invalidate];
    self.backgroundKeepAliveTimer = nil;
    [self.backgroundConnectTimer invalidate];
    self.backgroundConnectTimer = nil;

    [[UIApplication sharedApplication] endBackgroundTask:self.fetchingTaskIdentifier];
    self.fetchingTaskIdentifier = UIBackgroundTaskInvalid;
}

#pragma mark UI Delegates

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if (context == kSocketStatusObservationContext) {
        [self notifyStatusChange];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)notifyStatusChange {
    switch (self.status) {
        case kSocketStatusOpen:
            [[NSNotificationCenter defaultCenter] postNotificationName:SocketOpenedNotification object:self];
            break;
        case kSocketStatusClosed:
            [[NSNotificationCenter defaultCenter] postNotificationName:SocketClosedNotification object:self];
            break;
        case kSocketStatusConnecting:
            [[NSNotificationCenter defaultCenter] postNotificationName:SocketConnectingNotification object:self];
            break;
        default:
            break;
    }
}

+ (void)sendNotification {
    [[self sharedManager] notifyStatusChange];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end
