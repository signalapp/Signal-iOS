//  Copyright © 2016 Open Whisper Systems. All rights reserved.

NS_ASSUME_NONNULL_BEGIN

@interface OWSDeviceProvisioningURLParser : NSObject

@property (readonly, getter=isValid) BOOL valid;
@property (nonatomic, readonly) NSString *ephemeralDeviceId;
@property (nonatomic, readonly) NSData *publicKey;

- (instancetype)initWithProvisioningURL:(NSString *)provisioningURL;

@end

NS_ASSUME_NONNULL_END
