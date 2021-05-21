//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/SSKEnvironment.h>
#import <SignalServiceKit/TSSocketManager.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSSocketManager ()

@property (nonatomic) OWSWebSocket *websocket;

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

    _websocket = [[OWSWebSocket alloc] init];

    OWSSingletonAssert();

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)canMakeRequests
{
    return self.websocket.canMakeRequests;
}

- (void)makeRequest:(TSRequest *)request
            success:(TSSocketMessageSuccess)success
            failure:(TSSocketMessageFailure)failure
{
    [self.websocket makeRequest:request success:success failure:failure];
}

- (void)requestSocketOpen
{
    [self.websocket requestSocketOpen];
}

- (void)cycleSocket
{
    [self.websocket cycleSocket];
}

- (OWSWebSocketState)socketState
{
    return self.websocket.state;
}

- (BOOL)hasEmptiedInitialQueue
{
    return self.websocket.hasEmptiedInitialQueue;
}

@end

NS_ASSUME_NONNULL_END
