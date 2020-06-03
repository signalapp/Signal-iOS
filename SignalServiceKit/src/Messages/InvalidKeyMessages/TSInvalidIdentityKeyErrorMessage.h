//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "TSErrorMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSFingerprint;
@class SignalServiceAddress;

@interface TSInvalidIdentityKeyErrorMessage : TSErrorMessage

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithThread:(TSThread *)thread
             failedMessageType:(TSErrorMessageType)errorMessageType
                       address:(nullable SignalServiceAddress *)address NS_UNAVAILABLE;

- (void)throws_acceptNewIdentityKey NS_SWIFT_UNAVAILABLE("throws objc exceptions");
- (nullable NSData *)throws_newIdentityKey NS_SWIFT_UNAVAILABLE("throws objc exceptions");
- (SignalServiceAddress *)theirSignalAddress;

@end

NS_ASSUME_NONNULL_END
