//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <Curve25519Kit/Curve25519.h>
#import <SignalServiceKit/NSData+keyVersionByte.h>
#import <SignalServiceKit/OWSProvisioningMessage.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSUserAgent = @"OWI";
uint32_t const OWSProvisioningVersion = 1;

@interface OWSProvisioningMessage ()

@property (nonatomic, readonly) NSData *myPublicKey;
@property (nonatomic, readonly) NSData *myPrivateKey;
@property (nonatomic, readonly) SignalServiceAddress *accountAddress;
@property (nonatomic, readonly) NSData *theirPublicKey;
@property (nonatomic, readonly) NSData *profileKey;
@property (nonatomic, readonly) BOOL areReadReceiptsEnabled;
@property (nonatomic, readonly) NSString *provisioningCode;

@end

@implementation OWSProvisioningMessage

- (instancetype)initWithMyPublicKey:(NSData *)myPublicKey
                       myPrivateKey:(NSData *)myPrivateKey
                     theirPublicKey:(NSData *)theirPublicKey
                     accountAddress:(SignalServiceAddress *)accountAddress
                         profileKey:(NSData *)profileKey
                readReceiptsEnabled:(BOOL)areReadReceiptsEnabled
                   provisioningCode:(NSString *)provisioningCode
{
    self = [super init];
    if (!self) {
        return self;
    }

    _myPublicKey = myPublicKey;
    _myPrivateKey = myPrivateKey;
    _theirPublicKey = theirPublicKey;
    _accountAddress = accountAddress;
    _profileKey = profileKey;
    _areReadReceiptsEnabled = areReadReceiptsEnabled;
    _provisioningCode = provisioningCode;

    return self;
}

- (nullable NSData *)buildEncryptedMessageBody
{
    ProvisioningProtoProvisionMessageBuilder *messageBuilder =
        [ProvisioningProtoProvisionMessage builderWithIdentityKeyPublic:[self.myPublicKey prependKeyType]
                                                     identityKeyPrivate:self.myPrivateKey
                                                       provisioningCode:self.provisioningCode
                                                             profileKey:self.profileKey];

    messageBuilder.userAgent = OWSUserAgent;
    messageBuilder.readReceipts = self.areReadReceiptsEnabled;
    messageBuilder.provisioningVersion = OWSProvisioningVersion;

    NSString *_Nullable phoneNumber = self.accountAddress.phoneNumber;
    if (!phoneNumber) {
        OWSFailDebug(@"phone number unexpectedly missing");
        return nil;
    }
    messageBuilder.number = phoneNumber;

    NSString *_Nullable uuidString = self.accountAddress.uuidString;
    if (uuidString) {
        // TODO UUID: Eventually, this should be mandatory.
        messageBuilder.uuid = uuidString;
    }

    NSError *error;
    NSData *_Nullable plainTextProvisionMessage = [messageBuilder buildSerializedDataAndReturnError:&error];
    if (!plainTextProvisionMessage || error) {
        OWSFailDebug(@"could not serialize proto: %@.", error);
        return nil;
    }

    OWSProvisioningCipher *cipher = [[OWSProvisioningCipher alloc] initWithTheirPublicKey:self.theirPublicKey];
    NSData *_Nullable encryptedProvisionMessage = [cipher encrypt:plainTextProvisionMessage];
    if (encryptedProvisionMessage == nil) {
        OWSFailDebug(@"Failed to encrypt provision message");
        return nil;
    }

    // Note that this is a one-time-use *cipher* public key, not our Signal *identity* public key
    ProvisioningProtoProvisionEnvelopeBuilder *envelopeBuilder =
        [ProvisioningProtoProvisionEnvelope builderWithPublicKey:[cipher.ourPublicKey prependKeyType]
                                                            body:encryptedProvisionMessage];

    NSData *_Nullable envelopeData = [envelopeBuilder buildSerializedDataAndReturnError:&error];
    if (!envelopeData || error) {
        OWSFailDebug(@"could not serialize proto: %@.", error);
        return nil;
    }

    return envelopeData;
}

@end

NS_ASSUME_NONNULL_END
