//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSDeviceProvisioner.h"
#import "OWSDeviceProvisioningCodeService.h"
#import "OWSDeviceProvisioningService.h"
#import "OWSProvisioningMessage.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSDeviceProvisioner ()

@property (nonatomic, readonly) NSData *myPublicKey;
@property (nonatomic, readonly) NSData *myPrivateKey;
@property (nonatomic, readonly) NSData *theirPublicKey;
@property (nonatomic, readonly) NSString *accountIdentifier;
@property (nonatomic, nullable) NSString *ephemeralDeviceId;
@property (nonatomic, readonly) OWSDeviceProvisioningCodeService *provisioningCodeService;
@property (nonatomic, readonly) OWSDeviceProvisioningService *provisioningService;

@end

@implementation OWSDeviceProvisioner

- (instancetype)initWithMyPublicKey:(NSData *)myPublicKey
                       myPrivateKey:(NSData *)myPrivateKey
                     theirPublicKey:(NSData *)theirPublicKey
             theirEphemeralDeviceId:(NSString *)ephemeralDeviceId
                  accountIdentifier:(NSString *)accountIdentifier
            provisioningCodeService:(OWSDeviceProvisioningCodeService *)provisioningCodeService
                provisioningService:(OWSDeviceProvisioningService *)provisioningService
{
    self = [super init];
    if (!self) {
        return self;
    }

    _myPublicKey = myPublicKey;
    _myPrivateKey = myPrivateKey;
    _theirPublicKey = theirPublicKey;
    _accountIdentifier = accountIdentifier;
    _ephemeralDeviceId = ephemeralDeviceId;
    _provisioningCodeService = provisioningCodeService;
    _provisioningService = provisioningService;

    return self;
}

- (instancetype)initWithMyPublicKey:(NSData *)myPublicKey
                       myPrivateKey:(NSData *)myPrivateKey
                     theirPublicKey:(NSData *)theirPublicKey
             theirEphemeralDeviceId:(NSString *)ephemeralDeviceId
                  accountIdentifier:(NSString *)accountIdentifier
{
    return [self initWithMyPublicKey:myPublicKey
                        myPrivateKey:myPrivateKey
                      theirPublicKey:theirPublicKey
              theirEphemeralDeviceId:ephemeralDeviceId
                   accountIdentifier:accountIdentifier
             provisioningCodeService:[OWSDeviceProvisioningCodeService new]
                 provisioningService:[OWSDeviceProvisioningService new]];
}

- (void)provisionWithSuccess:(void (^)())successCallback failure:(void (^)(NSError *_Nonnull))failureCallback
{
    [self.provisioningCodeService requestProvisioningCodeWithSuccess:^(NSString *provisioningCode) {
        DDLogInfo(@"Retrieved provisioning code.");
        [self provisionWithCode:provisioningCode success:successCallback failure:failureCallback];
    }
        failure:^(NSError *error) {
            DDLogError(@"Failed to get provisioning code with error: %@", error);
            failureCallback(error);
        }];
}

- (void)provisionWithCode:(NSString *)provisioningCode
                  success:(void (^)())successCallback
                  failure:(void (^)(NSError *_Nonnull))failureCallback
{
    OWSProvisioningMessage *message = [[OWSProvisioningMessage alloc] initWithMyPublicKey:self.myPublicKey
                                                                             myPrivateKey:self.myPrivateKey
                                                                           theirPublicKey:self.theirPublicKey
                                                                        accountIdentifier:self.accountIdentifier
                                                                         provisioningCode:provisioningCode];

    [self.provisioningService provisionWithMessageBody:[message buildEncryptedMessageBody]
        ephemeralDeviceId:self.ephemeralDeviceId
        success:^{
            DDLogInfo(@"ProvisioningService SUCCEEDED");
            successCallback();
        }
        failure:^(NSError *error) {
            DDLogError(@"ProvisioningService FAILED with error:%@", error);
            failureCallback(error);
        }];
}

@end

NS_ASSUME_NONNULL_END
