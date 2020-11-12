//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface OWSDeviceProvisioningURLParser : NSObject

@property (readonly, getter=isValid) BOOL valid;
@property (nonatomic, readonly, nullable) NSString *ephemeralDeviceId;
@property (nonatomic, readonly, nullable) NSData *publicKey;

- (instancetype)initWithProvisioningURL:(NSString *)provisioningURL;

@end

NS_ASSUME_NONNULL_END
