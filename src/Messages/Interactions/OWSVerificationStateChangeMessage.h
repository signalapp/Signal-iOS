//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSRecipientIdentity.h"
#import "TSInfoMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class TSThread;

@interface OWSVerificationStateChangeMessage : TSInfoMessage

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                           thread:(TSThread *)thread
                verificationState:(OWSVerificationState)verificationState
                    isLocalChange:(BOOL)isLocalChange;

@end

NS_ASSUME_NONNULL_END
