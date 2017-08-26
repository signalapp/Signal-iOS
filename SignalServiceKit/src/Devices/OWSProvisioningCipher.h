//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface OWSProvisioningCipher : NSObject

@property (nonatomic, readonly) NSData *ourPublicKey;

- (instancetype)initWithTheirPublicKey:(NSData *)theirPublicKey;
- (nullable NSData *)encrypt:(NSData *)plainText;

@end

NS_ASSUME_NONNULL_END
