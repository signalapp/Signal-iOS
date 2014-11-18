//
//  Socket.m
//  Signal
//
//  Created by Dylan Bourgeois on 18/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "Socket.h"

NSString * const SocketOpenedNotification = @"SocketOpenedNotification";
NSString * const SocketClosedNotification = @"SocketClosedNotification";
NSString * const SocketConnectingNotification = @"SocketConnectingNotification";

@implementation Socket

-(instancetype)init
{
    if (self = [super init])
    {
        _status = kSocketStatusConnecting;
        [self addObserver:self forKeyPath:@"status" options:0 context:kSocketStatusObservationContext];
    }
    return self;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    
    if (context == kSocketStatusObservationContext)
    {
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
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}



@end
