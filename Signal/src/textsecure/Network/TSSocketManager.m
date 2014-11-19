//
//  TSSocketManager.m
//  TextSecureiOS
//
//  Created by Frederic Jacobs on 17/05/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSConstants.h"
#import "TSAccountManager.h"
#import "TSMessagesManager.h"
#import "TSSocketManager.h"
#import "TSStorageManager+keyingMaterial.h"
#import <CocoaLumberjack/DDLog.h>

#define kWebSocketHeartBeat 15
#define ddLogLevel LOG_LEVEL_DEBUG

@interface TSSocketManager ()
@property (nonatomic, retain) NSTimer *timer;
@property (nonatomic, retain) SRWebSocket *websocket;
@end

@implementation TSSocketManager

- (id)init{
    self = [super init];
    
    if (self) {
        self.websocket = nil;
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

+ (void)becomeActive{
    SRWebSocket *socket =[[self sharedManager] websocket];
    
    if (socket) {
        switch ([socket readyState]) {
            case SR_OPEN:
                DDLogVerbose(@"WebSocket already open on connection request");
                return;
            case SR_CONNECTING:
                DDLogVerbose(@"WebSocket is already connecting");
                return;
            default:
                [socket close];
                socket.delegate = nil;
                socket = nil;
                break;
        }
    }
    
    NSString *webSocketConnect = [textSecureWebSocketAPI stringByAppendingString:[[self sharedManager] webSocketAuthenticationString]];
    NSURL *webSocketConnectURL = [NSURL URLWithString:webSocketConnect];
    socket = [[SRWebSocket alloc] initWithURL:webSocketConnectURL];
    socket.delegate = [self sharedManager];
    [socket open];
    [[self sharedManager] setWebsocket:socket];
}

+ (void)resignActivity{
    SRWebSocket *socket =[[self sharedManager] websocket];
    [socket close];
}

#pragma mark - Delegate methods

- (void) webSocketDidOpen:(SRWebSocket *)webSocket{
    NSLog(@"WebSocket was sucessfully opened");
    self.timer = [NSTimer scheduledTimerWithTimeInterval:kWebSocketHeartBeat target:self selector:@selector(webSocketHeartBeat) userInfo:nil repeats:YES];
}

- (void) webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error{
    NSLog(@"Error connecting to socket %@", error);
    [self.timer invalidate];
}

- (void) webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)message{
    NSData *data    = [message dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error  = nil;
    
    NSDictionary *serializedMessage = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    NSString *base64message = [serializedMessage objectForKey:@"message"];
    
    
    if (!base64message || error) {
        NSLog(@"WTF?!");
        return;
    }
    
    [[TSMessagesManager sharedManager] handleBase64MessageSignal:base64message];
    
    
    NSString *ackedId = [serializedMessage objectForKey:@"id"];
    [self.websocket send:[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:@{@"type":@"1", @"id":ackedId} options:0 error:nil] encoding:NSUTF8StringEncoding]];
}

- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean{
    DDLogVerbose(@"WebSocket did close");
    [self.timer invalidate];
}

- (void)webSocketHeartBeat{
    DDLogVerbose(@"WebSocket sent ping");
    [self.websocket sendPing:nil];
}

- (NSString*)webSocketAuthenticationString{
    return [NSString stringWithFormat:@"?login=%@&password=%@", [[TSAccountManager registeredNumber] stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"],[TSStorageManager serverAuthToken]];
}

@end
