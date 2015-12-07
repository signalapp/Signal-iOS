//
//  TSSocketManager.h
//  TextSecureiOS
//
//  Created by Frederic Jacobs on 17/05/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
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

+ (void)becomeActiveFromForeground;
+ (void)becomeActiveFromBackgroundExpectMessage:(BOOL)expected;

+ (void)resignActivity;
+ (void)sendNotification;

@end
