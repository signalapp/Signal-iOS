//
//  NotificationsManager.h
//  Signal
//
//  Created by Frederic Jacobs on 22/12/15.
//  Copyright © 2015 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <TextSecureKit/NotificationsProtocol.h>

@class TSCall;

@interface NotificationsManager : NSObject <NotificationsProtocol>

- (void)notifyUserForCall:(TSCall *)call inThread:(TSThread *)thread;

@end
