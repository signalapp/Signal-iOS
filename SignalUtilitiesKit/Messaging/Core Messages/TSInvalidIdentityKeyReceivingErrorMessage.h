//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <SignalUtilitiesKit/TSInvalidIdentityKeyErrorMessage.h>

NS_ASSUME_NONNULL_BEGIN

@class SNProtoEnvelope;

// DEPRECATED - we no longer create new instances of this class (as of  mid-2017); However, existing instances may
// exist, so we should keep this class around to honor their old behavior.
__attribute__((deprecated)) @interface TSInvalidIdentityKeyReceivingErrorMessage : TSInvalidIdentityKeyErrorMessage

#ifdef DEBUG
+ (nullable instancetype)untrustedKeyWithEnvelope:(SNProtoEnvelope *)envelope
                                  withTransaction:(YapDatabaseReadWriteTransaction *)transaction;
#endif

@end

NS_ASSUME_NONNULL_END
