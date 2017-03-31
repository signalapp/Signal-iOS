//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SRWebSocket.h"

typedef enum : NSUInteger {
    kSocketStatusOpen,
    kSocketStatusClosed,
    kSocketStatusConnecting,
} SocketStatus;

static void *kSocketStatusObservationContext = &kSocketStatusObservationContext;

extern NSString *const SocketOpenedNotification;
extern NSString *const SocketClosedNotification;
extern NSString *const SocketConnectingNotification;

@interface TSSocketManager : NSObject <SRWebSocketDelegate>

- (instancetype)init NS_UNAVAILABLE;

+ (void)becomeActiveFromForeground;
+ (void)becomeActiveFromBackgroundExpectMessage:(BOOL)expected;

+ (void)resignActivity;
+ (void)sendNotification;

@end
