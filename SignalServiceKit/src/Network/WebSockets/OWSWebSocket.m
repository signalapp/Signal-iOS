//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSWebSocket.h"
#import "AppContext.h"
#import "AppReadiness.h"
#import "NSNotificationCenter+OWS.h"
#import "NSTimer+OWS.h"
#import "NotificationsProtocol.h"
#import "OWSBackgroundTask.h"
#import "OWSDevicesService.h"
#import "OWSError.h"
#import "OWSMessageManager.h"
#import "OWSMessageReceiver.h"
#import "OWSSignalService.h"
#import "SSKEnvironment.h"
#import "TSAccountManager.h"
#import "TSConstants.h"
#import "TSErrorMessage.h"
#import "TSRequest.h"
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/Threading.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

static const CGFloat kSocketHeartbeatPeriodSeconds = 30.f;
static const CGFloat kSocketReconnectDelaySeconds = 5.f;

// If the app is in the background, it should keep the
// websocket open if:
//
// a) It has received a notification or app has been activated in the last N seconds.
static const NSTimeInterval kKeepAliveDuration_Default = 20.f;
// b) It has received a message over the socket in the last N seconds.
static const NSTimeInterval kKeepAliveDuration_ReceiveMessage = 15.f;
// c) It is in the process of making a request.
static const NSTimeInterval kKeepAliveDuration_MakeRequestInForeground = 25.f;
static const NSTimeInterval kKeepAliveDuration_MakeRequestInBackground = 20.f;
// d) It has just received the response to a request.
static const NSTimeInterval kKeepAliveDuration_ReceiveResponse = 5.f;

NSNotificationName const NSNotificationWebSocketStateDidChange = @"NSNotificationWebSocketStateDidChange";

@interface TSSocketMessage : NSObject

@property (nonatomic, readonly) UInt64 requestId;
@property (nonatomic, nullable) TSSocketMessageSuccess success;
@property (nonatomic, nullable) TSSocketMessageFailure failure;
@property (nonatomic) BOOL hasCompleted;
@property (nonatomic, readonly) OWSBackgroundTask *backgroundTask;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

@end

#pragma mark -

@implementation TSSocketMessage

- (instancetype)initWithRequestId:(UInt64)requestId
                          success:(TSSocketMessageSuccess)success
                          failure:(TSSocketMessageFailure)failure
{
    if (self = [super init]) {
        OWSAssertDebug(success);
        OWSAssertDebug(failure);

        _requestId = requestId;
        _success = success;
        _failure = failure;
        _backgroundTask = [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];
    }

    return self;
}

- (void)didSucceedWithResponseObject:(id _Nullable)responseObject
{
    @synchronized(self) {
        if (self.hasCompleted) {
            return;
        }
        self.hasCompleted = YES;
    }

    OWSAssertDebug(self.success);
    OWSAssertDebug(self.failure);

    TSSocketMessageSuccess success = self.success;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        success(responseObject);
    });

    self.success = nil;
    self.failure = nil;
}

- (void)timeoutIfNecessary
{
    NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeMessageRequestFailed,
        NSLocalizedString(
            @"ERROR_DESCRIPTION_REQUEST_TIMED_OUT", @"Error indicating that a socket request timed out."));

    [self didFailWithStatusCode:0 responseData:nil error:error];
}

- (void)didFailBeforeSending
{
    NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeMessageRequestFailed,
        NSLocalizedString(@"ERROR_DESCRIPTION_REQUEST_FAILED", @"Error indicating that a socket request failed."));

    [self didFailWithStatusCode:0 responseData:nil error:error];
}

- (void)didFailWithStatusCode:(NSInteger)statusCode responseData:(nullable NSData *)responseData error:(NSError *)error
{
    OWSAssertDebug(error);

    @synchronized(self) {
        if (self.hasCompleted) {
            return;
        }
        self.hasCompleted = YES;
    }

    if (statusCode != 404) {
        OWSLogError(@"didFailWithStatusCode: %zd, %@", statusCode, error);
    } else {
        OWSLogVerbose(@"didFailWithStatusCode: %zd, %@", statusCode, error);
    }

    OWSAssertDebug(self.success);
    OWSAssertDebug(self.failure);

    TSSocketMessageFailure failure = self.failure;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        failure(statusCode, responseData, error);
    });

    self.success = nil;
    self.failure = nil;
}

