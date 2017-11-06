//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSCallNotificationsAdaptee.h"
#import <SignalServiceKit/NotificationsProtocol.h>

NS_ASSUME_NONNULL_BEGIN

@class OWSContactsManager;
@class OWSPreferences;
@class SignalCall;
@class TSCall;
@class TSContactThread;

@interface NotificationsManager : NSObject <NotificationsProtocol, OWSCallNotificationsAdaptee>

- (void)clearAllNotifications;

@end

NS_ASSUME_NONNULL_END
