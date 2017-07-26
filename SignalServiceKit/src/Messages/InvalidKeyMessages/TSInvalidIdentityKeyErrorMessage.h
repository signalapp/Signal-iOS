//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSErrorMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSFingerprint;

@interface TSInvalidIdentityKeyErrorMessage : TSErrorMessage

- (void)acceptNewIdentityKey;
- (nullable NSData *)newIdentityKey;
- (NSString *)theirSignalId;

@end

NS_ASSUME_NONNULL_END