@end

#pragma mark -

// OWSWebSocket's properties should only be accessed from the main thread.
@interface OWSWebSocket () <SSKWebSocketDelegate>

// This class has a few "tiers" of state.
//
// The first tier is the actual websocket and the timers used
// to keep it alive and connected.
@property (nonatomic, nullable) id<SSKWebSocket> websocket;
@property (nonatomic, nullable) NSTimer *heartbeatTimer;
@property (nonatomic, nullable) NSTimer *reconnectTimer;

#pragma mark -

// The second tier is the state property.  We initiate changes
// to the websocket by changing this property's value, and delegate
// events from the websocket also update this value as the websocket's
// state changes.
//
// Due to concurrency, this property can fall out of sync with the
// websocket's actual state, so we're defensive and distrustful of
// this property.
//
// We only ever access this state on the main thread.
@property (nonatomic) OWSWebSocketState state;
@property (nonatomic) BOOL hasEmptiedInitialQueue;
@property (nonatomic) BOOL willEmptyInitialQueue;

#pragma mark -

// The third tier is the state that is used to determine what the
// "desired" state of the websocket is.
//
// If we're keeping the socket open in the background, all three of these
// properties will be set.  Otherwise (if the app is active or if we're not
// trying to keep the socket open), all three should be clear.
//
// This represents how long we're trying to keep the socket open.
@property (nonatomic, nullable) NSDate *backgroundKeepAliveUntilDate;
// This timer is used to check periodically whether we should
// close the socket.
@property (nonatomic, nullable) NSTimer *backgroundKeepAliveTimer;
// This is used to manage the iOS "background task" used to
// keep the app alive in the background.
@property (nonatomic, nullable) OWSBackgroundTask *backgroundTask;

// We cache this value instead of consulting [UIApplication sharedApplication].applicationState,
// because UIKit only provides a "will resign active" notification, not a "did resign active"
// notification.
@property (nonatomic) BOOL appIsActive;

@property (nonatomic) BOOL hasObservedNotifications;

// This property should only be accessed while synchronized on the socket manager.
@property (nonatomic, readonly) NSMutableDictionary<NSNumber *, TSSocketMessage *> *socketMessageMap;

@property (atomic) BOOL canMakeRequests;

@end

#pragma mark -

@implementation OWSWebSocket

- (instancetype)init
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssertIsOnMainThread();

    _state = OWSWebSocketStateClosed;
    _hasEmptiedInitialQueue = NO;
    _willEmptyInitialQueue = NO;
    _socketMessageMap = [NSMutableDictionary new];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Dependencies

- (OWSSignalService *)signalService
{
    return [OWSSignalService shared];
}

- (OWSMessageReceiver *)messageReceiver
{
    return SSKEnvironment.shared.messageReceiver;
}

- (TSAccountManager *)tsAccountManager
{
    return TSAccountManager.shared;
}

- (OutageDetection *)outageDetection
{
    return OutageDetection.shared;
}

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

- (id<NotificationsProtocol>)notificationsManager
{
    return SSKEnvironment.shared.notificationsManager;
}

- (id<OWSUDManager>)udManager {
    return SSKEnvironment.shared.udManager;
}

#pragma mark -

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
                                                 name:NSNotificationNameRegistrationStateDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(isCensorshipCircumventionActiveDidChange:)
                                                 name:kNSNotificationName_IsCensorshipCircumventionActiveDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(deviceListUpdateModifiedDeviceList:)
                                                 name:NSNotificationNameDeviceListUpdateModifiedDeviceList
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(environmentDidChange:)
                                                 name:TSConstants.EnvironmentDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appExpiryDidChange:)
                                                 name:AppExpiry.AppExpiryDidChange
                                               object:nil];
}

