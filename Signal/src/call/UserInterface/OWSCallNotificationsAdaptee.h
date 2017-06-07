//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class SignalCall;

@protocol OWSCallNotificationsAdaptee <NSObject>

- (void)presentIncomingCall:(SignalCall *)call callerName:(NSString *)callerName;

- (void)presentMissedCall:(SignalCall *)call callerName:(NSString *)callerName;

- (void)presentRejectedCallWithUnseenIdentityChange:(SignalCall *)call
                                         callerName:(NSString *)callerName
    NS_SWIFT_NAME(presentRejectedCallWithUnseenIdentityChange(_:callerName:));

@end

NS_ASSUME_NONNULL_END
