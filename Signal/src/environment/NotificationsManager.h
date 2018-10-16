//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
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

#ifdef DEBUG

+ (void)presentDebugNotification;

#endif

@end

NS_ASSUME_NONNULL_END