#pragma mark - Manage Socket

- (void)ensureWebsocketIsOpen
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(!self.signalService.isCensorshipCircumventionActive);

    // Try to reuse the existing socket (if any) if it is in a valid state.
    if (self.websocket) {
        switch (self.websocket.state) {
            case SSKWebSocketStateOpen:
                self.state = OWSWebSocketStateOpen;
                return;
            case SSKWebSocketStateConnecting:
                OWSLogVerbose(@"WebSocket is already connecting");
                self.state = OWSWebSocketStateConnecting;
                return;
            default:
                break;
        }
    }

    OWSLogWarn(@"Creating new websocket");

    // If socket is not already open or connecting, connect now.
    //
    // First we need to close the existing websocket, if any.
    // The websocket delegate methods are invoked _after_ the websocket
    // state changes, so we may be just learning about a socket failure
    // or close event now.
    self.state = OWSWebSocketStateClosed;
    // Now open a new socket.
    self.state = OWSWebSocketStateConnecting;
}

- (NSString *)stringFromOWSWebSocketState:(OWSWebSocketState)state
{
    switch (state) {
        case OWSWebSocketStateClosed:
            return @"Closed";
        case OWSWebSocketStateOpen:
            return @"Open";
        case OWSWebSocketStateConnecting:
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
// delegate methods. These delegate methods are sometimes
// invoked _after_ web socket state changes, so we sometimes learn
// about changes to socket state in [ensureWebsocket].  Put another way,
// it's not safe to assume we'll learn of changes to websocket state
// in the websocket delegate methods.
//
// Therefore, we use the [setState:] setter to ensure alignment between
// websocket state and class state.
- (void)setState:(OWSWebSocketState)state
{
    OWSAssertIsOnMainThread();

    if (state != OWSWebSocketStateOpen) {
        self.hasEmptiedInitialQueue = NO;
        self.willEmptyInitialQueue = NO;
    }

    // If this state update is redundant, verify that
    // class state and socket state are aligned.
    //
    // Note: it's not safe to check the socket's readyState here as
    //       it may have been just updated on another thread. If so,
    //       we'll learn of that state change soon.
    if (_state == state) {
        switch (state) {
            case OWSWebSocketStateClosed:
                OWSAssertDebug(!self.websocket);
                break;
            case OWSWebSocketStateOpen:
                OWSAssertDebug(self.websocket);
                break;
            case OWSWebSocketStateConnecting:
                OWSAssertDebug(self.websocket);
                break;
        }
        return;
    }

    OWSLogWarn(
        @"Socket state: %@ -> %@", [self stringFromOWSWebSocketState:_state], [self stringFromOWSWebSocketState:state]);

    // If this state update is _not_ redundant,
    // update class state to reflect the new state.
    switch (state) {
        case OWSWebSocketStateClosed: {
            [self resetSocket];
            break;
        }
        case OWSWebSocketStateOpen: {
            OWSAssertDebug(self.state == OWSWebSocketStateConnecting);

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
        case OWSWebSocketStateConnecting: {
            // Discard the old socket which is already closed or is closing.
            [self resetSocket];

            // Create a new web socket.
            NSString *webSocketConnect =
                [TSConstants.textSecureWebSocketAPI stringByAppendingString:[self webSocketAuthenticationString]];
            NSURL *webSocketConnectURL = [NSURL URLWithString:webSocketConnect];
            NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:webSocketConnectURL];
            [request setValue:OWSURLSession.signalIosUserAgent forHTTPHeaderField:OWSURLSession.kUserAgentHeader];

            id<SSKWebSocket> socket = [SSKWebSocketManager buildSocketWithRequest:request];
            socket.delegate = self;

            [self setWebsocket:socket];

            // `connect` could hypothetically call a delegate method (e.g. if
            // the socket failed immediately for some reason), so we update the state
            // _before_ calling it, not after.
            _state = state;
            self.canMakeRequests = state == OWSWebSocketStateOpen;
            [socket connect];
            [self failAllPendingSocketMessagesIfNecessary];
            return;
        }
    }

    _state = state;
    self.canMakeRequests = state == OWSWebSocketStateOpen;

    [self failAllPendingSocketMessagesIfNecessary];
    [self notifyStatusChange];
}

- (void)notifyStatusChange
{
    [[NSNotificationCenter defaultCenter] postNotificationNameAsync:NSNotificationWebSocketStateDidChange
                                                             object:nil
                                                           userInfo:nil];
}

#pragma mark -

- (void)resetSocket
{
    OWSAssertIsOnMainThread();

    self.websocket.delegate = nil;
    [self.websocket disconnect];
    self.websocket = nil;
    [self.heartbeatTimer invalidate];
    self.heartbeatTimer = nil;
}

- (void)closeWebSocket
{
    OWSAssertIsOnMainThread();

    if (self.websocket) {
        OWSLogWarn(@"closeWebSocket.");
    }

    self.state = OWSWebSocketStateClosed;
}

#pragma mark - Message Sending

- (void)makeRequest:(TSRequest *)request success:(TSSocketMessageSuccess)success failure:(TSSocketMessageFailure)failure
{
    OWSAssertDebug(request);
    OWSAssertDebug(request.HTTPMethod.length > 0);
    OWSAssertDebug(success);
    OWSAssertDebug(failure);

    DispatchMainThreadSafe(^{
        NSTimeInterval keepAlive
            = (CurrentAppContext().isMainAppAndActive ? kKeepAliveDuration_MakeRequestInForeground
                                                      : kKeepAliveDuration_MakeRequestInBackground);
        [self requestSocketAliveForAtLeastSeconds:keepAlive];
    });

    TSSocketMessage *socketMessage = [[TSSocketMessage alloc] initWithRequestId:[Cryptography randomUInt64]
                                                                        success:success
                                                                        failure:failure];

    @synchronized(self) {
        self.socketMessageMap[@(socketMessage.requestId)] = socketMessage;
    }

    NSURL *requestUrl = request.URL;
    NSString *requestPath = [@"/" stringByAppendingString:requestUrl.path];

    NSData *_Nullable jsonData = nil;
    if (request.parameters) {
        NSError *error;
        jsonData =
            [NSJSONSerialization dataWithJSONObject:request.parameters options:(NSJSONWritingOptions)0 error:&error];
        if (!jsonData || error) {
            OWSFailDebug(@"could not serialize request JSON: %@", error);
            [socketMessage didFailBeforeSending];
            return;
        }
    }

    OWSHttpHeaders *httpHeaders = [OWSHttpHeaders new];
    [httpHeaders addHeaders:request.allHTTPHeaderFields overwriteOnConflict:NO];

    WebSocketProtoWebSocketRequestMessageBuilder *requestBuilder =
        [WebSocketProtoWebSocketRequestMessage builderWithVerb:request.HTTPMethod
                                                          path:requestPath
                                                     requestID:socketMessage.requestId];
    if (jsonData) {
        // TODO: Do we need body & headers for requests with no parameters?
        [requestBuilder setBody:jsonData];
        [httpHeaders addHeader:@"content-type" value:@"application/json" overwriteOnConflict:YES];
    }

    // Set User-Agent header.
    [httpHeaders addHeader:OWSURLSession.kUserAgentHeader
                      value:OWSURLSession.signalIosUserAgent
        overwriteOnConflict:YES];

    for (NSString *headerField in httpHeaders.headers) {
        NSString *_Nullable headerValue = httpHeaders.headers[headerField];
        OWSAssertDebug(headerValue != nil);
        [requestBuilder addHeaders:[NSString stringWithFormat:@"%@:%@", headerField, headerValue]];
    }

    NSError *error;
    WebSocketProtoWebSocketRequestMessage *_Nullable requestProto = [requestBuilder buildAndReturnError:&error];
    if (!requestProto || error) {
        OWSFailDebug(@"could not build proto: %@", error);
        return;
    }

    WebSocketProtoWebSocketMessageBuilder *messageBuilder = [WebSocketProtoWebSocketMessage builder];
    [messageBuilder setType:WebSocketProtoWebSocketMessageTypeRequest];
    [messageBuilder setRequest:requestProto];

    NSData *_Nullable messageData = [messageBuilder buildSerializedDataAndReturnError:&error];
    if (!messageData || error) {
        OWSFailDebug(@"could not serialize proto: %@.", error);
        [socketMessage didFailBeforeSending];
        return;
    }

    if (!self.canMakeRequests) {
        OWSLogError(@"makeRequest: socket not open.");
        [socketMessage didFailBeforeSending];
        return;
    }

    [self.websocket writeData:messageData];
    OWSLogInfo(@"making request: %llu, %@: %@, jsonData.length: %zd",
        socketMessage.requestId,
        request.HTTPMethod,
        requestPath,
        jsonData.length);

    const int64_t kSocketTimeoutSeconds = 10;
    __weak TSSocketMessage *weakSocketMessage = socketMessage;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kSocketTimeoutSeconds * NSEC_PER_SEC),
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
        ^{
            [weakSocketMessage timeoutIfNecessary];
        });
}

