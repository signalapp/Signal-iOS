//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SRWebSocket.h"

static void *kSocketStatusObservationContext = &kSocketStatusObservationContext;

extern NSString *const SocketOpenedNotification;
extern NSString *const SocketClosedNotification;
extern NSString *const SocketConnectingNotification;

@interface TSSocketManager : NSObject <SRWebSocketDelegate>

- (instancetype)init NS_UNAVAILABLE;

// If the app is in the foreground, we'll try to open the socket unless it's already
// open or connecting.
//
// If the app is in the background, we'll try to open the socket unless it's already
// open or connecting _and_ keep it open for at least N seconds.
// If the app is in the background and the socket is already open or connecting this
// might prolong how long we keep the socket open.
//
// This method can be called from any thread.
+ (void)requestSocketOpen;

+ (void)sendNotification;

@end
