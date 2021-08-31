//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/OWSWebSocket.h>
#import "NSTimer+OWS.h"
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/Threading.h>
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/AppReadiness.h>
#import <SignalServiceKit/NotificationsProtocol.h>
#import <SignalServiceKit/OWSBackgroundTask.h>
#import <SignalServiceKit/OWSError.h>
#import <SignalServiceKit/OWSMessageManager.h>
#import <SignalServiceKit/OWSSignalService.h>
#import <SignalServiceKit/SSKEnvironment.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSConstants.h>
#import <SignalServiceKit/TSErrorMessage.h>
#import <SignalServiceKit/TSRequest.h>

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

NSString *NSStringForOWSWebSocketType(OWSWebSocketType value)
{
    switch (value) {
        case OWSWebSocketTypeIdentified:
            return @"Identified";
        case OWSWebSocketTypeUnidentified:
            return @"Unidentified";
    }
}

#pragma mark -

// OWSWebSocket's properties should only be accessed from the main thread.
//
// TODO: Port to Swift.
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
@property (atomic, nullable) NSDate *backgroundKeepAliveUntilDate;
// This timer is used to check periodically whether we should
// close the socket.
@property (nonatomic, nullable) NSTimer *backgroundKeepAliveTimer;
// This is used to manage the iOS "background task" used to
// keep the app alive in the background.
@property (nonatomic, nullable) OWSBackgroundTask *backgroundTask;

// We cache this value instead of consulting [UIApplication sharedApplication].applicationState,
// because UIKit only provides a "will resign active" notification, not a "did resign active"
// notification.
@property (atomic) BOOL appIsActive;

@property (nonatomic) BOOL hasObservedNotifications;

// This property should only be accessed while synchronized on the socket manager.
@property (nonatomic, readonly) NSMutableDictionary<NSNumber *, SocketMessageInfo *> *messageInfoMap;

@property (atomic) BOOL canMakeRequests;

@end

#pragma mark -

@implementation OWSWebSocket

- (instancetype)initWithWebSocketType:(OWSWebSocketType)webSocketType
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssertIsOnMainThread();

    _webSocketType = webSocketType;
    _state = OWSWebSocketStateClosed;
    _hasEmptiedInitialQueue = NO;
    _willEmptyInitialQueue = NO;
    _messageInfoMap = [NSMutableDictionary new];

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
                                                 name:NSNotificationNameRegistrationStateDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(isCensorshipCircumventionActiveDidChange:)
                                                 name:kNSNotificationName_IsCensorshipCircumventionActiveDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(deviceListUpdateModifiedDeviceList:)
                                                 name:OWSDevicesService.deviceListUpdateModifiedDeviceList
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

    OWSLogWarn(@"Creating new websocket: %@", NSStringForOWSWebSocketType(self.webSocketType));

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

    OWSLogWarn(@"Socket state[%@]: %@ -> %@",
        NSStringForOWSWebSocketType(self.webSocketType),
        [self stringFromOWSWebSocketState:_state],
        [self stringFromOWSWebSocketState:state]);

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
            //
            // TODO: Use the unidentified URL for unidentified websockets.
            NSString *webSocketConnect = [TSConstants.mainServiceWebSocketAPI_identified
                stringByAppendingString:[self webSocketAuthenticationString]];
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
        OWSLogWarn(@"closeWebSocket: %@,", NSStringForOWSWebSocketType(self.webSocketType));
    }

    self.state = OWSWebSocketStateClosed;
}

#pragma mark - Message Sending