- (void)processWebSocketResponseMessage:(WebSocketProtoWebSocketResponseMessage *)message
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(message);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self processWebSocketResponseMessageAsync:message];
    });
}

- (void)processWebSocketResponseMessageAsync:(WebSocketProtoWebSocketResponseMessage *)message
{
    OWSAssertDebug(message);

    OWSLogInfo(@"received WebSocket response requestId: %llu, status: %u", message.requestID, message.status);

    DispatchMainThreadSafe(^{
        [self requestSocketAliveForAtLeastSeconds:kKeepAliveDuration_ReceiveResponse];
    });

    UInt64 requestId = message.requestID;
    UInt32 responseStatus = message.status;
    NSString *_Nullable responseMessage;
    if (message.hasMessage) {
        responseMessage = message.message;
    }
    NSData *_Nullable responseData;
    if (message.hasBody) {
        responseData = message.body;
    }

    // The websocket is only used to connect to the main signal
    // service, so we need to check for remote deprecation.
    if (responseStatus == AppExpiry.appExpiredStatusCode) {
        [AppExpiry.shared setHasAppExpiredAtCurrentVersion];
    }

    BOOL hasValidResponse = YES;
    id responseObject = responseData;
    if (responseData) {
        NSError *error;
        id _Nullable responseJson =
            [NSJSONSerialization JSONObjectWithData:responseData options:(NSJSONReadingOptions)0 error:&error];
        if (!responseJson || error) {
            OWSFailDebug(@"could not parse WebSocket response JSON: %@.", error);
            hasValidResponse = NO;
        } else {
            responseObject = responseJson;
        }
    }

    TSSocketMessage *_Nullable socketMessage;
    @synchronized(self) {
        socketMessage = self.socketMessageMap[@(requestId)];
        [self.socketMessageMap removeObjectForKey:@(requestId)];
    }

    if (!socketMessage) {
        OWSLogError(@"received response to unknown request.");
    } else {
        BOOL hasSuccessStatus = 200 <= responseStatus && responseStatus <= 299;
        BOOL didSucceed = hasSuccessStatus && hasValidResponse;
        if (didSucceed) {
            [self.tsAccountManager setIsDeregistered:NO];

            [socketMessage didSucceedWithResponseObject:responseObject];
        } else {
            if (responseStatus == 403) {
                // This should be redundant with our check for the socket
                // failing due to 403, but let's be thorough.
                if (self.tsAccountManager.isRegisteredAndReady) {
                    [self.tsAccountManager setIsDeregistered:YES];
                } else {
                    OWSFailDebug(@"Ignoring auth failure; not registered and ready.");
                }
            }

            NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeMessageResponseFailed,
                NSLocalizedString(
                    @"ERROR_DESCRIPTION_RESPONSE_FAILED", @"Error indicating that a socket response failed."));
            [socketMessage didFailWithStatusCode:(NSInteger)responseStatus responseData:responseData error:error];
        }
    }
}

