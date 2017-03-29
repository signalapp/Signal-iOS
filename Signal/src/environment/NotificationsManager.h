//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSCallNotificationsAdaptee.h"
#import <SignalServiceKit/NotificationsProtocol.h>

NS_ASSUME_NONNULL_BEGIN

@class TSCall;
@class TSContactThread;
@class OWSContactsManager;
@class SignalCall;
@class PropertyListPreferences;

@interface NotificationsManager : NSObject <NotificationsProtocol, OWSCallNotificationsAdaptee>

@end

NS_ASSUME_NONNULL_END
