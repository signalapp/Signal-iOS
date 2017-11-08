//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSDeviceProvisioningCodeService;
@class OWSDeviceProvisioningService;

@interface OWSDeviceProvisioner : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithMyPublicKey:(NSData *)myPublicKey
                       myPrivateKey:(NSData *)myPrivateKey
                     theirPublicKey:(NSData *)theirPublicKey
             theirEphemeralDeviceId:(NSString *)ephemeralDeviceId
                  accountIdentifier:(NSString *)accountIdentifier
                         profileKey:(NSData *)profileKey
                readReceiptsEnabled:(BOOL)areReadReceiptsEnabled
            provisioningCodeService:(OWSDeviceProvisioningCodeService *)provisioningCodeService
                provisioningService:(OWSDeviceProvisioningService *)provisioningService NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithMyPublicKey:(NSData *)myPublicKey
                       myPrivateKey:(NSData *)myPrivateKey
                     theirPublicKey:(NSData *)theirPublicKey
             theirEphemeralDeviceId:(NSString *)ephemeralDeviceId
                  accountIdentifier:(NSString *)accountIdentifier
                         profileKey:(NSData *)profileKey
                readReceiptsEnabled:(BOOL)areReadReceiptsEnabled;

- (void)provisionWithSuccess:(void (^)(void))successCallback failure:(void (^)(NSError *))failureCallback;

@end

NS_ASSUME_NONNULL_END