- (void)failAllPendingSocketMessagesIfNecessary
{
    if (!self.canMakeRequests) {
        [self failAllPendingSocketMessages];
    }
}

- (void)failAllPendingSocketMessages
{
    NSArray<TSSocketMessage *> *socketMessages;
    @synchronized(self) {
        socketMessages = self.socketMessageMap.allValues;
        [self.socketMessageMap removeAllObjects];
    }

    OWSLogInfo(@"failAllPendingSocketMessages: %zd.", socketMessages.count);

    for (TSSocketMessage *socketMessage in socketMessages) {
        [socketMessage didFailBeforeSending];
    }
}

#pragma mark - SSKWebSocketDelegate

- (void)websocketDidConnectWithSocket:(id<SSKWebSocket>)websocket
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(websocket);
    if (websocket != self.websocket) {
        // Ignore events from obsolete web sockets.
        return;
    }

    self.state = OWSWebSocketStateOpen;

    // If socket opens, we know we're not de-registered.
    [self.tsAccountManager setIsDeregistered:NO];

    [self.outageDetection reportConnectionSuccess];
}

- (void)websocketDidDisconnectWithSocket:(id<SSKWebSocket>)websocket error:(nullable NSError *)error
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(websocket);
    if (websocket != self.websocket) {
        // Ignore events from obsolete web sockets.
        return;
    }

    OWSLogWarn(@"Websocket did fail with error: %@", error);
    if ([error.domain isEqualToString:SSKWebSocketError.errorDomain]) {
        NSNumber *_Nullable statusCode = error.userInfo[SSKWebSocketError.kStatusCodeKey];
        if (statusCode.unsignedIntegerValue == 403) {
            if (self.tsAccountManager.isRegisteredAndReady) {
                [self.tsAccountManager setIsDeregistered:YES];
            } else {
                OWSLogWarn(@"Ignoring auth failure; not registered and ready.");
            }
        }
    }

    [self handleSocketFailure];
}

