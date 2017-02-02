//  Created by Michael Kirk on 12/28/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

NS_ASSUME_NONNULL_BEGIN

@class SignalCall;

@protocol OWSCallNotificationsAdaptee <NSObject>

- (void)presentIncomingCall:(SignalCall *)call callerName:(NSString *)callerName;

- (void)presentMissedCall:(SignalCall *)call callerName:(NSString *)callerName;

@end

NS_ASSUME_NONNULL_END
