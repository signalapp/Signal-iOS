//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSProvisioningProtosProvisionEnvelope;

@interface OWSProvisioningCipher : NSObject

@property (nonatomic, readonly) NSData *ourPublicKey;

- (instancetype)initWithTheirPublicKey:(NSData *)theirPublicKey;
- (nullable NSData *)encrypt:(NSData *)plainText;

// Forsta addition:
-(nullable NSData *)decrypt:(nonnull OWSProvisioningProtosProvisionEnvelope *)envelopeProto;

@end

NS_ASSUME_NONNULL_END