- (void)websocket:(id<SSKWebSocket>)websocket didReceiveMessage:(WebSocketProtoWebSocketMessage *)message
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(websocket);

    if (websocket != self.websocket) {
        // Ignore events from obsolete web sockets.
        return;
    }

    // If we receive a response, we know we're not de-registered.
    [self.tsAccountManager setIsDeregistered:NO];

    if (!message.hasType) {
        OWSFailDebug(@"webSocket:didReceiveMessage: missing type.");
    } else if (message.unwrappedType == WebSocketProtoWebSocketMessageTypeRequest) {
        [self processWebSocketRequestMessage:message.request];
    } else if (message.unwrappedType == WebSocketProtoWebSocketMessageTypeResponse) {
        [self processWebSocketResponseMessage:message.response];
    } else {
        OWSFailDebug(@"webSocket:didReceiveMessage: unknown.");
    }
}

#pragma mark -

- (dispatch_queue_t)serialQueue
{
    static dispatch_queue_t _serialQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _serialQueue = dispatch_queue_create("org.signal.websocket", DISPATCH_QUEUE_SERIAL);
    });

    return _serialQueue;
}

- (void)processWebSocketRequestMessage:(WebSocketProtoWebSocketRequestMessage *)message
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"Got message with verb: %@ and path: %@", message.verb, message.path);

    // If we receive a message over the socket while the app is in the background,
    // prolong how long the socket stays open.
    [self requestSocketAliveForAtLeastSeconds:kKeepAliveDuration_ReceiveMessage];

    if ([message.path isEqualToString:@"/api/v1/message"] && [message.verb isEqualToString:@"PUT"]) {

        __block OWSBackgroundTask *_Nullable backgroundTask =
            [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

        dispatch_async(self.serialQueue, ^{
            BOOL success = NO;
            @try {
                BOOL useSignalingKey = NO;
                uint64_t serverDeliveryTimestamp = 0;
                for (NSString *header in message.headers) {
                    if ([header isEqualToString:@"X-Signal-Key: true"]) {
                        useSignalingKey = YES;
                    } else if ([header hasPrefix:@"X-Signal-Timestamp:"]) {
                        NSArray<NSString *> *components = [header componentsSeparatedByString:@":"];
                        if (components.count == 2) {
                            serverDeliveryTimestamp = (uint64_t)[components[1] longLongValue];
                        } else {
                            OWSFailDebug(@"Invalidly formatted timestamp header %@", header);
                        }
                    }
                }

                if (serverDeliveryTimestamp == 0) {
                    OWSFailDebug(@"Missing server delivery timestamp");
                }

                NSData *_Nullable decryptedPayload;
                if (useSignalingKey) {
                    NSString *_Nullable signalingKey = self.tsAccountManager.storedSignalingKey;
                    OWSAssertDebug(signalingKey);
                    decryptedPayload =
                        [Cryptography decryptAppleMessagePayload:message.body withSignalingKey:signalingKey];
                } else {
                    OWSAssertDebug([message.headers containsObject:@"X-Signal-Key: false"]);

                    decryptedPayload = message.body;
                }

                if (!decryptedPayload) {
                    OWSLogWarn(@"Failed to decrypt incoming payload or bad HMAC");
                } else {
                    [self.messageReceiver handleReceivedEnvelopeData:decryptedPayload
                                             serverDeliveryTimestamp:serverDeliveryTimestamp];
                    success = YES;
                }
            } @catch (NSException *exception) {
                OWSFailDebug(@"Received an invalid envelope: %@", exception.debugDescription);
                // TODO: Add analytics.
            }

            if (!success) {
                DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                    ThreadlessErrorMessage *errorMessage = [ThreadlessErrorMessage corruptedMessageInUnknownThread];
                    [self.notificationsManager notifyUserForThreadlessErrorMessage:errorMessage
                                                                       transaction:transaction];
                });
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                [self sendWebSocketMessageAcknowledgement:message];
                OWSAssertDebug(backgroundTask);
                backgroundTask = nil;
            });
        });
    } else if ([message.path isEqualToString:@"/api/v1/queue/empty"]) {
        // Queue is drained.

        [self sendWebSocketMessageAcknowledgement:message];

        if (!self.hasEmptiedInitialQueue) {

            self.willEmptyInitialQueue = YES;

            // We need to flush the serial queue to ensure that
            // all received messages are enqueued by the message
            // receiver before we: a) mark the queue as empty.
            // b) notify.
            //
            // The socket might close and re-open while we're
            // flushing the queue. We use willEmptyInitialQueue
            // to detect this case.
            dispatch_async(self.serialQueue, ^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (!self.willEmptyInitialQueue) {
                        return;
                    }
                    self.willEmptyInitialQueue = NO;
                    self.hasEmptiedInitialQueue = YES;

                    [self notifyStatusChange];
                });
            });
        }
    } else {
        OWSLogWarn(@"Unsupported WebSocket Request");

        [self sendWebSocketMessageAcknowledgement:message];
    }
}

