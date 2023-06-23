//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/TSErrorMessage.h>

NS_ASSUME_NONNULL_BEGIN

@class SignalServiceAddress;

@interface TSInvalidIdentityKeyErrorMessage : TSErrorMessage

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

- (BOOL)acceptNewIdentityKeyWithError:(NSError **)error;
- (void)throws_acceptNewIdentityKey NS_SWIFT_UNAVAILABLE("throws objc exceptions");
- (nullable NSData *)throws_newIdentityKey NS_SWIFT_UNAVAILABLE("throws objc exceptions");
- (SignalServiceAddress *)theirSignalAddress;

@end

NS_ASSUME_NONNULL_END
