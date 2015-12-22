//
//  NotificationsProtocol.h
//  Pods
//
//  Created by Frederic Jacobs on 05/12/15.
//
//

#import <Foundation/Foundation.h>

@class TSErrorMessage;
@class TSIncomingMessage;
@class TSThread;

@protocol NotificationsProtocol <NSObject>

- (void)notifyUserForIncomingMessage:(TSIncomingMessage *)incomingMessage
                                from:(NSString *)name
                            inThread:(TSThread *)thread;

- (void)notifyUserForErrorMessage:(TSErrorMessage *)error inThread:(TSThread *)thread;

@end