- (void)sendWebSocketMessageAcknowledgement:(WebSocketProtoWebSocketRequestMessage *)request
{
    OWSAssertIsOnMainThread();
    NSError *error;
    BOOL didSucceed = [self.websocket sendResponseForRequest:request status:200 message:@"OK" error:&error];
    if (!didSucceed) {
        if (IsNetworkConnectivityFailure(error)) {
            OWSLogWarn(@"Error: %@", error);
        } else {
            OWSFailDebug(@"Error: %@", error);
        }
    }
}

- (void)cycleSocket
{
    OWSAssertIsOnMainThread();

    [self closeWebSocket];

    [self applyDesiredSocketState];
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

    [self.outageDetection reportConnectionFailure];
}

- (void)webSocketHeartBeat
{
    OWSAssertIsOnMainThread();

    if ([self shouldSocketBeOpen]) {
        [self.websocket writePing];
    } else {
        OWSLogWarn(@"webSocketHeartBeat closing web socket");
        [self closeWebSocket];
        [self applyDesiredSocketState];
    }
}

- (NSString *)webSocketAuthenticationString
{

    NSString *login = [self.tsAccountManager.storedServerUsername stringByReplacingOccurrencesOfString:@"+"
                                                                                            withString:@"%2B"];
    return [NSString stringWithFormat:@"?login=%@&password=%@", login, self.tsAccountManager.storedServerAuthToken];
}

