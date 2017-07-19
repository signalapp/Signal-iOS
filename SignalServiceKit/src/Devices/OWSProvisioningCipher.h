//  Copyright © 2016 Open Whisper Systems. All rights reserved.

NS_ASSUME_NONNULL_BEGIN

@interface OWSProvisioningCipher : NSObject

@property (nonatomic, readonly) NSData *ourPublicKey;

- (instancetype)initWithTheirPublicKey:(NSData *)theirPublicKey;
- (NSData *)encrypt:(NSData *)plainText;

@end

NS_ASSUME_NONNULL_END
