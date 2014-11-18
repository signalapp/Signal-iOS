//
//  Socket.h
//  Signal
//
//  Created by Dylan Bourgeois on 18/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

typedef enum : NSUInteger {
    kSocketStatusOpen,
    kSocketStatusClosed,
    kSocketStatusConnecting,
} SocketStatus;

static void *kSocketStatusObservationContext = &kSocketStatusObservationContext;

extern NSString * const SocketOpenedNotification;
extern NSString * const SocketClosedNotification;
extern NSString * const SocketConnectingNotification;



#import <Foundation/Foundation.h>

@interface Socket : NSObject

@property (nonatomic) SocketStatus status;

@end