#pragma mark - Socket LifeCycle

- (BOOL)shouldSocketBeOpen
{
    OWSAssertIsOnMainThread();

    // Don't open socket in app extensions.
    if (!CurrentAppContext().isMainApp) {
        return NO;
    }

    if (!AppReadiness.isAppReady) {
        return NO;
    }

    if (![self.tsAccountManager isRegisteredAndReady]) {
        return NO;
    }

    if (AppExpiry.shared.isExpired) {
        return NO;
    }

    if (self.signalService.isCensorshipCircumventionActive) {
        OWSLogWarn(@"Skipping opening of websocket due to censorship circumvention.");
        return NO;
    }

    if (self.appIsActive) {
        // If app is active, keep web socket alive.
        return YES;
    } else if (SSKDebugFlags.keepWebSocketOpenInBackground) {
        return YES;
    } else if (self.backgroundKeepAliveUntilDate && [self.backgroundKeepAliveUntilDate timeIntervalSinceNow] > 0.f) {
        OWSAssertDebug(self.backgroundKeepAliveTimer);
        // If app is doing any work in the background, keep web socket alive.
        return YES;
    } else {
        return NO;
    }
}

- (void)requestSocketAliveForAtLeastSeconds:(NSTimeInterval)durationSeconds
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(durationSeconds > 0.f);

    if (self.appIsActive) {
        // If app is active, clean up state used to keep socket alive in background.
        [self clearBackgroundState];
    } else if (!self.backgroundKeepAliveUntilDate) {
        OWSAssertDebug(!self.backgroundKeepAliveUntilDate);
        OWSAssertDebug(!self.backgroundKeepAliveTimer);

        OWSLogInfo(@"activating socket in the background");

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
        OWSAssertDebug(self.backgroundKeepAliveUntilDate);
        OWSAssertDebug(self.backgroundKeepAliveTimer);
        OWSAssertDebug([self.backgroundKeepAliveTimer isValid]);

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

- (void)requestSocketOpen
{
    DispatchMainThreadSafe(^{
        [self observeNotificationsIfNecessary];

        // If the app is active and the user is registered, this will
        // simply open the websocket.
        //
        // If the app is inactive, it will open the websocket for a
        // period of time.
        [self requestSocketAliveForAtLeastSeconds:kKeepAliveDuration_Default];
    });
}

// This method aligns the socket state with the "desired" socket state.
- (void)applyDesiredSocketState
{
    OWSAssertIsOnMainThread();

#ifdef DEBUG
    if (CurrentAppContext().isRunningTests) {
        OWSLogWarn(@"Suppressing socket in tests.");
        return;
    }
#endif

    if (!AppReadiness.isAppReady) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            [AppReadiness runNowOrWhenAppDidBecomeReady:^{
                [self applyDesiredSocketState];
            }];
        });
        return;
    }

    if ([self shouldSocketBeOpen]) {
        if (self.state != OWSWebSocketStateOpen) {
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
    OWSAssertDebug([self shouldSocketBeOpen]);

    if (self.reconnectTimer) {
        OWSAssertDebug([self.reconnectTimer isValid]);
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

- (void)deviceListUpdateModifiedDeviceList:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();
    
    [self cycleSocket];
}

- (void)environmentDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();
    
    [self cycleSocket];
}

- (void)appExpiryDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self applyDesiredSocketState];
}

@end

NS_ASSUME_NONNULL_END
