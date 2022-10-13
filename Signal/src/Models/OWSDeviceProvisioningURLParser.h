//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@interface OWSDeviceProvisioningURLParser : NSObject

@property (readonly, getter=isValid) BOOL valid;
@property (nonatomic, readonly, nullable) NSString *ephemeralDeviceId;
@property (nonatomic, readonly, nullable) NSData *publicKey;

- (instancetype)initWithProvisioningURL:(NSString *)provisioningURL;

@end

NS_ASSUME_NONNULL_END
