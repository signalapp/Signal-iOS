//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSRecipientIdentity;
@class RelayCall;

@protocol OWSCallNotificationsAdaptee <NSObject>

- (void)presentIncomingCall:(RelayCall *)call callerName:(NSString *)callerName;

- (void)presentMissedCall:(RelayCall *)call callerName:(NSString *)callerName;

- (void)presentMissedCallBecauseOfNewIdentity:(RelayCall *)call
                                   callerName:(NSString *)callerName
    NS_SWIFT_NAME(presentMissedCallBecauseOfNewIdentity(call:callerName:));

- (void)presentMissedCallBecauseOfNoLongerVerifiedIdentity:(RelayCall *)call
                                                callerName:(NSString *)callerName
    NS_SWIFT_NAME(presentMissedCallBecauseOfNoLongerVerifiedIdentity(call:callerName:));

@end

NS_ASSUME_NONNULL_END
