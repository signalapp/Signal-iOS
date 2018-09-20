//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSCallNotificationsAdaptee.h"
#import <RelayServiceKit/NotificationsProtocol.h>

NS_ASSUME_NONNULL_BEGIN

@class FLContactsManager;
@class OWSPreferences;
@class SignalCall;
@class TSCall;
@class TSThread;

@interface NotificationsManager : NSObject <NotificationsProtocol, OWSCallNotificationsAdaptee>

- (void)clearAllNotifications;

#ifdef DEBUG

+ (void)presentDebugNotification;

#endif

@end

NS_ASSUME_NONNULL_END
