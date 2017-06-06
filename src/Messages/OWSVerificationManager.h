//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kNSNotificationName_VerificationStateDidChange;

typedef NS_ENUM(NSUInteger, OWSVerificationState) {
    OWSVerificationStateDefault,
    OWSVerificationStateVerified,
    OWSVerificationStateNoLongerVerified,
};

// This class can be safely accessed and used from any thread.
@interface OWSVerificationManager : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)sharedManager;

- (void)setVerificationState:(OWSVerificationState)verificationState
              forPhoneNumber:(NSString *)phoneNumber
       isUserInitiatedChange:(BOOL)isUserInitiatedChange;

- (OWSVerificationState)verificationStateForPhoneNumber:(NSString *)phoneNumber;

@end

NS_ASSUME_NONNULL_END
