//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSDeviceProvisioner.h"
#import "OWSDeviceProvisioningCodeService.h"
#import "OWSDeviceProvisioningService.h"
#import "OWSError.h"
#import "OWSProvisioningMessage.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSDeviceProvisioner ()

@property (nonatomic, readonly) NSData *myPublicKey;
@property (nonatomic, readonly) NSData *myPrivateKey;
@property (nonatomic, readonly) NSData *theirPublicKey;
@property (nonatomic, readonly) NSString *accountIdentifier;
@property (nonatomic, readonly) NSData *profileKey;
@property (nonatomic, nullable) NSString *ephemeralDeviceId;
@property (nonatomic, readonly) BOOL areReadReceiptsEnabled;
@property (nonatomic, readonly) OWSDeviceProvisioningCodeService *provisioningCodeService;
@property (nonatomic, readonly) OWSDeviceProvisioningService *provisioningService;

@end

@implementation OWSDeviceProvisioner

- (instancetype)initWithMyPublicKey:(NSData *)myPublicKey
                       myPrivateKey:(NSData *)myPrivateKey
                     theirPublicKey:(NSData *)theirPublicKey
             theirEphemeralDeviceId:(NSString *)ephemeralDeviceId
                  accountIdentifier:(NSString *)accountIdentifier
                         profileKey:(NSData *)profileKey
                readReceiptsEnabled:(BOOL)areReadReceiptsEnabled
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
    _profileKey = profileKey;
    _ephemeralDeviceId = ephemeralDeviceId;
    _areReadReceiptsEnabled = areReadReceiptsEnabled;
    _provisioningCodeService = provisioningCodeService;
    _provisioningService = provisioningService;

    return self;
}

- (instancetype)initWithMyPublicKey:(NSData *)myPublicKey
                       myPrivateKey:(NSData *)myPrivateKey
                     theirPublicKey:(NSData *)theirPublicKey
             theirEphemeralDeviceId:(NSString *)ephemeralDeviceId
                  accountIdentifier:(NSString *)accountIdentifier
                         profileKey:(NSData *)profileKey
                readReceiptsEnabled:(BOOL)areReadReceiptsEnabled
{
    return [self initWithMyPublicKey:myPublicKey
                        myPrivateKey:myPrivateKey
                      theirPublicKey:theirPublicKey
              theirEphemeralDeviceId:ephemeralDeviceId
                   accountIdentifier:accountIdentifier
                          profileKey:profileKey
                 readReceiptsEnabled:areReadReceiptsEnabled
             provisioningCodeService:[OWSDeviceProvisioningCodeService new]
                 provisioningService:[OWSDeviceProvisioningService new]];
}

- (void)provisionWithSuccess:(void (^)(void))successCallback failure:(void (^)(NSError *_Nonnull))failureCallback
{
    [self.provisioningCodeService
        requestProvisioningCodeWithSuccess:^(NSString *provisioningCode) {
            OWSLogInfo(@"Retrieved provisioning code.");
            [self provisionWithCode:provisioningCode success:successCallback failure:failureCallback];
        }
        failure:^(NSError *error) {
            OWSLogError(@"Failed to get provisioning code with error: %@", error);
            failureCallback(error);
        }];
}

- (void)provisionWithCode:(NSString *)provisioningCode
                  success:(void (^)(void))successCallback
                  failure:(void (^)(NSError *_Nonnull))failureCallback
{
    OWSProvisioningMessage *message = [[OWSProvisioningMessage alloc] initWithMyPublicKey:self.myPublicKey
                                                                             myPrivateKey:self.myPrivateKey
                                                                           theirPublicKey:self.theirPublicKey
                                                                        accountIdentifier:self.accountIdentifier
                                                                               profileKey:self.profileKey
                                                                      readReceiptsEnabled:self.areReadReceiptsEnabled
                                                                         provisioningCode:provisioningCode];

    NSData *_Nullable messageBody = [message buildEncryptedMessageBody];
    if (messageBody == nil) {
        NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToEncryptMessage, @"Failed building provisioning message");
        failureCallback(error);
        return;
    }

    [self.provisioningService provisionWithMessageBody:messageBody
        ephemeralDeviceId:self.ephemeralDeviceId
        success:^{
            OWSLogInfo(@"ProvisioningService SUCCEEDED");
            successCallback();
        }
        failure:^(NSError *error) {
            OWSLogError(@"ProvisioningService FAILED with error:%@", error);
            failureCallback(error);
        }];
}

@end

NS_ASSUME_NONNULL_END