- (void)makeRequestInternal:(TSRequest *)request
                    success:(TSSocketMessageSuccess)success
                    failure:(TSSocketMessageFailure)failure
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

    SocketMessageInfo *messageInfo = [[SocketMessageInfo alloc] initWithRequest:request
                                                                     requestUrl:request.URL
                                                                        success:success
                                                                        failure:failure];

    @synchronized(self) {
        self.messageInfoMap[@(messageInfo.requestId)] = messageInfo;
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
            [messageInfo didFailInvalidRequest];
            return;
        }
    }

    OWSHttpHeaders *httpHeaders = [OWSHttpHeaders new];
    [httpHeaders addHeaders:request.allHTTPHeaderFields overwriteOnConflict:NO];

    WebSocketProtoWebSocketRequestMessageBuilder *requestBuilder =
        [WebSocketProtoWebSocketRequestMessage builderWithVerb:request.HTTPMethod
                                                          path:requestPath
                                                     requestID:messageInfo.requestId];
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
        [messageInfo didFailInvalidRequest];
        return;
    }

    if (!self.canMakeRequests) {
        OWSLogError(@"makeRequest[%@]: socket not open.", NSStringForOWSWebSocketType(self.webSocketType));
        [messageInfo didFailDueToNetwork];
        return;
    }

    [self.websocket writeData:messageData];
    OWSLogInfo(@"making request[%@]: %llu, %@: %@, jsonData.length: %zd, socketType: %@",
        NSStringForOWSWebSocketType(self.webSocketType),
        messageInfo.requestId,
        request.HTTPMethod,
        requestPath,
        jsonData.length,
        NSStringForOWSWebSocketType(self.webSocketType));

    const int64_t kSocketTimeoutSeconds = 10;
    __weak SocketMessageInfo *weakMessageInfo = messageInfo;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kSocketTimeoutSeconds * NSEC_PER_SEC),
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
        ^{ [weakMessageInfo timeoutIfNecessary]; });
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

    OWSLogInfo(@"received WebSocket response[%@], requestId: %llu, status: %u",
        NSStringForOWSWebSocketType(self.webSocketType),
        message.requestID,
        message.status);

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

    OWSHttpHeaders *headers = [OWSWebSocket parseServiceHeaders:message.headers];

    SocketMessageInfo *_Nullable messageInfo;
    @synchronized(self) {
        messageInfo = self.messageInfoMap[@(requestId)];
        [self.messageInfoMap removeObjectForKey:@(requestId)];
    }

    if (!messageInfo) {
        OWSLogError(@"Received response to unknown request: %@.", NSStringForOWSWebSocketType(self.webSocketType));
    } else {
        BOOL hasSuccessStatus = 200 <= responseStatus && responseStatus <= 299;
        BOOL didSucceed = hasSuccessStatus;
        if (didSucceed) {
            [self.tsAccountManager setIsDeregistered:NO];

            [messageInfo didSucceedWithStatus:responseStatus
                                      headers:headers
                                     bodyData:responseData
                                      message:responseMessage];
        } else {
            if (self.webSocketType == OWSWebSocketTypeUnidentified) {
                // We should never get 403 from the UD socket.
                OWSAssertDebug(responseStatus != 403);
            }
            if (responseStatus == 403 && self.webSocketType == OWSWebSocketTypeIdentified) {
                // This should be redundant with our check for the socket
                // failing due to 403, but let's be thorough.
                if (self.tsAccountManager.isRegisteredAndReady) {
                    [self.tsAccountManager setIsDeregistered:YES];
                } else {
                    OWSFailDebug(@"Ignoring auth failure; not registered and ready.");
                }
            }

            [messageInfo didFailWithResponseStatus:responseStatus
                                   responseHeaders:headers
                                     responseError:nil
                                      responseData:responseData];
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
    NSArray<SocketMessageInfo *> *messageInfos;
    @synchronized(self) {
        messageInfos = self.messageInfoMap.allValues;
        [self.messageInfoMap removeAllObjects];
    }

    OWSLogInfo(@"failAllPendingSocketMessages[%@]: %lu.",
        NSStringForOWSWebSocketType(self.webSocketType),
        (unsigned long)messageInfos.count);

    for (SocketMessageInfo *messageInfo in messageInfos) {
        [messageInfo didFailDueToNetwork];
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

    OWSLogInfo(@"%@.", NSStringForOWSWebSocketType(self.webSocketType));

    OWSLogWarn(@"Websocket did fail with error[%@]: %@", NSStringForOWSWebSocketType(self.webSocketType), error);
    if ([error.domain isEqualToString:SSKWebSocketError.errorDomain]) {
        NSNumber *_Nullable statusCode = error.userInfo[SSKWebSocketError.kStatusCodeKey];
        if (statusCode.unsignedIntegerValue == 403 && self.webSocketType == OWSWebSocketTypeIdentified) {
            if (self.tsAccountManager.isRegisteredAndReady) {
                [self.tsAccountManager setIsDeregistered:YES];
            } else {
                OWSLogWarn(@"Ignoring auth failure; not registered and ready: %@.",
                    NSStringForOWSWebSocketType(self.webSocketType));
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

    OWSLogInfo(@"Got message[%@], verb: %@, path: %@",
        NSStringForOWSWebSocketType(self.webSocketType),
        message.verb,
        message.path);

    // If we receive a message over the socket while the app is in the background,
    // prolong how long the socket stays open.
    [self requestSocketAliveForAtLeastSeconds:kKeepAliveDuration_ReceiveMessage];

    if ([message.path isEqualToString:@"/api/v1/message"] && [message.verb isEqualToString:@"PUT"]) {

        __block OWSBackgroundTask *_Nullable backgroundTask =
            [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

        dispatch_async(self.serialQueue, ^{
            if (self.verboseLogging) {
                OWSLogInfo(@"%@ 1", NSStringForOWSWebSocketType(self.webSocketType));
            }

            void (^ackMessage)(BOOL success) = ^void(BOOL success) {
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
            };

            uint64_t serverDeliveryTimestamp = 0;
            for (NSString *header in message.headers) {
                if ([header hasPrefix:@"X-Signal-Timestamp:"]) {
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

            NSData *_Nullable encryptedEnvelope = message.body;

            if (!encryptedEnvelope) {
                OWSLogWarn(@"Missing encrypted envelope on message");
                ackMessage(NO);
            } else {
                EnvelopeSource envelopeSource;
                switch (self.webSocketType) {
                    case OWSWebSocketTypeIdentified:
                        envelopeSource = EnvelopeSourceWebsocketIdentified;
                    case OWSWebSocketTypeUnidentified:
                        envelopeSource = EnvelopeSourceWebsocketUnidentified;
                }
                if (self.verboseLogging) {
                    OWSLogInfo(@"%@ 2", NSStringForOWSWebSocketType(self.webSocketType));
                }
                [MessageProcessor.shared
                    processEncryptedEnvelopeData:encryptedEnvelope
                               encryptedEnvelope:nil
                         serverDeliveryTimestamp:serverDeliveryTimestamp
                                  envelopeSource:envelopeSource
                                      completion:^(NSError *error) {
                                          if (self.verboseLogging) {
                                              OWSLogInfo(@"%@ 3", NSStringForOWSWebSocketType(self.webSocketType));
                                          }
                                          ackMessage(YES);
                                      }];
            }
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
        OWSLogWarn(@"Unsupported WebSocket Request: %@.", NSStringForOWSWebSocketType(self.webSocketType));

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
            OWSLogWarn(@"Error[%@]: %@", NSStringForOWSWebSocketType(self.webSocketType), error);
        } else {
            OWSFailDebug(@"Error[%@]: %@", NSStringForOWSWebSocketType(self.webSocketType), error);
        }
    }
}

- (BOOL)verboseLogging
{
    return OWSWebSocket.verboseLogging;
}

+ (BOOL)verboseLogging
{
    return SSKDebugFlags.internalLogging;
}

- (void)cycleSocket
{
    OWSAssertIsOnMainThread();

    if (self.verboseLogging) {
        OWSLogInfo(@"%@.", NSStringForOWSWebSocketType(self.webSocketType));
    }

    [self closeWebSocket];

    [self applyDesiredSocketState];
}

- (void)handleSocketFailure
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"%@.", NSStringForOWSWebSocketType(self.webSocketType));

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
        OWSLogWarn(@"webSocketHeartBeat closing web socket: %@.", NSStringForOWSWebSocketType(self.webSocketType));
        [self closeWebSocket];
        [self applyDesiredSocketState];
    }
}

- (NSString *)webSocketAuthenticationString
{
    switch (self.webSocketType) {
        case OWSWebSocketTypeUnidentified:
            // UD socket is unauthenticated.
            return @"";
        case OWSWebSocketTypeIdentified: {
            NSString *login = [self.tsAccountManager.storedServerUsername stringByReplacingOccurrencesOfString:@"+"
                                                                                                    withString:@"%2B"];
            return [NSString
                stringWithFormat:@"?login=%@&password=%@", login, self.tsAccountManager.storedServerAuthToken];
        }
    }
}

#pragma mark - Socket LifeCycle

- (BOOL)shouldSocketBeOpen
{
    // Don't open socket in app extensions.
    if (!CurrentAppContext().isMainApp) {
        if (SSKFeatureFlags.deprecateREST) {
            // If we've deprecated REST, we _do_ want to open both websockets in the app extensions.
        } else {
            if (self.verboseLogging) {
                OWSLogInfo(@"%@ 1", NSStringForOWSWebSocketType(self.webSocketType));
            }
            return NO;
        }
    }

    if (!AppReadiness.isAppReady) {
        if (self.verboseLogging) {
            OWSLogInfo(@"%@ 2", NSStringForOWSWebSocketType(self.webSocketType));
        }
        return NO;
    }

    if (![self.tsAccountManager isRegisteredAndReady]) {
        if (SSKFeatureFlags.deprecateREST && self.webSocketType == OWSWebSocketTypeUnidentified) {
            // If we've deprecated REST, we _do_ want to open the unidentified websocket
            // before the user is registered.
        } else {
            if (self.verboseLogging) {
                OWSLogInfo(@"%@ 3", NSStringForOWSWebSocketType(self.webSocketType));
            }
            return NO;
        }
    }

    if (AppExpiry.shared.isExpired) {
        if (self.verboseLogging) {
            OWSLogInfo(@"%@ 4", NSStringForOWSWebSocketType(self.webSocketType));
        }
        return NO;
    }

    if (self.signalService.isCensorshipCircumventionActive) {
        OWSLogWarn(@"Skipping opening of websocket due to censorship circumvention.");
        if (SSKFeatureFlags.deprecateREST) {
            // If we've deprecated REST, we _do_ want to open both websockets when using CC.
        } else {
            if (self.verboseLogging) {
                OWSLogInfo(@"%@ 5", NSStringForOWSWebSocketType(self.webSocketType));
            }
            return NO;
        }
    }

    // TODO: We need to revisit the websocket behavior for the NSE.
    NSDate *_Nullable backgroundKeepAliveUntilDate = self.backgroundKeepAliveUntilDate;
    if (self.appIsActive) {
        // If app is active, keep web socket alive.
        if (self.verboseLogging) {
            OWSLogInfo(@"%@ 6", NSStringForOWSWebSocketType(self.webSocketType));
        }
        return YES;
    } else if (SSKDebugFlags.keepWebSocketOpenInBackground) {
        if (self.verboseLogging) {
            OWSLogInfo(@"%@ 7", NSStringForOWSWebSocketType(self.webSocketType));
        }
        return YES;
    } else if (backgroundKeepAliveUntilDate && [backgroundKeepAliveUntilDate timeIntervalSinceNow] > 0.f) {
        OWSAssertDebug(self.backgroundKeepAliveTimer);
        // If app is doing any work in the background, keep web socket alive.
        if (self.verboseLogging) {
            OWSLogInfo(@"%@ 8", NSStringForOWSWebSocketType(self.webSocketType));
        }
        return YES;
    } else {
        if (self.verboseLogging) {
            OWSLogInfo(@"%@ 9", NSStringForOWSWebSocketType(self.webSocketType));
        }
        return NO;
    }
}

- (void)requestSocketAliveForAtLeastSeconds:(NSTimeInterval)durationSeconds
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(durationSeconds > 0.f);

    NSDate *_Nullable backgroundKeepAliveUntilDate = self.backgroundKeepAliveUntilDate;
    if (self.appIsActive) {
        // If app is active, clean up state used to keep socket alive in background.
        [self clearBackgroundState];
    } else if (!backgroundKeepAliveUntilDate) {
        OWSAssertDebug(!self.backgroundKeepAliveTimer);

        OWSLogInfo(@"Activating socket in the background: %@.", NSStringForOWSWebSocketType(self.webSocketType));

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
                                              if (strongSelf.verboseLogging) {
                                                  OWSLogInfo(
                                                      @"%@.", NSStringForOWSWebSocketType(strongSelf.webSocketType));
                                              }
                                              [strongSelf applyDesiredSocketState];
                                          }];
    } else {
        OWSAssertDebug(self.backgroundKeepAliveTimer);
        OWSAssertDebug([self.backgroundKeepAliveTimer isValid]);

        if ([backgroundKeepAliveUntilDate timeIntervalSinceNow] < durationSeconds) {
            // Update state used to keep socket alive in background.
            self.backgroundKeepAliveUntilDate = [NSDate dateWithTimeIntervalSinceNow:durationSeconds];
        }
    }

    if (self.verboseLogging) {
        OWSLogInfo(@"%@.", NSStringForOWSWebSocketType(self.webSocketType));
    }

    [self applyDesiredSocketState];
}

- (void)backgroundKeepAliveFired
{
    OWSAssertIsOnMainThread();

    if (self.verboseLogging) {
        OWSLogInfo(@"%@.", NSStringForOWSWebSocketType(self.webSocketType));
    }

    [self applyDesiredSocketState];
}

- (void)requestSocketOpen
{
    if (self.verboseLogging) {
        OWSLogInfo(@"%@. 1", NSStringForOWSWebSocketType(self.webSocketType));
    }
    DispatchMainThreadSafe(^{
        if (self.verboseLogging) {
            OWSLogInfo(@"%@. 2", NSStringForOWSWebSocketType(self.webSocketType));
        }
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

#if DEBUG || TESTABLE_BUILD
    if (CurrentAppContext().isRunningTests) {
        OWSLogWarn(@"Suppressing socket in tests.");
        return;
    }
#endif

    if (!AppReadiness.isAppReady) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                    ^{ [self applyDesiredSocketState]; });
            });
        });
        return;
    }

    BOOL shouldSocketBeOpen = self.shouldSocketBeOpen;
    if (self.verboseLogging) {
        OWSLogInfo(@"%@, shouldSocketBeOpen: %d", NSStringForOWSWebSocketType(self.webSocketType), shouldSocketBeOpen);
    }
    if (shouldSocketBeOpen) {
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

    if (self.verboseLogging) {
        OWSLogInfo(@"%@.", NSStringForOWSWebSocketType(self.webSocketType));
    }

    self.appIsActive = YES;
    [self applyDesiredSocketState];
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    self.appIsActive = NO;

    if (self.verboseLogging) {
        OWSLogInfo(@"%@.", NSStringForOWSWebSocketType(self.webSocketType));
    }

    // TODO: It might be nice to use `requestSocketAliveForAtLeastSeconds:` to
    //       keep the socket open for a few seconds after the app is
    //       inactivated.
    [self applyDesiredSocketState];
}

- (void)registrationStateDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    if (self.verboseLogging) {
        OWSLogInfo(@"%@.", NSStringForOWSWebSocketType(self.webSocketType));
    }

    [self applyDesiredSocketState];
}

- (void)isCensorshipCircumventionActiveDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    if (self.verboseLogging) {
        OWSLogInfo(@"%@.", NSStringForOWSWebSocketType(self.webSocketType));
    }

    [self applyDesiredSocketState];
}

- (void)deviceListUpdateModifiedDeviceList:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    if (self.webSocketType == OWSWebSocketTypeIdentified) {
        [self cycleSocket];
    }
}

- (void)environmentDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();
    
    [self cycleSocket];
}

- (void)appExpiryDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    if (self.verboseLogging) {
        OWSLogInfo(@"%@.", NSStringForOWSWebSocketType(self.webSocketType));
    }

    [self applyDesiredSocketState];
}

@end

NS_ASSUME_NONNULL_END
