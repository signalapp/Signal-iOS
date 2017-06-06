//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSRecipientIdentity;
@class SignalCall;

@protocol OWSCallNotificationsAdaptee <NSObject>

- (void)presentIncomingCall:(SignalCall *)call callerName:(NSString *)callerName;

- (void)presentMissedCall:(SignalCall *)call callerName:(NSString *)callerName;

- (void)presentMissedCallBecauseOfNewIdentity:(SignalCall *)call
                                   callerName:(NSString *)callerName
    NS_SWIFT_NAME(presentMissedCallBecauseOfNewIdentity(call:callerName:));

- (void)presentMissedCallBecauseOfNoLongerVerifiedIdentity:(SignalCall *)call
                                                callerName:(NSString *)callerName
    NS_SWIFT_NAME(presentMissedCallBecauseOfNoLongerVerifiedIdentity(call:callerName:));

@end

NS_ASSUME_NONNULL_END
