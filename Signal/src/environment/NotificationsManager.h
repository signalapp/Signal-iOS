//  Created by Frederic Jacobs on 22/12/15.
//  Copyright © 2015 Open Whisper Systems. All rights reserved.

#import "OWSCallNotificationsAdaptee.h"
#import <SignalServiceKit/NotificationsProtocol.h>

NS_ASSUME_NONNULL_BEGIN

@class TSCall;
@class TSContactThread;
@class OWSContactsManager;
@class SignalCall;
@class PropertyListPreferences;

@interface NotificationsManager : NSObject <NotificationsProtocol, OWSCallNotificationsAdaptee>

#pragma mark - RedPhone Call Notifications

- (void)notifyUserForCall:(TSCall *)call inThread:(TSThread *)thread;

@end

NS_ASSUME_NONNULL_END
