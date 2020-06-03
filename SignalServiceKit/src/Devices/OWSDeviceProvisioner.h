//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSDeviceProvisioningCodeService;
@class OWSDeviceProvisioningService;
@class SignalServiceAddress;

@interface OWSDeviceProvisioner : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithMyPublicKey:(NSData *)myPublicKey
                       myPrivateKey:(NSData *)myPrivateKey
                     theirPublicKey:(NSData *)theirPublicKey
             theirEphemeralDeviceId:(NSString *)ephemeralDeviceId
                     accountAddress:(SignalServiceAddress *)accountAddress
                         profileKey:(NSData *)profileKey
                readReceiptsEnabled:(BOOL)areReadReceiptsEnabled
            provisioningCodeService:(OWSDeviceProvisioningCodeService *)provisioningCodeService
                provisioningService:(OWSDeviceProvisioningService *)provisioningService NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithMyPublicKey:(NSData *)myPublicKey
                       myPrivateKey:(NSData *)myPrivateKey
                     theirPublicKey:(NSData *)theirPublicKey
             theirEphemeralDeviceId:(NSString *)ephemeralDeviceId
                     accountAddress:(SignalServiceAddress *)accountAddress
                         profileKey:(NSData *)profileKey
                readReceiptsEnabled:(BOOL)areReadReceiptsEnabled;

- (void)provisionWithSuccess:(void (^)(void))successCallback failure:(void (^)(NSError *))failureCallback;

@end

NS_ASSUME_NONNULL_END
