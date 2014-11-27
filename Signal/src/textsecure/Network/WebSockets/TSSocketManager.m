//
//  TSSocketManager.m
//  TextSecureiOS
//
//  Created by Frederic Jacobs on 17/05/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "SubProtocol.pb.h"

#import "TSConstants.h"
#import "TSAccountManager.h"
#import "TSMessagesManager.h"
#import "TSSocketManager.h"
#import "TSStorageManager+keyingMaterial.h"
#import <CocoaLumberjack/DDLog.h>

#import "NSData+Base64.h"
#import "Cryptography.h"
#import "IncomingPushMessageSignal.pb.h"

#define kWebSocketHeartBeat    15
#define kWebSocketReconnectTry 5

NSString * const SocketOpenedNotification     = @"SocketOpenedNotification";
NSString * const SocketClosedNotification     = @"SocketClosedNotification";
NSString * const SocketConnectingNotification = @"SocketConnectingNotification";

@interface TSSocketManager ()
@property (nonatomic, retain) NSTimer *pingTimer;
@property (nonatomic, retain) NSTimer *reconnectTimer;

@property (nonatomic, retain) SRWebSocket *websocket;
@property (nonatomic) SocketStatus status;
@end

@implementation TSSocketManager

- (id)init{
    self = [super init];
    
    if (self) {
        self.websocket = nil;
        [self addObserver:self forKeyPath:@"status" options:0 context:kSocketStatusObservationContext];
    }
    
    return self;
}

+ (id)sharedManager {
    static TSSocketManager *sharedMyManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMyManager = [[self alloc] init];
    });
    return sharedMyManager;
}

#pragma mark - Manage Socket

+ (void)becomeActive {
    TSSocketManager *sharedInstance = [self sharedManager];
    SRWebSocket *socket             = [sharedInstance websocket];
    
    if (socket) {
        switch ([socket readyState]) {
            case SR_OPEN:
                DDLogVerbose(@"WebSocket already open on connection request");
                sharedInstance.status = kSocketStatusOpen;
                return;
            case SR_CONNECTING:
                DDLogVerbose(@"WebSocket is already connecting");
                sharedInstance.status = kSocketStatusConnecting;
                return;
            default:
                [socket close];
                sharedInstance.status = kSocketStatusClosed;
                socket.delegate = nil;
                socket = nil;
                break;
        }
    }
    
    NSString *webSocketConnect = [textSecureWebSocketAPI stringByAppendingString:[[self sharedManager] webSocketAuthenticationString]];
    NSURL *webSocketConnectURL = [NSURL URLWithString:webSocketConnect];
    socket                     = [[SRWebSocket alloc] initWithURL:webSocketConnectURL];
    socket.delegate            = [self sharedManager];
    [socket open];
    [[self sharedManager] setWebsocket:socket];
}

+ (void)resignActivity{
    SRWebSocket *socket = [[self sharedManager] websocket];
    [socket close];
}

#pragma mark - Delegate methods

- (void) webSocketDidOpen:(SRWebSocket *)webSocket {
    self.pingTimer  = [NSTimer scheduledTimerWithTimeInterval:kWebSocketHeartBeat target:self selector:@selector(webSocketHeartBeat) userInfo:nil repeats:YES];
    self.status     = kSocketStatusOpen;
    
    [self.reconnectTimer invalidate];
    self.reconnectTimer = nil;
}

- (void) webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error {
    DDLogError(@"Error connecting to socket %@", error);
    [self.pingTimer invalidate];
    self.status = kSocketStatusClosed;
    [self scheduleRetry];
}

- (void) webSocket:(SRWebSocket *)webSocket didReceiveMessage:(NSData*)data {
    WebSocketMessage *wsMessage = [WebSocketMessage parseFromData:data];
    
    if (wsMessage.type == WebSocketMessageTypeRequest) {
        [self processWebSocketRequestMessage:wsMessage.request];
    } else if (wsMessage.type == WebSocketMessageTypeResponse){
        [self processWebSocketResponseMessage:wsMessage.response];
    } else{
        DDLogWarn(@"Got a WebSocketMessage of unknown type");
    }
}

- (void)processWebSocketRequestMessage:(WebSocketRequestMessage*)message {
    DDLogInfo(@"Got message with verb: %@ and path: %@", message.verb, message.path);
    
    [self sendWebSocketMessageAcknowledgement:message];
    
    if ([message.path isEqualToString:@"/api/v1/message"] && [message.verb isEqualToString:@"PUT"]){
        
        NSString *base64String   = [[NSString alloc] initWithData:message.body encoding:NSUTF8StringEncoding];
        
        NSData *encryptedSignal  = [NSData dataFromBase64String:base64String];
        NSData *decryptedPayload = [Cryptography decryptAppleMessagePayload:encryptedSignal
                                                           withSignalingKey:TSStorageManager.signalingKey];
        
        if (!decryptedPayload) {
            DDLogWarn(@"Failed to decrypt incoming payload or bad HMAC");
            return;
        }
        
        IncomingPushMessageSignal *messageSignal = [IncomingPushMessageSignal parseFromData:decryptedPayload];
        
        [[TSMessagesManager sharedManager] handleMessageSignal:messageSignal];
    } else{
        DDLogWarn(@"Unsupported WebSocket Request");
    }
}

- (void)processWebSocketResponseMessage:(WebSocketResponseMessage*)message {
    DDLogWarn(@"Client should not receive WebSocket Respond messages");
}

- (void)sendWebSocketMessageAcknowledgement:(WebSocketRequestMessage*)request {
    WebSocketResponseMessageBuilder *response = [WebSocketResponseMessage builder];
    [response setStatus:200];
    [response setMessage:@"OK"];
    [response setId:request.id];
    
    WebSocketMessageBuilder *message = [WebSocketMessage builder];
    [message setResponse:response.build];
    [message setType:WebSocketMessageTypeResponse];
    
    @try {
        [self.websocket send:message.build.data];
    }
    @catch (NSException *exception) {
        DDLogWarn(@"Caught exception while trying to write on the socket %@", exception.debugDescription);
    }
}

- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean {
    DDLogVerbose(@"WebSocket did close");
    [self.pingTimer invalidate];
    self.status = kSocketStatusClosed;
    [self scheduleRetry];
}

- (void)webSocketHeartBeat {
    @try {
        [self.websocket sendPing:nil];
    }
    @catch (NSException *exception) {
        DDLogWarn(@"Caught exception while trying to write on the socket %@", exception.debugDescription);
    }
}

- (NSString*)webSocketAuthenticationString{
    return [NSString stringWithFormat:@"?login=%@&password=%@", [[TSAccountManager registeredNumber] stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"],[TSStorageManager serverAuthToken]];
}

- (void)scheduleRetry{
    if (!self.reconnectTimer || ![self.reconnectTimer isValid]) {
        self.reconnectTimer = [NSTimer scheduledTimerWithTimeInterval:kWebSocketReconnectTry target:[self class] selector:@selector(becomeActive) userInfo:nil repeats:YES];
    }
}

#pragma mark UI Delegates

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == kSocketStatusObservationContext)
    {
        [self notifyStatusChange];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)notifyStatusChange{
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

+ (void)sendNotification{
    [[self sharedManager] notifyStatusChange];
}

@end
