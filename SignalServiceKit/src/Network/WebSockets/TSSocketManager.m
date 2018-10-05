//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSSocketManager.h"
#import "SSKEnvironment.h"

NS_ASSUME_NONNULL_BEGIN

@interface TSSocketManager ()

@property (nonatomic) OWSWebSocket *websocketDefault;
@property (nonatomic) OWSWebSocket *websocketUD;

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

    _websocketDefault = [[OWSWebSocket alloc] initWithWebSocketType:OWSWebSocketTypeDefault];
    _websocketUD = [[OWSWebSocket alloc] initWithWebSocketType:OWSWebSocketTypeUD];

    OWSSingletonAssert();

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

+ (instancetype)shared
{
    OWSAssert(SSKEnvironment.shared.socketManager);

    return SSKEnvironment.shared.socketManager;
}

- (OWSWebSocket *)webSocketOfType:(OWSWebSocketType)webSocketType
{
    switch (webSocketType) {
        case OWSWebSocketTypeDefault:
            return self.websocketDefault;
        case OWSWebSocketTypeUD:
            return self.websocketUD;
    }
}

- (BOOL)canMakeRequestsOfType:(OWSWebSocketType)webSocketType
{
    return [self webSocketOfType:webSocketType].canMakeRequests;
}

- (void)makeRequest:(TSRequest *)request
      webSocketType:(OWSWebSocketType)webSocketType
            success:(TSSocketMessageSuccess)success
            failure:(TSSocketMessageFailure)failure
{
    [[self webSocketOfType:webSocketType] makeRequest:request success:success failure:failure];
}

- (void)requestSocketOpen
{
    [self.websocketDefault requestSocketOpen];
    [self.websocketUD requestSocketOpen];
}

- (void)cycleSocket
{
    [self.websocketDefault cycleSocket];
    [self.websocketUD cycleSocket];
}

- (OWSWebSocketState)highestSocketState
{
    if (self.websocketDefault.state == OWSWebSocketStateOpen || self.websocketUD.state == OWSWebSocketStateOpen) {
        return OWSWebSocketStateOpen;
    } else if (self.websocketDefault.state == OWSWebSocketStateConnecting
        || self.websocketUD.state == OWSWebSocketStateConnecting) {
        return OWSWebSocketStateConnecting;
    } else {
        return OWSWebSocketStateClosed;
    }
}

@end

NS_ASSUME_NONNULL_END
